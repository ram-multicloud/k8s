# Kubernetes Deployment, Manifest YAML & Deployment Strategies

## 1. What is a Deployment?

A **Deployment** is a Kubernetes object that manages a set of identical Pods through a **ReplicaSet**. It gives you:

- Desired number of replicas (self-healing: crashed Pods are recreated)
- Rolling updates and rollbacks
- Declarative management (you describe the desired state, Kubernetes makes it real)

```
Deployment  -->  ReplicaSet  -->  Pods
```

When you change the Pod template (for example the image), the Deployment creates a **new ReplicaSet** and gradually moves Pods from the old one to the new one.

---

## 2. Anatomy of a Manifest YAML

Every Kubernetes manifest has four top-level fields:

| Field | Purpose |
|---|---|
| `apiVersion` | API group and version of the object (`apps/v1` for Deployment) |
| `kind` | Type of object (`Deployment`, `Service`, `ConfigMap`, ...) |
| `metadata` | Name, namespace, labels, annotations |
| `spec` | Desired state of the object |

### YAML rules to remember

- Indentation uses **spaces only** (2 spaces is the convention). Never tabs.
- `key: value` for maps, `- item` for lists.
- Strings with special characters should be quoted.
- `---` separates multiple objects in one file.

---

## 3. Writing a Deployment Manifest

### Step-by-step

1. Set `apiVersion: apps/v1` and `kind: Deployment`.
2. Give it a `name` (and labels) under `metadata`.
3. Under `spec`, set `replicas`.
4. Define `selector.matchLabels` (how the Deployment finds its Pods).
5. Define `template` (the Pod blueprint). Its labels **must match** the selector.
6. Under `template.spec.containers`, set image, ports, resources, probes.

### Complete example: `nginx-deployment.yaml`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment
  namespace: default
  labels:
    app: nginx
spec:
  replicas: 3
  revisionHistoryLimit: 5
  selector:
    matchLabels:
      app: nginx
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
        - name: nginx
          image: nginx:1.25
          ports:
            - containerPort: 80
          env:
            - name: APP_ENV
              value: "production"
          resources:
            requests:
              cpu: "100m"
              memory: "128Mi"
            limits:
              cpu: "250m"
              memory: "256Mi"
          readinessProbe:
            httpGet:
              path: /
              port: 80
            initialDelaySeconds: 5
            periodSeconds: 5
          livenessProbe:
            httpGet:
              path: /
              port: 80
            initialDelaySeconds: 15
            periodSeconds: 10
```

### Field explanation

| Field | Meaning |
|---|---|
| `replicas` | Number of Pods to keep running |
| `revisionHistoryLimit` | How many old ReplicaSets to keep for rollback |
| `selector.matchLabels` | Labels used to identify Pods owned by this Deployment |
| `strategy` | How Pods are replaced during an update |
| `template.metadata.labels` | Labels applied to Pods (must match the selector) |
| `containers[].image` | Container image and tag (avoid `latest` in production) |
| `resources.requests` | Minimum guaranteed resources used by the scheduler |
| `resources.limits` | Maximum resources the container may use |
| `readinessProbe` | Pod receives traffic only when this passes |
| `livenessProbe` | Container is restarted if this fails |

---

## 4. Exposing the Deployment with a Service

```yaml
apiVersion: v1
kind: Service
metadata:
  name: nginx-service
spec:
  type: ClusterIP        # ClusterIP | NodePort | LoadBalancer
  selector:
    app: nginx           # must match Pod labels
  ports:
    - port: 80           # Service port
      targetPort: 80     # Container port
```

---

## 5. Essential kubectl Commands

```bash
# Create / update
kubectl apply -f nginx-deployment.yaml

# View
kubectl get deployments
kubectl get rs
kubectl get pods -l app=nginx -o wide
kubectl describe deployment nginx-deployment

# Scale
kubectl scale deployment nginx-deployment --replicas=5

# Update image
kubectl set image deployment/nginx-deployment nginx=nginx:1.26

# Rollout management
kubectl rollout status deployment/nginx-deployment
kubectl rollout history deployment/nginx-deployment
kubectl rollout undo deployment/nginx-deployment
kubectl rollout undo deployment/nginx-deployment --to-revision=2
kubectl rollout pause deployment/nginx-deployment
kubectl rollout resume deployment/nginx-deployment

