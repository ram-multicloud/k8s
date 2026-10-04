# Installing a Kubernetes Cluster with kubeadm

A step-by-step guide to build a multi-node Kubernetes cluster (1 control plane + N worker nodes) using `kubeadm`, `containerd` and a CNI plugin.

---

## 1. Architecture

```
                +-------------------------+
                |  Control Plane Node     |
                |  kube-apiserver         |
                |  etcd                   |
                |  scheduler              |
                |  controller-manager     |
                |  kubelet + containerd   |
                +-----------+-------------+
                            |
          +-----------------+-----------------+
          |                                   |
+---------+----------+             +----------+---------+
|  Worker Node 1     |             |  Worker Node 2     |
|  kubelet           |             |  kubelet           |
|  kube-proxy        |             |  kube-proxy        |
|  containerd        |             |  containerd        |
+--------------------+             +--------------------+
```

| Component | Role |
|---|---|
| `kubeadm` | Bootstraps the cluster (`init`, `join`, `reset`, `upgrade`) |
| `kubelet` | Node agent; runs pods on every node |
| `kubectl` | CLI to talk to the cluster |
| `containerd` | Container runtime (CRI) |
| CNI plugin | Pod networking (Calico / Flannel / Cilium) |

---

## 2. Prerequisites

| Requirement | Control Plane | Worker |
|---|---|---|
| OS | Ubuntu 22.04 / 24.04 (or similar Linux) | same |
| CPU | 2 vCPU minimum | 2 vCPU minimum |
| RAM | 2 GB minimum (4 GB recommended) | 2 GB minimum |
| Disk | 20 GB+ | 20 GB+ |
| Network | Full connectivity between all nodes | same |
| Unique | Hostname, MAC address, `product_uuid` | same |
| Swap | **Disabled** | **Disabled** |

> On AWS / Azure, create the VMs in the same VPC / VNet and open the ports below in the Security Group / NSG.

### Ports to open

**Control plane**

| Port | Protocol | Purpose | Used by |
|---|---|---|---|
| 6443 | TCP | Kubernetes API server | All |
| 2379-2380 | TCP | etcd client / peer | kube-apiserver, etcd |
| 10250 | TCP | Kubelet API | Self, control plane |
| 10259 | TCP | kube-scheduler | Self |
| 10257 | TCP | kube-controller-manager | Self |

**Worker nodes**

| Port | Protocol | Purpose | Used by |
|---|---|---|---|
| 10250 | TCP | Kubelet API | Self, control plane |
| 10256 | TCP | kube-proxy | Self, load balancers |
| 30000-32767 | TCP | NodePort Services | All |

> Also allow the ports required by your CNI (e.g. Calico: TCP 179, UDP 4789 / IP-in-IP protocol 4).

---

## 3. Steps on ALL nodes (control plane + workers)

Run everything in this section on **every** node.

### Step 1: Set hostname and hosts file

```bash
sudo hostnamectl set-hostname <controlplane | worker1 | worker2>
```

Add entries on every node (use your private IPs):

```bash
sudo tee -a /etc/hosts <<EOF
10.0.0.10 controlplane
10.0.0.11 worker1
10.0.0.12 worker2
EOF
```

Verify uniqueness:

```bash
ip link
sudo cat /sys/class/dmi/id/product_uuid
```

### Step 2: Disable swap

The kubelet will not start with swap enabled (default behaviour).

```bash
sudo swapoff -a
sudo sed -i '/ swap / s/^/#/' /etc/fstab
free -h        # Swap should show 0
```

### Step 3: Load kernel modules

```bash
sudo tee /etc/modules-load.d/k8s.conf <<EOF
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter
```

### Step 4: Set sysctl parameters

```bash
sudo tee /etc/sysctl.d/k8s.conf <<EOF
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sudo sysctl --system
```

Verify:

```bash
lsmod | grep -E 'overlay|br_netfilter'
sysctl net.bridge.bridge-nf-call-iptables net.ipv4.ip_forward
```

### Step 5: Install containerd

```bash
sudo apt-get update
sudo apt-get install -y containerd
```

Generate the default config and enable the **systemd cgroup driver**:

```bash
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

sudo systemctl restart containerd
sudo systemctl enable containerd
systemctl status containerd --no-pager
```

> **Why SystemdCgroup?** kubelet and containerd must use the same cgroup driver. On systemd-based distros, `systemd` is the recommended driver. A mismatch causes pods to crash-loop.

### Step 6: Install kubeadm, kubelet, kubectl

