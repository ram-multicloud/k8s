# Kubernetes ReplicationController (RC) and ReplicaSet (RS)

## ReplicationController (RC)

```yaml
apiVersion: v1
kind: ReplicationController
metadata:
  name: nopcommerce-rc
  labels:
    app: nopcommerce
spec:
  replicas: 3
  selector:
    app: nopcommerce
  template:
    metadata:
      labels:
        app: nopcommerce
    spec:
      containers:
      - name: nopcommerce-container
        image: httpd:latest
        ports:
        - containerPort: 80
        resources:
          limits:
            memory: "512Mi"
            cpu: "500m"
          requests:
            memory: "256Mi"
            cpu: "250m"
```

### Create RC

```bash
kubectl apply -f rc.yaml
```

### View RC

```bash
kubectl get rc
```

---

## ReplicaSet (RS)

```yaml
apiVersion: apps/v1
kind: ReplicaSet
metadata:
  name: nopcommerce-rs
  labels:
    app: nopcommerce
spec:
  replicas: 3
  selector:
    matchLabels:
      app: nopcommerce
  template:
    metadata:
      labels:
        app: nopcommerce
    spec:
      containers:
      - name: nopcommerce-container
        image: httpd:latest
        ports:
        - containerPort: 80
        resources:
          limits:
            memory: "512Mi"
            cpu: "500m"
          requests:
            memory: "256Mi"
            cpu: "250m"
```

### Create RS

```bash
kubectl apply -f rs.yaml
```

### View RS

```bash
kubectl get rs
```

---

## RC vs RS

| Feature | ReplicationController | ReplicaSet |
|----------|----------------------|------------|
| API Version | v1 | apps/v1 |
| Selector Support | Equality-based only | Equality + Set-based |
| Used By Deployment | No | Yes |
| Recommended | No | Yes |
| Current Usage | Legacy | Modern Kubernetes |

### Common Commands

```bash
kubectl get pods
kubectl get rc
kubectl get rs
kubectl describe rc nopcommerce-rc
kubectl describe rs nopcommerce-rs
kubectl delete rc nopcommerce-rc
kubectl delete rs nopcommerce-rs
```

**Note:** In modern Kubernetes, **Deployment → ReplicaSet → Pods** is the recommended approach instead of using ReplicationController directly.
