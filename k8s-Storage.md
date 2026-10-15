# Kubernetes Storage: Concepts, Types and Examples

## 1. Why Storage Matters in Kubernetes

Containers are **ephemeral**. When a container restarts, everything written to its filesystem is lost. Pods can also be rescheduled to a different node at any time. Kubernetes storage solves two problems:

1. **Persistence**: data survives container restarts and pod rescheduling.
2. **Sharing**: multiple containers in a pod (or multiple pods) can share data.

---

## 2. Storage Building Blocks (Overview)

| Object | Scope | Purpose |
|---|---|---|
| Volume | Pod | Directory accessible to containers in a pod. Lifetime tied to the pod (except persistent types) |
| PersistentVolume (PV) | Cluster | A piece of storage provisioned by admin or dynamically |
| PersistentVolumeClaim (PVC) | Namespace | A user's request for storage |
| StorageClass (SC) | Cluster | Defines "classes" of storage and enables dynamic provisioning |
| CSI Driver | Cluster | Plugin that connects Kubernetes to a storage backend (EBS, Azure Disk, NFS, etc.) |

**Flow:**

```
Pod  -->  PVC  -->  PV  -->  Actual storage (EBS / Azure Disk / NFS ...)
                     ^
                     |
               StorageClass (dynamic provisioning)
```

---

## 3. Ephemeral Volume Types

These live and die with the pod.

### 3.1 emptyDir

An empty directory created when the pod starts on a node. Deleted when the pod is removed. Survives container restarts within the same pod.

**Use cases:** scratch space, cache, sharing files between sidecar and main container.

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: emptydir-demo
spec:
  containers:
    - name: writer
      image: busybox
      command: ["sh", "-c", "while true; do date >> /data/log.txt; sleep 5; done"]
      volumeMounts:
        - name: shared
          mountPath: /data
    - name: reader
      image: busybox
      command: ["sh", "-c", "tail -f /data/log.txt"]
      volumeMounts:
        - name: shared
          mountPath: /data
  volumes:
    - name: shared
      emptyDir: {}
```

RAM-backed variant:

```yaml
volumes:
  - name: cache
    emptyDir:
      medium: Memory
      sizeLimit: 256Mi
```

### 3.2 hostPath

Mounts a file or directory from the **node's filesystem** into the pod.

**Use cases:** node-level agents (log collectors, monitoring), single-node dev clusters.
**Warning:** ties the pod to a node and is a security risk. Avoid in production.

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: hostpath-demo
spec:
  containers:
    - name: app
      image: nginx
      volumeMounts:
        - name: logs
          mountPath: /var/log/nginx
  volumes:
    - name: logs
      hostPath:
        path: /var/log/myapp
        type: DirectoryOrCreate
```

### 3.3 ConfigMap and Secret Volumes

Inject configuration or sensitive data as files.

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
data:
  app.properties: |
    mode=production
    log_level=info
---
apiVersion: v1
kind: Pod
metadata:
  name: config-demo
spec:
  containers:
    - name: app
      image: nginx
      volumeMounts:
        - name: config
          mountPath: /etc/app
          readOnly: true
        - name: creds
          mountPath: /etc/creds
          readOnly: true
  volumes:
    - name: config
      configMap:
        name: app-config
    - name: creds
      secret:
        secretName: db-secret
```

### 3.4 Other Ephemeral Types

| Type | Description |
|---|---|
| `downwardAPI` | Expose pod metadata (labels, name, limits) as files |
| `projected` | Combine configMap, secret, downwardAPI and serviceAccountToken into one directory |
| Generic ephemeral volume | PVC-like volume created and deleted with the pod, backed by a StorageClass |

---

## 4. Persistent Storage

### 4.1 PersistentVolume (PV)

A cluster-level resource representing real storage.

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: pv-nfs
spec:
  capacity:
    storage: 5Gi
  accessModes:
    - ReadWriteMany
  persistentVolumeReclaimPolicy: Retain
  storageClassName: manual
  nfs:
    server: 10.0.0.50
    path: /exports/data
```

### 4.2 PersistentVolumeClaim (PVC)

A request for storage by a user. Kubernetes binds it to a matching PV.

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: pvc-nfs
spec:
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 5Gi
  storageClassName: manual
