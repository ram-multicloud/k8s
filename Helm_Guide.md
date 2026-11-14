# Helm: Complete Notebook

## 1. What Is Helm and Why Do We Need It?

### 1.1 The problem

Deploying to Kubernetes means describing resources in YAML and sending them to the API with `kubectl`. Those YAML files are **static**. They are not built to take parameters.

Two manifests for two different applications are usually almost identical (name, image, labels, ports and replicas differ). Without parameters you copy and edit them for every application and every environment.

### 1.2 The solution

**Helm is the package manager for Kubernetes.** It is an open-source tool for packaging and deploying applications.

| Linux package world | Helm world |
|---|---|
| `.deb` / `.rpm` package | **Chart** |
| apt / yum / dnf | `helm` |
| Package repository | **Chart repository** |
| Installed package | **Release** |

- A **chart** holds the declarative Kubernetes resource files needed to deploy an application, written as templates.
- A **chart repository** is where charts are published. Chart developers write the YAML, package it and publish it. End users search the repository and install what they need.
- A **release** is one installed instance of a chart in a cluster. The same chart can be installed many times under different release names.

Example: Bitnami publishes a MySQL chart, so installing MySQL is one command instead of writing the Pod, Service and storage YAML yourself.

---

## 2. Helm Commands Compared to DNF 

| DNF | Helm | Purpose |
|---|---|---|
| `install` | `helm install` | Install an application and its dependencies |
| `upgrade` | `helm upgrade` | Upgrade to a newer version |
| `downgrade` | `helm rollback` | Return to a previous version |
| `remove` | `helm uninstall` | Delete an application |

**Hidden complexity:** to deploy MySQL by hand you create resources for containers, networking and storage. With Helm you search for the MySQL chart and install it.

**Lifecycle hooks:** Helm can run actions automatically at stages of a release. The class examples were taking a backup on upgrade, restoring data on rollback, and validating the Kubernetes environment before install. See section 14.

---

## 3. Install and Configure Helm 

### 3.1 Install

```bash
# Windows (used in the 2026 class)
choco install kubernetes-helm -y
# the class pinned a version: choco install kubernetes-helm --version=3.3.0 -y

# Linux / macOS
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
# or: brew install helm

helm version
```

Official guide: https://helm.sh/docs/intro/install/. Pinning an old version is fine for a classroom, but use a current Helm 3 release for real work.

### 3.2 Helm 2 versus Helm 3

Helm and Kubernetes work like a client and a server. The Helm client pushes the resources to the cluster.

| | Helm 2 | Helm 3 |
|---|---|---|
| Server component | **Tiller** runs inside the cluster | **No Tiller**, uses the Kubernetes API directly |
| Credentials | Tiller's own service account | Your `kubectl` credentials (kubeconfig) |
| Chart `apiVersion` | `v1` | `v2` |
| Dependencies file [Added] | `requirements.yaml` | `dependencies:` inside `Chart.yaml` |
| Release storage [Added] | ConfigMaps in the Tiller namespace | Secrets in the release's own namespace |
| Install without a name [Added] | Generated a random name | Name is required, or use `--generate-name` |
| Renamed commands [Added] | `helm delete`, `helm fetch`, `helm search` | `helm uninstall`, `helm pull`, `helm search repo` / `helm search hub` |

Helm 3 is the version used everywhere in this notebook.

### 3.3 Configuration: environment variables and paths

Helm works with sensible defaults. Low-level options come from environment variables:

| Variable | Purpose |
|---|---|
| `XDG_CACHE_HOME` | Alternative location for cached files |
| `XDG_CONFIG_HOME` | Alternative location for Helm configuration |
| `XDG_DATA_HOME` | Alternative location for Helm data |
| `HELM_DRIVER` | Backend that stores release information (for example `secret`, `configmap`, `memory`) |
| `HELM_NO_PLUGINS` | Set to disable plugins |
| `KUBECONFIG` | Use an alternative Kubernetes config file |

Default paths:

| OS | Cache | Config | Data |
|---|---|---|---|
| Windows | `%TEMP%\helm` | `%APPDATA%\helm` | `%APPDATA%\helm` |
| Linux | `$HOME/.cache/helm` | `$HOME/.config/helm` | `$HOME/.local/share/helm` |
| macOS | `$HOME/Library/Caches/helm` | `$HOME/Library/Preferences/helm` | `$HOME/Library/helm` |

Full list: https://helm.sh/docs/helm/helm/

---

## 4. Repositories and Plugins

### 4.1 `helm repo`

| Subcommand | Purpose |
|---|---|
| `add` | Add a chart repository |
| `list` | List configured repositories |
| `remove` | Remove a repository |
| `update` | Refresh the local list of available charts |
| `index` | Generate an `index.yaml` for a directory of packaged charts |

### 4.2 Example from class: install MySQL from Bitnami

```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update
helm install my-release bitnami/mysql
helm uninstall my-release
```

Check the chart's current repository address in its documentation before relying on it, because large vendors do change where charts are published.

### 4.3 Searching and inspecting charts  [Added]

```bash
helm search repo mysql                   # search your added repositories
helm search hub grafana                  # search Artifact Hub (https://artifacthub.io)
helm show chart  bitnami/mysql
helm show values bitnami/mysql > mysql-values.yaml    # read this before installing
helm pull bitnami/mysql --untar          # download and unpack to study its templates
```

### 4.4 Plugins

Plugins add features to Helm and are managed with `helm plugin` (`install`, `list`, `update`, `uninstall`). A list of community plugins is at https://helm.sh/docs/community/related/. Commonly useful ones [Added]: `helm-diff` (preview upgrade changes) and `helm-secrets` (encrypted values).

---

## 5. Chart Structure

Create a chart:

```bash
helm create --help
helm create helloworld
```

Generated layout:

```text
helloworld/
├── Chart.yaml          # chart metadata
├── values.yaml         # default values, overridden at deploy time
├── .helmignore         # files left out of the packaged chart
├── charts/             # dependency charts (subcharts)
└── templates/          # Kubernetes manifest templates
    ├── NOTES.txt       # message printed after install or upgrade
    ├── _helpers.tpl    # reusable named templates (no manifest output)
    ├── deployment.yaml
    ├── service.yaml
    ├── serviceaccount.yaml
    ├── ingress.yaml
    ├── hpa.yaml
    └── tests/
        └── test-connection.yaml
```

Reference for every file and directory:

| File or directory | Purpose | Required? |
|---|---|---|
| `Chart.yaml` | Metadata about the chart | Yes |
| `templates/` | Kubernetes resources in YAML (templates) | Yes, unless dependencies are declared in `Chart.yaml` |
| `templates/NOTES.txt` | Usage instructions shown after install | No |
| `values.yaml` | The chart's default values | No, but every chart should have one |
| `.helmignore` | Files and directories to leave out when packaging | No |
| `charts/` | Charts this chart depends on | Created automatically by dependency management |
| `Chart.lock` | Records the dependency versions that were applied | Created automatically |
| `crds/` | Custom Resource Definitions installed before the templates | No |
| `README.md` | Install and usage information | No, but good practice |
| `LICENSE` | License of the chart | No |
| `values.schema.json` | JSON schema that validates the values | No |

