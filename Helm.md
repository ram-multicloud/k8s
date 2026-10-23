# Helm Complete Tutorial

From first principles to building, overriding and deploying your own chart.

## Table of Contents

1. [What is Helm?](#1-what-is-helm)
2. [Key Concepts](#2-key-concepts)
3. [Install Helm and Verify](#3-install-helm-and-verify)
4. [Using Existing Charts (Quick Start)](#4-using-existing-charts-quick-start)
5. [Chart Folder Structure](#5-chart-folder-structure)
6. [Chart.yaml Explained](#6-chartyaml-explained)
7. [values.yaml and Variables](#7-valuesyaml-and-variables)
8. [Template Language Basics](#8-template-language-basics)
9. [Build Your Own Chart Step by Step](#9-build-your-own-chart-step-by-step)
10. [Overriding Values](#10-overriding-values)
11. [Validate Before Deploying](#11-validate-before-deploying)
12. [Deploy and Manage Releases](#12-deploy-and-manage-releases)
13. [Dependencies and Subcharts](#13-dependencies-and-subcharts)
14. [Hooks and Tests](#14-hooks-and-tests)
15. [Package and Share Charts](#15-package-and-share-charts)
16. [Multi-Environment Strategy](#16-multi-environment-strategy)
17. [Best Practices](#17-best-practices)
18. [Troubleshooting](#18-troubleshooting)
19. [Cheat Sheet](#19-cheat-sheet)

---

## 1. What is Helm?

Helm is the **package manager for Kubernetes**. It is to Kubernetes what `apt` is to Ubuntu or `npm` is to Node.js.

### The problem Helm solves

A real application needs many Kubernetes manifests: Deployment, Service, ConfigMap, Secret, Ingress, ServiceAccount, and more. Without Helm:

- You copy and paste near-identical YAML for dev, test and prod.
- Changing an image tag or replica count means editing many files.
- There is no single "install", "upgrade" or "rollback" for the whole application.
- Sharing an application with others means sharing a folder of YAML.

### What Helm gives you

| Feature | Benefit |
|---|---|
| **Templating** | One set of templates, many environments driven by values |
| **Packaging** | Bundle all manifests into one versioned unit (a chart) |
| **Release management** | Install, upgrade, rollback, uninstall as one operation |
| **Dependency management** | A chart can depend on other charts (for example app + database) |
| **Sharing** | Publish to chart repositories or OCI registries |

### Helm 3 architecture

```
  helm CLI  ───────────────►  Kubernetes API server
     │                              │
     │ renders templates            │ stores release state
     │ locally (client-side)        │ as Secrets in the target namespace
     ▼                              ▼
  Chart + Values  ──►  Manifests  ──►  Cluster resources
```

- Helm 3 has **no Tiller** (the in-cluster server component of Helm 2). The CLI talks directly to the API server using your kubeconfig, so your RBAC permissions apply.
- Release history is stored as Secrets named `sh.helm.release.v1.<release>.v<revision>` in the release's namespace.

---

## 2. Key Concepts

| Term | Meaning |
|---|---|
| **Chart** | A package: a folder (or `.tgz`) containing templates, default values and metadata |
| **Release** | One installed instance of a chart in a cluster. Install the same chart twice and you get two releases |
| **Revision** | A numbered version of a release. Every install, upgrade or rollback creates a new revision |
| **Repository** | A server hosting packaged charts (`index.yaml` + `.tgz` files) |
| **Values** | Configuration that is injected into templates. Defaults live in `values.yaml` and can be overridden |
| **Template** | A Kubernetes manifest with Go template placeholders |
| **Subchart / Dependency** | A chart that another chart (the parent) includes |

```
Chart (blueprint)  +  Values (config)  ──helm install──►  Release (running instance)
```

Analogy: the **chart is a class**, **values are constructor arguments**, and a **release is an object** created from it.

---

## 3. Install Helm and Verify

### Linux (official script)

```bash
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh
```

### Other platforms

```bash
# macOS
brew install helm

# Windows
choco install kubernetes-helm

# Ubuntu/Debian (snap)
sudo snap install helm --classic
```

### Verify

```bash
helm version
kubectl get nodes        # Helm uses the same kubeconfig as kubectl
```

Helm uses the current context in `~/.kube/config`. Override with `--kubeconfig` or `--kube-context`.

---

## 4. Using Existing Charts (Quick Start)

Before writing your own chart, learn the consumer workflow.

```bash
# 1. Add a repository
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

# 2. Search for charts
helm search repo nginx
helm search repo bitnami/nginx --versions | head

# 3. Inspect the chart before installing
helm show chart  bitnami/nginx
helm show values bitnami/nginx | less
helm show readme bitnami/nginx

# 4. Install a release
helm install my-nginx bitnami/nginx --namespace web --create-namespace

# 5. See what is installed
helm list -A
helm status my-nginx -n web

# 6. Remove it
helm uninstall my-nginx -n web
```

Command shape: `helm install <RELEASE_NAME> <CHART> [flags]`.

---

## 5. Chart Folder Structure

Generate a starter chart:

```bash
helm create myapp
tree myapp
```

```
myapp/
├── Chart.yaml            # Chart metadata (name, version, dependencies)
├── values.yaml           # Default configuration values
├── .helmignore           # Files to exclude when packaging
├── charts/               # Dependency charts (subcharts) are stored here
└── templates/            # Kubernetes manifest templates
    ├── NOTES.txt         # Message printed after install/upgrade
    ├── _helpers.tpl      # Reusable named templates (no manifest output)
    ├── deployment.yaml
    ├── service.yaml
    ├── serviceaccount.yaml
    ├── ingress.yaml
    ├── hpa.yaml
    └── tests/
        └── test-connection.yaml
```

The exact set of generated files varies slightly between Helm versions.

### What each part does

| File / Folder | Purpose |
|---|---|
| `Chart.yaml` | Required. Name, chart version, app version, description, dependencies |
| `values.yaml` | Default values. Users override these at install or upgrade time |
| `templates/` | Every file here is rendered through the template engine. Files that produce YAML are sent to Kubernetes |
| `templates/_helpers.tpl` | Files starting with `_` are **not** rendered as manifests. Used for named templates and functions |
| `templates/NOTES.txt` | Usage notes shown to the user after deploy |
| `templates/tests/` | Pods that run with `helm test` |
| `charts/` | Packaged dependencies (populated by `helm dependency update`) |
| `crds/` (optional) | Raw CRD YAML, installed first and **not templated** |
| `values.schema.json` (optional) | JSON Schema to validate user-supplied values |
| `.helmignore` | Like `.gitignore` for chart packaging |

---

## 6. Chart.yaml Explained

```yaml
apiVersion: v2              # v2 = Helm 3 charts
name: myapp                 # Chart name (must match the folder name)
description: A Helm chart for my web application
type: application           # application (deployable) or library (reusable templates only)
version: 0.1.0              # CHART version (SemVer). Bump when the chart changes
appVersion: "1.0.0"         # Version of the APP being deployed (informational)
kubeVersion: ">=1.25.0-0"   # Optional: supported Kubernetes versions
keywords:
  - web
  - demo
maintainers:
  - name: Ram
dependencies:               # Optional: subcharts
  - name: redis
    version: "19.x.x"
    repository: https://charts.bitnami.com/bitnami
    condition: redis.enabled
```

**`version` vs `appVersion`**

| Field | Meaning | Example |
|---|---|---|
| `version` | Version of the **chart packaging** | Changed a template, bump `0.1.0` to `0.2.0` |
| `appVersion` | Version of the **application** inside the chart | App image `nginx:1.27` means `appVersion: "1.27"` |

---

## 7. values.yaml and Variables

`values.yaml` holds the defaults. Templates read these values through the `.Values` object.

```yaml
# values.yaml
replicaCount: 2

image:
  repository: nginx
  tag: "1.27"
  pullPolicy: IfNotPresent

service:
  type: ClusterIP
  port: 80

ingress:
  enabled: false
  className: nginx
  host: myapp.example.com

resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 250m
    memory: 256Mi

env:
  APP_ENV: development
  LOG_LEVEL: info
```

### Built-in objects available in templates

| Object | What it contains | Example |
|---|---|---|
| `.Values` | Merged values (defaults + overrides) | `{{ .Values.image.tag }}` |
| `.Release.Name` | Name of the release | `my-app` |
| `.Release.Namespace` | Target namespace | `prod` |
| `.Release.IsInstall` / `.Release.IsUpgrade` | Booleans for the current operation | |
| `.Release.Revision` | Revision number | `3` |
| `.Chart.Name`, `.Chart.Version`, `.Chart.AppVersion` | Data from `Chart.yaml` | `{{ .Chart.AppVersion }}` |
| `.Files` | Access non-template files in the chart | `{{ .Files.Get "config.ini" }}` |
| `.Capabilities.KubeVersion` | Cluster version information | `{{ .Capabilities.KubeVersion.Version }}` |
| `.Template.Name` | Path of the current template file | |

Note: built-in objects start with a **capital letter**. Values you define can use any name; lowerCamelCase is the convention.

---

## 8. Template Language Basics

Helm templates use Go's `text/template` plus the Sprig function library. Anything inside `{{ ... }}` is evaluated; everything else is output as-is.

### 8.1 Printing values

```yaml
replicas: {{ .Values.replicaCount }}
image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
namespace: {{ .Release.Namespace }}
```

### 8.2 Pipelines and functions

A pipeline passes the value on the left into the function on the right, like a Unix pipe.

```yaml
name: {{ .Values.name | upper | quote }}
tag: {{ .Values.image.tag | default .Chart.AppVersion | quote }}
```

| Function | Purpose | Example |
|---|---|---|
| `quote` | Wrap in double quotes | `{{ .Values.port \| quote }}` |
| `default` | Fallback when the value is empty | `{{ .Values.tag \| default "latest" }}` |
| `required` | Fail rendering if missing | `{{ required "image.tag is required" .Values.image.tag }}` |
| `upper`, `lower`, `title` | Case conversion | |
| `trunc`, `trimSuffix` | Truncate or trim strings | `{{ .Release.Name \| trunc 63 }}` |
| `toYaml` | Convert an object to YAML text | `{{ toYaml .Values.resources }}` |
| `indent N`, `nindent N` | Indent text (`nindent` adds a leading newline) | `{{ toYaml .Values.x \| nindent 4 }}` |
| `b64enc` | Base64 encode (for Secrets) | `{{ .Values.password \| b64enc }}` |
| `include` | Render a named template and return a string (pipeable) | `{{ include "myapp.labels" . \| nindent 4 }}` |
| `tpl` | Render a string as a template | `{{ tpl .Values.configText . }}` |
| `lookup` | Query live cluster objects | `lookup "v1" "Secret" "ns" "name"` |

### 8.3 Whitespace control

A hyphen inside the braces trims whitespace:

- `{{-` removes whitespace (including newlines) **before** the action.
- `-}}` removes whitespace **after** the action.

```yaml
{{- if .Values.ingress.enabled }}
# this line starts at column 0 with no blank line before it
{{- end }}
```

Wrong whitespace is the number one cause of "mapping values are not allowed" YAML errors. Always check with `helm template`.

### 8.4 Conditionals

```yaml
{{- if .Values.ingress.enabled }}
# ... Ingress manifest ...
{{- end }}

{{- if eq .Values.service.type "NodePort" }}
nodePort: {{ .Values.service.nodePort }}
{{- else if eq .Values.service.type "LoadBalancer" }}
# ...
{{- else }}
# ...
{{- end }}
```

| Operator | Meaning |
|---|---|
| `eq`, `ne` | equal, not equal |
| `lt`, `gt`, `le`, `ge` | comparisons |
| `and`, `or`, `not` | logic (for example `and .Values.a .Values.b`) |
| `empty` | true if the value is empty (0, "", nil, empty list or map) |

Falsy values: `false`, `0`, `""`, `nil`, empty list, empty map.

### 8.5 `with` (change scope)

`with` sets `.` to the given value and skips the block if it is empty.

```yaml
{{- with .Values.nodeSelector }}
nodeSelector:
  {{- toYaml . | nindent 2 }}
{{- end }}
```

Inside `with`, `.` is no longer the root. Use `$` to reach the root:

```yaml
{{- with .Values.image }}
image: {{ .repository }}:{{ .tag }}
release: {{ $.Release.Name }}
{{- end }}
```

### 8.6 `range` (loops)

Loop over a list:

```yaml
# values.yaml
ports:
  - 80
  - 443
```

```yaml
ports:
{{- range .Values.ports }}
  - containerPort: {{ . }}
{{- end }}
```

Loop over a map (key and value):

```yaml
env:
{{- range $key, $value := .Values.env }}
  - name: {{ $key }}
    value: {{ $value | quote }}
{{- end }}
```

### 8.7 Variables

Assign to a variable with `:=`, reassign with `=`.

```yaml
{{- $fullName := include "myapp.fullname" . -}}
{{- $port := .Values.service.port -}}
name: {{ $fullName }}
port: {{ $port }}
```

### 8.8 Named templates (`define`, `include`)

Defined in `templates/_helpers.tpl`, reused everywhere:

```yaml
{{- define "myapp.labels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}
```

Use it:

```yaml
metadata:
  labels:
    {{- include "myapp.labels" . | nindent 4 }}
```

Always pass `.` (the context) as the second argument. Prefer `include` over `template` because `include` output can be piped.

### 8.9 Comments

```yaml
{{- /* This comment is removed from the rendered output */ -}}
# This YAML comment IS kept in the rendered output
```

---

## 9. Build Your Own Chart Step by Step

We build a web application chart called **myapp** with a Deployment, Service, ConfigMap and optional Ingress.

### Step 1: Create the skeleton and clean it

```bash
helm create myapp
cd myapp
rm -rf templates/*          # start clean so you understand every file
rm -f templates/tests/*
```

### Step 2: Write `Chart.yaml`

```yaml
apiVersion: v2
name: myapp
description: Simple web application
type: application
version: 0.1.0
appVersion: "1.27"
```

### Step 3: Write `values.yaml`

```yaml
replicaCount: 2

image:
  repository: nginx
  tag: ""                    # empty means use Chart.appVersion
  pullPolicy: IfNotPresent

service:
  type: ClusterIP
  port: 80

ingress:
  enabled: false
  className: nginx
  host: myapp.example.com

env:
  APP_ENV: development
  LOG_LEVEL: info

resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 250m
    memory: 256Mi
```

### Step 4: Write `templates/_helpers.tpl`

```yaml
{{/* Full resource name: <release>-<chart>, max 63 chars */}}
{{- define "myapp.fullname" -}}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/* Labels used to select pods (must stay stable) */}}
{{- define "myapp.selectorLabels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/* Common labels */}}
{{- define "myapp.labels" -}}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{ include "myapp.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}
```

### Step 5: Write `templates/configmap.yaml`

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ include "myapp.fullname" . }}
  labels:
    {{- include "myapp.labels" . | nindent 4 }}
data:
  {{- range $key, $value := .Values.env }}
  {{ $key }}: {{ $value | quote }}
  {{- end }}
```

### Step 6: Write `templates/deployment.yaml`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "myapp.fullname" . }}
  labels:
    {{- include "myapp.labels" . | nindent 4 }}
spec:
  replicas: {{ .Values.replicaCount }}
  selector:
    matchLabels:
      {{- include "myapp.selectorLabels" . | nindent 6 }}
  template:
    metadata:
      annotations:
        # Restart pods automatically when the ConfigMap content changes
        checksum/config: {{ include (print $.Template.BasePath "/configmap.yaml") . | sha256sum }}
      labels:
        {{- include "myapp.selectorLabels" . | nindent 8 }}
    spec:
      containers:
        - name: {{ .Chart.Name }}
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag | default .Chart.AppVersion }}"
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          ports:
            - name: http
              containerPort: 80
          envFrom:
            - configMapRef:
                name: {{ include "myapp.fullname" . }}
          readinessProbe:
            httpGet:
              path: /
              port: http
          livenessProbe:
            httpGet:
              path: /
              port: http
          resources:
            {{- toYaml .Values.resources | nindent 12 }}
```

### Step 7: Write `templates/service.yaml`

```yaml
apiVersion: v1
kind: Service
metadata:
  name: {{ include "myapp.fullname" . }}
  labels:
    {{- include "myapp.labels" . | nindent 4 }}
spec:
  type: {{ .Values.service.type }}
  ports:
    - port: {{ .Values.service.port }}
      targetPort: http
      protocol: TCP
      name: http
  selector:
    {{- include "myapp.selectorLabels" . | nindent 4 }}
```

### Step 8: Write `templates/ingress.yaml` (conditional)

```yaml
{{- if .Values.ingress.enabled }}
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: {{ include "myapp.fullname" . }}
  labels:
    {{- include "myapp.labels" . | nindent 4 }}
spec:
  ingressClassName: {{ .Values.ingress.className }}
  rules:
    - host: {{ .Values.ingress.host | quote }}
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: {{ include "myapp.fullname" . }}
                port:
                  number: {{ .Values.service.port }}
{{- end }}
```

### Step 9: Write `templates/NOTES.txt`

```
Release {{ .Release.Name }} installed in namespace {{ .Release.Namespace }}.

Access the application:
  kubectl port-forward svc/{{ include "myapp.fullname" . }} 8080:{{ .Values.service.port }} -n {{ .Release.Namespace }}
  curl http://localhost:8080
```

### Step 10: Final structure

```
myapp/
├── Chart.yaml
├── values.yaml
└── templates/
    ├── _helpers.tpl
    ├── configmap.yaml
    ├── deployment.yaml
    ├── service.yaml
    ├── ingress.yaml
    └── NOTES.txt
```

### Step 11: Lint, render and deploy

```bash
helm lint ./myapp
helm template my-release ./myapp                  # print rendered YAML only
helm install my-release ./myapp -n demo --create-namespace
kubectl get all -n demo
```

### Step 12: Test it

```bash
kubectl port-forward svc/my-release-myapp 8080:80 -n demo
curl http://localhost:8080
```

---

## 10. Overriding Values

Values come from several sources and are **merged**. Later sources win.

### Precedence (lowest to highest)

| Order | Source |
|---|---|
| 1 | `values.yaml` inside the chart (defaults) |
| 2 | Parent chart's `values.yaml` (for subcharts) |
| 3 | `-f` / `--values` files, in the order given (later file wins) |
| 4 | `--set`, `--set-string`, `--set-file`, `--set-json` (highest) |

### 10.1 Override with `--set`

```bash
helm install my-release ./myapp \
  --set replicaCount=3 \
  --set image.tag=1.26 \
  --set service.type=NodePort
```

`--set` syntax:

| Need | Syntax |
|---|---|
| Nested key | `--set image.tag=1.26` |
| Multiple values | `--set a=1,b=2` |
| List item | `--set ports[0]=80,ports[1]=443` |
| List with braces | `--set "hosts={a.com,b.com}"` |
| Keep as string | `--set-string version=1.20` |
| Dot in key name | `--set annotations."kubernetes\.io/foo"=bar` |
| Value from a file | `--set-file config=./app.conf` |

### 10.2 Override with a values file (recommended)

`values-prod.yaml` needs only the keys that **differ**:

```yaml
replicaCount: 5

image:
  tag: "1.27.1"

service:
  type: LoadBalancer

ingress:
  enabled: true
  host: myapp.prod.example.com

env:
  APP_ENV: production
  LOG_LEVEL: warn

resources:
  requests:
    cpu: 500m
    memory: 512Mi
  limits:
    cpu: "1"
    memory: 1Gi
```

```bash
helm install my-release ./myapp -f values-prod.yaml
```

### 10.3 Layering multiple files

```bash
helm upgrade --install my-release ./myapp \
  -f values-base.yaml \
  -f values-prod.yaml \
  --set image.tag=1.27.2
```

Result: `values.yaml` < `values-base.yaml` < `values-prod.yaml` < `--set`.

### 10.4 Merge behavior to remember

- **Maps** merge key by key. Overriding `env.LOG_LEVEL` keeps `env.APP_ENV`.
- **Lists** are **replaced entirely**, never merged item by item.
- Set a key to `null` to delete a default: `--set env.LOG_LEVEL=null`.

### 10.5 Inspect what was applied

```bash
helm get values my-release                # only your overrides
helm get values my-release --all          # overrides + defaults (computed)
helm get manifest my-release              # rendered manifests in the cluster
```

### 10.6 Upgrade value flags

| Flag | Behavior |
|---|---|
| (default) | Chart defaults + only the values supplied in this command |
| `--reuse-values` | Reuse last release's values and merge new `--set` on top |
| `--reset-values` | Ignore previous overrides, use chart defaults + new values |
| `--reset-then-reuse-values` | Reset to the new chart's defaults, then reapply last release's overrides |

Common trap: after `helm upgrade ./myapp --set image.tag=2.0` **without** `--reuse-values`, earlier `--set` overrides are lost. Keeping all overrides in values files avoids this.

### 10.7 Validate values with a schema (optional)

`values.schema.json` in the chart root:

```json
{
  "$schema": "https://json-schema.org/draft-07/schema#",
  "type": "object",
  "required": ["replicaCount"],
  "properties": {
    "replicaCount": { "type": "integer", "minimum": 1 },
    "service": {
      "type": "object",
      "properties": {
        "type": { "enum": ["ClusterIP", "NodePort", "LoadBalancer"] }
      }
    }
  }
}
```

Helm validates values against it during `install`, `upgrade`, `lint` and `template`.

---

## 11. Validate Before Deploying

```bash
# 1. Static checks for chart structure and syntax
helm lint ./myapp
helm lint ./myapp -f values-prod.yaml

# 2. Render locally (no cluster changes)
helm template my-release ./myapp -f values-prod.yaml
helm template my-release ./myapp -s templates/deployment.yaml   # one file only

# 3. Simulate an install against the cluster (no changes saved)
helm install my-release ./myapp --dry-run --debug

# 4. Validate rendered output with kubectl
helm template my-release ./myapp | kubectl apply --dry-run=server -f -

# 5. See what an upgrade would change (needs the helm-diff plugin)
helm plugin install https://github.com/databus23/helm-diff
helm diff upgrade my-release ./myapp -f values-prod.yaml
```

| Command | Talks to cluster? | Use |
|---|---|---|
| `helm lint` | No | Catch chart errors |
| `helm template` | No | See rendered YAML |
| `helm install --dry-run` | Yes (read) | Server-side render with cluster capabilities |
| `kubectl apply --dry-run=server` | Yes | Validate against API schemas and admission |

---

## 12. Deploy and Manage Releases

### 12.1 Install

```bash
helm install my-release ./myapp \
  --namespace demo \
  --create-namespace \
  -f values-prod.yaml \
  --wait --timeout 5m
```

| Flag | Purpose |
|---|---|
| `-n`, `--namespace` | Target namespace for the release |
| `--create-namespace` | Create the namespace if it does not exist |
| `--wait` | Wait until pods, Deployments and Services are ready |
| `--atomic` | On failure, roll back automatically (implies `--wait`) |
| `--timeout` | How long to wait (default 5m) |
| `--generate-name` | Let Helm pick a release name |

### 12.2 Upgrade

```bash
helm upgrade my-release ./myapp -n demo -f values-prod.yaml --set image.tag=1.27.2
```

**Idempotent deploy** (install if absent, otherwise upgrade). Use this in CI/CD:

```bash
helm upgrade --install my-release ./myapp \
  -n demo --create-namespace \
  -f values-prod.yaml \
  --atomic --timeout 5m
```

### 12.3 Inspect

```bash
helm list -n demo                    # releases in a namespace
helm list -A                         # all namespaces
helm status my-release -n demo
helm get all my-release -n demo      # values + manifest + notes + hooks
helm get manifest my-release -n demo
helm get notes my-release -n demo
```

### 12.4 History and rollback

```bash
helm history my-release -n demo

# REVISION  STATUS      DESCRIPTION
# 1         superseded  Install complete
# 2         superseded  Upgrade complete
# 3         deployed    Upgrade complete

helm rollback my-release 2 -n demo     # roll back to revision 2 (creates revision 4)
helm rollback my-release -n demo       # roll back to the previous revision
```

Limit stored history with `--history-max 10` on upgrade.

### 12.5 Uninstall

```bash
helm uninstall my-release -n demo
helm uninstall my-release -n demo --keep-history   # keep history so you can roll back
```

### 12.6 Release lifecycle

```
install ──► revision 1 (deployed)
   │
upgrade ──► revision 2 (deployed), revision 1 (superseded)
   │
rollback ─► revision 3 (deployed, same content as revision 1)
   │
uninstall ► resources removed (history removed unless --keep-history)
```

---

## 13. Dependencies and Subcharts

A chart can bundle other charts, for example an app plus Redis.

### Declare in `Chart.yaml`

```yaml
dependencies:
  - name: redis
    version: "19.x.x"
    repository: https://charts.bitnami.com/bitnami
    condition: redis.enabled        # turn on/off via values
    alias: cache                    # optional rename
```

### Download

```bash
helm dependency update ./myapp      # downloads into charts/ and writes Chart.lock
helm dependency build ./myapp       # rebuild from Chart.lock
helm dependency list ./myapp
```

### Configure a subchart from the parent's values

Values under the subchart's name (or alias) are passed to it:

```yaml
# myapp/values.yaml
redis:
  enabled: true
  architecture: standalone
  auth:
    enabled: false
```

### Global values

Values under `global:` are visible to the parent **and** all subcharts:

```yaml
global:
  environment: production
```

```yaml
{{ .Values.global.environment }}
```

---

## 14. Hooks and Tests

### Hooks

Hooks run Jobs or Pods at specific points in the release lifecycle, such as database migrations before an upgrade.

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: {{ include "myapp.fullname" . }}-migrate
  annotations:
    "helm.sh/hook": pre-install,pre-upgrade
    "helm.sh/hook-weight": "0"
    "helm.sh/hook-delete-policy": before-hook-creation,hook-succeeded
spec:
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: migrate
          image: busybox
          command: ["sh", "-c", "echo running migrations"]
```

| Hook | Runs |
|---|---|
| `pre-install` / `post-install` | Before / after resources are created |
| `pre-upgrade` / `post-upgrade` | Before / after an upgrade |
| `pre-delete` / `post-delete` | Before / after uninstall |
| `pre-rollback` / `post-rollback` | Around a rollback |
| `test` | When `helm test` runs |

### Tests

`templates/tests/test-connection.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: {{ include "myapp.fullname" . }}-test
  annotations:
    "helm.sh/hook": test
spec:
  restartPolicy: Never
  containers:
    - name: curl
      image: curlimages/curl
      command: ["curl", "--fail", "http://{{ include "myapp.fullname" . }}:{{ .Values.service.port }}"]
```

```bash
helm test my-release -n demo
```

---

## 15. Package and Share Charts

### Package into a `.tgz`

```bash
helm package ./myapp                      # creates myapp-0.1.0.tgz
helm package ./myapp --version 0.2.0 --app-version 1.28
```

### Install from the package

```bash
helm install my-release ./myapp-0.1.0.tgz
```

### Host a simple repository (for example GitHub Pages or S3)

```bash
mkdir repo && mv myapp-0.1.0.tgz repo/
helm repo index repo/ --url https://example.com/charts
# upload repo/ (index.yaml + .tgz) to your web host

helm repo add mycharts https://example.com/charts
helm install my-release mycharts/myapp
```

### OCI registry (Docker Hub, GHCR, ECR, ACR)

```bash
helm registry login ghcr.io -u <USER>
helm push myapp-0.1.0.tgz oci://ghcr.io/<USER>/charts
helm install my-release oci://ghcr.io/<USER>/charts/myapp --version 0.1.0
```

---

## 16. Multi-Environment Strategy

Keep **one chart** and **one values file per environment**.

```
myapp/
├── Chart.yaml
├── values.yaml              # safe defaults
├── templates/
envs/
├── values-dev.yaml
├── values-staging.yaml
└── values-prod.yaml
```

```bash
# dev
helm upgrade --install myapp ./myapp -n dev  --create-namespace -f envs/values-dev.yaml

# prod
helm upgrade --install myapp ./myapp -n prod --create-namespace -f envs/values-prod.yaml \
  --set image.tag=$GIT_SHA
```

CI/CD pattern: the pipeline builds an image, then runs `helm upgrade --install --atomic --set image.tag=<build-id>`.

**Secrets:** never commit real secrets in values files. Use an external secret operator, sealed secrets, SOPS (`helm-secrets` plugin) or pass them at deploy time from your CI secret store.

---

## 17. Best Practices

1. Quote strings that may be misread: `{{ .Values.x | quote }}`.
2. Give every value a safe default in `values.yaml` and document it with comments.
3. Use `required` for values that have no sensible default.
4. Keep selector labels stable. Changing `matchLabels` on a Deployment breaks upgrades because that field is immutable.
5. Use `_helpers.tpl` for names and labels instead of repeating them.
6. Add the `checksum/config` annotation so pods restart when a ConfigMap or Secret changes.
7. Always set resource requests and limits through values.
8. Run `helm lint` and `helm template` in CI before every deploy.
9. Use `helm upgrade --install --atomic --wait` for deployments.
10. Prefer values files over long `--set` lists, and keep them in Git.
11. Pin dependency and image versions. Avoid `latest`.
12. Bump the chart `version` whenever templates change.
13. Use `.Release.Namespace` instead of hardcoding namespaces.
14. Add `values.schema.json` for charts shared with other teams.

---

## 18. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `YAML parse error ... mapping values are not allowed` | Bad indentation or whitespace from templating | Use `nindent`, add `{{-`, check with `helm template` |
| `nil pointer evaluating interface {}` | Referencing a missing key (for example `.Values.a.b` when `a` is not defined) | Add the default to `values.yaml`, or guard with `if` / `default` |
| `Error: INSTALLATION FAILED: cannot re-use a name that is still in use` | Release name already exists | Use `helm upgrade --install` or pick a new name |
| `another operation (install/upgrade/rollback) is in progress` | A previous operation was interrupted | `helm history`, then `helm rollback`, or delete the stuck `pending-*` release Secret |
| Upgrade lost earlier overrides | Missing `--reuse-values` | Keep all overrides in values files |
| Pods do not restart after ConfigMap change | No checksum annotation | Add `checksum/config` annotation |
| `field is immutable` | Changed selector labels or another immutable field | Uninstall and reinstall, or avoid changing immutable fields |
| Wrong value used | Precedence confusion | `helm get values <release> --all`, and check `-f` order |
| `Error: path "..." not found` | Wrong chart path | Run the command from the correct directory |

Debug toolkit:

```bash
helm lint ./myapp
helm template my-release ./myapp --debug
helm install my-release ./myapp --dry-run --debug
helm get manifest my-release
helm get values my-release --all
kubectl describe pod <pod>
kubectl logs <pod>
```

---

## 19. Cheat Sheet

```bash
# Repos
helm repo add <name> <url>      helm repo update      helm repo list
helm search repo <keyword>      helm search hub <keyword>

# Inspect charts
helm show chart|values|readme <chart>
helm pull <chart> --untar

# Create and check
helm create <name>
helm lint <path>
helm template <release> <path> -f <values>

# Deploy
helm install <release> <chart> -n <ns> --create-namespace -f values.yaml --set k=v
helm upgrade --install <release> <chart> -n <ns> -f values.yaml --atomic --wait
helm test <release>

# Inspect releases
helm list -A            helm status <release>        helm history <release>
helm get values|manifest|notes|all <release>

# Undo
helm rollback <release> [REVISION]
helm uninstall <release> [--keep-history]

# Dependencies and packaging
helm dependency update <path>
helm package <path>
helm push <chart.tgz> oci://<registry>/<path>
```

### Template syntax cheat sheet

| Task | Syntax |
|---|---|
| Print value | `{{ .Values.key }}` |
| Default | `{{ .Values.key \| default "x" }}` |
| Quote | `{{ .Values.key \| quote }}` |
| Required | `{{ required "msg" .Values.key }}` |
| If / else | `{{- if cond }} ... {{- else }} ... {{- end }}` |
| Scope | `{{- with .Values.key }} ... {{- end }}` |
| Loop list | `{{- range .Values.list }} {{ . }} {{- end }}` |
| Loop map | `{{- range $k, $v := .Values.map }} ... {{- end }}` |
| Variable | `{{- $x := .Values.key -}}` |
| Define | `{{- define "name" -}} ... {{- end }}` |
| Include | `{{- include "name" . \| nindent 4 }}` |
| Object to YAML | `{{- toYaml .Values.obj \| nindent 4 }}` |
| Root scope inside `with` / `range` | `$.Values`, `$.Release.Name` |
