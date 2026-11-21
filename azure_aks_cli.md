# AKS Cluster Creation (Azure CLI) and Nexus Deployment with a Public Load Balancer

## 1. What we are building

```
Internet --> Azure Public Load Balancer (public IP :8081)
                 --> Kubernetes Service (type: LoadBalancer)
                       --> Nexus Pod (sonatype/nexus3, port 8081)
                             --> PersistentVolumeClaim (Azure Disk)
```

- **AKS** = Azure Kubernetes Service. Azure runs the control plane (API server, etcd, scheduler) for you; you only pay for and manage the worker nodes (node pool).
- **Service type LoadBalancer** on AKS automatically creates a rule on the cluster's **Standard Azure Load Balancer** and assigns a **public IP**. That is how Nexus becomes reachable from the internet.
- **Nexus** is an artifact repository (Maven, Docker, npm, etc.). It stores data in `/nexus-data`, so it needs persistent storage.

---

## 2. Prerequisites

- Azure subscription
- Azure CLI installed (`az --version`)
- `kubectl` installed (or install via `az aks install-cli`)

```bash
# Login and select subscription
az login
az account list -o table
az account set --subscription "<subscription-id-or-name>"

# Make sure required providers are registered (usually already are)
az provider register --namespace Microsoft.ContainerService
az provider register --namespace Microsoft.Network
az provider register --namespace Microsoft.Compute
```

---

## 3. Create the AKS cluster using CLI

### 3.1 Set variables
```bash
az vm list-skus -l centralindia --size Standard_D2s -o table # get list size suppourt
```
```bash
RG=rg-aks-demo
LOCATION=centralindia
CLUSTER=aks-nexus-demo
NODE_COUNT=2
NODE_SIZE=Standard_D2s_v4     # 2 vCPU / 8 GB. Nexus needs ~4 GB RAM minimum
```

### 3.2 Create resource group

```bash
az group create --name $RG --location $LOCATION
```

### 3.3 Create the cluster

```bash
az aks create \
  --resource-group $RG \
  --name $CLUSTER \
  --node-count $NODE_COUNT \
  --node-vm-size $NODE_SIZE \
  --network-plugin azure \
  --load-balancer-sku standard \
  --enable-managed-identity \
  --generate-ssh-keys
```

What the important flags mean:

| Flag | Meaning |
|------|---------|
| `--node-count` | Number of worker nodes in the default (system) node pool |
| `--node-vm-size` | VM size of the nodes. Pick one with enough RAM for Nexus |
| `--network-plugin azure` | Azure CNI: pods get VNet IPs. (`kubenet` is the older alternative) |
| `--load-balancer-sku standard` | Standard SKU LB (default). Required for public IPs of type LoadBalancer services |
| `--enable-managed-identity` | Cluster uses a managed identity instead of a service principal secret |
| `--generate-ssh-keys` | Creates SSH keys in `~/.ssh` for node access if none exist |

Optional extras:

```bash
--kubernetes-version 1.30        # pin a version (check: az aks get-versions -l $LOCATION -o table)
--zones 1 2 3                    # spread nodes across availability zones
--enable-cluster-autoscaler --min-count 1 --max-count 3
--tier free                      # free control plane tier (no SLA)
```

Creation takes about 5 to 10 minutes.

### 3.4 Connect kubectl to the cluster

```bash
alias kubectl='"/c/Program Files/Docker/Docker/resources/bin/kubectl.exe"'
echo "alias kubectl='\"/c/Program Files/Docker/Docker/resources/bin/kubectl.exe\"'" >> ~/.bashrc

kubectl version --client
az aks get-credentials --resource-group $RG --name $CLUSTER --overwrite-existing

kubectl get nodes -o wide
kubectl get pods -A
```

All nodes should be `Ready`.

> Behind the scenes Azure also creates a second resource group named `MC_<rg>_<cluster>_<location>` (the node resource group). It holds the VMSS, VNet, NSG, **Load Balancer** and **public IPs**.

---

## 4. Deploy Nexus with a public Load Balancer

### 4.1 Namespace

```bash
kubectl create namespace nexus
```

### 4.2 Persistent volume claim (Azure Disk)

AKS ships with storage classes. Check them:

```bash
kubectl get storageclass
```

`managed-csi` (Azure Disk) is normally available.

`nexus-pvc.yaml`

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: nexus-data
  namespace: nexus
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: managed-csi
  resources:
    requests:
      storage: 20Gi
```

### 4.3 Deployment

`nexus-deployment.yaml`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nexus
  namespace: nexus
  labels:
    app: nexus
spec:
  replicas: 1                 # Nexus OSS is single instance
  strategy:
    type: Recreate            # RWO disk cannot be attached to two pods at once
  selector:
    matchLabels:
      app: nexus
  template:
    metadata:
      labels:
        app: nexus
    spec:
      securityContext:
        fsGroup: 200          # nexus user in the image has UID/GID 200
      containers:
        - name: nexus
          image: sonatype/nexus3:latest
          ports:
            - containerPort: 8081
          resources:
            requests:
              cpu: "500m"
              memory: "2Gi"
            limits:
              cpu: "2"
              memory: "4Gi"
          readinessProbe:
            httpGet:
              path: /service/rest/v1/status
              port: 8081
            initialDelaySeconds: 60
            periodSeconds: 15
          livenessProbe:
            httpGet:
              path: /service/rest/v1/status
              port: 8081
            initialDelaySeconds: 120
            periodSeconds: 30
          volumeMounts:
            - name: nexus-data
              mountPath: /nexus-data
      volumes:
        - name: nexus-data
          persistentVolumeClaim:
            claimName: nexus-data
```

