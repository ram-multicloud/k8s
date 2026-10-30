# nopCommerce Helm Chart: Detailed Guide

This document explains the `nopcommerce` Helm chart: what it deploys, how each Docker Compose setting was translated to Kubernetes, what every file does, how to configure, install and troubleshoot it, and what to harden before production.

---

## 1. Overview

The chart deploys two components:

| Component | Kubernetes kind | Purpose |
|---|---|---|
| **nopCommerce** (`nop:1.0`) | Deployment + Service (+ optional Ingress) | The ASP.NET Core web application, listening on port 5000 |
| **MySQL 8.0** | StatefulSet + Service | The database used by nopCommerce |

Supporting objects:

- **ConfigMap**: non-secret environment variables for the app
- **Secret**: DB passwords and the full connection string
- **PVC** (app): persistent storage for nopCommerce writable folders
- **volumeClaimTemplate** (MySQL): persistent storage for the database

### Architecture

```
                 ┌────────────── Kubernetes namespace ──────────────┐
 Internet ──►  Ingress (optional)
                    │
                    ▼
              Service: <release>-nopcommerce  (port 5000)
                    │
                    ▼
              Deployment: nop pod
                ├─ initContainer: wait-for-mysql (nc -z host:3306)
                ├─ container: dotnet Nop.Web.dll
                │     env  ◄── ConfigMap  (ASPNETCORE_*, DOTNET_*, ...)
                │     env  ◄── Secret     (ConnectionStrings__ConnectionString)
                │     vols ◄── PVC        (App_Data, images, files)
                    │
                    ▼  (TCP 3306, cluster-internal)
              Service: <release>-nopcommerce-mysql
                    │
                    ▼
              StatefulSet: mysql-0
                    └─ PVC (/var/lib/mysql, subPath: data)
```

---

## 2. Docker Compose → Kubernetes mapping

| Docker Compose | Helm / Kubernetes equivalent | Notes |
|---|---|---|
| `services.nop` | `Deployment` (`nop-deployment.yaml`) | |
| `services.mysql` | `StatefulSet` (`mysql-statefulset.yaml`) | StatefulSet is the right kind for a database with stable storage |
| `image: nop:1.0` | `nop.image.repository` / `nop.image.tag` | Must be pushed to a registry the cluster can pull from |
| `container_name` | *(dropped)* | Kubernetes generates pod names; use Services for stable addressing |
| `command: ["dotnet","Nop.Web.dll"]` | `nop.command` | Rendered as the container `command` |
| `environment` (plain values) | `ConfigMap` → `envFrom` | |
| `environment` (DB connection string) | `Secret` → `secretKeyRef` | Contains the DB password, so it's not in the ConfigMap |
| `ASPNETCORE_ENVIRONMENT` (listed twice) | single key, `Production` | A map can't hold duplicates; the last value in the compose file (`Production`) wins |
| `ports: "5000:5000"` | `Service` port 5000 (+ optional Ingress) | Type `ClusterIP` by default |
| `ports: "3306:3306"` (mysql) | `Service` ClusterIP only | **Not** exposed outside the cluster |
| `networks: nop-network` | Namespace-level cluster networking | Pods reach each other by Service DNS name |
| `Server=mysql` in connection string | `Server=<release>-nopcommerce-mysql` | Built automatically in `secret.yaml` |
| `volumes: nop-data:/app` | PVC with **subPath mounts** | See section 5.3 for why |
| `volumes: mysql-data` | `volumeClaimTemplates` | |
| `restart: unless-stopped` | Default pod `restartPolicy: Always` + probes | Nothing extra needed |
| MySQL env vars | Same names, passwords from Secret | |

---

## 3. Chart structure and file-by-file explanation

```
nopcommerce/
├── Chart.yaml
├── values.yaml
├── .helmignore
└── templates/
    ├── _helpers.tpl
    ├── configmap.yaml
    ├── secret.yaml
    ├── nop-deployment.yaml
    ├── nop-pvc.yaml
    ├── nop-service.yaml
    ├── ingress.yaml
    ├── mysql-service.yaml
    ├── mysql-statefulset.yaml
    └── NOTES.txt
```

### 3.1 `Chart.yaml`
Chart metadata: name `nopcommerce`, chart version `0.1.0`, and `appVersion` `4.90.8` (the nopCommerce version from your compose file). `appVersion` is informational and is used in labels and `NOTES.txt`.

