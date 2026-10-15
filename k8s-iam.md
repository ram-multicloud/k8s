# Kubernetes Identity and Access Management (IAM)

## 1. Overview

Every request to the Kubernetes API server goes through three stages:

```
Client (kubectl / Pod / CI)
        |
        v
1. Authentication   -> Who are you?
        |
        v
2. Authorization    -> What are you allowed to do?
        |
        v
3. Admission Control -> Is this request valid / policy-compliant?
        |
        v
   etcd (persisted)
```

| Stage | Question | Mechanism |
|---|---|---|
| Authentication (AuthN) | Who is making the request? | Certificates, tokens, OIDC, webhook |
| Authorization (AuthZ) | Can they do this action? | RBAC (default), ABAC, Node, Webhook |
| Admission Control | Should the request be modified or rejected? | Validating/Mutating webhooks, Pod Security, policy engines |

Kubernetes has **no user object**. Users are managed outside the cluster (certificates, OIDC provider, cloud IAM). Only **ServiceAccounts** exist as API objects.

---

## 2. Authentication

### 2.1 Types of Identities

| Identity | Used by | Managed by |
|---|---|---|
| Normal user | Humans (admins, developers) | External (certs, OIDC, cloud IAM) |
| ServiceAccount | Pods and in-cluster processes | Kubernetes API |
| Anonymous | Unauthenticated requests | Usually disabled |

### 2.2 Authentication Methods

| Method | Description |
|---|---|
| X.509 client certificates | CN = username, O = group. Used by kubeconfig and control-plane components |
| Bearer tokens | ServiceAccount tokens, static token files (not recommended) |
| OIDC | Integrate with Okta, Azure AD (Entra ID), Keycloak, Google |
| Webhook token | API server calls an external service to validate tokens |
| Cloud IAM authenticators | AWS `aws-iam-authenticator` (EKS), Azure AD (AKS) |
| Authenticating proxy | Reverse proxy sets identity headers |

### 2.3 Example: Creating a User with a Client Certificate

```bash
# 1. Generate key and CSR
openssl genrsa -out ram.key 2048
openssl req -new -key ram.key -out ram.csr -subj "/CN=ram/O=dev-team"

# 2. Submit a CertificateSigningRequest
cat <<EOF | kubectl apply -f -
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: ram
spec:
  request: $(base64 -w0 < ram.csr)
  signerName: kubernetes.io/kube-apiserver-client
  expirationSeconds: 86400
  usages:
    - client auth
EOF

# 3. Approve and fetch the certificate
kubectl certificate approve ram
kubectl get csr ram -o jsonpath='{.status.certificate}' | base64 -d > ram.crt

# 4. Add to kubeconfig
kubectl config set-credentials ram --client-certificate=ram.crt --client-key=ram.key --embed-certs=true
kubectl config set-context ram-ctx --cluster=<cluster-name> --user=ram
```

The user `ram` (group `dev-team`) is now authenticated, but has **no permissions** until RBAC is configured.

---

## 3. Authorization: RBAC

RBAC (Role-Based Access Control) is the default authorization mode. Permissions are **additive only**: there are no deny rules.

### 3.1 RBAC Objects

| Object | Scope | Purpose |
|---|---|---|
| Role | Namespace | Set of permissions inside one namespace |
| ClusterRole | Cluster | Cluster-wide permissions, non-namespaced resources (nodes, PVs), or reusable role across namespaces |
| RoleBinding | Namespace | Grants a Role or ClusterRole to subjects within a namespace |
| ClusterRoleBinding | Cluster | Grants a ClusterRole to subjects across the whole cluster |

### 3.2 Subjects

A binding can target:

- `User`
- `Group`
- `ServiceAccount`

### 3.3 Rule Structure

```yaml
rules:
  - apiGroups: [""]            # "" = core group (pods, services, configmaps)
    resources: ["pods"]
    verbs: ["get", "list", "watch"]
```

Common verbs: `get`, `list`, `watch`, `create`, `update`, `patch`, `delete`, `deletecollection`.

Common API groups:

| apiGroup | Resources |
|---|---|
| `""` (core) | pods, services, configmaps, secrets, persistentvolumeclaims, namespaces, nodes |
| `apps` | deployments, statefulsets, daemonsets, replicasets |
| `batch` | jobs, cronjobs |
| `networking.k8s.io` | ingresses, networkpolicies |
| `rbac.authorization.k8s.io` | roles, rolebindings, clusterroles |

