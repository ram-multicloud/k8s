# Kubernetes CRD (Custom Resource Definition)

## What is a CRD?

A CRD lets you **add your own object type** to Kubernetes.

Kubernetes has built-in types like `Pod`, `Deployment` and `Service`. With a CRD you can add types like `Website`, `Database` or `Backup`, and then use `kubectl` on them like any built-in type.

| Term | Meaning |
|---|---|
| **CRD** | The definition: "a new type called Website exists" |
| **Custom Resource (CR)** | An actual object of that type: "my-site is a Website" |
| **Controller / Operator** | A program that watches the objects and does real work (creates pods, services, etc.) |

> A CRD alone only **stores data**. It does nothing until a controller acts on it.

## Why do we need CRDs?

1. **Store your own data in Kubernetes.** You get storage, validation, RBAC, `kubectl` support and watch events for free.
2. **Describe what you want in one object.** Example: "a Postgres database with 3 replicas" becomes one `Database` object.
3. **Build operators.** CRD + controller = automation. cert-manager, Argo CD, Prometheus Operator and Istio all work this way.

---

## Example: a `Website` type

### 1. The CRD: `crd.yaml`

```yaml
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: websites.demo.example.com      # must be <plural>.<group>
spec:
  group: demo.example.com
  scope: Namespaced                    # or Cluster
  names:
    plural: websites
    singular: website
    kind: Website
    shortNames: [ws]                   # kubectl get ws
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
              required: [url]
              properties:
                url:
                  type: string
                replicas:
                  type: integer
                  minimum: 1
                  maximum: 5
                  default: 1
      additionalPrinterColumns:        # columns shown by kubectl get
        - name: URL
          type: string
          jsonPath: .spec.url
        - name: Replicas
          type: integer
          jsonPath: .spec.replicas
        - name: Age
          type: date
          jsonPath: .metadata.creationTimestamp
```

What each part does:

| Field | Purpose |
|---|---|
| `group` | API group, used in `apiVersion: demo.example.com/v1` |
| `names` | How the type is named (`kind`, `plural`, short name) |
| `scope` | `Namespaced` (lives in a namespace) or `Cluster` |
| `schema` | Validation rules: `url` is required, `replicas` must be 1 to 5 |
| `additionalPrinterColumns` | What `kubectl get` displays |

### 2. A custom resource: `website.yaml`

```yaml
apiVersion: demo.example.com/v1
kind: Website
metadata:
  name: my-site
spec:
  url: https://example.com
  replicas: 2
```

---

## Deploy

```bash
kubectl apply -f crd.yaml
kubectl get crd websites.demo.example.com

kubectl apply -f website.yaml
kubectl get websites        # or: kubectl get ws
```

Expected output:

```
NAME      URL                   REPLICAS   AGE
my-site   https://example.com   2          5s
```

More checks:

```bash
kubectl describe website my-site
kubectl explain website.spec       # docs generated from your schema
kubectl get website my-site -o yaml
```

---

## Test validation

**Bad value (replicas over 5):**

```bash
kubectl apply -f - <<EOF
apiVersion: demo.example.com/v1
kind: Website
metadata:
  name: bad-site
spec:
  url: https://example.com
  replicas: 10
EOF
```

Expected: rejected with an error like

```
The Website "bad-site" is invalid: spec.replicas: Invalid value: 10: spec.replicas in body should be less than or equal to 5
```

**Missing `url`:** rejected because `url` is required.

**Missing `replicas`:** accepted, and `replicas` defaults to `1`.

---

## Good to know

- `kubectl get pods` shows nothing new. The `Website` is just stored data. To make it create pods, you need a **controller** (written with tools like Kubebuilder, Operator SDK, or a simple script using the Kubernetes API).
- CRDs are **cluster-scoped objects**, so creating one needs cluster-level permission. Access to the custom resources themselves is controlled by RBAC:

```yaml
rules:
  - apiGroups: ["demo.example.com"]   # the CRD's group
    resources: ["websites"]           # the CRD's plural name
    verbs: ["get", "list", "watch"]
```

- **Deleting a CRD deletes all objects of that type.**

## Cleanup

```bash
kubectl delete -f website.yaml
kubectl delete -f crd.yaml
```
