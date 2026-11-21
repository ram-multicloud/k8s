# Grafana: How It Works and How to Deploy a Dashboard

## Part 1: How Grafana Works

### What Grafana is

Grafana is an open-source **visualization and alerting** platform. It does **not** collect or store metrics itself (apart from its own config and dashboard definitions). It connects to external **data sources**, runs queries against them, and renders the results as graphs, tables, gauges and so on.

### The big picture

```
 Apps / Servers / K8s          Collectors / Storage                Grafana
┌──────────────────┐        ┌─────────────────────────┐      ┌───────────────────┐
│ node_exporter    │ scrape │ Prometheus (metrics)    │ query│ Data source       │
│ app /metrics     │───────▶│ Loki (logs)             │◀─────│  ↓                │
│ kube-state-metrics│       │ Tempo (traces)          │      │ Panel (query+viz) │
│ Promtail / agents│ push   │ Azure Monitor, MySQL,   │      │  ↓                │
└──────────────────┘        │ CloudWatch, Elastic ... │      │ Dashboard         │
                            └─────────────────────────┘      │  ↓                │
                                                             │ Alerts / Sharing  │
                                                             └───────────────────┘
```

### Core concepts

| Concept | Meaning |
|---|---|
| **Data source** | A connection to a backend (Prometheus, Loki, Azure Monitor, CloudWatch, MySQL, Elasticsearch, etc.). Grafana queries it live. |
| **Query** | Written in the data source's own language (PromQL for Prometheus, LogQL for Loki, KQL for Azure, SQL for databases). |
| **Panel** | One visualization: a query plus a display type (time series, stat, gauge, table, bar chart, logs, heatmap). |
| **Dashboard** | A collection of panels arranged in a grid, saved as a **JSON** document. |
| **Variables** | Dropdowns (e.g. `namespace`, `pod`, `instance`) that make dashboards reusable. Panels reference them like `$namespace`. |
| **Folders / Orgs / Teams** | Organize dashboards and control access (RBAC). |
| **Alerting** | Rules evaluate queries on a schedule; when a condition holds, notifications go to contact points (email, Slack, Teams, PagerDuty, webhook). |
| **Annotations** | Markers on graphs (deployments, incidents) to correlate events with metrics. |
| **Plugins** | Extra data sources, panels, and apps installed into Grafana. |
| **Provisioning** | Data sources and dashboards defined as files/ConfigMaps so Grafana is configured as code. |

### Request flow (what happens when you open a dashboard)

1. Browser loads the dashboard JSON from the Grafana server.
2. For each panel, Grafana's backend sends the panel's query to the configured data source (Grafana acts as a proxy, so credentials stay on the server).
3. The data source returns time series or table data.
4. Grafana applies transformations (join, filter, rename, calculate) and the browser renders the visualization.
5. The dashboard auto-refreshes at the chosen interval (e.g. every 10s or 1m).

### Where Grafana stores its own data

- Dashboards, users, data source definitions, alert rules → internal database (**SQLite** by default, **MySQL/PostgreSQL** for HA/production).
- Plugins and local files → `/var/lib/grafana`.
- Config → `/etc/grafana/grafana.ini` (or environment variables like `GF_SECURITY_ADMIN_PASSWORD`).
- Default port: **3000**.

### Typical monitoring stack

```
Prometheus  → metrics (CPU, memory, requests, K8s state)
Loki        → logs
Tempo       → traces
Grafana     → one UI for all of the above + alerting
```

---

## Part 2: Deploy Grafana

Pick one of the options below.

### Option A: Docker (quickest, for learning)

```bash
docker run -d --name grafana -p 3000:3000 \
  -v grafana-data:/var/lib/grafana \
  grafana/grafana:latest
```

Open `http://localhost:3000`. Default login is `admin` / `admin` (you will be asked to change it).

---

### Option B: Kubernetes (AKS) with kube-prometheus-stack (recommended)

This installs **Prometheus + Alertmanager + Grafana + node-exporter + kube-state-metrics** together, with ready-made Kubernetes dashboards and the Prometheus data source already wired up.

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

kubectl create namespace monitoring

helm install monitoring prometheus-community/kube-prometheus-stack \
  -n monitoring \
  --set grafana.adminPassword='ChangeMe123!' \
  --set grafana.service.type=LoadBalancer \
  --set grafana.persistence.enabled=true \
  --set grafana.persistence.size=10Gi

kubectl get pods -n monitoring -w
```

Get the address and password:

```bash
kubectl get svc -n monitoring monitoring-grafana

# if you did not set the password yourself
kubectl get secret -n monitoring monitoring-grafana \
  -o jsonpath="{.data.admin-password}" | base64 -d; echo
```

No public IP? Use port-forward:

```bash
kubectl port-forward -n monitoring svc/monitoring-grafana 3000:80
# open http://localhost:3000   (user: admin)
```

---

### Option C: Standalone Grafana Helm chart

Use this when Prometheus (or another data source) already exists.

```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update
kubectl create namespace monitoring
```

`grafana-values.yaml`:

```yaml
adminUser: admin
adminPassword: ChangeMe123!

service:
  type: LoadBalancer

persistence:
  enabled: true
  size: 10Gi