### 3.4 Example: Namespaced Read-Only Role

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: pod-reader
  namespace: dev
rules:
  - apiGroups: [""]
    resources: ["pods", "pods/log"]
    verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: ram-pod-reader
  namespace: dev
subjects:
  - kind: User
    name: ram
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: pod-reader
  apiGroup: rbac.authorization.k8s.io
```

### 3.5 Example: Cluster-Wide Role for a Group

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: node-viewer
rules:
  - apiGroups: [""]
    resources: ["nodes"]
    verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: ops-node-viewer
subjects:
  - kind: Group
    name: ops-team
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: node-viewer
  apiGroup: rbac.authorization.k8s.io
```

### 3.6 Reusing a ClusterRole in One Namespace

A ClusterRole bound with a **RoleBinding** is limited to that namespace.

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: dev-team-edit
  namespace: dev
subjects:
  - kind: Group
    name: dev-team
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: edit
  apiGroup: rbac.authorization.k8s.io
```

### 3.7 Built-in ClusterRoles

| ClusterRole | Access |
|---|---|
| `cluster-admin` | Full control over everything |
| `admin` | Full access within a namespace (including RBAC for that namespace) |
| `edit` | Read/write most objects in a namespace, no RBAC changes |
| `view` | Read-only on most objects, no Secrets |

### 3.8 Imperative Commands

```bash
kubectl create role pod-reader --verb=get,list,watch --resource=pods -n dev
kubectl create rolebinding ram-pod-reader --role=pod-reader --user=ram -n dev
kubectl create clusterrolebinding ops-admin --clusterrole=cluster-admin --group=ops-team
```

### 3.9 Testing Permissions

```bash
kubectl auth can-i create deployments -n dev
kubectl auth can-i list pods -n dev --as ram
kubectl auth can-i '*' '*' --as system:serviceaccount:dev:app-sa
kubectl auth can-i --list -n dev --as ram
```

---

## 4. ServiceAccounts

A ServiceAccount is the identity of a **Pod** when it talks to the API server.

### 4.1 Key Facts

- Every namespace has a `default` ServiceAccount.
- Pods use `default` unless `serviceAccountName` is set.
- Modern clusters use **bound, short-lived, audience-scoped tokens** (projected volumes), not long-lived Secret tokens.
- Username format: `system:serviceaccount:<namespace>:<name>`.

### 4.2 Example: ServiceAccount with Limited Access

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: app-sa
  namespace: dev
automountServiceAccountToken: false     # opt in per pod
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: configmap-reader
  namespace: dev
rules:
  - apiGroups: [""]
    resources: ["configmaps"]
    verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: app-sa-configmap-reader
  namespace: dev
subjects:
  - kind: ServiceAccount
    name: app-sa
    namespace: dev
roleRef:
  kind: Role
  name: configmap-reader
  apiGroup: rbac.authorization.k8s.io
---
apiVersion: v1
kind: Pod
metadata:
  name: app
  namespace: dev
spec:
  serviceAccountName: app-sa
  automountServiceAccountToken: true
  containers:
    - name: app
      image: bitnami/kubectl
      command: ["sleep", "3600"]
```

Test from inside the pod:

```bash
kubectl exec -n dev app -- kubectl get configmaps     # allowed
kubectl exec -n dev app -- kubectl get pods           # forbidden
```

### 4.3 Requesting a Token Manually

```bash
kubectl create token app-sa -n dev --duration=1h
```

### 4.4 Best Practices

- One ServiceAccount per application.
- Set `automountServiceAccountToken: false` for pods that do not call the API.
- Never bind application ServiceAccounts to `cluster-admin`.

---

## 5. Cloud IAM Integration

Pods often need to access cloud services (S3, Key Vault, etc.). Do **not** store cloud access keys in Secrets. Map a Kubernetes ServiceAccount to a cloud identity.

### 5.1 AWS EKS

**Two layers of AWS and Kubernetes access:**