# Generate a starter manifest without creating anything
kubectl create deployment web --image=nginx --replicas=3 --dry-run=client -o yaml > web.yaml

# Delete
kubectl delete -f nginx-deployment.yaml
```

---

## 6. Deployment Strategies

Kubernetes has **two built-in strategies** (`RollingUpdate` and `Recreate`). Blue/Green and Canary are **patterns** you build using labels, Services, or tools such as Ingress, Argo Rollouts, Flagger, or a service mesh.

| Strategy | Built-in? | Downtime | Extra resources | Rollback speed |
|---|---|---|---|---|
| Rolling Update | Yes | None | Low | Medium |
| Recreate | Yes | Yes | None | Slow |
| Blue/Green | Pattern | None | High (2x) | Instant |
| Canary | Pattern | None | Low | Fast |

---

### 6.1 Rolling Update (default)

Pods are replaced **gradually**: new Pods are started while old ones are terminated, so the app stays available.

**Controls**

- `maxSurge`: how many extra Pods may be created above `replicas` during the update (number or %).
- `maxUnavailable`: how many Pods may be unavailable during the update (number or %).

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-rolling
spec:
  replicas: 4
  selector:
    matchLabels:
      app: web
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1          # up to 5 Pods during update
      maxUnavailable: 1    # at least 3 Pods always available
  template:
    metadata:
      labels:
        app: web
    spec:
      containers:
        - name: web
          image: nginx:1.25
          ports:
            - containerPort: 80
          readinessProbe:
            httpGet:
              path: /
              port: 80
```

**Flow:** `v1 v1 v1 v1` → `v1 v1 v1 v2` → `v1 v1 v2 v2` → `v1 v2 v2 v2` → `v2 v2 v2 v2`

**Use when:** Most stateless applications; you want zero downtime with no extra infrastructure.
**Watch out:** Old and new versions run side by side briefly, so they must be backward compatible (for example, database schema).

---

### 6.2 Recreate

All old Pods are **killed first**, then new Pods are created. There is a period of downtime.

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-recreate
spec:
  replicas: 3
  selector:
    matchLabels:
      app: web-recreate
  strategy:
    type: Recreate
  template:
    metadata:
      labels:
        app: web-recreate
    spec:
      containers:
        - name: web
          image: nginx:1.26
          ports:
            - containerPort: 80
```

**Flow:** `v1 v1 v1` → *(all stopped)* → `v2 v2 v2`

**Use when:**
- The app cannot run two versions at once (for example, a breaking DB migration)
- Dev/test environments
- Apps holding an exclusive lock on a volume (ReadWriteOnce)

**Watch out:** Downtime equals shutdown time plus startup time.

---

### 6.3 Blue/Green

Two full environments run in parallel: **Blue** (current) and **Green** (new). Traffic is switched at once by changing the Service selector.

**Blue deployment (v1, live)**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-blue
spec:
  replicas: 3
  selector:
    matchLabels:
      app: myapp
      version: blue
  template:
    metadata:
      labels:
        app: myapp
        version: blue
    spec:
      containers:
        - name: app
          image: myrepo/myapp:1.0
          ports:
            - containerPort: 8080
```

**Green deployment (v2, idle until switch)**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-green
spec:
  replicas: 3
  selector:
    matchLabels:
      app: myapp
      version: green
  template:
    metadata:
      labels:
        app: myapp
        version: green
    spec:
      containers:
        - name: app
          image: myrepo/myapp:2.0
          ports:
            - containerPort: 8080
```

**Service (points to blue)**

```yaml
apiVersion: v1
kind: Service
metadata:
  name: myapp-service
spec:
  selector:
    app: myapp
    version: blue        # change to "green" to switch traffic
  ports:
    - port: 80
      targetPort: 8080
```

**Switch traffic to green**

```bash
kubectl patch service myapp-service \
  -p '{"spec":{"selector":{"app":"myapp","version":"green"}}}'