Official reference: https://helm.sh/docs/topics/charts/

### YAML refresher used in class 

A multi-line string uses a block marker:

```yaml
configurations: |
  server.port=8443
  logging.file.path=/var/log
```

---

## 6. `Chart.yaml` in Detail

```yaml
apiVersion: v2            # v2 means Helm 3 chart format
name: website-qt          # chart name (lower case, no dots)
description: Helm chart for the QT website
type: application         # application (default) or library
version: 0.1.0            # the CHART version (SemVer)
appVersion: "2.4"         # the version of the APPLICATION being deployed

# optional descriptive fields
home: https://example.com
icon: https://example.com/icon.png
keywords: [website, apache]
sources:
  - https://github.com/example/website-qt
maintainers:
  - name: Your Name
    email: you@example.com

# optional dependencies (section 15)
dependencies: []
```

| Field | Notes |
|---|---|
| `apiVersion` | `v2` is for Helm 3 |
| `name` | Identifies the chart |
| `version` | Helm uses it to order and identify charts |
| `appVersion` | The application's own release tag. It is information only |
| `type` | The class notes list sample categories (database, monitoring, RBAC) for illustration. The real values are `application` and `library` |
| `home`, `icon`, `maintainers`, `keywords`, `sources` | Descriptive metadata |

**Chart versioning (SemVer):**

| Change | Bump | Example |
|---|---|---|
| Bug fix in templates | Patch | 0.1.0 → 0.1.1 |
| New backward-compatible option | Minor | 0.1.0 → 0.2.0 |
| Breaking change in values or behaviour | Major | 0.1.0 → 1.0.0 |

Sample real-world file: https://github.com/bitnami/charts/blob/master/bitnami/mysql/Chart.yaml

---

## 7. Installing, Upgrading and Overriding Values

### 7.1 First install

`helm create` produces a working Nginx chart, so you can install it straight away:

```bash
helm create myapp
helm install myapp ./myapp
```

The output shows `NAME`, `LAST DEPLOYED`, `NAMESPACE`, `STATUS: deployed`, `REVISION: 1` and the contents of `NOTES.txt`. The generated notes explain how to port-forward to a pod and open the app on `http://127.0.0.1:8080`.

### 7.2 Command sequence from the 31/Oct class

```bash
helm create httpd                    # create a sample chart
helm template http-app httpd/        # render YAML only (nothing is installed)
helm install http-app httpd/         # install
helm upgrade http-app httpd/         # upgrade an existing release
helm upgrade -i http-app httpd/      # upgrade, or install if it does not exist

# override one value from the command line
helm upgrade http-app httpd/ --set service.type=NodePort

# override values from a file
helm upgrade http-app httpd/ --values override.yaml

# target a namespace and create it if missing
helm upgrade -i http-app httpd/ --values override.yaml --namespace dev-1 --create-namespace

# or create the namespace first yourself
kubectl create ns frontend
helm upgrade -i http-app httpd/ --values override.yaml --namespace frontend
```

Syntax: `helm template [release-name] [chart-path-or-url] [flags]`.

### 7.3 Value precedence  [Added]

From lowest to highest:

1. The chart's own `values.yaml`
2. `-f / --values` files (a later file overrides an earlier one)
3. `--set`, `--set-string`, `--set-file`

### 7.4 Useful flags  [Added]

| Flag | Purpose |
|---|---|
| `--set key=value` | Override one value |
| `--set-string key=value` | Force a string (for example a port number you want kept as text) |
| `-f values.yaml` | Override from a file (repeatable) |
| `-n <ns>` / `--create-namespace` | Target namespace, create if missing |
| `--wait --timeout 5m` | Wait until resources are ready |
| `--atomic` | Roll back automatically if the install or upgrade fails (implies `--wait`) |
| `--dry-run --debug` | Preview what would be installed |
| `--version <v>` | Install a specific chart version |

### 7.5 `helm template` versus `helm install --dry-run`  [Added]

| | `helm template` | `helm install --dry-run --debug` |
|---|---|---|
| Needs a cluster | No | Yes |
| Checks against cluster (APIs, existing resources) | No | Yes |
| Typical use | Develop and review YAML, CI checks | Last check before a real install |

---

## 8. The Template Engine

### 8.1 Go templates

Helm is written in Go and uses Go's `text/template` package for its templates (https://pkg.go.dev/text/template). Anything inside `{{` and `}}` is an **action** (logic, control structure or data lookup). Everything outside actions is copied to the output as is.

```yaml
product: {{ .Values.product | default "kubernetes" | quote }}
```

### 8.2 Pipelines

A pipeline chains commands with `|`, exactly like a Unix pipe. The value on the left is passed as the **last argument** of the next function.

In the example above:

1. `.Values.product` is read from the values data.
2. It is passed as the last argument to `default`.
3. The result of `default` is passed to `quote`.

The leading dot in `.Values.product` is the **root object** of the current scope.

### 8.3 Whitespace control

A dash inside the braces trims whitespace on that side.

```text
{{ "Hello" -}}, {{- "World" }}, {{- "of Helm" -}}
```

renders as `Hello,World,of Helm`. In manifests, `{{-` removes the blank line left by a control action, which keeps YAML indentation valid.

### 8.4 Template functions