### 3.2 `values.yaml`
The single place to configure the chart. Sections are `nop`, `ingress` and `mysql`. See the reference in section 4.

### 3.3 `templates/_helpers.tpl`
Reusable named templates:

| Helper | What it produces |
|---|---|
| `nopcommerce.name` | Chart name (overridable with `nameOverride`) |
| `nopcommerce.fullname` | `<release>-<chart>` (overridable with `fullnameOverride`), truncated to 63 chars |
| `nopcommerce.labels` | Common labels (chart, release, version, managed-by) |
| `nopcommerce.nop.selector` | Selector labels for the web pods (`component: web`) |
| `nopcommerce.mysql.selector` | Selector labels for the DB pods (`component: mysql`) |
| `nopcommerce.mysql.host` | In-cluster MySQL Service name, or `mysql.external.host` if `mysql.enabled=false` |
| `nopcommerce.mysql.port` | The MySQL port to use (internal or external) |
| `nopcommerce.secretName` | Name of the Secret holding DB credentials (generated, or `mysql.existingSecret`) |

### 3.4 `templates/configmap.yaml`
Loops over `nop.env` and creates one ConfigMap key per entry. The Deployment loads it with `envFrom`, so adding a new variable only requires adding it to `values.yaml`.

### 3.5 `templates/secret.yaml`
Created **only if** `mysql.existingSecret` is empty. It holds three keys:

| Key | Used by |
|---|---|
| `root-password` | MySQL (`MYSQL_ROOT_PASSWORD`) |
| `password` | MySQL (`MYSQL_PASSWORD`) |
| `connection-string` | nopCommerce (`ConnectionStrings__ConnectionString`) |

The connection string is rendered as:

```
Server=<mysql-host>;Port=<port>;Database=<db>;Uid=<user>;Pwd=<password>;AllowUserVariables=True;
```

### 3.6 `templates/nop-deployment.yaml`
Key behaviour:

- **Replicas**: `nop.replicaCount` (default 1).
- **Strategy**: `Recreate` when persistence is enabled with `ReadWriteOnce`. A rolling update would try to attach the same RWO volume to two pods and get stuck.
- **Rollout on config change**: the pod template carries `checksum/config` and `checksum/secret` annotations, so `helm upgrade` restarts the pods when the ConfigMap or Secret changes.
- **initContainer `wait-for-mysql`**: runs `nc -z <host> <port>` in a loop until the database accepts TCP connections, so the app doesn't start before MySQL.
- **Main container**: `command` from `nop.command`, port named `http`, env from the ConfigMap plus the connection string from the Secret, and any `nop.extraEnv`.
- **Probes** (TCP on the `http` port):
  - `startupProbe`: up to 60 × 10 s = 10 minutes, to allow slow first start and the installer
  - `readinessProbe`: every 10 s
  - `livenessProbe`: every 20 s
- **Volumes**: mounts the PVC through `subPath` entries (section 5.3).

### 3.7 `templates/nop-pvc.yaml`
Creates the app PVC when `nop.persistence.enabled=true` and no `existingClaim` is given. Supports `storageClass`, `accessMode` and `size`.

### 3.8 `templates/nop-service.yaml`
Exposes the web pods on `nop.service.port` (default 5000), targeting the named container port `http`. Supports `ClusterIP`, `NodePort` (with `nop.service.nodePort`) and `LoadBalancer`.

### 3.9 `templates/ingress.yaml`
Rendered only when `ingress.enabled=true`. Supports `className`, annotations, multiple hosts/paths and TLS. Backend is the nop Service.

### 3.10 `templates/mysql-service.yaml`
Rendered when `mysql.enabled=true`. A ClusterIP Service on port 3306. The StatefulSet's `serviceName` points at it.

### 3.11 `templates/mysql-statefulset.yaml`
- Image `mysql:8.0`, one replica.
- Env: `MYSQL_ROOT_PASSWORD` and `MYSQL_PASSWORD` from the Secret; `MYSQL_DATABASE` and `MYSQL_USER` from values.
- **Probes**: `mysqladmin ping` as readiness (after 15 s) and liveness (after 60 s).
- **Storage**: `volumeClaimTemplates` when `mysql.persistence.enabled=true`; otherwise an `emptyDir` (data is lost when the pod is rescheduled).
- **`subPath: data`**: MySQL refuses to initialise in a directory that is not empty, and many volumes contain a `lost+found` folder. Mounting a sub-directory avoids that problem.