| Layer | Question | Mechanism |
|---|---|---|
| Cluster access (humans/nodes) | Who can call the Kubernetes API? | EKS access entries (or `aws-auth` ConfigMap, legacy) mapped to Kubernetes groups |
| Workload access (pods) | How does a pod call AWS APIs? | IRSA or EKS Pod Identity |

**Cluster access entry example:**

```bash
aws eks create-access-entry \
  --cluster-name demo \
  --principal-arn arn:aws:iam::123456789012:role/DevOpsRole \
  --kubernetes-groups dev-team

aws eks associate-access-policy \
  --cluster-name demo \
  --principal-arn arn:aws:iam::123456789012:role/DevOpsRole \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy \
  --access-scope type=namespace,namespaces=dev
```

**IRSA (IAM Roles for Service Accounts):**

The ServiceAccount is annotated with an IAM role ARN. The pod receives a projected OIDC token that AWS STS exchanges for temporary credentials.

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: s3-reader
  namespace: dev
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/s3-read-role
```

IAM role trust policy:

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "Federated": "arn:aws:iam::123456789012:oidc-provider/oidc.eks.ap-south-1.amazonaws.com/id/EXAMPLE"
    },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "oidc.eks.ap-south-1.amazonaws.com/id/EXAMPLE:sub": "system:serviceaccount:dev:s3-reader",
        "oidc.eks.ap-south-1.amazonaws.com/id/EXAMPLE:aud": "sts.amazonaws.com"
      }
    }
  }]
}
```

Pod using it:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: s3-test
  namespace: dev
spec:
  serviceAccountName: s3-reader
  containers:
    - name: aws-cli
      image: amazon/aws-cli
      command: ["aws", "s3", "ls"]
```

**EKS Pod Identity** is the newer alternative: an agent on each node provides credentials, and the association is created with `aws eks create-pod-identity-association` (no OIDC provider setup or annotation needed).

### 5.2 Azure AKS

| Layer | Mechanism |
|---|---|
| Cluster access (humans) | Microsoft Entra ID integration + Azure RBAC for Kubernetes authorization |
| Workload access (pods) | Microsoft Entra Workload Identity |

**Azure RBAC for Kubernetes example:**

```bash
az role assignment create \
  --assignee ram@example.com \
  --role "Azure Kubernetes Service RBAC Reader" \
  --scope /subscriptions/<sub-id>/resourceGroups/<rg>/providers/Microsoft.ContainerService/managedClusters/<cluster>/namespaces/dev
```

**Workload Identity example:**

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: kv-reader
  namespace: dev
  annotations:
    azure.workload.identity/client-id: <managed-identity-client-id>
---
apiVersion: v1
kind: Pod
metadata:
  name: kv-test
  namespace: dev
  labels:
    azure.workload.identity/use: "true"
spec:
  serviceAccountName: kv-reader
  containers:
    - name: app
      image: mcr.microsoft.com/azure-cli
      command: ["sleep", "3600"]
```

A federated credential on the managed identity trusts the cluster OIDC issuer and the subject `system:serviceaccount:dev:kv-reader`.

### 5.3 Comparison

| Aspect | AWS EKS | Azure AKS |
|---|---|---|
| Human authentication | IAM (access entries / aws-auth) | Entra ID (OIDC) |
| Human authorization | Kubernetes RBAC or EKS access policies | Kubernetes RBAC or Azure RBAC |
| Pod-to-cloud identity | IRSA / Pod Identity | Workload Identity |
| Mechanism | OIDC federation + STS | OIDC federation + Entra token exchange |

---

## 6. Admission Control

After AuthN and AuthZ, admission controllers can **mutate** or **validate** requests.

| Type | Examples |
|---|---|
| Built-in | `NamespaceLifecycle`, `LimitRanger`, `ResourceQuota`, `ServiceAccount`, `PodSecurity` |
| Dynamic webhooks | `MutatingAdmissionWebhook`, `ValidatingAdmissionWebhook` |
| ValidatingAdmissionPolicy | Native CEL-based rules, no webhook server needed |
| Policy engines | OPA Gatekeeper, Kyverno |

### 6.1 Pod Security Admission

Enforces Pod Security Standards (`privileged`, `baseline`, `restricted`) per namespace via labels:

```bash
kubectl label namespace dev \
  pod-security.kubernetes.io/enforce=restricted \
  pod-security.kubernetes.io/warn=restricted
```