Functions transform data. They range from simple ones like `indent` and `nindent` to functions that read from the cluster. Most come from the **Sprig** library (http://masterminds.github.io/sprig/), and Helm adds more of its own. There are over a hundred in total (list: https://helm.sh/docs/chart_template_guide/function_list/).

| Function | Purpose | Example |
|---|---|---|
| `default` | Fallback for empty values | `{{ .Values.tag \| default "latest" }}` |
| `required` [Added] | Fail rendering with a message when missing | `{{ required "image.repository is required" .Values.image.repository }}` |
| `quote` | Wrap in double quotes | `{{ .Values.name \| quote }}` |
| `upper` / `lower` | Change case | `{{ .Values.appName \| upper }}` |
| `indent` / `nindent` | Indent text (`nindent` adds a newline first) | `{{ toYaml .Values.x \| nindent 4 }}` |
| `toYaml` / `toJson` [Added] | Convert maps and lists to text | `{{ toJson .Values.args }}` |
| `printf` [Added] | Format a string | `{{ printf "%s-%s" .Release.Name .Chart.Name }}` |
| `trunc`, `trimSuffix` [Added] | Keep names within 63 characters | `{{ .Release.Name \| trunc 63 \| trimSuffix "-" }}` |
| `b64enc` [Added] | Base64 for Secrets | `{{ .Values.password \| b64enc }}` |
| `sha256sum` [Added] | Hash text | used for config checksums |
| `include` [Added] | Render a named template to a string | `{{ include "x.labels" . }}` |
| `lookup` [Added] | Read an existing resource from the cluster | returns empty under `helm template` |

### 8.5 Methods

- `.Capabilities.APIVersions.Has "<api or type>"` checks whether the cluster supports an API or resource type.
- `.Files` reads non-template files bundled in the chart:

| Method | Purpose |
|---|---|
| `.Files.Get name` | Contents of a file |
| `.Files.GetBytes name` | Contents as bytes |
| `.Files.Glob pattern` | Select a group of files |
| `.Files.AsConfig` | Turn a file group into flat YAML for a ConfigMap `data:` section |
| `.Files.AsSecret` | Same, base64-encoded for a Secret |
| `.Files.Lines name` | File contents line by line |

### 8.6 What Helm passes into every template

When Helm renders a template it passes **one data object**, written `.` inside the template.

**`.Values`** holds the values from `values.yaml`, `-f` files and `--set`. There is no fixed schema; the structure is whatever the chart defines.

**`.Release`**

| Property | Meaning |
|---|---|
| `.Release.Name` | Name of the release |
| `.Release.Namespace` | Namespace the chart is released to |
| `.Release.IsInstall` | `true` when this is a first install |
| `.Release.IsUpgrade` | `true` for an upgrade or a rollback |
| `.Release.Service` | The tool doing the release (`Helm`) |
| `.Release.Revision` [Added] | Revision number: 1, 2, 3... |

**`.Chart`** holds the contents of `Chart.yaml`: `.Chart.Name`, `.Chart.Version`, `.Chart.AppVersion`, `.Chart.Annotations`. Note the capital first letter in templates, although the keys are lower case in `Chart.yaml`. To pass custom data from `Chart.yaml` into a template, put it under `annotations`.

**`.Capabilities`** describes the cluster: `.Capabilities.ApiVersions`, `.Capabilities.KubeVersion.Version`, `.Capabilities.KubeVersion.Major`, `.Capabilities.KubeVersion.Minor`.

**`.Template`** describes the template being rendered: `.Template.Name` (for example `inventory/templates/deployment.yaml`) and `.Template.BasePath` (`inventory/templates`).

### 8.7 Practice with the playground

You can try templates in the browser at https://helm-playground.com/ (used in the 01/Nov class).

---

## 9. Values and Types  [Class: 01/Nov/2026]

| Type | Example in `values.yaml` |
|---|---|
| string | `name: apache` |
| integer | `replicas: 2` |
| float | `ratio: 0.5` |
| boolean | `enabled: true` |
| null | `tag: null` |
| list | `ports: [80, 443]` |
| map | `image: {name: alpine, tag: latest}` |

### 9.1 Checking and converting types in templates

| Task | Template |
|---|---|
| See the type | `{{ typeOf .Values.replicas }}` (an `int` from a file often shows as `float64`) |
| To integer | `{{ .Values.replicas \| int }}` |
| To string | `{{ .Values.replicas \| toString }}` |
| Text to number | `{{ "8080" \| atoi }}` |
| Add quotes | `{{ .Values.appName \| quote }}` |
| Upper case | `{{ .Values.appName \| upper }}` |
| Lower case | `{{ .Values.appName \| lower }}` |

---

## 10. Logic and Flow Control 

### 10.1 Comparison and boolean functions

| Function | Meaning | Example |
|---|---|---|
| `eq` | equal | `eq .Values.env "prod"` |
| `ne` | not equal | `ne .Values.env "prod"` |
| `gt` | greater than | `gt (int .Values.replicas) 1` |
| `ge` | greater than or equal | `ge (int .Values.replicas) 2` |
| `lt` | less than | `lt (int .Values.replicas) 5` |
| `le` | less than or equal | `le (int .Values.replicas) 5` |
| `and` | all must be true | `and .Values.enabled (eq .Values.env "prod")` |
| `or` | any one true | `or .Values.a .Values.b` |
| `not` | opposite | `not .Values.enabled` |
| `empty` | null, empty, zero, empty list or map | `empty .Values.nodeSelector` |

Functions take their arguments **after** the name (prefix style), and a nested call goes in parentheses. A leading `-` right after `{{` is whitespace trimming, never a flag.

### 10.2 `if`, `else if`, `else`, `end`

```yaml
{{- if eq .Values.env "prod" }}
replicas: {{ .Values.prod.replicas }}
{{- else }}
replicas: 1
{{- end }}
```

Every `if`, `with` and `range` must be closed by `end`.

**Whole-file switch (09/Aug example):** put the first and last lines of `ingress.yaml` inside an `if` so the resource only exists when enabled:

```yaml
{{- if .Values.ingress.enabled }}
# ... the whole Ingress manifest ...
{{- end }}
```

with `values.yaml`:

```yaml
ingress:
  enabled: false
```

**Service type switch (corrected from the 01/Nov example):**

```yaml
{{- if eq .Values.service.type "NodePort" }}
spec:
  type: NodePort
{{- else if eq .Values.service.type "ClusterIP" }}
spec:
  type: ClusterIP
{{- else }}
spec:
  type: LoadBalancer
{{- end }}
```

**Replica rule using `gt` (corrected):**

```yaml
{{- if gt (int .Values.replicas) 1 }}
replicas: {{ .Values.prod.replicas }}
{{- else }}
replicas: 1
{{- end }}
```

### 10.3 `with`

`with` checks that a value is not empty and **changes the scope** (`.`) to that value for the block.

```yaml
# values.yaml
nodeSelector:
  nodeType: dev
```

```yaml
{{- with .Values.nodeSelector }}
nodeSelector:
  {{- toYaml . | nindent 2 }}
{{- end }}
```

Inside the block `.` is the `nodeSelector` map, so `$` is needed to reach root objects (for example `$.Release.Name`). If `nodeSelector` is empty, the whole block disappears.

### 10.4 `range` (loops)

**List**

```yaml
# values.yaml
characters:
  - ironman
  - thor
  - hulk
```

```yaml
characters:
{{- range .Values.characters }}
  - {{ . | quote }}
{{- end }}
```

**Map (key and value)**

```yaml
# values.yaml
movies:
  avengers: "This is a good movie"
  wintersoldier: "This is too good a movie"
```

```yaml
movies:
{{- range $key, $value := .Values.movies }}
  {{ $key }}: {{ $value | quote }}
{{- end }}
```

> The class version printed `- {{ $key }}: ...` which makes a list of one-pair maps. Both are valid YAML, but if you want a normal map in the output, drop the dash as above.

**List of maps (with `$` for the root)**

```yaml
# values.yaml
hosts:
  - host: site.example.com
    path: /
  - host: www.example.com
    path: /web
```

```yaml
{{- range .Values.hosts }}
- host: {{ .host | quote }}
  path: {{ .path | default "/" }}
  release: {{ $.Release.Name }}
{{- end }}
```

### 10.5 Variables  [Added]

```yaml
{{- $env := .Values.env | default "dev" }}
labels:
  env: {{ $env | quote }}
```

`$` on its own always means the root context, even inside `range` or `with`.

### 10.6 `with` versus `range`  [Added]

| Block | Runs | `.` becomes | Use for |
|---|---|---|---|
| `with X` | Once, if X is not empty | X | Optional blocks (`nodeSelector`, `resources`) |
| `range X` | Once per item | The current item | Lists and maps |

---

## 11. Named Templates and `_helpers.tpl`  [Class: 11/Aug/2021, 31/Oct/2026; detail Added]

Docs: https://helm.sh/docs/chart_template_guide/named_templates/

A **named template** is a reusable snippet defined once and used in many files. Files whose names start with an underscore (such as `_helpers.tpl`) are never rendered as manifests, so they are the place for helpers.

### 11.1 Define and use

```yaml
{{/* templates/_helpers.tpl */}}
{{- define "myapp.selectorLabels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
```

```yaml
# templates/deployment.yaml
selector:
  matchLabels:
    {{- include "myapp.selectorLabels" . | nindent 6 }}
```

### 11.2 `include` versus `template`

| | `template "x" .` | `include "x" .` |
|---|---|---|
| Output | Written directly | Returned as a string |
| Can be piped (`\| nindent 4`) | No | Yes |
| Recommended | Rarely | **Always** |

### 11.3 Rules

- Always pass the context: `include "x" .`. Without the dot, `.Values` and `.Release` are empty inside the helper.
- Prefix names with the chart name (`myapp.labels`). Template names are global across a chart and all its subcharts.
- Look at the `_helpers.tpl` that `helm create` generates. It has the standard `name`, `fullname`, `chart`, `labels` and `selectorLabels` helpers.

---

## 12. Worked Examples and Class Exercises

### 12.1 The Pod experiment

The class turned a plain Pod manifest into a template. The original manifest:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: pod-example
spec:
  containers:
  - name: ubuntu
    image: ubuntu:trusty
    command: ["sleep"]
    args: ["1d"]
```

`values.yaml`

```yaml
pod:
  name: "experiment-1"

image:
  repository: ubuntu
  pullPolicy: IfNotPresent
  tag: "latest"

container:
  command: ["sleep"]
  args: ["1d"]
```

`templates/pod.yaml` (with the fix for lists):

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: {{ .Values.pod.name }}
spec:
  containers:
  - name: ubuntu
    image: {{ .Values.image.repository | default "alpine" }}:{{ .Values.image.tag | default "latest" }}
    command: {{ .Values.container.command | toJson }}
    args: {{ .Values.container.args | toJson }}
```

> **Gotcha:** printing a list with `{{ .Values.container.command }}` produces Go-style text like `[sleep]` (no quotes), which breaks for commands with spaces or special characters. `toJson` produces `["sleep"]`, which is valid YAML. This same slip appears in the 01/Nov deployment (section 12.4).

Test:

```bash
helm template exp .
```

### 12.2 Exercise: nginx Deployment chart from scratch 

**Task:** build a chart by hand (without `helm create`) for this manifest, taking labels, image, tag, ports and replicas from `values.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: deployment-example
spec:
  replicas: 3
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: nginx:1.14
```

**My solution** (the teacher's own is in his GitHub repository):

```bash
mkdir -p nginx-deploy/templates
```

`nginx-deploy/Chart.yaml`

```yaml
apiVersion: v2
name: nginx-deploy
description: Nginx Deployment built from scratch
type: application
version: 0.1.0
appVersion: "1.14"
```

`nginx-deploy/values.yaml`

```yaml
nameOverride: ""
replicaCount: 3

labels:
  app: nginx

image:
  repository: nginx
  tag: "1.14"
  pullPolicy: IfNotPresent

containerPort: 80
```

`nginx-deploy/templates/deployment.yaml`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ .Release.Name }}-{{ .Chart.Name }}
  labels:
    {{- toYaml .Values.labels | nindent 4 }}