# Provision the data source as code
datasources:
  datasources.yaml:
    apiVersion: 1
    datasources:
      - name: Prometheus
        type: prometheus
        access: proxy
        url: http://monitoring-kube-prometheus-prometheus.monitoring.svc:9090
        isDefault: true

# Provision a dashboard provider and pull a community dashboard
dashboardProviders:
  dashboardproviders.yaml:
    apiVersion: 1
    providers:
      - name: default
        orgId: 1
        folder: ""
        type: file
        disableDeletion: false
        editable: true
        options:
          path: /var/lib/grafana/dashboards/default

dashboards:
  default:
    node-exporter-full:
      gnetId: 1860
      revision: 37
      datasource: Prometheus
```

Install:

```bash
helm install grafana grafana/grafana -n monitoring -f grafana-values.yaml

kubectl get secret -n monitoring grafana \
  -o jsonpath="{.data.admin-password}" | base64 -d; echo
```

> Adjust the Prometheus service URL to match your cluster (`kubectl get svc -n monitoring`).
> Dashboard `gnetId` downloads need internet access from the Grafana pod. Revision numbers change over time, so check grafana.com/grafana/dashboards.

---

## Part 3: Add the Data Source (manual UI method)

1. Connections → Data sources → **Add data source**
2. Choose **Prometheus**
3. URL: `http://<prometheus-service>.<namespace>.svc:9090`
4. Click **Save & test**. You should see a green success message.

---

## Part 4: Create / Import a Dashboard

### Import a ready-made dashboard

1. Dashboards → New → **Import**
2. Enter a dashboard ID from grafana.com, for example:
   - **1860**: Node Exporter Full (Linux server metrics)
   - **15757** / **15760**: Kubernetes cluster / pod views
   - **315**: Kubernetes cluster monitoring (older, widely used)
3. Click **Load**, pick the Prometheus data source, then **Import**.

### Build your own dashboard

1. Dashboards → New → **New dashboard** → **Add visualization**
2. Select the data source.
3. Enter a query, for example:

```promql
# CPU usage % per node
100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# Memory used %
(1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100

# Pod CPU usage in a namespace
sum(rate(container_cpu_usage_seconds_total{namespace="$namespace"}[5m])) by (pod)
```

4. Choose a visualization (Time series, Gauge, Stat, Table), set the unit (percent, bytes) and thresholds.
5. Add a **variable**: Dashboard settings → Variables → New  
   Name: `namespace`, Type: Query, Query: `label_values(kube_pod_info, namespace)`
6. Save the dashboard.

### Dashboard as code (provision via ConfigMap)

With the kube-prometheus-stack sidecar enabled, any ConfigMap with the label `grafana_dashboard: "1"` is picked up automatically:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: my-dashboard
  namespace: monitoring
  labels:
    grafana_dashboard: "1"
data:
  my-dashboard.json: |
    {
      "title": "My App Dashboard",
      "uid": "my-app-dash",
      "schemaVersion": 39,
      "time": { "from": "now-6h", "to": "now" },
      "panels": [
        {
          "type": "timeseries",
          "title": "Pod CPU",
          "gridPos": { "h": 8, "w": 12, "x": 0, "y": 0 },
          "targets": [
            {
              "expr": "sum(rate(container_cpu_usage_seconds_total{namespace=\"default\"}[5m])) by (pod)",
              "legendFormat": "{{pod}}"
            }
          ]
        }
      ]
    }
```

```bash
kubectl apply -f my-dashboard.yaml
```

The dashboard appears in Grafana within about a minute.

---

## Part 5: Set Up an Alert

1. Alerting → Alert rules → **New alert rule**
2. Query: `100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)`
3. Condition: `IS ABOVE 80` for `5m`
4. Pick a folder and evaluation group (e.g. every 1m)
5. Alerting → Contact points → add Slack / email / Teams
6. Alerting → Notification policies → route alerts to that contact point

---

## Part 6: Securing and Operating Grafana

- Put Grafana behind an **Ingress with TLS**; set `root_url` in `grafana.ini`
- Enable SSO (Azure AD / Entra ID via OAuth) instead of local users
- Use **PostgreSQL/MySQL** as the backend DB when running multiple replicas
- Keep `persistence` enabled so dashboards survive pod restarts, or provision everything as code
- Store admin credentials in a Kubernetes Secret (`admin.existingSecret`) rather than plain values
- Back up the Grafana database or export dashboards JSON into Git

---

## Troubleshooting

| Problem | Check |
|---|---|
| Dashboard panels show "No data" | Time range, correct data source selected, query returns data in Prometheus UI |
| Data source test fails | Service name/namespace/port in URL; network policy; pod can reach Prometheus |
| Pod `Pending` | PVC not bound: `kubectl describe pvc -n monitoring` |
| Forgot admin password | `kubectl get secret` as shown above, or `grafana cli admin reset-admin-password <new>` inside the pod |
| Imported dashboard has empty variables | Dashboard expects different metric/label names than your exporters provide |
| Provisioned dashboard missing | ConfigMap label `grafana_dashboard: "1"` and the sidecar is enabled |

---

## Cleanup

```bash
helm uninstall monitoring -n monitoring      # Option B
helm uninstall grafana -n monitoring         # Option C
kubectl delete namespace monitoring
docker rm -f grafana                          # Option A
```