Notes:
- `fsGroup: 200` fixes the common `Permission denied` error on `/nexus-data`.
- `strategy: Recreate` avoids a stuck rollout where the new pod cannot mount the disk the old pod still holds.
- Pin an exact image tag (for example `sonatype/nexus3:3.xx.x`) instead of `latest` for real use.

### 4.4 Service of type LoadBalancer (this creates the public LB)

`nexus-service.yaml`

```yaml
apiVersion: v1
kind: Service
metadata:
  name: nexus-svc
  namespace: nexus
  annotations:
    # Optional: health probe path used by the Azure LB
    service.beta.kubernetes.io/azure-load-balancer-health-probe-request-path: /service/rest/v1/status
spec:
  type: LoadBalancer
  selector:
    app: nexus
  ports:
    - name: http
      port: 8081          # port on the public LB
      targetPort: 8081    # container port
      protocol: TCP
```

To expose on port 80 instead, set `port: 80` and keep `targetPort: 8081`.

### 4.5 Apply everything

```bash
kubectl apply -f nexus-pvc.yaml
kubectl apply -f nexus-deployment.yaml
kubectl apply -f nexus-service.yaml
```

### 4.6 Verify

```bash
kubectl get pvc -n nexus            # STATUS should be Bound
kubectl get pods -n nexus -w        # wait for 1/1 Running (first start takes 1 to 3 min)
kubectl get svc -n nexus -w         # wait until EXTERNAL-IP changes from <pending> to an IP
```

Example output:

```
NAME        TYPE           CLUSTER-IP     EXTERNAL-IP     PORT(S)          AGE
nexus-svc   LoadBalancer   10.0.123.45    20.xx.xx.xx     8081:31234/TCP   2m
```

Open in browser: `http://<EXTERNAL-IP>:8081`

### 4.7 Get the initial admin password

```bash
kubectl exec -n nexus deploy/nexus -- sh -c 'cat /nexus-data/admin.password'
```

Login as `admin` with that password. Nexus will ask you to set a new password and deletes the file afterwards.

---

## 5. Optional: use a static public IP

By default the public IP is dynamic and is released if the service is deleted. To keep a fixed IP:

```bash
NODE_RG=$(az aks show -g $RG -n $CLUSTER --query nodeResourceGroup -o tsv)

az network public-ip create \
  --resource-group $NODE_RG \
  --name nexus-public-ip \
  --sku Standard \
  --allocation-method Static

az network public-ip show -g $NODE_RG -n nexus-public-ip --query ipAddress -o tsv
```

Then add to the Service:

```yaml
spec:
  type: LoadBalancer
  loadBalancerIP: <the-static-ip>
```

and add the annotation:

```yaml
metadata:
  annotations:
    service.beta.kubernetes.io/azure-load-balancer-resource-group: <NODE_RG value>
```

(If you create the IP in a different resource group than the node RG, grant the cluster identity Network Contributor on it.)

---

## 6. How the public LB flow works

1. You create a `Service` with `type: LoadBalancer`.
2. The **cloud-controller-manager** in AKS sees it and talks to Azure.
3. Azure allocates a **public IP** and adds a **frontend IP configuration**, **load balancing rule** (8081 -> NodePort) and a **health probe** on the Standard Load Balancer in the node resource group.
4. The LB sends traffic to the nodes on the NodePort, and `kube-proxy` forwards it to the Nexus pod on 8081.
5. The IP appears in `EXTERNAL-IP` of the service.

---

## 7. Troubleshooting

| Problem | Check / Fix |
|---------|-------------|
| `EXTERNAL-IP` stuck on `<pending>` | `kubectl describe svc nexus-svc -n nexus` and look at events. Check public IP quota in the region and the cluster identity permissions |
| PVC stays `Pending` | `kubectl describe pvc -n nexus`. Verify storage class name with `kubectl get sc` |
| Pod `CrashLoopBackOff` with permission errors | Make sure `fsGroup: 200` is set |
| Pod `OOMKilled` / restarts | Increase memory limit or use a bigger node size (Nexus needs about 4 GB) |
| Pod Running but browser times out | Wait for startup (readiness). Check NSG on the node subnet allows inbound 8081. AKS normally adds this automatically |
| Logs | `kubectl logs -n nexus deploy/nexus -f` |
| Pod events | `kubectl describe pod -n nexus -l app=nexus` |

---

## 8. Security note

Exposing Nexus directly over HTTP on a public IP is fine for learning but not for production. For real use:
- Put it behind an **Ingress controller** with **TLS** (cert-manager + Let's Encrypt).
- Restrict access with `loadBalancerSourceRanges` in the Service:

```yaml
spec:
  type: LoadBalancer
  loadBalancerSourceRanges:
    - 203.0.113.10/32
```

- Or use an internal load balancer with the annotation `service.beta.kubernetes.io/azure-load-balancer-internal: "true"`.

---

## 9. Cleanup (to avoid charges)

```bash
# Remove only Nexus (this also releases the public IP)
kubectl delete namespace nexus

# Stop the cluster temporarily
az aks stop -g $RG -n $CLUSTER
az aks start -g $RG -n $CLUSTER

# Delete everything
az group delete --name $RG --yes --no-wait
```

---

## 10. Quick command summary

```bash
az group create -n rg-aks-demo -l centralindia
az aks create -g rg-aks-demo -n aks-nexus-demo --node-count 2 \
  --node-vm-size Standard_D2s_v3 --generate-ssh-keys
az aks get-credentials -g rg-aks-demo -n aks-nexus-demo

kubectl create ns nexus
kubectl apply -f nexus-pvc.yaml -f nexus-deployment.yaml -f nexus-service.yaml
kubectl get svc -n nexus -w
kubectl exec -n nexus deploy/nexus -- cat /nexus-data/admin.password
```

