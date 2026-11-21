# Azure Kubernetes Service (AKS) Guide

## What is Azure Kubernetes Service (AKS)?
Azure Kubernetes Service (AKS) is Microsoft's managed Kubernetes platform on Azure. AKS reduces the operational overhead of managing Kubernetes by handling control plane management, upgrades, monitoring integration, and scaling capabilities.

### Key Benefits
- Managed Kubernetes control plane
- Automatic scaling and upgrades
- Azure AD integration
- Integrated monitoring with Azure Monitor
- Load balancing and ingress support
- High availability and security features
- Cost optimization with node pools

## AKS Architecture
- Control Plane: Managed by Azure
- Worker Nodes: Virtual machines running containers
- Node Pools: Group of worker nodes
- Pods: Smallest deployable units
- Services: Network access to applications
- Ingress: External HTTP/HTTPS routing

## Prerequisites
1. Azure Subscription
2. Azure Portal access
3. Azure CLI installed locally
4. kubectl installed

## Create AKS Using Azure Portal

### Step 1: Sign in
1. Open https://portal.azure.com
2. Sign in with your Azure account.

### Step 2: Create AKS Cluster
1. Search for 'Kubernetes services'.
2. Click 'Create'.
3. Select 'Create Kubernetes cluster'.

### Step 3: Basics Tab
Fill in:
- Subscription
- Resource Group
- Kubernetes Cluster Name
- Region
- Availability Zones (optional)
- Kubernetes Version
- Node Size (VM Size)
- Node Count

### Step 4: Node Pools
1. Configure system node pool.
2. Set VM size.
3. Configure autoscaling if needed.

### Step 5: Authentication
1. Enable Microsoft Entra ID (recommended).
2. Configure RBAC.

### Step 6: Networking
1. Choose Azure CNI Overlay or Azure CNI.
2. Configure network settings.
3. Enable private cluster if required.

### Step 7: Monitoring
1. Enable Azure Monitor.
2. Enable Container Insights.

### Step 8: Review and Create
1. Validate configuration.
2. Click Create.
3. Wait for deployment to complete.

## Connect to AKS from Local Machine

### Install Azure CLI
Verify installation:

```bash
az version
```

### Login to Azure

```bash
az login
```

### Install kubectl

```bash
kubectl version --client
```

### Get AKS Credentials
Replace values with your resource group and cluster name.

```bash
az aks get-credentials   --resource-group myResourceGroup   --name myAKSCluster
```

### Verify Connection

```bash
kubectl get nodes
```

Expected output shows AKS worker nodes.

### View Cluster Information

```bash
kubectl cluster-info
```

### List Pods

```bash
kubectl get pods -A
```

## Deploy a Sample Application

```bash
kubectl create deployment nginx --image=nginx
kubectl expose deployment nginx --port=80 --type=LoadBalancer
```

Check service:

```bash
kubectl get svc
```

## Useful AKS Commands

```bash
kubectl get nodes
kubectl get pods -A
kubectl get deployments
kubectl describe pod <pod-name>
kubectl logs <pod-name>
```

## Troubleshooting

### Context Check
```bash
kubectl config current-context
```

### Check Cluster Access
```bash
kubectl get nodes
```

### Re-download Credentials
```bash
az aks get-credentials --resource-group myResourceGroup --name myAKSCluster --overwrite-existing
```