```

### 4.3 Using the PVC in a Pod

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: app-with-pvc
spec:
  containers:
    - name: app
      image: nginx
      volumeMounts:
        - name: data
          mountPath: /usr/share/nginx/html
  volumes:
    - name: data
      persistentVolumeClaim:
        claimName: pvc-nfs
```

### 4.4 Access Modes

| Mode | Short | Meaning |
|---|---|---|
| ReadWriteOnce | RWO | Read-write by a single **node** |
| ReadOnlyMany | ROX | Read-only by many nodes |
| ReadWriteMany | RWX | Read-write by many nodes |
| ReadWriteOncePod | RWOP | Read-write by a single **pod** |

Typical support:

| Backend | RWO | ROX | RWX |
|---|---|---|---|
| AWS EBS | Yes | No | No |
| AWS EFS | Yes | Yes | Yes |
| Azure Disk | Yes | No | No |
| Azure Files | Yes | Yes | Yes |
| NFS | Yes | Yes | Yes |

### 4.5 Reclaim Policies

What happens to the PV when its PVC is deleted.

| Policy | Behaviour |
|---|---|
| `Retain` | PV and data are kept; admin must clean up manually |
| `Delete` | PV and the underlying storage are deleted (default for dynamic provisioning) |
| `Recycle` | Deprecated (basic `rm -rf`) |

### 4.6 PV/PVC Lifecycle

```
Available --> Bound --> Released --> (Retain: manual cleanup | Delete: removed)
```

---

## 5. StorageClass and Dynamic Provisioning

Instead of admins pre-creating PVs, a **StorageClass** lets Kubernetes create storage on demand when a PVC is submitted.

### 5.1 AWS EBS (gp3) StorageClass

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ebs-gp3
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
  fsType: ext4
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
```

### 5.2 Azure Disk StorageClass

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: azure-premium
provisioner: disk.csi.azure.com
parameters:
  skuName: Premium_LRS
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
```

### 5.3 PVC Using a StorageClass

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: mysql-pvc
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: ebs-gp3
  resources:
    requests:
      storage: 10Gi
```

No PV is written by hand. The CSI driver creates the EBS volume and the PV automatically.

### 5.4 Key StorageClass Fields

| Field | Description |
|---|---|
| `provisioner` | CSI driver that creates the storage |
| `parameters` | Backend-specific options (disk type, IOPS, encryption) |
| `reclaimPolicy` | `Delete` or `Retain` for dynamically created PVs |
| `volumeBindingMode` | `Immediate` or `WaitForFirstConsumer` (waits for pod scheduling, so the disk is created in the right zone) |
| `allowVolumeExpansion` | Allows PVC resize |

### 5.5 Default StorageClass

```bash
kubectl patch storageclass ebs-gp3 \
  -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
```

A PVC with no `storageClassName` uses the default class.

---

## 6. Complete Example: MySQL with Persistent Storage

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: mysql-pvc
spec:
  accessModes: ["ReadWriteOnce"]
  storageClassName: ebs-gp3
  resources:
    requests:
      storage: 10Gi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mysql
spec:
  replicas: 1
  selector:
    matchLabels:
      app: mysql
  template:
    metadata:
      labels:
        app: mysql
    spec:
      containers:
        - name: mysql
          image: mysql:8
          env:
            - name: MYSQL_ROOT_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: mysql-secret
                  key: password
          ports:
            - containerPort: 3306
          volumeMounts:
            - name: mysql-data
              mountPath: /var/lib/mysql
      volumes:
        - name: mysql-data
          persistentVolumeClaim:
            claimName: mysql-pvc
```

Verify:

```bash
kubectl get sc
kubectl get pvc
kubectl get pv
kubectl describe pvc mysql-pvc

# Test persistence
kubectl delete pod -l app=mysql
kubectl get pods          # new pod starts and re-attaches the same volume
```

---

## 7. StatefulSet with volumeClaimTemplates

