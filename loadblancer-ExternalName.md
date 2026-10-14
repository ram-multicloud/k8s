# Kubernetes LoadBalancer and ExternalName Services

A practical guide: what they are, when to use them, and how to deploy and validate them on a kubeadm cluster.

---

## 1. The Big Picture

| | LoadBalancer | ExternalName |
|---|---|---|
| Question it answers | "How do users **outside** reach my app?" | "How do Pods **inside** reach something outside?" |
| Direction | Outside → cluster | Cluster → outside |
| What it creates | An external IP in front of your Pods | A DNS alias (CNAME) only |
| Has selector / Pods | Yes | No |
| Has ClusterIP | Yes | No |
| Proxies traffic | Yes (L4) | No, DNS only |

---

## 2. LoadBalancer

### What it is

A `LoadBalancer` Service exposes your app outside the cluster through an external IP. Kubernetes asks an external system to provide that IP:

- **Cloud (AWS, Azure, GCP):** the cloud controller creates a real load balancer.
- **kubeadm / bare metal:** nothing creates it by default, so `EXTERNAL-IP` stays `<pending>`. Install **MetalLB** to hand out IPs from your own network.

It builds on the other types: every LoadBalancer Service also gets a ClusterIP and a NodePort.

```
Client → EXTERNAL-IP → Node (NodePort) → Service (ClusterIP) → Pods
```

### Use cases

- Expose a web app or API directly to users or other networks.
- Expose non-HTTP TCP/UDP services (databases, game servers, MQTT).
- The entry point for an Ingress controller (Traefik, HAProxy, etc.).

> One LoadBalancer Service means one external IP (one cloud bill). For many HTTP apps, use one LoadBalancer for an Ingress controller and route with Ingress rules instead.

### Example

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
  namespace: demo
spec:
  replicas: 3
  selector:
    matchLabels:
      app: web
  template:
    metadata:
      labels:
        app: web
    spec:
      containers:
        - name: nginx
          image: nginx:1.27
          ports:
            - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: web-lb
  namespace: demo
spec:
  type: LoadBalancer
  selector:
    app: web
  ports:
    - port: 80          # port on the external IP
      targetPort: 80    # container port
```

### Deploy

```bash
kubectl create namespace demo
kubectl apply -f lb.yaml
kubectl get svc -n demo
```

### Validate

```bash
# 1. Pods are running and the Service has endpoints
kubectl get pods -n demo -o wide
kubectl get endpoints web-lb -n demo

# 2. EXTERNAL-IP is assigned (not <pending>)
kubectl get svc web-lb -n demo

# 3. Access from outside
curl http://<EXTERNAL-IP>

# 4. Access by DNS from inside the cluster
kubectl run client -n demo --rm -it --image=busybox:1.36 --restart=Never -- wget -qO- http://web-lb
```

Expected: the nginx welcome page.

### kubeadm: fixing `<pending>`

Install MetalLB and give it an IP pool in your node subnet (unused IPs):

```bash
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.16.1/config/manifests/metallb-native.yaml
kubectl wait -n metallb-system --for=condition=ready pod --selector=app=metallb --timeout=120s
```

```yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: lab-pool
  namespace: metallb-system
spec:
  addresses:
    - 192.168.1.240-192.168.1.250
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: lab-l2
  namespace: metallb-system
spec:
  ipAddressPools:
    - lab-pool
```

If kube-proxy runs in IPVS mode, enable `strictARP: true` in the `kube-proxy` ConfigMap first. Open port 7946 between nodes.

Without MetalLB you can still test through the NodePort: `curl http://<NODE-IP>:<NODEPORT>` (shown in `kubectl get svc`, e.g. `80:32444/TCP`).

---

## 3. ExternalName

### What it is

An `ExternalName` Service is a **DNS alias** inside the cluster. When a Pod looks up the Service name, CoreDNS returns a CNAME to an external hostname. There is no ClusterIP, no Pods, no proxying and no port mapping.

```
Pod → external-db (cluster DNS) → CNAME → mydb.abc123.us-east-1.rds.amazonaws.com
```

### Use cases

- **External database or API:** apps use a stable internal name (`external-db`) instead of the real hostname (managed DB, SaaS API).
- **Migration:** start with an external service, later move it into the cluster by replacing the Service with a normal one of the same name. Apps do not change.
- **Environment switching:** a different `externalName` per namespace (dev, staging, prod).
- **Cross-namespace alias:** point to `redis.platform.svc.cluster.local`.