spec:
  replicas: {{ .Values.replicaCount }}
  selector:
    matchLabels:
      {{- toYaml .Values.labels | nindent 6 }}
  template:
    metadata:
      labels:
        {{- toYaml .Values.labels | nindent 8 }}
    spec:
      containers:
        - name: nginx
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          ports:
            - containerPort: {{ .Values.containerPort }}
```

Run:

```bash
helm lint nginx-deploy/
helm template demo nginx-deploy/
helm install demo nginx-deploy/
kubectl get deploy,pods
helm upgrade demo nginx-deploy/ --set replicaCount=5 --set image.tag=1.25
helm uninstall demo
```

### 12.3 Exercise: Jenkins chart

**Task:** create a Deployment and a Service for Jenkins (image `jenkins/jenkins` from Docker Hub) as a chart named `myjenkins`.

```bash
helm create myjenkins
cd myjenkins
rm -rf templates/*.yaml templates/tests      # keep _helpers.tpl and NOTES.txt
```

`values.yaml` (replace the contents)

```yaml
replicaCount: 1

image:
  repository: jenkins/jenkins
  tag: lts
  pullPolicy: IfNotPresent

service:
  type: NodePort
  httpPort: 8080
  agentPort: 50000
  nodePort: 30808

persistence:
  enabled: false        # set true and a size to keep /var/jenkins_home
  size: 5Gi

resources: {}
```

`templates/deployment.yaml`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ .Release.Name }}-jenkins
  labels:
    app: {{ .Release.Name }}-jenkins
spec:
  replicas: {{ .Values.replicaCount }}
  strategy:
    type: Recreate
  selector:
    matchLabels:
      app: {{ .Release.Name }}-jenkins
  template:
    metadata:
      labels:
        app: {{ .Release.Name }}-jenkins
    spec:
      securityContext:
        fsGroup: 1000
      containers:
        - name: jenkins
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          ports:
            - name: http
              containerPort: 8080
            - name: agent
              containerPort: 50000
          {{- with .Values.resources }}
          resources:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          volumeMounts:
            - name: jenkins-home
              mountPath: /var/jenkins_home
      volumes:
        - name: jenkins-home
          {{- if .Values.persistence.enabled }}
          persistentVolumeClaim:
            claimName: {{ .Release.Name }}-jenkins-home
          {{- else }}
          emptyDir: {}
          {{- end }}
```

`templates/service.yaml`

```yaml
apiVersion: v1
kind: Service
metadata:
  name: {{ .Release.Name }}-jenkins
spec:
  type: {{ .Values.service.type }}
  selector:
    app: {{ .Release.Name }}-jenkins
  ports:
    - name: http
      port: {{ .Values.service.httpPort }}
      targetPort: http
      {{- if and (eq .Values.service.type "NodePort") .Values.service.nodePort }}
      nodePort: {{ .Values.service.nodePort }}
      {{- end }}
    - name: agent
      port: {{ .Values.service.agentPort }}
      targetPort: agent
```

`templates/pvc.yaml`

```yaml
{{- if .Values.persistence.enabled }}
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: {{ .Release.Name }}-jenkins-home
spec:
  accessModes: ["ReadWriteOnce"]
  resources:
    requests:
      storage: {{ .Values.persistence.size }}
{{- end }}
```

Deploy and get the first admin password:

```bash
helm lint .
helm install ci . -n jenkins --create-namespace
kubectl logs -n jenkins deploy/ci-jenkins | grep -A2 "initial"      # password is printed at startup
kubectl get svc -n jenkins
```

### 12.4 The `website-qt` Apache chart  [Class: 01/Nov/2026, corrected]

The 01/Nov class used `helm-playground.com` to turn an Apache Deployment (with an init container that downloads a website template into a shared volume) into a chart.

`values.yaml` (same structure as class)

```yaml
appName: apache2
replicas: 2

containers:
  apache:
    image: httpd
    tag: "2.4.69"          # check that this tag exists in your registry; "2.4" also works
    port: 80

  initContainers:
    downloadtemplate:
      image: alpine
      tag: latest
      command:
        - sh
        - -c
        - >-
          apk add --no-cache wget unzip &&
          wget -O /tmp/site.zip https://templatemo.com/tm-zip-files-2020/templatemo_589_lugx_gaming.zip &&
          unzip /tmp/site.zip -d /tmp/site &&
          cp -r /tmp/site/templatemo_589_lugx_gaming/. /usr/local/apache2/htdocs/
```

`templates/deployment.yaml`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ .Values.appName }}-deployment
  labels:
    app: {{ .Values.appName }}
spec:
  replicas: {{ .Values.replicas }}
  selector:
    matchLabels:
      app: {{ .Values.appName }}
  strategy:
    type: Recreate
  template:
    metadata:
      labels:
        app: {{ .Values.appName }}
    spec:
      initContainers:
        - name: {{ .Values.appName }}-init-downloadtemplate
          image: "{{ .Values.containers.initContainers.downloadtemplate.image }}:{{ .Values.containers.initContainers.downloadtemplate.tag }}"
          command: {{ .Values.containers.initContainers.downloadtemplate.command | toJson }}
          volumeMounts:
            - name: {{ .Values.appName }}-html
              mountPath: /usr/local/apache2/htdocs/
      containers:
        - name: {{ .Values.appName }}
          image: "{{ .Values.containers.apache.image }}:{{ .Values.containers.apache.tag }}"
          ports:
            - containerPort: {{ .Values.containers.apache.port }}
          volumeMounts:
            - name: {{ .Values.appName }}-html
              mountPath: /usr/local/apache2/htdocs/
      volumes:
        - name: {{ .Values.appName }}-html
          emptyDir: {}
```

What changed from the class version:

| Class version | Here | Why |
|---|---|---|
| `command: {{ ...command }}` | `command: {{ ... \| toJson }}` | Lists must be converted to valid YAML text |
| `replicas: 2` hard-coded | `replicas: {{ .Values.replicas }}` | The class goal was to parameterise everything |
| `cp .../* ...` then `rm -rf` the folder | Unzip to `/tmp/site`, then `cp -r .../. htdocs/` | Simpler and also copies hidden files and sub-folders |
| One very long command string | Folded YAML (`>-`) over several lines | Easier to read and edit |

Add a Service (class task: "make your deployment a helm template and try the operations above") with the `if / else if / else` pattern from 10.2:

`values.yaml` additions

```yaml
service:
  type: ClusterIP        # ClusterIP | NodePort | LoadBalancer
  port: 80
  nodePort: ""
nodeSelector: {}
```

`templates/service.yaml`

```yaml
apiVersion: v1
kind: Service
metadata:
  name: {{ .Values.appName }}-service
spec:
  type: {{ .Values.service.type }}
  selector:
    app: {{ .Values.appName }}
  ports:
    - port: {{ .Values.service.port }}
      targetPort: {{ .Values.containers.apache.port }}
      {{- if and (eq .Values.service.type "NodePort") .Values.service.nodePort }}
      nodePort: {{ .Values.service.nodePort }}
      {{- end }}
```

And an optional `nodeSelector` using `with` inside the pod spec:

```yaml
      {{- with .Values.nodeSelector }}
      nodeSelector:
        {{- toYaml . | nindent 8 }}
      {{- end }}
```

Try:

```bash
helm lint website-qt/
helm template site website-qt/
helm upgrade -i site website-qt/ -n dev --create-namespace --set service.type=NodePort --set service.nodePort=30080
kubectl port-forward svc/apache2-service 8080:80 -n dev
```

### 12.5 Task: Nexus as a Helm chart  [Class: 31/Oct/2026 task; chart Added]

The 31/Oct class deployed Sonatype Nexus Repository (HTTP only, NodePort) with a long shell script. That script reads settings from environment variables, makes sure a default StorageClass exists, creates the namespace, a PersistentVolumeClaim, a Deployment and a NodePort Service, waits for readiness, and prints the admin password.

A Helm chart replaces most of the script. Mapping:

| Script setting | Chart value |
|---|---|
| `NAMESPACE` | `helm install -n <ns> --create-namespace` |
| `NODE_PORT` (default 30081) | `service.nodePort` |
| `STORAGE_SIZE` (10Gi) | `persistence.size` |
| `STORAGE_CLASS` | `persistence.storageClass` |
| `NEXUS_IMAGE` | `image.repository`, `image.tag` |
| Java options | `javaOpts` |
| Resource requests and limits | `resources` |
| Waiting and the final summary | `--wait --timeout 10m` and `NOTES.txt` |

```bash
helm create nexus
cd nexus
rm -rf templates/*.yaml templates/tests       # keep _helpers.tpl and NOTES.txt
```

`Chart.yaml`

```yaml
apiVersion: v2
name: nexus
description: Sonatype Nexus Repository on Kubernetes
type: application
version: 0.1.0
appVersion: "3"
```

`values.yaml`

```yaml
image:
  repository: sonatype/nexus3
  tag: latest              # pin a version for production
  pullPolicy: IfNotPresent

javaOpts: "-Xms1g -Xmx1g -XX:MaxDirectMemorySize=1g -Djava.util.prefs.userRoot=/nexus-data/javaprefs"

persistence:
  enabled: true
  size: 10Gi
  storageClass: ""         # empty = cluster default

service:
  type: NodePort
  port: 8081
  nodePort: 30081

resources:
  requests: { cpu: 500m, memory: 2Gi }
  limits:   { cpu: "2",  memory: 3Gi }
```

`templates/pvc.yaml`

```yaml
{{- if .Values.persistence.enabled }}
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: {{ .Release.Name }}-nexus-data
spec:
  accessModes:
    - ReadWriteOnce
  {{- with .Values.persistence.storageClass }}
  storageClassName: {{ . | quote }}
  {{- end }}
  resources:
    requests:
      storage: {{ .Values.persistence.size }}
{{- end }}
```

`templates/deployment.yaml`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ .Release.Name }}-nexus
  labels:
    app: {{ .Release.Name }}-nexus
spec:
  replicas: 1
  strategy:
    type: Recreate
  selector:
    matchLabels:
      app: {{ .Release.Name }}-nexus
  template:
    metadata:
      labels:
        app: {{ .Release.Name }}-nexus
    spec:
      securityContext:
        fsGroup: 200
      containers:
        - name: nexus
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          ports:
            - name: http
              containerPort: 8081
          env:
            - name: INSTALL4J_ADD_VM_PARAMS
              value: {{ .Values.javaOpts | quote }}
          {{- with .Values.resources }}
          resources:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          readinessProbe:
            httpGet:
              path: /service/rest/v1/status
              port: 8081
            initialDelaySeconds: 90
            periodSeconds: 15
            timeoutSeconds: 5
            failureThreshold: 20
          livenessProbe:
            httpGet:
              path: /service/rest/v1/status
              port: 8081
            initialDelaySeconds: 300
            periodSeconds: 30
            timeoutSeconds: 10
            failureThreshold: 6
          volumeMounts:
            - name: nexus-data
              mountPath: /nexus-data
      volumes:
        - name: nexus-data
          {{- if .Values.persistence.enabled }}
          persistentVolumeClaim:
            claimName: {{ .Release.Name }}-nexus-data
          {{- else }}
          emptyDir: {}
          {{- end }}
```

`templates/service.yaml`

```yaml
apiVersion: v1
kind: Service
metadata:
  name: {{ .Release.Name }}-nexus
spec:
  type: {{ .Values.service.type }}
  selector:
    app: {{ .Release.Name }}-nexus
  ports:
    - name: http
      port: {{ .Values.service.port }}
      targetPort: http
      {{- if and (eq .Values.service.type "NodePort") .Values.service.nodePort }}
      nodePort: {{ .Values.service.nodePort }}
      {{- end }}
```

`templates/NOTES.txt`

```text
Nexus is starting. The first start takes 2 to 5 minutes.

Watch:      kubectl get pods -n {{ .Release.Namespace }} -w
Admin pass: kubectl exec -n {{ .Release.Namespace }} deploy/{{ .Release.Name }}-nexus -- cat /nexus-data/admin.password
{{- if eq .Values.service.type "NodePort" }}
Open:       http://<node-ip>:{{ .Values.service.nodePort }}
{{- end }}
```

Deploy and remove:

```bash
helm lint nexus/
helm upgrade -i nexus nexus/ -n nexus --create-namespace --wait --timeout 10m
kubectl get pods,svc,pvc -n nexus

helm uninstall nexus -n nexus
kubectl delete pvc -n nexus nexus-nexus-data       # the PVC is kept on purpose unless you delete it
```

If no default StorageClass exists in the cluster, the class script installed a local-path provisioner first. With the chart, either install a StorageClass beforehand or set `persistence.enabled=false` for a throwaway test.

### 12.6 Task: install Grafana from its Helm chart  [Class: 01/Nov/2026 task]

Official guide: https://grafana.com/docs/grafana/latest/setup-grafana/installation/helm/

```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update
helm search repo grafana/grafana
helm show values grafana/grafana > grafana-values.yaml    # read what you can change

helm install my-grafana grafana/grafana \
  -n monitoring --create-namespace \
  --set service.type=NodePort \
  --set persistence.enabled=true \
  --set persistence.size=5Gi

# admin password
kubectl get secret -n monitoring my-grafana \
  -o jsonpath="{.data.admin-password}" | base64 --decode ; echo

kubectl get svc -n monitoring my-grafana       # find the NodePort and open it
```

Better practice is to keep overrides in a file:

```yaml
# grafana-override.yaml
service:
  type: NodePort
persistence:
  enabled: true
  size: 5Gi
adminUser: admin
```

```bash
helm upgrade -i my-grafana grafana/grafana -n monitoring --create-namespace -f grafana-override.yaml
```

---

## 13. Release Lifecycle  [Added, based on the class command sequence]

A **release** is one installed instance of a chart. Each install or upgrade creates a new **revision**. Helm 3 stores revisions as Secrets in the release's namespace so it can roll back.

```bash
helm install site website-qt/ -n dev --create-namespace
helm upgrade site website-qt/ -n dev --set replicas=3

helm list -A                         # all releases in all namespaces
helm status site -n dev
helm get values site -n dev          # your overrides
helm get values site -n dev --all    # overrides plus defaults
helm get manifest site -n dev        # the YAML as installed
helm get notes site -n dev
helm history site -n dev

helm rollback site 1 -n dev          # creates a NEW revision that matches revision 1
helm uninstall site -n dev
helm uninstall site -n dev --keep-history    # allows rollback after uninstall
```

Notes:

- `helm upgrade --reuse-values` keeps old overrides but ignores new chart defaults. Prefer passing the same `-f` files each time.
- The `selector` of a Deployment cannot change after creation, so keep selector labels stable between chart versions.
- A changed ConfigMap does not restart pods by itself. Use a checksum annotation (section 17.3).

---

## 14. Hooks and Tests  [Class: 03/Aug/2021, 11/Aug/2021 (docs link); examples Added]

Docs: https://helm.sh/docs/topics/charts_hooks/

**Hooks** run Jobs or Pods at points in the release lifecycle (a backup before upgrade, a data restore after rollback, an environment check before install). They are ordinary templates with an annotation.

| Hook | Runs |
|---|---|
| `pre-install` / `post-install` | Before / after resources are created |
| `pre-upgrade` / `post-upgrade` | Before / after an upgrade |
| `pre-rollback` / `post-rollback` | Around a rollback |
| `pre-delete` / `post-delete` | Around an uninstall |
| `test` | When you run `helm test` |

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: {{ .Release.Name }}-backup
  annotations:
    "helm.sh/hook": pre-upgrade
    "helm.sh/hook-weight": "0"                       # lower weights run first
    "helm.sh/hook-delete-policy": hook-succeeded     # clean up when finished
spec:
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: backup
          image: busybox
          command: ["sh", "-c", "echo taking backup && sleep 3"]
```

**Chart tests:** a Pod with the `test` hook, run with `helm test <release>`.

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: "{{ .Release.Name }}-test"
  annotations:
    "helm.sh/hook": test
spec:
  restartPolicy: Never
  containers:
    - name: wget
      image: busybox
      command: ['wget']
      args: ['{{ .Release.Name }}-service:80']
```

---

## 15. Dependencies and Subcharts  [Class: 01/Nov/2026 (Chart.yaml), 04/Aug/2021 (charts/ and Chart.lock); detail Added]

Docs: https://helm.sh/docs/helm/helm_dependency/

A chart can depend on other charts, for example an application plus a database.

### 15.1 Declare in `Chart.yaml`

The 01/Nov example used the keys `dependancy` and `repostry`. The correct keys are `dependencies` and `repository`:

```yaml
dependencies:
  - name: mysql
    version: "12.x.x"
    repository: https://charts.bitnami.com/bitnami      # confirm the chart's current repository
    condition: mysql.enabled
```

### 15.2 Commands

```bash
helm dependency update website-qt/     # download into charts/, write Chart.lock
helm dependency build website-qt/      # rebuild exactly from Chart.lock (use in CI)
helm dependency list website-qt/
```

### 15.3 Configure the subchart from the parent `values.yaml`

```yaml
mysql:                       # key = the dependency name
  enabled: true
  auth:
    database: appdb
    username: appuser
```

### 15.4 Global values

```yaml
global:
  environment: dev
```

Every chart, parent and subcharts, reads it as `{{ .Values.global.environment }}`.

### 15.5 Rules

- `condition:` switches a subchart on or off.
- Commit `Chart.lock`; do not commit the downloaded `.tgz` files in `charts/`.
- A change inside a subchart means bumping that subchart's version and the parent's.

---

## 16. Package, Host and Share Charts  [Class: 11/Aug/2021 (hosting); steps Added]

The 11/Aug class pointed out that an organisation can host its own charts, for example in **JFrog Artifactory** (https://www.jfrog.com/confluence/display/JFROG/Kubernetes+Helm+Chart+Repositories). Other supported options are documented at https://helm.sh/docs/topics/chart_repository/. Nexus (from the 31/Oct task) can also host Helm charts.

### 16.1 Package

```bash
helm package website-qt/                          # creates website-qt-0.1.0.tgz
helm package website-qt/ --version 0.2.0 --app-version 2.4.62 --destination ./dist
```

### 16.2 Classic chart repository (a web server with `index.yaml`)

```bash
mkdir repo && cp website-qt-0.1.0.tgz repo/
helm repo index repo/ --url https://<your-host>/charts        # generates repo/index.yaml
# upload repo/ to GitHub Pages, a static site, Artifactory or Nexus

helm repo add qt https://<your-host>/charts
helm install site qt/website-qt
```

### 16.3 OCI registry (Docker Hub, GHCR, Azure Container Registry, ECR)

```bash
helm registry login <registry-host> --username <user> --password <token>
helm push website-qt-0.1.0.tgz oci://<registry-host>/helm
helm install site oci://<registry-host>/helm/website-qt --version 0.1.0 -n dev
```

---

## 17. Real-World Chart Features  [Added]

### 17.1 Validate values with `values.schema.json`

Listed in the 04/Aug file table. Helm checks it on `lint`, `template`, `install` and `upgrade`:

```json
{
  "$schema": "https://json-schema.org/draft-07/schema#",
  "type": "object",
  "required": ["replicas"],
  "properties": {
    "replicas": { "type": "integer", "minimum": 1 },
    "service": {
      "type": "object",
      "properties": {
        "type": { "type": "string", "enum": ["ClusterIP", "NodePort", "LoadBalancer"] }
      }
    }
  }
}
```

```bash
helm lint website-qt/ --set replicas=0          # fails: below the minimum
helm lint website-qt/ --set service.type=Foo    # fails: not in the list
```

### 17.2 ConfigMap and Secret templates

```yaml
# configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ .Release.Name }}-config
data:
  {{- range $key, $value := .Values.config }}
  {{ $key }}: {{ $value | quote }}
  {{- end }}
---
# secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name: {{ .Release.Name }}-secret
type: Opaque
data:
  password: {{ required "secret.password is required" .Values.secret.password | b64enc | quote }}
```

Never commit real passwords in `values.yaml`. Pass them from pipeline secrets with `--set`, use an external secret manager, or use the `helm-secrets` plugin.

### 17.3 Restart pods when a ConfigMap changes

```yaml
  template:
    metadata:
      annotations:
        checksum/config: {{ include (print $.Template.BasePath "/configmap.yaml") . | sha256sum }}
```

### 17.4 Standard `helm create` extras you should recognise

| Template | What it adds |
|---|---|
| `serviceaccount.yaml` | A ServiceAccount, switched on or off from values |
| `ingress.yaml` | An Ingress, wrapped in `if .Values.ingress.enabled` |
| `hpa.yaml` | A HorizontalPodAutoscaler when `autoscaling.enabled` is true |
| `tests/test-connection.yaml` | A `helm test` Pod |

---

## 18. Debugging and Best Practices  [Added]

### 18.1 Debug checklist

| Symptom | What to do |
|---|---|
| YAML parse error | `helm template ... --debug` and read the lines near the error |
| Wrong indentation | Check the `nindent` number and the `{{-` dashes |
| `nil pointer evaluating interface` | A key is missing in values; add it or use `default` |
| Value seems ignored | `helm get values <rel> --all`; check precedence and the key path |
| List or special characters in `--set` | Quote it: `--set 'ingress.hosts[0].host=a.b.com'` |
| `cannot re-use a name that is still in use` | Use `helm upgrade -i`, or pick another release name |
| Release stuck as `failed` or `pending-upgrade` | `helm history`, then `helm rollback` or `helm uninstall` |
| Pods not ready after upgrade | `kubectl describe pod`, `kubectl logs`, `kubectl rollout status` |

### 18.2 Best practices

1. Document every key in `values.yaml` with a comment.
2. Use `include` with helper templates for names and labels.
3. Do not hard-code namespaces; use `.Release.Namespace` or leave it out.
4. Use `required` for values with no safe default.
5. Keep secrets out of Git.
6. Pin chart and image versions; avoid `latest` in production.
7. Run `helm lint` and `helm template` in CI before deploying.
8. Deploy with `helm upgrade --install --atomic --wait --timeout 5m`.
9. Always set resource requests and limits through values.
10. Bump the chart `version` on every change.

### 18.3 CI/CD deploy step

```bash
helm lint ./website-qt
helm upgrade --install site ./website-qt \
  --namespace prod --create-namespace \
  -f values-prod.yaml \
  --set image.tag="${BUILD_ID}" \
  --atomic --wait --timeout 5m
```

---

## 19. Corrections Log: Slips in the Class Notes

| Where | In the notes | Correct form |
|---|---|---|
| 01/Nov, Chart.yaml | `dependancy:` / `repostry:` | `dependencies:` / `repository:` |
| 01/Nov, Chart.yaml | `type: application # db, Monitoring, RBAC` | `type` is `application` or `library`; the other words are only examples of app categories |
| 01/Nov, `eq` | `{{ -eq .Values.env "prod" }}` | `{{- if eq .Values.env "prod" }}` |
| 01/Nov, `and` / `or` | `{{ and .Values.enable -eq .Values.env "prod" }}` | `{{ if and .Values.enable (eq .Values.env "prod") }}` |
| 01/Nov, service switch | `{{- if .Values.service.type "nodeport" }}` | `{{- if eq .Values.service.type "NodePort" }}` |
| 01/Nov, service YAML | `apiversion: newtworking.k8s.io/v1`, `kind: service`, `type: nodeport` | `apiVersion: v1`, `kind: Service`, `type: NodePort` |
| 01/Nov, `with` | `toyaml` | `toYaml` |
| 01/Nov and 09/Aug | `command: {{ ...command }}` | `command: {{ ...command \| toJson }}` |
| 01/Nov, `typeOf` | "Typeoff" | `typeOf` |
| 31/Oct | Folders `http/` and `httpd/`, releases `http-app` and `http-demo`, tree labelled `myapp/` | Keep the same chart folder and release names throughout |
| 31/Oct | `--creat\ne-namespace` (line break in the middle of the flag) | `--create-namespace` |
| 04/Aug | `template/NOTES.txt` | The folder is `templates/` |

---

## 20. Full Topic Checklist

| Area | Topic | Section | In class? |
|---|---|---|---|
| Basics | What Helm is, charts, repos, releases | 1 | Yes |
| Basics | Helm vs DNF commands | 2 | Yes |
| Basics | Install, Helm 2 vs 3, env vars, paths | 3 | Yes |
| Basics | Repos, search, plugins | 4 | Yes (search extras added) |
| Charts | Structure, `helm create`, `Chart.yaml` | 5, 6 | Yes |
| Deploy | template, install, upgrade, `-i`, `--set`, `--values`, namespaces | 7 | Yes |
| Templates | Go templates, pipelines, objects, functions, methods | 8 | Yes |
| Templates | Value types and type functions | 9 | Yes |
| Templates | if / else, with, range, logic functions | 10 | Yes |
| Templates | Variables, `required`, `include` | 8, 10, 11 | Added |
| Templates | Named templates, `_helpers.tpl` | 11 | Yes (introduced), detail added |
| Practice | Pod experiment, nginx, Jenkins, website-qt, Nexus, Grafana | 12 | Yes (solutions added) |
| Lifecycle | history, rollback, get, uninstall, `--atomic` | 13 | Added |
| Advanced | Hooks, tests | 14 | Mentioned, examples added |
| Advanced | Dependencies, subcharts, global values | 15 | Mentioned, detail added |
| Advanced | Package, repositories, OCI | 16 | Hosting mentioned, steps added |
| Advanced | Schema, ConfigMap/Secret, checksum | 17 | Added |
| Quality | Debugging, best practices, CI/CD | 18 | Added |

---

## 21. Quiz

1. Why are plain Kubernetes YAML files a problem when you deploy the same app to several environments?
2. What did Helm 3 remove compared to Helm 2, and where does Helm 3 get its credentials?
3. What is the difference between `version` and `appVersion` in `Chart.yaml`?
4. Which command renders templates without installing anything?
5. What does `helm upgrade -i` do?
6. In `{{ .Values.product | default "kubernetes" | quote }}`, in what order do things happen?
7. What does a dash in `{{-` do?
8. When is `.Release.IsUpgrade` true?
9. What is the difference between `with` and `range`?
10. Why is `command: {{ .Values.x.command }}` a bug when `command` is a list?
11. Why prefer `include` over `template`?
12. Which file lists the dependency versions that were actually applied?
13. How do you make pods restart when a ConfigMap changes?
14. How do you roll back to revision 2 of a release called `site` in namespace `dev`?

<details>
<summary>Answers</summary>

1. They are static and cannot take parameters, so you copy and edit them for every app and environment.
2. Tiller. Helm 3 uses your kubeconfig (the same credentials as `kubectl`).
3. `version` is the chart's own version; `appVersion` is the packaged application's version.
4. `helm template <release> <chart>`.
5. Upgrades the release if it exists, otherwise installs it.
6. `.Values.product` is read, passed to `default` (which supplies "kubernetes" if it is empty), and the result is passed to `quote`.
7. It trims the whitespace on that side of the action.
8. On an upgrade or a rollback.
9. `with` tests that a value is not empty and changes scope once; `range` loops over every item of a list or map.
10. A list is printed Go-style (for example `[sleep]`), which is not valid YAML for commands; use `toJson` or `toYaml | nindent`.
11. `include` returns a string, so it can be piped (for example to `nindent`); `template` cannot.
12. `Chart.lock`.
13. Add a checksum annotation of the ConfigMap to the pod template.
14. `helm rollback site 2 -n dev`.
</details>

---

## 22. Command Cheat Sheet

```bash
# Create and inspect
helm create <name>
helm lint <chart>
helm template <rel> <chart> [-f values.yaml] [--set k=v] [-s templates/x.yaml]
helm show values <chart>        helm show chart <chart>
helm pull <chart> --untar

# Repositories and plugins
helm repo add <name> <url>      helm repo update        helm repo list
helm repo remove <name>         helm repo index <dir> --url <url>
helm search repo <word>         helm search hub <word>
helm plugin list

# Install and upgrade
helm install <rel> <chart> -n <ns> --create-namespace [-f f.yaml] [--set k=v]
helm upgrade -i <rel> <chart> -n <ns> [--atomic --wait --timeout 5m]

# Inspect releases
helm list -A                    helm status <rel> -n <ns>
helm get values <rel>           helm get manifest <rel>      helm history <rel>

# Undo
helm rollback <rel> <revision>  helm uninstall <rel> -n <ns>

# Dependencies and publishing
helm dependency update <chart>  helm dependency build <chart>
helm package <chart>            helm registry login <host>   helm push <tgz> oci://<host>/<path>

# Test
helm test <rel> -n <ns>
```

### Template syntax cheat sheet

| Need | Syntax |
|---|---|
| Print a value | `{{ .Values.x }}` |
| Fallback | `{{ .Values.x \| default "y" }}` |
| Condition | `{{- if eq .Values.env "prod" }} ... {{- else }} ... {{- end }}` |
| Optional block | `{{- with .Values.x }} ... {{- end }}` |
| Loop a list | `{{- range .Values.list }} {{ . }} {{- end }}` |
| Loop a map | `{{- range $k, $v := .Values.map }} {{ $k }}={{ $v }} {{- end }}` |
| Variable | `{{- $x := .Values.y }}` |
| Embed YAML | `{{- toYaml .Values.x \| nindent 4 }}` |
| List as YAML | `{{ .Values.list \| toJson }}` |
| Reuse helper | `{{- include "chart.labels" . \| nindent 4 }}` |
| Root inside a loop | `{{ $.Release.Name }}` |
| Comment | `{{/* text */}}` |

---

## 23. References

- Helm docs: https://helm.sh/docs/
- Chart template guide: https://helm.sh/docs/chart_template_guide/
- Function list: https://helm.sh/docs/chart_template_guide/function_list/
- Named templates: https://helm.sh/docs/chart_template_guide/named_templates/
- Charts reference: https://helm.sh/docs/topics/charts/
- Chart hooks: https://helm.sh/docs/topics/charts_hooks/
- Chart repositories: https://helm.sh/docs/topics/chart_repository/
- Helm dependency: https://helm.sh/docs/helm/helm_dependency/
- Helm template command: https://helm.sh/docs/helm/helm_template/
- Sprig function library: http://masterminds.github.io/sprig/
- Go text/template: https://pkg.go.dev/text/template
- Helm playground: https://helm-playground.com/
- Artifact Hub: https://artifacthub.io/
- Grafana Helm install: https://grafana.com/docs/grafana/latest/setup-grafana/installation/helm/
- Class posts: see the table in section 0.1