### 3.12 `templates/NOTES.txt`
Text printed after `helm install`/`upgrade`: how to reach the app (ingress URL or a `kubectl port-forward` command) and a reminder to change the default passwords.

---

## 4. Configuration reference (`values.yaml`)

### 4.1 General

| Key | Default | Description |
|---|---|---|
| `nameOverride` | `""` | Override the chart name used in resource names |
| `fullnameOverride` | `""` | Override the full resource name prefix |

### 4.2 `nop.*` (web application)

| Key | Default | Description |
|---|---|---|
| `nop.replicaCount` | `1` | Number of web pods. Keep 1 unless shared (RWX) storage is used |
| `nop.image.repository` | `nop` | Image repository |
| `nop.image.tag` | `1.0` | Image tag |
| `nop.image.pullPolicy` | `IfNotPresent` | Pull policy |
| `nop.imagePullSecrets` | `[]` | Registry secrets for private registries |
| `nop.command` | `["dotnet","Nop.Web.dll"]` | Container command |
| `nop.containerPort` | `5000` | Port the app listens on (must match `ASPNETCORE_URLS`) |
| `nop.env` | see file | Map of plain environment variables |
| `nop.extraEnv` | `[]` | Raw list of extra env entries (supports `valueFrom`) |
| `nop.service.type` | `ClusterIP` | `ClusterIP`, `NodePort` or `LoadBalancer` |
| `nop.service.port` | `5000` | Service port |
| `nop.service.nodePort` | `null` | Fixed node port when type is `NodePort` |
| `nop.persistence.enabled` | `true` | Create/use a PVC for writable app data |
| `nop.persistence.size` | `5Gi` | PVC size |
| `nop.persistence.storageClass` | `""` | StorageClass (empty = cluster default) |
| `nop.persistence.accessMode` | `ReadWriteOnce` | PVC access mode |
| `nop.persistence.existingClaim` | `""` | Use a pre-existing PVC instead of creating one |
| `nop.persistence.mounts` | 3 entries | List of `{subPath, mountPath}` pairs |
| `nop.resources` | `{}` | CPU/memory requests and limits |
| `nop.nodeSelector` / `tolerations` / `affinity` | empty | Scheduling constraints |

### 4.3 `ingress.*`

| Key | Default | Description |
|---|---|---|
| `ingress.enabled` | `false` | Create an Ingress |
| `ingress.className` | `""` | e.g. `nginx` |
| `ingress.annotations` | `{}` | e.g. cert-manager or proxy-body-size annotations |
| `ingress.hosts` | `nop.example.com` | List of hosts, each with `paths` |
| `ingress.tls` | `[]` | Standard Kubernetes ingress TLS block |

### 4.4 `mysql.*`

| Key | Default | Description |
|---|---|---|
| `mysql.enabled` | `true` | Deploy MySQL with this chart. Set `false` to use an external DB |
| `mysql.external.host` | `""` | Host of the external DB (required when `enabled=false`) |
| `mysql.external.port` | `3306` | Port of the external DB |
| `mysql.image.repository` / `tag` | `mysql` / `8.0` | Image |
| `mysql.port` | `3306` | Service port |
| `mysql.database` | `nopcommerce` | Database name |
| `mysql.user` | `nopuser` | Application DB user |
| `mysql.rootPassword` | `rootpassword` | **Change this** |
| `mysql.password` | `noppassword` | **Change this** |
| `mysql.existingSecret` | `""` | Use your own Secret (keys: `root-password`, `password`, `connection-string`) |
| `mysql.service.type` | `ClusterIP` | Keep internal |
| `mysql.persistence.enabled` | `true` | Use a PVC for `/var/lib/mysql` |
| `mysql.persistence.size` | `10Gi` | PVC size |
| `mysql.persistence.storageClass` | `""` | StorageClass |
| `mysql.persistence.accessMode` | `ReadWriteOnce` | Access mode |
| `mysql.resources`, `nodeSelector`, `tolerations`, `affinity` | empty | As above |

---

## 5. Design decisions explained

### 5.1 Why a StatefulSet for MySQL?
A StatefulSet gives the database pod a stable identity and its own persistent volume that survives restarts and rescheduling. A plain Deployment can work for single-node setups, but a StatefulSet is the standard choice for databases.

### 5.2 Why is the connection string in a Secret?
It contains the DB password. Keeping it in a Secret means it is not visible in the ConfigMap or in `kubectl describe pod` as a plain value.

