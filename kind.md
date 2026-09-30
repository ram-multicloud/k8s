# Install kind on Windows

kind (Kubernetes IN Docker) runs each Kubernetes node as a Docker container, so you need a container runtime first.

```
Windows  ->  WSL2  ->  Docker Desktop  ->  kind  ->  Kubernetes cluster (nodes = containers)
                                              ^
                                           kubectl talks to the cluster
```

## Prerequisites

| Requirement | Notes |
|---|---|
| Windows 10 (64-bit) or Windows 11 | Virtualization enabled in BIOS/UEFI |
| WSL 2 | Backend used by Docker Desktop |
| Docker Desktop | kind needs Docker (or Podman) running |
| Admin PowerShell | For installing tools |
| 8 GB RAM recommended | More for multi-node clusters |

---

## Step 1: Enable WSL 2

Open **PowerShell as Administrator**:

```powershell
wsl --install
```

Restart the computer when prompted. Verify:

```powershell
wsl --status
```

---

## Step 2: Install Docker Desktop

Download from https://www.docker.com/products/docker-desktop/ and install, or use winget:

```powershell
winget install Docker.DockerDesktop
```

1. Start Docker Desktop.
2. Go to **Settings > General** and make sure **Use the WSL 2 based engine** is checked.
3. Wait until Docker shows **Engine running**.

Verify:

```powershell
docker version
docker run hello-world
```

---

## Step 3: Install kind

Pick **one** of the methods below.

### Option A: winget (recommended)

```powershell
winget install Kubernetes.kind
```

### Option B: Chocolatey

```powershell
choco install kind
```

### Option C: Download the binary manually

```powershell
curl.exe -Lo kind-windows-amd64.exe https://kind.sigs.k8s.io/dl/v0.33.0/kind-windows-amd64
New-Item -ItemType Directory -Force -Path C:\kind
Move-Item .\kind-windows-amd64.exe C:\kind\kind.exe
```

Add `C:\kind` to your PATH (current user):

```powershell
[Environment]::SetEnvironmentVariable("Path", $env:Path + ";C:\kind", "User")
```

> `v0.33.0` was the version in the kind docs when this was written. Check https://github.com/kubernetes-sigs/kind/releases for the latest and change the version in the URL.

**Close and reopen PowerShell**, then verify:

```powershell
kind version
```

---

## Step 4: Install kubectl

```powershell
winget install Kubernetes.kubectl
```

or

```powershell
choco install kubernetes-cli
```

Verify:

```powershell
kubectl version --client
```

---

## Step 5: Create a Cluster

### Single-node cluster

```powershell
kind create cluster --name dev
```

### Multi-node cluster (1 control plane + 2 workers)

Create a file named `kind-config.yaml`:

```yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
  - role: worker
  - role: worker
```

Create the cluster:

```powershell
kind create cluster --name dev --config kind-config.yaml
```

---

## Step 6: Verify the Cluster

```powershell
kind get clusters
kubectl cluster-info --context kind-dev
kubectl get nodes
kubectl get pods -A
```

Expected: all nodes show `Ready`.

```
NAME                STATUS   ROLES           AGE   VERSION
dev-control-plane   Ready    control-plane   1m    v1.xx.x
dev-worker          Ready    <none>          1m    v1.xx.x
dev-worker2         Ready    <none>          1m    v1.xx.x
```

You can also see the nodes as Docker containers:

```powershell
docker ps
```

---

## Step 7: Test with a Sample App

```powershell
kubectl create deployment nginx --image=nginx --replicas=2
kubectl get pods
kubectl expose deployment nginx --port=80 --type=ClusterIP
kubectl port-forward svc/nginx 8080:80
```

Open http://localhost:8080 in the browser to see the nginx welcome page. Press `Ctrl+C` to stop the port-forward.

---

## Step 8: Delete the Cluster

```powershell
kind delete cluster --name dev
```

---

## Useful Commands

| Command | Purpose |
|---|---|
| `kind create cluster --name <name>` | Create a cluster |
| `kind get clusters` | List clusters |
| `kind get nodes --name <name>` | List nodes of a cluster |
| `kind delete cluster --name <name>` | Delete a cluster |
| `kind load docker-image <image> --name <name>` | Load a local image into the cluster |
| `kubectl config get-contexts` | List kubectl contexts |
| `kubectl config use-context kind-<name>` | Switch context |

---

## Troubleshooting

| Problem | Fix |
|---|---|
| `kind` is not recognized | Reopen PowerShell after installing; check PATH |
| `Cannot connect to the Docker daemon` | Start Docker Desktop and wait for **Engine running** |
| Cluster creation hangs or times out | Give Docker more memory (Docker Desktop > Settings > Resources) |
| WSL 2 errors | Run `wsl --update`, enable virtualization in BIOS |
| Port already in use | Use a different local port in `port-forward` |