```

**Rollback:** patch the selector back to `blue`.

**Use when:** You need instant cutover and instant rollback, and can afford double the resources.
**Watch out:** Cost (2x Pods) and shared database compatibility.

---

### 6.4 Canary

A **small percentage** of traffic is sent to the new version first. If metrics look healthy, the share is increased until the new version takes over.

**Stable (v1): 9 replicas**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-stable
spec:
  replicas: 9
  selector:
    matchLabels:
      app: myapp
      track: stable
  template:
    metadata:
      labels:
        app: myapp
        track: stable
    spec:
      containers:
        - name: app
          image: myrepo/myapp:1.0
          ports:
            - containerPort: 8080
```

**Canary (v2): 1 replica (about 10% of traffic)**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-canary
spec:
  replicas: 1
  selector:
    matchLabels:
      app: myapp
      track: canary
  template:
    metadata:
      labels:
        app: myapp
        track: canary
    spec:
      containers:
        - name: app
          image: myrepo/myapp:2.0
          ports:
            - containerPort: 8080
```

**Service (selects both, using only the shared label)**

```yaml
apiVersion: v1
kind: Service
metadata:
  name: myapp-service
spec:
  selector:
    app: myapp           # matches stable AND canary Pods
  ports:
    - port: 80
      targetPort: 8080
```

Traffic split is roughly proportional to Pod count: 9 stable : 1 canary = 90% : 10%.

**Promote step by step**

```bash
kubectl scale deployment app-canary --replicas=3
kubectl scale deployment app-stable --replicas=7
# ... continue until canary has all replicas, then
kubectl set image deployment/app-stable app=myrepo/myapp:2.0
kubectl delete deployment app-canary
```

**Use when:** You want to test with real users and limit the blast radius.
**Note:** Replica-based splitting is coarse. For precise percentages (1%, 5%), use Ingress-NGINX canary annotations, a service mesh (Istio, Linkerd), or **Argo Rollouts / Flagger**.

**Ingress-NGINX canary example (precise weight)**

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: myapp-canary
  annotations:
    nginx.ingress.kubernetes.io/canary: "true"
    nginx.ingress.kubernetes.io/canary-weight: "10"
spec:
  ingressClassName: nginx
  rules:
    - host: myapp.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: myapp-canary-svc
                port:
                  number: 80
```

---

### 6.5 Other Strategies (brief)

| Strategy | Description |
|---|---|
| **A/B Testing** | Route users to different versions based on headers, cookies, or user attributes (needs Ingress or service mesh) |
| **Shadow / Mirroring** | Copy live traffic to the new version without returning its responses to users (needs service mesh) |

---

## 7. Choosing a Strategy

| Situation | Recommended |
|---|---|
| Typical stateless web app | Rolling Update |
| Cannot run two versions together | Recreate |
| Need instant rollback, critical release | Blue/Green |
| Want to validate with real traffic gradually | Canary |
| Dev / test environment | Recreate or Rolling Update |

---

## 8. Best Practices

- Always define **readiness probes**; rolling updates depend on them to know when a Pod is ready.
- Set **resource requests and limits**.
- Use **specific image tags** (`myapp:1.4.2`), never `latest`.
- Keep `revisionHistoryLimit` reasonable so rollbacks are possible.
- Use `maxUnavailable: 0` with `maxSurge: 1` for zero-downtime updates.
- Store manifests in Git and apply them through CI/CD.
- Validate before applying: `kubectl apply --dry-run=server -f file.yaml`.

---

## 9. Quick Troubleshooting

```bash
kubectl rollout status deployment/<name>      # is the rollout stuck?
kubectl describe deployment <name>            # events and conditions
kubectl get pods -l app=<label>               # Pod states
kubectl describe pod <pod>                    # scheduling / image pull errors
kubectl logs <pod> --previous                 # logs from crashed container
kubectl rollout undo deployment/<name>        # roll back quickly
```

| Symptom | Common cause |
|---|---|
| `ImagePullBackOff` | Wrong image name/tag or missing registry credentials |
| `CrashLoopBackOff` | Application crashing; check logs |
| `Pending` | Not enough cluster resources or unmet scheduling constraints |
| Rollout stuck | Readiness probe failing on new Pods |
| Service has no endpoints | Service selector does not match Pod labels |