### 5.3 Why not mount the PVC on `/app`?
In Docker, a *named* volume is populated from the image's content the first time it is created, so `nop-data:/app` works. In Kubernetes, an empty PVC mounted at `/app` **hides** everything the image placed there (including `Nop.Web.dll`), and the container would fail to start.

The chart therefore mounts only nopCommerce's writable directories:

| subPath on the PVC | Mount path | Contains |
|---|---|---|
| `App_Data` | `/app/App_Data` | Settings files (e.g. `appsettings.json`/`dataSettings`), logs, data protection keys |
| `images` | `/app/wwwroot/images` | Product and thumbnail images |
| `files` | `/app/wwwroot/files` | Uploaded files |

If your installation also writes elsewhere (for example installed plugins or themes), add more entries to `nop.persistence.mounts`. Be aware that mounting over a directory that already holds files from the image hides those files.

### 5.4 Why `Recreate` strategy?
With a ReadWriteOnce volume, a rolling update would start the new pod while the old one still holds the volume, which often leaves the new pod stuck in `ContainerCreating`. `Recreate` stops the old pod first.

### 5.5 Why an init container?
nopCommerce needs the database during start-up. The init container delays the app until MySQL accepts TCP connections, avoiding crash loops while MySQL initialises for the first time.

### 5.6 Why TCP probes?
They are generic and work before the application is installed. After the first-time installation completes you may prefer an HTTP probe on `/` or a health endpoint that suits your configuration.

---

## 6. Installation

### 6.1 Prerequisites
- Kubernetes cluster and `kubectl` configured
- Helm 3
- A default StorageClass (or set `storageClass` explicitly)
- The `nop:1.0` image available in a registry the cluster can pull from. For example:
  ```bash
  docker tag nop:1.0 <registry>/nop:1.0
  docker push <registry>/nop:1.0
  ```

### 6.2 Validate

```bash
tar xzf nopcommerce-chart.tgz
helm lint ./nopcommerce
helm template nop ./nopcommerce | less     # inspect rendered manifests
```

### 6.3 Install

```bash
helm install nop ./nopcommerce \
  --namespace nop --create-namespace \
  --set nop.image.repository=<registry>/nop \
  --set mysql.rootPassword='<strong-root-pw>' \
  --set mysql.password='<strong-app-pw>'
```

Or with a values file (recommended):

```yaml
# my-values.yaml
nop:
  image:
    repository: myregistry.example.com/nop
    tag: "1.0"
  imagePullSecrets:
    - name: regcred
ingress:
  enabled: true
  className: nginx
  hosts:
    - host: shop.example.com
      paths:
        - path: /
          pathType: Prefix
mysql:
  rootPassword: "change-me-root"
  password: "change-me-app"
  persistence:
    size: 20Gi
```

```bash
helm install nop ./nopcommerce -n nop --create-namespace -f my-values.yaml
```

### 6.4 Access the app

Without ingress:
```bash
kubectl port-forward svc/nop-nopcommerce 5000:5000 -n nop
# open http://localhost:5000
```

With ingress: open `http(s)://<your host>`.

The first visit shows the **nopCommerce installation wizard**. The database connection string is already supplied through the environment variable, so complete the wizard (store admin e-mail, password and so on) and continue.

### 6.5 Upgrade and uninstall

```bash
helm upgrade nop ./nopcommerce -n nop -f my-values.yaml
helm rollback nop 1 -n nop
helm uninstall nop -n nop
```

> `helm uninstall` removes the app PVC, but the MySQL PVC created from `volumeClaimTemplates` is **kept** by Kubernetes. Delete it manually if you really want to wipe the data:
> `kubectl delete pvc -l app.kubernetes.io/instance=nop -n nop`

---

## 7. Using an external MySQL database

```bash
helm install nop ./nopcommerce -n nop \
  --set mysql.enabled=false \
  --set mysql.external.host=mydb.example.com \
  --set mysql.external.port=3306 \
  --set mysql.database=nopcommerce \
  --set mysql.user=nopuser \
  --set mysql.password='<pw>'
```

In this mode no MySQL StatefulSet or Service is created; the init container waits for the external host, and the connection string points to it. This is the recommended setup for production (managed databases such as Azure Database for MySQL, Amazon RDS or Cloud SQL). Never put root credentials in the application connection string.

---