For stateful apps with multiple replicas, each replica needs its **own** volume. StatefulSets create one PVC per pod automatically.

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: web
spec:
  serviceName: web
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
          image: nginx
          volumeMounts:
            - name: www
              mountPath: /usr/share/nginx/html
  volumeClaimTemplates:
    - metadata:
        name: www
      spec:
        accessModes: ["ReadWriteOnce"]
        storageClassName: ebs-gp3
        resources:
          requests:
            storage: 1Gi
```

Result:

```
www-web-0   -> Pod web-0
www-web-1   -> Pod web-1
www-web-2   -> Pod web-2
```

If `web-1` is deleted and recreated, it re-attaches to `www-web-1`. PVCs are **not** deleted when the StatefulSet is scaled down or deleted.

---

## 8. Volume Expansion

Requires `allowVolumeExpansion: true` on the StorageClass.

```bash
kubectl patch pvc mysql-pvc -p '{"spec":{"resources":{"requests":{"storage":"20Gi"}}}}'
kubectl get pvc mysql-pvc -w
```

Volumes can only be **expanded**, never shrunk.

---

## 9. Volume Snapshots

Point-in-time copies of a PVC (needs CSI snapshot support).

```yaml
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshotClass
metadata:
  name: ebs-snap-class
driver: ebs.csi.aws.com
deletionPolicy: Delete
---
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: mysql-snap
spec:
  volumeSnapshotClassName: ebs-snap-class
  source:
    persistentVolumeClaimName: mysql-pvc
```

Restore into a new PVC:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: mysql-restored
spec:
  storageClassName: ebs-gp3
  dataSource:
    name: mysql-snap
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
  accessModes: ["ReadWriteOnce"]
  resources:
    requests:
      storage: 10Gi
```

---

## 10. Block vs Filesystem Volume Mode

| Mode | Description |
|---|---|
| `Filesystem` (default) | Volume is formatted and mounted as a directory |
| `Block` | Raw block device exposed to the pod (databases that manage their own storage) |

```yaml
spec:
  volumeMode: Block
```

```yaml
containers:
  - name: app
    volumeDevices:
      - name: raw
        devicePath: /dev/xvda
```

---

## 11. Storage Types by Backend

| Category | Examples | Typical Access Mode | Notes |
|---|---|---|---|
| Block storage | AWS EBS, Azure Disk, GCE PD | RWO | Fast, single-node attach, zone-bound |
| File storage | AWS EFS, Azure Files, NFS, CephFS | RWX | Shared across pods and nodes |
| Object storage | S3, Azure Blob | Not mounted natively | Accessed via SDK/API (or special CSI drivers) |
| Local storage | `local` PV, hostPath | RWO | Fastest, but tied to a node |

---

## 12. Quick Command Reference

```bash
kubectl get sc
kubectl get pv
kubectl get pvc -A
kubectl describe pvc <name>
kubectl describe pv <name>
kubectl get volumeattachments
kubectl get volumesnapshot
kubectl delete pvc <name>
```

---

## 13. Troubleshooting

| Symptom | Likely Cause | Fix |
|---|---|---|
| PVC stuck in `Pending` | No matching PV / no default StorageClass / CSI driver missing | `kubectl describe pvc`, check SC and CSI pods |
| Pod stuck in `ContainerCreating` | Volume attach/mount failure | `kubectl describe pod`, check events |
| `Multi-Attach error` | RWO volume still attached to another node | Wait for detach or delete the old pod |
| Pod in wrong AZ, volume can't attach | `volumeBindingMode: Immediate` | Use `WaitForFirstConsumer` |
| PV stuck in `Released` | Reclaim policy `Retain` | Remove `claimRef` or recreate the PV |
| Cannot resize PVC | `allowVolumeExpansion` not enabled | Patch the StorageClass |

---

## 14. Summary

- **Volumes** give pods storage; ephemeral types (`emptyDir`, `configMap`, `secret`) die with the pod.
- **PV** is the storage, **PVC** is the request, **StorageClass** is the template for dynamic provisioning.
- Use **RWO** for block disks (EBS, Azure Disk) and **RWX** for shared file systems (EFS, Azure Files, NFS).
- Prefer **dynamic provisioning** with `WaitForFirstConsumer`.
- Use **StatefulSets with volumeClaimTemplates** for replicated stateful apps.
- Choose reclaim policy carefully: `Retain` for important data, `Delete` for disposable data.
