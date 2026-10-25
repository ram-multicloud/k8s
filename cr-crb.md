# Kubernetes ClusterRole & ClusterRoleBinding

| Object | Scope | What it does |
|---|---|---|
| `ClusterRole` | Whole cluster | List of permissions (can include nodes, CRDs, all namespaces) |
| `ClusterRoleBinding` | Whole cluster | Gives a ClusterRole to a user/group/ServiceAccount everywhere |

Think of it as: **ClusterRole = "what"**, **ClusterRoleBinding = "who"**.

Key rules:
- RBAC only **allows**. There is no deny.
- ClusterRole + **ClusterRoleBinding** = access in all namespaces.
- ClusterRole + **RoleBinding** = access in that one namespace only.
- Nodes, namespaces, PVs, CRDs themselves are cluster-scoped, so they need a ClusterRole.

---

## Example: read pods, nodes and a custom resource (CRD)

Goal: a ServiceAccount that can **read pods, nodes and `Widget` custom resources**, but can't delete or touch secrets.

### 1. Save as `rbac-demo.yaml`

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: rbac-demo
---
# --- CRD: adds a new type called "Widget" ---
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: widgets.demo.example.com      # <plural>.<group>
spec:
  group: demo.example.com
  scope: Namespaced
  names:
    plural: widgets
    singular: widget
    kind: Widget
  versions:
    - name: v1
      served: true
      storage: true
      schema:
        openAPIV3Schema:
          type: object
          properties:
            spec:
              type: object
              properties:
                size:
                  type: string
---
# --- A Widget instance ---
apiVersion: demo.example.com/v1
kind: Widget
metadata:
  name: my-widget
  namespace: rbac-demo
spec:
  size: large
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: demo-sa
  namespace: rbac-demo
---
# --- ClusterRole: WHAT is allowed ---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: demo-reader
rules:
  - apiGroups: [""]                    # core group
    resources: ["pods", "nodes"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["demo.example.com"]    # the CRD's group
    resources: ["widgets"]             # the CRD's plural name
    verbs: ["get", "list", "watch"]
---
# --- ClusterRoleBinding: WHO gets it ---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: demo-reader-binding
subjects:
  - kind: ServiceAccount
    name: demo-sa
    namespace: rbac-demo
roleRef:
  kind: ClusterRole
  name: demo-reader
  apiGroup: rbac.authorization.k8s.io
---
# --- Pod running as demo-sa (for testing) ---
apiVersion: v1
kind: Pod
metadata:
  name: api-client
  namespace: rbac-demo
spec:
  serviceAccountName: demo-sa
  containers:
    - name: curl
      image: curlimages/curl:8.10.1
      command: ["sleep", "3600"]
```

### 2. Deploy

```bash
kubectl apply -f rbac-demo.yaml
kubectl wait --for=condition=Ready pod/api-client -n rbac-demo --timeout=90s
kubectl get widgets -n rbac-demo        # shows my-widget
```

> If `apply` complains about the `Widget` before the CRD is ready, just run `kubectl apply -f rbac-demo.yaml` a second time.

---

## Test

### Quick test (`auth can-i`)

```bash
SA=system:serviceaccount:rbac-demo:demo-sa

kubectl auth can-i list pods --all-namespaces --as=$SA   # yes
kubectl auth can-i list nodes --as=$SA                   # yes
kubectl auth can-i list widgets -n rbac-demo --as=$SA    # yes

kubectl auth can-i delete widgets -n rbac-demo --as=$SA  # no
kubectl auth can-i delete pods -n default --as=$SA       # no
kubectl auth can-i list secrets -n default --as=$SA      # no
```

### Real test (from inside the Pod)

```bash
kubectl exec -n rbac-demo api-client -- sh -c '
D=/var/run/secrets/kubernetes.io/serviceaccount
T=$(cat $D/token)
A=https://kubernetes.default.svc
c() { curl -s -o /dev/null -w "%{http_code}\n" --cacert $D/ca.crt -H "Authorization: Bearer $T" "$@"; }

echo "list pods (200):";    c $A/api/v1/pods
echo "list nodes (200):";   c $A/api/v1/nodes
echo "list widgets (200):"; c $A/apis/demo.example.com/v1/widgets
echo "list secrets (403):"; c $A/api/v1/secrets
echo "delete widget (403):"; c -X DELETE $A/apis/demo.example.com/v1/namespaces/rbac-demo/widgets/my-widget
'
```

Expected: `200 200 200 403 403`.

---

