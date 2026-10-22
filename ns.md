# Kubernetes Namespace and ServiceAccount

## 1. Namespace

### What is it?

A **Namespace** is a logical partition inside a Kubernetes cluster. It lets multiple teams, projects, or environments share one cluster without their resources colliding.

Think of a cluster as an office building and namespaces as separate floors: each floor has its own rooms (Pods, Services, ConfigMaps), and the same room name can exist on different floors.

### Why use it?

- **Isolation**: separate `dev`, `test`, `prod` or team-wise resources
- **Name scoping**: two Pods named `web` can exist in different namespaces
- **Access control**: RBAC permissions can be given per namespace
- **Resource limits**: apply `ResourceQuota` and `LimitRange` per namespace

### Default namespaces

| Namespace | Purpose |
|---|---|
| `default` | Used when no namespace is specified |
| `kube-system` | Kubernetes system components (CoreDNS, kube-proxy) |
| `kube-public` | Publicly readable data, rarely used |
| `kube-node-lease` | Node heartbeat (Lease objects) |

### Example: create a namespace

Imperative:

```bash
kubectl create namespace dev
```

Declarative (`namespace.yaml`):

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: dev
  labels:
    env: development
```

```bash
kubectl apply -f namespace.yaml
kubectl get namespaces
```

### Example: deploy into a namespace

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: web
  namespace: dev
spec:
  containers:
    - name: nginx
      image: nginx:1.27
```

```bash
kubectl apply -f pod.yaml
kubectl get pods -n dev
kubectl get pods -A          # all namespaces
```

Set a default namespace for your current context so you do not need `-n` every time:

```bash
kubectl config set-context --current --namespace=dev
```

### Important notes

- Not every resource is namespaced. **Namespaced**: Pod, Service, Deployment, ConfigMap, Secret, ServiceAccount, Role. **Cluster-wide**: Node, PersistentVolume, Namespace, ClusterRole, StorageClass.
- Namespaces do **not** provide network isolation by themselves. Use `NetworkPolicy` for that.
- Cross-namespace DNS: `<service>.<namespace>.svc.cluster.local`
- Deleting a namespace deletes everything inside it.

---

## 2. ServiceAccount

### What is it?

A **ServiceAccount** is an identity for **processes running in Pods** (not for humans). When a Pod needs to talk to the Kubernetes API (for example, to list Pods or read a ConfigMap), it authenticates using its ServiceAccount.

| Identity type | Used by |
|---|---|
| User account | Humans (kubectl, admins) |
| ServiceAccount | Pods / applications |

### Key facts

- ServiceAccounts are **namespaced**.
- Every namespace has a `default` ServiceAccount, and Pods use it if none is specified.
- A ServiceAccount has **no permissions by default**. Permissions come from **RBAC** (Role + RoleBinding).
- Modern Kubernetes (1.24+) mounts a short-lived, auto-rotated token into the Pod (projected volume) instead of creating long-lived Secrets.

### How the pieces fit together

```
ServiceAccount  <--- RoleBinding --->  Role
 (who)                                (what actions are allowed)
     ^
     |
    Pod uses it (serviceAccountName)
```

---

## 3. Full Example: Pod that can list Pods in `dev`

**Goal:** an app Pod in the `dev` namespace should be able to read (list/get) Pods in `dev`, and nothing more.

### Step 1: Namespace

```bash
kubectl create namespace dev
```

### Step 2: ServiceAccount

```yaml
# sa.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: pod-reader-sa
  namespace: dev
```

### Step 3: Role (what is allowed)

```yaml
# role.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: pod-reader
  namespace: dev
rules:
  - apiGroups: [""]          # "" = core API group
    resources: ["pods"]
    verbs: ["get", "list", "watch"]
```

### Step 4: RoleBinding (attach Role to ServiceAccount)

```yaml
# rolebinding.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: pod-reader-binding
  namespace: dev
subjects:
  - kind: ServiceAccount
    name: pod-reader-sa
    namespace: dev
roleRef:
  kind: Role
  name: pod-reader
  apiGroup: rbac.authorization.k8s.io
```

### Step 5: Pod using the ServiceAccount

```yaml
# pod.yaml
apiVersion: v1
kind: Pod
metadata:
  name: api-client
  namespace: dev
spec:
  serviceAccountName: pod-reader-sa
  containers:
    - name: kubectl
      image: bitnami/kubectl:latest
      command: ["sleep", "3600"]
```

### Apply everything

```bash
kubectl apply -f sa.yaml -f role.yaml -f rolebinding.yaml -f pod.yaml
```

### Step 6: Verify permissions

Check from outside using impersonation:

```bash
# Allowed
kubectl auth can-i list pods \
  --as=system:serviceaccount:dev:pod-reader-sa -n dev
# yes

# Not allowed (no delete verb)
kubectl auth can-i delete pods \
  --as=system:serviceaccount:dev:pod-reader-sa -n dev
# no

# Not allowed (different namespace)
kubectl auth can-i list pods \
  --as=system:serviceaccount:dev:pod-reader-sa -n kube-system
# no
```

Check from inside the Pod:

```bash
kubectl exec -it api-client -n dev -- kubectl get pods -n dev
# works

kubectl exec -it api-client -n dev -- kubectl get pods -n kube-system
# Error: forbidden
```

### Where is the token inside the Pod?

```bash
kubectl exec -it api-client -n dev -- ls /var/run/secrets/kubernetes.io/serviceaccount/
# ca.crt  namespace  token
```

---

## 4. Role vs ClusterRole

| | Role / RoleBinding | ClusterRole / ClusterRoleBinding |
|---|---|---|
| Scope | One namespace | Whole cluster |
| Use for | App permissions inside a namespace | Nodes, PVs, or access across all namespaces |

A `ClusterRole` can also be bound with a `RoleBinding` to grant its permissions only within one namespace.

---

## 5. Useful Commands

```bash
# Namespaces
kubectl get ns
kubectl describe ns dev
kubectl delete ns dev

# ServiceAccounts
kubectl get sa -n dev
kubectl create serviceaccount my-sa -n dev
kubectl describe sa pod-reader-sa -n dev

# Generate a short-lived token manually
kubectl create token pod-reader-sa -n dev

# RBAC
kubectl get role,rolebinding -n dev
kubectl auth can-i --list --as=system:serviceaccount:dev:pod-reader-sa -n dev
```

---

## 6. Best Practices

- Use a **dedicated ServiceAccount per application**; avoid using `default`.
- Follow **least privilege**: grant only the verbs and resources needed.
- If a Pod never calls the API, disable token mounting:

  ```yaml
  spec:
    automountServiceAccountToken: false
  ```

- Combine namespaces with `ResourceQuota`, `LimitRange`, and `NetworkPolicy` for real multi-tenant isolation.

---

## 7. Quick Summary

| Concept | One-line meaning |
|---|---|
| Namespace | Logical partition of a cluster for isolation and organization |
| ServiceAccount | Identity a Pod uses to talk to the Kubernetes API |
| Role | Set of allowed actions in a namespace |
| RoleBinding | Connects a Role to a ServiceAccount (or user/group) |