## 8. Using your own Secret

```bash
kubectl create secret generic nop-db -n nop \
  --from-literal=root-password='...' \
  --from-literal=password='...' \
  --from-literal=connection-string='Server=nop-nopcommerce-mysql;Port=3306;Database=nopcommerce;Uid=nopuser;Pwd=...;AllowUserVariables=True;'

helm install nop ./nopcommerce -n nop --set mysql.existingSecret=nop-db
```

All three keys must exist. This keeps passwords out of Helm values and release history.

---

## 9. Verification

```bash
kubectl get pods,svc,pvc -n nop
kubectl logs deploy/nop-nopcommerce -n nop -c wait-for-mysql
kubectl logs deploy/nop-nopcommerce -n nop
kubectl logs sts/nop-nopcommerce-mysql -n nop
kubectl exec -it nop-nopcommerce-mysql-0 -n nop -- \
  mysql -unopuser -p -e "SHOW DATABASES;"
```

Expected: `nop-nopcommerce-mysql-0` is `1/1 Running`, the web pod is `1/1 Running`, and both PVCs are `Bound`.

---

## 10. Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Web pod stuck in `Init:0/1` | MySQL not ready or wrong host | Check MySQL pod and logs. For external DBs, verify `mysql.external.host` and network/firewall rules |
| `ImagePullBackOff` | `nop:1.0` is a local-only image | Push to a registry and set `nop.image.repository`. Add `imagePullSecrets` if private |
| Pod `Pending` with PVC unbound | No default StorageClass | Set `nop.persistence.storageClass` and `mysql.persistence.storageClass` |
| `CrashLoopBackOff` right after start | DB connection failure | Check the web pod logs; confirm credentials and that the user can connect from the pod |
| MySQL: "directory is not empty" | Volume root contains `lost+found` | Already handled via `subPath: data`. If you changed the mounts, keep a subPath |
| MySQL password change has no effect | MySQL only reads the `MYSQL_*` env vars on **first** initialisation | Change the user password inside MySQL (`ALTER USER ...`) and update the Secret, or delete the MySQL PVC to re-initialise (data loss) |
| Installer asks for DB details again after restart | App settings file not persisted | Make sure `App_Data` is mounted from the PVC and `nop.persistence.enabled=true` |
| New pod stuck `ContainerCreating` during upgrade | RWO volume attached to the old pod | The chart uses `Recreate` to avoid this; do not override the strategy with RWO storage |
| Uploaded images vanish after restart | Persistence disabled or path not mounted | Enable persistence and add the correct path to `nop.persistence.mounts` |
| Large file upload fails behind ingress | Proxy body size limit | Add an annotation, e.g. `nginx.ingress.kubernetes.io/proxy-body-size: "50m"` |

---

## 11. Security and production-hardening checklist

- [ ] Replace the default passwords or use `mysql.existingSecret` (or an external secrets operator).
- [ ] Do not commit `values.yaml` with real passwords to Git.
- [ ] Use a managed or external database for production, with backups.
- [ ] Keep MySQL as `ClusterIP`. Consider a NetworkPolicy allowing only the web pods to reach port 3306.
- [ ] Use a dedicated DB user (as this chart does), never `root`, for the app.
- [ ] Enable TLS on the ingress (cert-manager is a common choice).
- [ ] Set `nop.resources` and `mysql.resources` (requests and limits).
- [ ] Pin image tags (avoid `latest`) and consider image digests.
- [ ] Add a `securityContext` (non-root, read-only root filesystem where possible). This requires mounting writable paths explicitly.
- [ ] Back up the MySQL volume or run scheduled `mysqldump` jobs, and back up the app PVC (images and files).
- [ ] Regularly update to the latest nopCommerce and MySQL patch releases.

---

## 12. Known limitations

- **Single web replica by default.** nopCommerce stores uploaded files and settings on disk, so horizontal scaling requires shared ReadWriteMany storage (NFS, Azure Files, EFS and so on) plus extra nopCommerce configuration (shared data-protection keys, distributed cache, and so on).
- **Single MySQL instance.** There is no replication or high availability in this chart.
- **Plugins and themes** installed via the admin UI write to directories not persisted by default. Add the relevant paths to `nop.persistence.mounts` if you use them.
- **Probes are TCP-based** and only confirm the port is open, not that the application is fully healthy.
- The chart was not linted or rendered in my sandbox, so run `helm lint` and `helm template` before installing.