### Example

```yaml
apiVersion: v1
kind: Service
metadata:
  name: external-site
  namespace: demo
spec:
  type: ExternalName
  externalName: httpbin.org
```

For a real database it would look like this, and the app config would use `DB_HOST=external-db`:

```yaml
spec:
  type: ExternalName
  externalName: mydb.abc123.us-east-1.rds.amazonaws.com
```

### Deploy

```bash
kubectl apply -f externalname.yaml
kubectl get svc external-site -n demo
```

Expected output (`CLUSTER-IP` and `PORT(S)` show `<none>`, and `EXTERNAL-IP` holds the target hostname):

```
NAME            TYPE           CLUSTER-IP   EXTERNAL-IP   PORT(S)   AGE
external-site   ExternalName   <none>       httpbin.org   <none>    5s
```

### Validate

```bash
# 1. DNS: should show a CNAME to httpbin.org
kubectl run client -n demo --rm -it --image=busybox:1.36 --restart=Never -- nslookup external-site

# 2. Connectivity: send the real hostname in the Host header
kubectl run client -n demo --rm -it --image=curlimages/curl --restart=Never -- \
  curl -s -H "Host: httpbin.org" http://external-site/get
```

Expected: a CNAME answer, then a JSON response from httpbin.

### Limitations

- `externalName` must be a **DNS name**, not an IP address. For an IP, use a Service without selector plus an EndpointSlice.
- **Only works inside the cluster.** Your laptop cannot resolve or reach `external-site`.
- DNS only: no load balancing, no health checks, no port remapping.
- **Host header / TLS:** the client sends `external-site` as the hostname, so HTTPS certificate checks and virtual-hosted sites can fail. Send the real `Host` header, or connect with the real hostname.

### Accessing it from your local machine

Run a small proxy Pod in the cluster that forwards to `external-site`, then port-forward to the proxy.

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: ext-proxy-conf
  namespace: demo
data:
  default.conf: |
    server {
      listen 80;
      location / {
        proxy_pass http://external-site.demo.svc.cluster.local;
        proxy_set_header Host httpbin.org;
      }
    }
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ext-proxy
  namespace: demo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ext-proxy
  template:
    metadata:
      labels:
        app: ext-proxy
    spec:
      containers:
        - name: nginx
          image: nginx:1.27
          ports:
            - containerPort: 80
          volumeMounts:
            - name: conf
              mountPath: /etc/nginx/conf.d
      volumes:
        - name: conf
          configMap:
            name: ext-proxy-conf
```

```bash
kubectl port-forward -n demo deploy/ext-proxy 8080:80
curl http://localhost:8080/get      # in another terminal
```

---

## 4. DNS Names in the Cluster

CoreDNS names every Service `<service>.<namespace>.svc.cluster.local`.

| Service type | What DNS returns |
|---|---|
| ClusterIP / LoadBalancer | A record with the ClusterIP |
| Headless (`clusterIP: None`) | The IPs of all Pods |
| ExternalName | CNAME to the external hostname |

```bash
web-lb                                 # same namespace
web-lb.demo                            # from another namespace
web-lb.demo.svc.cluster.local          # full name
```

These names resolve **only inside the cluster**. A LoadBalancer's external IP gets no public DNS name automatically: add a DNS record or hosts-file entry pointing to the `EXTERNAL-IP`, or use ExternalDNS.

---

## 5. Which One Should I Use?

| Need | Use |
|---|---|
| Users outside the cluster must reach my app | **LoadBalancer** |
| Many HTTP apps behind one IP | One LoadBalancer + **Ingress** |
| Pods need a friendly name for an external DB or API | **ExternalName** |
| Pods need Pod IPs directly (StatefulSets, clustering) | Headless Service |

---

## 6. Troubleshooting

| Symptom | Check |
|---|---|
| LoadBalancer `EXTERNAL-IP` is `<pending>` | No provider on kubeadm: install MetalLB and apply the IPAddressPool and L2Advertisement |
| External IP assigned but unreachable | The pool must be in the node subnet; check `strictARP` for IPVS; open port 7946 |
| `endpoints` is empty | Service selector does not match Pod labels |
| ExternalName does not resolve | `kubectl get svc`, then test with `nslookup` from a Pod; check CoreDNS pods in `kube-system` |
| ExternalName resolves but HTTP fails | Send the real `Host` header; check outbound internet from the Pods |

---

## 7. Cleanup

```bash
kubectl delete namespace demo
```
