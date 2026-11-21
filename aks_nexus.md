# Deploy Nexus Repository on AKS and Publish a Helm Package

## Overview

1. Create an AKS cluster
2. Install Nexus Repository Manager on AKS using its Helm chart
3. Expose Nexus and log in
4. Create a Helm **hosted** repository in Nexus
5. Create, package, and upload your own Helm chart
6. Add the Nexus repo to Helm and install from it

---

## Prerequisites

- Azure CLI (`az`), `kubectl`, `helm` v3 installed
- An Azure subscription and `az login` done

```bash
az login
az account set --subscription "<subscription-id>"
```

---

## 1. Create the AKS cluster

```bash
RG=rg-nexus-demo
LOC=centralindia
AKS=aks-nexus-demo

az group create -n $RG -l $LOC

az aks create \
  -g $RG -n $AKS \
  --node-count 2 \
  --node-vm-size Standard_D4s_v5 \
  --generate-ssh-keys

az aks get-credentials -g $RG -n $AKS --overwrite-existing
kubectl get nodes
```

> Nexus is memory hungry. Use nodes with at least 4 vCPU / 16 GB for comfortable operation.
> For a small lab, `Standard_D2s_v5` can work if you lower the JVM and resource settings (see values file).

---

## 2. Install Nexus using Helm

```bash
helm repo add sonatype https://sonatype.github.io/helm3-charts/
helm repo update
helm search repo sonatype/nexus-repository-manager

kubectl create namespace nexus
```

Create `nexus-values.yaml`:

```yaml
# nexus-values.yaml
nexus:
  resources:
    requests:
      cpu: 1
      memory: 4Gi
    limits:
      cpu: 2
      memory: 6Gi

persistence:
  enabled: true
  storageClass: managed-csi      # Azure Disk CSI (default on AKS)
  storageSize: 20Gi

service:
  type: LoadBalancer             # simplest for demo; use Ingress for production
```

> Chart values change between versions. Run `helm show values sonatype/nexus-repository-manager`
> and confirm key names before installing.

Install:

```bash
helm install nexus sonatype/nexus-repository-manager \
  -n nexus -f nexus-values.yaml

kubectl get pods -n nexus -w
```

Nexus takes a few minutes to start. Wait until the pod is `1/1 Running`.

---

## 3. Access Nexus

```bash
kubectl get svc -n nexus
# Note the EXTERNAL-IP of the nexus service (port 8081)
```

Open `http://<EXTERNAL-IP>:8081`.

No public IP? Port-forward instead:

```bash
kubectl port-forward -n nexus svc/nexus-nexus-repository-manager 8081:8081
# open http://localhost:8081
```

Get the initial admin password:

```bash
kubectl exec -n nexus deploy/nexus-nexus-repository-manager -- \
  cat /nexus-data/admin.password
```

Log in as `admin` and complete the setup wizard (set a new password).

---

## 4. Create a Helm hosted repository

### Option A: UI

Settings (gear icon) → Repository → Repositories → Create repository → **helm (hosted)**

- Name: `helm-hosted`
- Blob store: `default`
- Deployment policy: `Allow redeploy` (handy for testing) or `Disable redeploy` (production)

### Option B: REST API

```bash
NEXUS=http://<EXTERNAL-IP>:8081
PASS='<admin-password>'

curl -u admin:$PASS -X POST "$NEXUS/service/rest/v1/repositories/helm/hosted" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "helm-hosted",
    "online": true,
    "storage": {
      "blobStoreName": "default",
      "strictContentTypeValidation": true,
      "writePolicy": "ALLOW"
    }
  }'
```

Repository URL will be: `http://<EXTERNAL-IP>:8081/repository/helm-hosted/`

---

## 5. Create and package a Helm chart

```bash
helm create mychart
helm lint mychart
helm package mychart
# creates mychart-0.1.0.tgz
```

---

## 6. Publish the package to Nexus

Nexus helm hosted repos accept an HTTP PUT of the `.tgz`:

```bash
curl -u admin:$PASS \
  http://<EXTERNAL-IP>:8081/repository/helm-hosted/ \
  --upload-file mychart-0.1.0.tgz
```

Or with an explicit file name:

```bash
curl -u admin:$PASS -X PUT \
  http://<EXTERNAL-IP>:8081/repository/helm-hosted/mychart-0.1.0.tgz \
  --upload-file mychart-0.1.0.tgz
```

Verify in the UI: Browse → `helm-hosted` → you should see `mychart-0.1.0.tgz` and `index.yaml`.

> Use a dedicated user with the `nx-repository-view-helm-helm-hosted-*` privileges instead of `admin` for CI/CD.

---

## 7. Consume the chart from Nexus

```bash
helm repo add mynexus http://<EXTERNAL-IP>:8081/repository/helm-hosted/ \
  --username admin --password $PASS

helm repo update
helm search repo mynexus

helm install myapp mynexus/mychart -n demo --create-namespace
kubectl get pods -n demo
```

> Helm may refuse HTTP repos with credentials in some setups. If so, use `--pass-credentials`
> or (better) put Nexus behind an Ingress with TLS.

---

## Optional: Publish as OCI (Docker-type repo)

Helm 3.8+ supports OCI. In Nexus create a **docker (hosted)** repo with an HTTP/HTTPS connector (e.g. port 5000), expose that port, then:

```bash
helm registry login <nexus-host>:5000 -u admin
helm push mychart-0.1.0.tgz oci://<nexus-host>:5000/helm-charts
helm install myapp oci://<nexus-host>:5000/helm-charts/mychart --version 0.1.0
```

---

## Production hardening notes

- Put Nexus behind an **Ingress (NGINX) with TLS** (cert-manager + Let's Encrypt)
- Use a Premium or Standard SSD storage class, and take regular backups of `/nexus-data`
- Change default credentials, create role-based users, disable anonymous access if not needed
- Set JVM options and resources according to the Sonatype sizing guide
- Consider Azure Blob as an external blob store if your Nexus edition supports it

---

## Troubleshooting

| Problem | Check |
|---|---|
| Pod stuck `Pending` | `kubectl describe pod -n nexus` (PVC bound? enough node memory?) |
| Pod `CrashLoopBackOff` / OOMKilled | Raise memory limits or use larger nodes |
| `admin.password` file not found | Password was already changed; reset via Nexus console |
| `401` on upload | Wrong credentials or missing privileges on the repo |
| `400` on upload | Redeploy policy disallows overwriting the same version, bump chart version |
| Helm repo add fails | Confirm URL ends with `/` and the pod is ready |

---

## Cleanup

```bash
helm uninstall nexus -n nexus
az group delete -n rg-nexus-demo --yes --no-wait
```