### 6.2 Example: Kyverno Policy

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: disallow-latest-tag
spec:
  validationFailureAction: Enforce
  rules:
    - name: no-latest
      match:
        any:
          - resources:
              kinds: ["Pod"]
      validate:
        message: "Using the 'latest' image tag is not allowed."
        pattern:
          spec:
            containers:
              - image: "!*:latest"
```

---

## 7. Related Access Controls

| Control | Purpose |
|---|---|
| NetworkPolicy | Controls which pods can talk to which (network-level access) |
| Secrets + encryption at rest | Protects sensitive data in etcd |
| Audit logging | Records who did what and when |
| securityContext | Limits what a container can do on the node (runAsNonRoot, capabilities) |

Audit policy snippet:

```yaml
apiVersion: audit.k8s.io/v1
kind: Policy
rules:
  - level: Metadata
    resources:
      - group: ""
        resources: ["secrets"]
  - level: RequestResponse
    resources:
      - group: "rbac.authorization.k8s.io"
```

---

## 8. End-to-End Example: Developer Team in Namespace `dev`

Goal: members of `dev-team` can manage workloads in `dev` only, and the app pod can read an S3 bucket.

```yaml
# 1. Namespace
apiVersion: v1
kind: Namespace
metadata:
  name: dev
---
# 2. Bind built-in 'edit' role to the group in this namespace only
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: dev-team-edit
  namespace: dev
subjects:
  - kind: Group
    name: dev-team
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: edit
  apiGroup: rbac.authorization.k8s.io
---
# 3. Workload identity for the app (EKS IRSA)
apiVersion: v1
kind: ServiceAccount
metadata:
  name: s3-reader
  namespace: dev
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/s3-read-role
```

Verify:

```bash
kubectl auth can-i create deployments -n dev --as ram --as-group dev-team   # yes
kubectl auth can-i create deployments -n prod --as ram --as-group dev-team  # no
```

---

## 9. Troubleshooting

| Symptom | Meaning | Check |
|---|---|---|
| `Unauthorized` (401) | Authentication failed | kubeconfig credentials, token expiry, cert validity |
| `Forbidden` (403) | Authenticated but not authorized | RBAC bindings, `kubectl auth can-i` |
| `forbidden: User "system:anonymous"` | No credentials sent | kubeconfig context, auth plugin |
| Pod gets 403 from API | ServiceAccount lacks a binding | `kubectl auth can-i --as system:serviceaccount:<ns>:<sa>` |
| Pod cannot assume cloud role | Wrong annotation, trust policy or federated credential | Check SA annotation, OIDC issuer, subject string |
| Request rejected by admission | Policy violation | Read the error message; check Pod Security labels and policies |

Useful commands:

```bash
kubectl get roles,rolebindings -n dev
kubectl get clusterrolebindings -o wide | grep <subject>
kubectl describe rolebinding <name> -n dev
kubectl get sa -n dev
kubectl who-am-i          # or: kubectl auth whoami  (v1.28+)
```

---

## 10. Best Practices

1. **Least privilege**: grant only the verbs and resources needed.
2. Prefer **Roles/RoleBindings** over ClusterRoles/ClusterRoleBindings.
3. Avoid wildcards (`*`) in verbs, resources and apiGroups.
4. Use groups from your identity provider instead of binding individual users.
5. Restrict access to **Secrets**; `list` and `watch` on secrets also reveal their contents.
6. Use dedicated ServiceAccounts and disable token automounting when not needed.
7. Use **workload identity** (IRSA, Pod Identity, Azure Workload Identity) instead of static cloud keys.
8. Limit use of `cluster-admin`; protect `escalate`, `bind` and `impersonate` verbs.
9. Enable **audit logging** and review RBAC periodically.
10. Enforce Pod Security Standards and policy engines for guardrails.

---

## 11. Summary

- Every API request passes **Authentication → Authorization → Admission**.
- Kubernetes has no user objects: humans come from certificates, OIDC or cloud IAM; pods use **ServiceAccounts**.
- **RBAC** = Role/ClusterRole (what) + RoleBinding/ClusterRoleBinding (who gets it).
- Cloud permissions for pods come from federated identities, not stored keys.
- Admission controllers and policy engines add guardrails beyond RBAC.