Set the Kubernetes minor version you want (check the latest supported release at <https://kubernetes.io/releases/>):

```bash
export K8S_VERSION=v1.34
```

Add the Kubernetes apt repository:

```bash
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl gpg

sudo mkdir -p -m 755 /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/${K8S_VERSION}/deb/Release.key \
  | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${K8S_VERSION}/deb/ /" \
  | sudo tee /etc/apt/sources.list.d/kubernetes.list
```

Install and pin the versions:

```bash
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl
sudo systemctl enable --now kubelet
```

Verify:

```bash
kubeadm version
kubectl version --client
```

> The kubelet will restart every few seconds until `kubeadm init` / `join` gives it instructions. This is expected.

---

## 4. Steps on the CONTROL PLANE node only

### Step 7: Initialize the cluster

Pick a Pod network CIDR that does **not** overlap with your VPC/VNet range.

| CNI | Default Pod CIDR |
|---|---|
| Calico | `192.168.0.0/16` |
| Flannel | `10.244.0.0/16` |

```bash
sudo kubeadm init \
  --pod-network-cidr=10.244.0.0/16 \
  --apiserver-advertise-address=<CONTROL_PLANE_PRIVATE_IP>
```

On success, the output ends with a `kubeadm join ...` command. **Copy it** — workers need it.

### Step 8: Configure kubectl access

```bash
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

Check:

```bash
kubectl get nodes
kubectl get pods -A
```

The control plane shows `NotReady` and CoreDNS stays `Pending` until a CNI is installed.

### Step 9: Install a CNI plugin

**Option A: Flannel** (simple, matches `10.244.0.0/16`)

```bash
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
```

**Option B: Calico** (supports NetworkPolicy; use `192.168.0.0/16` or edit the CIDR in the manifest)

```bash
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.30.0/manifests/calico.yaml
```

> Check the CNI project's documentation for the latest manifest version.

Wait until everything is `Running`:

```bash
kubectl get pods -A -w
kubectl get nodes
```

---

## 5. Steps on WORKER nodes only

### Step 10: Join the cluster

Run the join command printed by `kubeadm init` (as root / with `sudo`):

```bash
sudo kubeadm join <CONTROL_PLANE_IP>:6443 \
  --token <token> \
  --discovery-token-ca-cert-hash sha256:<hash>
```

**Lost the join command or token expired** (tokens last 24 hours)? Generate a new one on the control plane:

```bash
kubeadm token create --print-join-command
```

---

## 6. Verify the cluster (control plane)

```bash
kubectl get nodes -o wide
kubectl get pods -A
kubectl cluster-info
```

Expected:

```
NAME           STATUS   ROLES           AGE   VERSION
controlplane   Ready    control-plane   10m   v1.34.x
worker1        Ready    <none>          3m    v1.34.x
worker2        Ready    <none>          3m    v1.34.x
```

Optionally label workers:

```bash
kubectl label node worker1 node-role.kubernetes.io/worker=
kubectl label node worker2 node-role.kubernetes.io/worker=
```

### Smoke test

```bash
kubectl create deployment nginx --image=nginx --replicas=2
kubectl expose deployment nginx --type=NodePort --port=80
kubectl get pods -o wide
kubectl get svc nginx
```

Open `http://<any-node-ip>:<nodeport>` in a browser (NodePort must be allowed in the Security Group / NSG).

Clean up:

```bash
kubectl delete svc nginx
kubectl delete deployment nginx
```

---

## 7. Command summary

| Step | Where | Action |
|---|---|---|
| 1 | All | Set hostname, `/etc/hosts` |
| 2 | All | Disable swap |
| 3 | All | Load `overlay`, `br_netfilter` modules |
| 4 | All | Set sysctl networking params |
| 5 | All | Install containerd (`SystemdCgroup = true`) |
| 6 | All | Install kubeadm, kubelet, kubectl |
| 7 | Control plane | `kubeadm init` |
| 8 | Control plane | Configure `~/.kube/config` |
| 9 | Control plane | Install CNI |
| 10 | Workers | `kubeadm join` |
| 11 | Control plane | Verify nodes and pods |

---

## 8. Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `kubeadm init` preflight fails on swap | Swap still on | `swapoff -a`, edit `/etc/fstab` |
| Preflight: `bridge-nf-call-iptables` missing | Modules/sysctl not set | Redo Steps 3 and 4 |
| Node stays `NotReady` | No CNI installed or CNI pods failing | Install CNI; `kubectl get pods -n kube-system` |
| CoreDNS `Pending` | CNI not installed | Apply CNI manifest |
| Pods crash-loop, kubelet restarts | Cgroup driver mismatch | Set `SystemdCgroup = true`, restart containerd and kubelet |
| `join` times out | Port 6443 blocked or wrong IP | Check Security Group/NSG, firewall, connectivity (`nc -vz <ip> 6443`) |
| `join` token invalid | Token expired | `kubeadm token create --print-join-command` |
| `The connection to the server localhost:8080 was refused` | kubeconfig not set | Redo Step 8 |
| Pod CIDR conflict | Pod CIDR overlaps VPC range | `kubeadm reset` and re-init with a different CIDR |

Useful debug commands:

```bash
journalctl -u kubelet -f
journalctl -u containerd -f
sudo crictl ps -a
kubectl describe node <node>
kubectl get events -A --sort-by=.metadata.creationTimestamp
```

---

## 9. Reset a node (start over)

Run on the node you want to wipe:

```bash
sudo kubeadm reset -f
sudo rm -rf /etc/cni/net.d $HOME/.kube/config
sudo iptables -F && sudo iptables -t nat -F && sudo iptables -t mangle -F && sudo iptables -X
sudo systemctl restart containerd
```

To remove a worker from the cluster properly, run on the control plane first:

```bash
kubectl drain <node> --ignore-daemonsets --delete-emptydir-data
kubectl delete node <node>
```

---

## 10. Quick revision questions

1. Why must swap be disabled for the kubelet?
2. What do `overlay` and `br_netfilter` modules do?
3. Why is `SystemdCgroup = true` required in containerd?
4. Why does the node show `NotReady` before a CNI is installed?
5. How do you regenerate a join command after the token expires?
6. What happens if the Pod CIDR overlaps with the VPC CIDR?
