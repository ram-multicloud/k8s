# Helm Templates for Beginners: Learn by Real Use Cases

A step-by-step teaching guide. Every concept comes with **what it is**, **a simple example**, and **where you use it in real life**.

---

## Table of Contents

1. [The big idea](#1-the-big-idea)
2. [Chart structure](#2-chart-structure)
3. [Our running project](#3-our-running-project-school-website)
4. [Your first template](#4-your-first-template)
5. [Built-in objects](#5-built-in-objects)
6. [Value types](#6-value-types)
7. [Passing values](#7-passing-values-the-most-important-skill)
8. [Template variables](#8-template-variables)
9. [Useful functions](#9-useful-functions)
10. [Control flow: if, with, range](#10-control-flow-if-with-range)
11. [Named templates (helpers)](#11-named-templates-helpers)
12. [Real use case: dev, test, prod](#12-real-use-case-dev-test-and-prod)
13. [Real use case: ConfigMap and Secret](#13-real-use-case-configmap-and-secret)
14. [Subcharts and global values](#14-subcharts-and-global-values)
15. [Validating values with a schema](#15-validating-values-with-a-schema)
16. [Debugging](#16-debugging)
17. [Common mistakes](#17-common-mistakes)
18. [Exercises](#18-exercises)
19. [Cheat sheet](#19-cheat-sheet)

---

## 1. The big idea

### The form letter analogy

A school sends the same letter to 500 parents:

> Dear **{{ parent }}**, your child **{{ child }}** is in class **{{ class }}**.

The letter is written **once**. Only the blanks change.

| Mail merge | Helm |
|---|---|
| Letter with blanks | **Template** (`templates/*.yaml`) |
| List of names and classes | **Values** (`values.yaml`) |
| Printed letters | **Rendered Kubernetes YAML** |

```
 values.yaml ─┐
 -f file     ─┼──►  Template  ──►  Final Kubernetes YAML  ──►  Cluster
 --set       ─┘   (with blanks)
```

### Why do we need Helm?

**Problem without Helm:** you have the same app in dev, test, and prod. You copy the YAML 3 times and change a few lines in each. A bug fix means editing 3 files and hoping you did not miss one.

**With Helm:** one template, three small values files.

> **Real use cases:**
> - Deploy the same app to many environments (dev / test / prod)
> - Deploy the same app for many customers (one namespace each)
> - Install popular software (Nginx, PostgreSQL, Prometheus) with one command
> - Roll back a bad release in one command (`helm rollback`)

### Two words to remember

| Word | Meaning |
|---|---|
| **Chart** | A folder containing templates and values (the package) |
| **Release** | One installed copy of a chart in a cluster |

You can install the **same chart** many times with different release names.

---

## 2. Chart structure

Create one with:

```bash
helm create school-site
```

```
school-site/
├── Chart.yaml          # name and version of the chart
├── values.yaml         # default values (the blanks' defaults)
├── values.schema.json  # (optional) rules for values
├── charts/             # dependencies (subcharts)
└── templates/
    ├── _helpers.tpl    # reusable snippets (not deployed itself)
    ├── deployment.yaml
    ├── service.yaml
    ├── ingress.yaml
    └── NOTES.txt       # message shown after install
```

### `Chart.yaml`

```yaml
apiVersion: v2
name: school-site
description: Website for our school
version: 0.1.0        # version of the CHART (templates)
appVersion: "1.27"    # version of the APP inside (for example the nginx version)
```

> **Use case:** `version` changes when you edit the chart. `appVersion` changes when the software inside changes. Teams use these to track what is deployed.

---

## 3. Our running project: School Website

All examples use this scenario.

> A school runs its website (nginx) on Kubernetes in three environments.

| Environment | Copies (replicas) | Image tag | Public web address? |
|---|---|---|---|
| dev | 1 | 1.26 | No |
| test | 2 | 1.27 | No |
| prod | 3 | 1.27 | Yes |

The app is the same everywhere. Only a few numbers differ. This is exactly what Helm is for.

---

## 4. Your first template

### Step 1: values (the blanks)

`values.yaml`

```yaml
appName: school-site
replicas: 1
image:
  name: nginx
  tag: "1.26"
port: 80
```

### Step 2: template (the letter)

`templates/deployment.yaml`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ .Values.appName }}
spec:
  replicas: {{ .Values.replicas }}
  selector:
    matchLabels:
      app: {{ .Values.appName }}
  template:
    metadata:
      labels:
        app: {{ .Values.appName }}
    spec:
      containers:
        - name: {{ .Values.appName }}
          image: "{{ .Values.image.name }}:{{ .Values.image.tag }}"
          ports:
            - containerPort: {{ .Values.port }}
```

**How to read it:** `{{ .Values.replicas }}` means *"go to values, find `replicas`, put it here."*

### Step 3: preview the result

```bash
helm template demo ./school-site
```

Output:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: school-site
spec:
  replicas: 1
  ...
          image: "nginx:1.26"
```

### Syntax you just used

| Syntax | Meaning |
|---|---|
| `{{ ... }}` | Code. Replaced by its result. |
| `.Values` | The values (from `values.yaml`, `-f`, `--set`) |
| `.Values.image.tag` | Go inside `image`, take `tag` (dot means "inside") |
| `{{- ... }}` | Remove the blank space/newline **before** the code |
| `{{ ... -}}` | Remove the blank space/newline **after** the code |
| `{{/* text */}}` | A comment that is not printed |

---

## 5. Built-in objects

Helm gives you information for free. You do not define these.

| Object | What it gives | Example output |
|---|---|---|
| `.Release.Name` | Name you gave at install | `school-prod` |
| `.Release.Namespace` | Namespace of install | `production` |
| `.Release.IsInstall` | `true` on first install | `true` |
| `.Release.IsUpgrade` | `true` on upgrade | `false` |
| `.Chart.Name` | From Chart.yaml | `school-site` |
| `.Chart.Version` | Chart version | `0.1.0` |
| `.Chart.AppVersion` | App version | `1.27` |
| `.Capabilities.KubeVersion.Version` | Cluster version | `v1.30.0` |
| `.Template.Name` | Current file | `school-site/templates/deployment.yaml` |

### Use case 1: unique names per release

Install the chart twice in the same namespace without name clashes:

```yaml
metadata:
  name: {{ .Release.Name }}-web
```

```bash
helm install class9 ./school-site     # creates class9-web
helm install class10 ./school-site    # creates class10-web
```

### Use case 2: labels with chart info

```yaml
labels:
  app.kubernetes.io/instance: {{ .Release.Name }}
  helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
```

### Use case 3: use app version as the default image tag

```yaml
image: "nginx:{{ .Values.image.tag | default .Chart.AppVersion }}"
```

### Use case 4: run a job only on first install

```yaml
{{- if .Release.IsInstall }}
# create the initial database tables only the first time
{{- end }}
```

---

## 6. Value types

Values are YAML, so they have types.

```yaml
appName: "school-site"   # String    - text
replicas: 3              # Integer   - whole number
cpuLimit: 0.5            # Float     - decimal
debug: false             # Boolean   - true or false
nodeSelector: null       # Null      - nothing
ports: [80, 443]         # List      - many items in order
image:                   # Map       - things with names
  name: nginx
  tag: "1.27"
```

| Type | Typical use case |
|---|---|
| **String** | App name, image name, hostname, log level |
| **Integer** | Replicas, port numbers, timeouts |
| **Float** | CPU share, ratios |
| **Boolean** | Feature switches: `ingress.enabled`, `debug` |
| **Null** | "Not set, use the default" |
| **List** | Several ports, hosts, or allowed IPs |
| **Map** | Grouped settings: `image`, `service`, `resources` |

### What counts as "false" in an `if`?

`false`, `0`, `""` (empty string), `null`, `[]` (empty list), `{}` (empty map).

> **Use case:** `{{- if .Values.nodeSelector }}` only prints the block when you actually provided something.

### Checking and converting types inside templates

```yaml
{{ typeOf .Values.replicas }}        # int64 (or float64)
{{ kindOf .Values.ports }}           # slice
{{ .Values.replicas | int }}         # convert to integer
{{ .Values.replicas | toString }}    # convert to string
{{ "8080" | atoi }}                  # text to number
```

> **Use case:** Kubernetes `env` values **must be strings**. A port such as `8080` must be written `{{ .Values.port | quote }}`, otherwise you get an error.

### Type traps students must know

**Trap 1: version numbers.**

```yaml
tag: 1.20        # WRONG: becomes the number 1.2
tag: "1.20"      # RIGHT: stays the text 1.20
```

**Trap 2: words like yes/no/on/off.** Quote them: `"yes"`.

**Trap 3: big numbers** may print as `1e+09`. Fix: `{{ .Values.big | int64 }}` or store as a string.

---

## 7. Passing values (the most important skill)

### 7.1 Which value wins? (precedence)

```
chart's values.yaml   <   -f file(s)   <   --set flags
     (weakest)                                 (strongest)
```

- With several `-f` files, **the last file wins**.
- Maps are **merged** key by key. Lists are **replaced fully**.

### 7.2 Method 1: default `values.yaml`

Edit the file in the chart. Works with plain `helm install demo ./school-site`.

> **Use case:** the safe defaults that work for everyone.

### 7.3 Method 2: a values file with `-f` (best practice)

`values-prod.yaml`

```yaml
replicas: 3
image:
  tag: "1.27"
```

```bash
helm install school-prod ./school-site -f values-prod.yaml
```

Only list what is **different**. The rest comes from the default file.

> **Use case:** one file per environment (`values-dev.yaml`, `values-test.yaml`, `values-prod.yaml`), stored in Git.

Multiple files (last wins):

```bash
helm install school-prod ./school-site -f values-prod.yaml -f values-secrets.yaml
```

> **Use case:** keep normal settings in Git and secrets in a separate file that is not committed.

### 7.4 Method 3: `--set` (quick change)

```bash
helm install demo ./school-site --set replicas=3
helm install demo ./school-site --set image.tag=1.27
helm install demo ./school-site --set image.name=nginx,image.tag=1.27
```

> **Use case:** CI/CD pipelines that inject the new image tag on every build:
> ```bash
> helm upgrade --install school ./school-site --set image.tag=$GIT_COMMIT_SHA
> ```

### 7.5 How to pass every type with `--set`

| Type | Command | Result |
|---|---|---|
| String | `--set appName=my-site` | `"my-site"` |
| Integer | `--set replicas=3` | `3` |
| Float | `--set cpuLimit=0.5` | `0.5` |
| Boolean | `--set debug=true` | `true` |
| Null (delete default) | `--set nodeSelector=null` | key removed |
| **Force string** | `--set-string image.tag=1.20` | `"1.20"` |
| List | `--set 'ports={80,443}'` | `[80, 443]` |
| List item by position | `--set 'ports[0]=8080'` | first item |
| List of maps | `--set 'hosts[0].name=a.com'` | |
| Map | `--set env.LOG_LEVEL=debug` | |
| Value containing a comma | `--set 'msg=hello\, world'` | `"hello, world"` |
| Key containing a dot | `--set 'labels.app\.io/name=x'` | key `app.io/name` |
| Content of a file | `--set-file config=./app.conf` | file text |
| JSON | `--set-json 'ports=[80,443]'` | parsed JSON |

> **Use case for `--set-file`:** load a whole certificate, license key, or config file into a value.

> **Rule of thumb:** use `--set` for 1 or 2 values; use `-f` for anything bigger.

### 7.6 Method 4: from standard input

```bash
echo "replicas: 4" | helm install demo ./school-site -f -
```

### 7.7 Which command uses these?

All of these accept the same flags:

```bash
helm template NAME ./chart -f x.yaml --set a=b     # preview only
helm install   NAME ./chart -f x.yaml --set a=b    # first install
helm upgrade   NAME ./chart -f x.yaml --set a=b    # change an existing release
helm upgrade --install NAME ./chart ...            # install or upgrade (used in CI/CD)
```

> **Important:** on `helm upgrade`, values from the previous install are **not** kept unless you pass them again (or use `--reuse-values`). Always pass your `-f` files again.

---

## 8. Template variables

Different from "values". These are **temporary names you create inside a template**.

```yaml
{{- $name := .Values.appName }}
{{- $env := .Values.environment | default "dev" }}

metadata:
  name: {{ $name }}-{{ $env }}
```

- Create: `$x := value`
- Change later: `$x = newValue`

### Use case 1: avoid repeating a long expression

```yaml
{{- $fullName := printf "%s-%s" .Release.Name .Chart.Name }}
name: {{ $fullName }}
serviceName: {{ $fullName }}-svc
```

### Use case 2: store the result of a decision

```yaml
{{- $size := "small" }}
{{- if gt (int .Values.replicas) 5 }}
  {{- $size = "large" }}
{{- end }}
size: {{ $size }}
```

### Use case 3: the root `$` (very important)

Inside `range` and `with`, the dot `.` changes meaning. Use `$` to get back to the top.

```yaml
{{- range .Values.hosts }}
- host: {{ . }}                 # . is the current host
  release: {{ $.Release.Name }} # $ is always the root
{{- end }}
```

> **Analogy:** `.` is "where I am standing", `$` is "the school gate" (always the same place).

---

## 9. Useful functions

A function transforms a value. Use the pipe `|` to chain them left to right.

```yaml
{{ .Values.appName | upper | quote }}     # "SCHOOL-SITE"
```

### 9.1 `quote`: wrap in quotes

```yaml
value: {{ .Values.port | quote }}      # "80"
```
> **Use case:** environment variables and annotations, which Kubernetes requires as strings.

### 9.2 `default`: fallback if empty

```yaml
tag: {{ .Values.image.tag | default "latest" }}
replicas: {{ .Values.replicas | default 2 }}
```
> **Use case:** users do not have to set everything. Sensible defaults.

### 9.3 `required`: fail with a clear message

```yaml
password: {{ required "Please set db.password" .Values.db.password | b64enc }}
```
> **Use case:** passwords, domain names, and anything that has no safe default. The install **stops** with your message instead of deploying a broken app.

### 9.4 `upper`, `lower`, `title`, `trunc`, `trimSuffix`

```yaml
name: {{ .Release.Name | lower | trunc 63 | trimSuffix "-" }}
```
> **Use case:** Kubernetes names must be lowercase and at most 63 characters. This keeps them valid.

### 9.5 `printf`: build text

```yaml
image: {{ printf "%s/%s:%s" .Values.registry .Values.image.name .Values.image.tag }}
```
> **Use case:** assembling image names, URLs, and connection strings.

### 9.6 `toYaml` + `nindent`: insert a whole block

```yaml
# values.yaml
resources:
  limits:
    cpu: 500m
    memory: 256Mi
```

```yaml
# template
          resources:
            {{- toYaml .Values.resources | nindent 12 }}
```

Renders as:

```yaml
          resources:
            limits:
              cpu: 500m
              memory: 256Mi
```

> **Use case:** `resources`, `tolerations`, `affinity`, `securityContext`, anything with a complex structure. The student writes the block in values; the template pastes it in. The number after `nindent` must equal the indentation level where the block sits.

### 9.7 `b64enc` / `b64dec`

```yaml
data:
  password: {{ .Values.db.password | b64enc }}
```
> **Use case:** Kubernetes Secrets store values in base64.

### 9.8 `include`: use a named template

```yaml
labels:
  {{- include "school-site.labels" . | nindent 4 }}
```
> **Use case:** same labels on every resource without copy and paste (see section 11).

### 9.9 `tpl`: treat a value as a template

```yaml
# values.yaml
message: "Welcome to {{ .Release.Name }}"
```
```yaml
data:
  greeting: {{ tpl .Values.message . }}
```
> **Use case:** let users write dynamic text in values (for example hostnames containing the release name).

### 9.10 `sha256sum`: restart pods when config changes

```yaml
template:
  metadata:
    annotations:
      checksum/config: {{ include (print $.Template.BasePath "/configmap.yaml") . | sha256sum }}
```
> **Use case:** Kubernetes does **not** restart pods when a ConfigMap changes. This hash changes with the config, which forces a rolling restart. Very common in production charts.

### 9.11 `lookup`: read from the live cluster

```yaml
{{- $existing := lookup "v1" "Secret" .Release.Namespace "db-secret" }}
```
> **Use case:** do not regenerate a random password on every upgrade. Note: `lookup` returns empty during `helm template`.

### 9.12 `hasKey`, `dict`, `list`, `merge`

```yaml
{{- if hasKey .Values "ingress" }} ... {{- end }}
{{- $labels := dict "team" "school" "tier" "web" }}
```

### 9.13 Comparison and logic

| Function | Meaning | Example |
|---|---|---|
| `eq` | equals | `eq .Values.env "prod"` |
| `ne` | not equal | `ne .Values.env "dev"` |
| `gt`, `lt`, `ge`, `le` | greater, less | `gt (int .Values.replicas) 1` |
| `and` | both true | `and .Values.enabled (eq .Values.env "prod")` |
| `or` | either true | `or .Values.a .Values.b` |
| `not` | opposite | `not .Values.debug` |
| `empty` | is empty | `empty .Values.nodeSelector` |

---

## 10. Control flow: if, with, range

### 10.1 `if`: "only if..."

```yaml
{{- if .Values.ingress.enabled }}
apiVersion: networking.k8s.io/v1
kind: Ingress
...
{{- end }}
```

With else:

```yaml
{{- if eq .Values.environment "prod" }}
replicas: 3
{{- else if eq .Values.environment "test" }}
replicas: 2
{{- else }}
replicas: 1
{{- end }}
```

> **Use cases:**
> - Create an Ingress only when `ingress.enabled=true` (prod yes, dev no)
> - Add persistent storage only in prod
> - Add a debug sidecar only in dev
> - Turn on autoscaling only when requested

### 10.2 `with`: "if this exists, work inside it"

`with` does two things: checks it is not empty, **and** changes `.` to that value.

```yaml
{{- with .Values.nodeSelector }}
nodeSelector:
  {{- toYaml . | nindent 2 }}
{{- end }}
```

If `nodeSelector` is empty, nothing is printed at all.

> **Use case:** optional blocks: `nodeSelector`, `tolerations`, `affinity`, `imagePullSecrets`, `resources`. Keeps the output clean.

### 10.3 `range`: "repeat for each item"

**Loop over a list**

```yaml
# values.yaml
hosts:
  - school.example.com
  - www.school.example.com
```
```yaml
rules:
  {{- range .Values.hosts }}
  - host: {{ . }}
  {{- end }}
```

**Loop over a map (key and value)**

```yaml
# values.yaml
env:
  SCHOOL_NAME: "Green Valley High"
  LOG_LEVEL: info
```
```yaml
env:
  {{- range $key, $value := .Values.env }}
  - name: {{ $key }}
    value: {{ $value | quote }}
  {{- end }}
```

Output:

```yaml
env:
  - name: LOG_LEVEL
    value: "info"
  - name: SCHOOL_NAME
    value: "Green Valley High"
```

(Maps are printed in alphabetical key order.)

**Loop with a counter**

```yaml
{{- range $i, $port := .Values.ports }}
- name: port-{{ $i }}
  containerPort: {{ $port }}
{{- end }}
```

> **Use cases:**
> - Many environment variables from one map
> - Many ingress hosts or paths
> - Many ports on one service
> - Create several similar resources (one CronJob per class)

---

## 11. Named templates (helpers)

When you repeat the same piece in many files, define it once in `templates/_helpers.tpl`.

### Define

```yaml
{{- define "school-site.labels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}

{{- define "school-site.fullname" -}}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 63 | trimSuffix "-" }}
{{- end }}
```

### Use (in any template)

```yaml
metadata:
  name: {{ include "school-site.fullname" . }}
  labels:
    {{- include "school-site.labels" . | nindent 4 }}
```

> **Use case:** the Deployment, Service, Ingress, and ConfigMap all need the **same name and labels**. Change them in one place and everything updates. Without this, labels drift apart and Services stop finding their Pods.

**Rules:**
- Always pass the dot: `include "name" .`
- Use `include`, not `template`, because `include` can be piped (`| nindent 4`).
- Prefix the name with the chart name to avoid clashes: `"school-site.labels"`.

### Passing extra arguments with `dict`

A named template accepts **one** argument, so bundle several:

```yaml
{{ include "school-site.container" (dict "root" . "name" "sidecar" "image" "busybox") }}
```

```yaml
{{- define "school-site.container" -}}
- name: {{ .name }}
  image: {{ .image }}
  env:
    - name: RELEASE
      value: {{ .root.Release.Name }}
{{- end }}
```

---

## 12. Real use case: dev, test, and prod

This ties everything together.

### `values.yaml` (safe defaults, good for dev)

```yaml
environment: dev
replicas: 1

image:
  name: nginx
  tag: "1.26"

service:
  type: ClusterIP
  port: 80

ingress:
  enabled: false
  host: ""

env:
  LOG_LEVEL: debug

resources: {}
```

### `values-test.yaml`

```yaml
environment: test
replicas: 2
image:
  tag: "1.27"
env:
  LOG_LEVEL: info
```

### `values-prod.yaml`

```yaml
environment: prod
replicas: 3
image:
  tag: "1.27"
ingress:
  enabled: true
  host: school.example.com
env:
  LOG_LEVEL: warn
resources:
  requests:
    cpu: 200m
    memory: 256Mi
  limits:
    cpu: 500m
    memory: 512Mi
```

### `templates/deployment.yaml`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "school-site.fullname" . }}
  labels:
    {{- include "school-site.labels" . | nindent 4 }}
spec:
  replicas: {{ .Values.replicas }}
  selector:
    matchLabels:
      app.kubernetes.io/instance: {{ .Release.Name }}
  template:
    metadata:
      labels:
        {{- include "school-site.labels" . | nindent 8 }}
    spec:
      containers:
        - name: web
          image: "{{ .Values.image.name }}:{{ .Values.image.tag }}"
          ports:
            - containerPort: {{ .Values.service.port }}
          env:
            - name: ENVIRONMENT
              value: {{ .Values.environment | quote }}
            {{- range $k, $v := .Values.env }}
            - name: {{ $k }}
              value: {{ $v | quote }}
            {{- end }}
          {{- with .Values.resources }}
          resources:
            {{- toYaml . | nindent 12 }}
          {{- end }}
```

### `templates/service.yaml`

```yaml
apiVersion: v1
kind: Service
metadata:
  name: {{ include "school-site.fullname" . }}
  labels:
    {{- include "school-site.labels" . | nindent 4 }}
spec:
  type: {{ .Values.service.type }}
  ports:
    - port: {{ .Values.service.port }}
      targetPort: {{ .Values.service.port }}
  selector:
    app.kubernetes.io/instance: {{ .Release.Name }}
```

### `templates/ingress.yaml`

```yaml
{{- if .Values.ingress.enabled }}
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: {{ include "school-site.fullname" . }}
spec:
  rules:
    - host: {{ required "ingress.host is required when ingress is enabled" .Values.ingress.host }}
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: {{ include "school-site.fullname" . }}
                port:
                  number: {{ .Values.service.port }}
{{- end }}
```

### Deploy to each environment

```bash
helm upgrade --install school-dev  ./school-site -n dev
helm upgrade --install school-test ./school-site -n test -f values-test.yaml
helm upgrade --install school-prod ./school-site -n prod -f values-prod.yaml --create-namespace
```

### What each feature did

| Feature | Where it helped |
|---|---|
| `values-*.yaml` files | Different settings per environment, same templates |
| `if .Values.ingress.enabled` | Public address only in prod |
| `required` | Stops prod install if the host is forgotten |
| `range` over `env` | Any number of env variables from values |
| `with` + `toYaml` | Resource limits only when provided |
| `include` helpers | Same name and labels in every resource |

---

## 13. Real use case: ConfigMap and Secret

### ConfigMap from a map in values

```yaml
# values.yaml
config:
  SCHOOL_NAME: "Green Valley High"
  TIMEZONE: "Asia/Kolkata"
```

```yaml
# templates/configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ include "school-site.fullname" . }}-config
data:
  {{- range $key, $value := .Values.config }}
  {{ $key }}: {{ $value | quote }}
  {{- end }}
```

### ConfigMap from a whole file

Put `app.conf` inside the chart, then:

```yaml
data:
  app.conf: |-
{{ .Files.Get "app.conf" | indent 4 }}
```

> **Use case:** nginx config, SQL scripts, or property files you want to keep as real files in the chart.

### Secret

```yaml
# templates/secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name: {{ include "school-site.fullname" . }}-db
type: Opaque
data:
  password: {{ required "db.password is required" .Values.db.password | b64enc | quote }}
```

Pass the password at install time and **never write it in Git**:

```bash
helm upgrade --install school ./school-site --set db.password=$DB_PASSWORD
```

or from a file:

```bash
helm upgrade --install school ./school-site --set-file db.password=./password.txt
```

### Use the ConfigMap and Secret in the Deployment

```yaml
          envFrom:
            - configMapRef:
                name: {{ include "school-site.fullname" . }}-config
          env:
            - name: DB_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: {{ include "school-site.fullname" . }}-db
                  key: password
```

### Restart pods automatically when config changes

```yaml
  template:
    metadata:
      annotations:
        checksum/config: {{ include (print $.Template.BasePath "/configmap.yaml") . | sha256sum }}
```

---

## 14. Subcharts and global values

### What is a subchart?

A chart your chart depends on. Example: your website needs a PostgreSQL database; instead of writing it yourself, you use the existing PostgreSQL chart.

`Chart.yaml`

```yaml
dependencies:
  - name: postgresql
    version: "15.x.x"
    repository: https://charts.bitnami.com/bitnami
```

```bash
helm dependency update ./school-site
```

### Passing values to a subchart

Use the **subchart's name** as the key:

```yaml
# values.yaml of the parent
postgresql:
  auth:
    username: school
    database: schooldb
```

```bash
helm install school ./school-site --set postgresql.auth.password=secret123
```

### Global values: visible in parent and all subcharts

```yaml
global:
  imageRegistry: registry.example.com
  environment: prod
```

Any chart can use `{{ .Values.global.imageRegistry }}`.

> **Use case:** one registry address or one environment name shared by every chart in the release.

### Turn a subchart on or off

```yaml
dependencies:
  - name: postgresql
    condition: postgresql.enabled
```

```bash
helm install school ./school-site --set postgresql.enabled=false   # use an external database instead
```

---

## 15. Validating values with a schema

Create `values.schema.json` next to `values.yaml`. Helm checks values **before** deploying.

```json
{
  "$schema": "https://json-schema.org/draft-07/schema#",
  "type": "object",
  "required": ["image"],
  "properties": {
    "replicas": { "type": "integer", "minimum": 1, "maximum": 20 },
    "debug": { "type": "boolean" },
    "environment": { "type": "string", "enum": ["dev", "test", "prod"] },
    "image": {
      "type": "object",
      "required": ["name", "tag"],
      "properties": {
        "name": { "type": "string" },
        "tag": { "type": "string" }
      }
    }
  }
}
```

Test it:

```bash
helm template demo ./school-site --set replicas=abc
# Error: replicas: Invalid type. Expected: integer, given: string

helm template demo ./school-site --set environment=staging
# Error: environment must be one of: dev, test, prod
```

> **Use case:** catch typos and wrong types **early**, with a clear message, instead of getting a confusing Kubernetes error later. Great when many teams use your chart.

---

## 16. Debugging

| Command | What it does |
|---|---|
| `helm lint ./chart` | Finds syntax mistakes |
| `helm template NAME ./chart` | Shows rendered YAML (no cluster needed) |
| `helm template NAME ./chart -s templates/ingress.yaml` | Shows just one file |
| `helm install NAME ./chart --dry-run --debug` | Simulates an install and prints everything |
| `helm get values NAME` | Values you supplied for a release |
| `helm get values NAME --all` | Final values (defaults and yours merged) |
| `helm get manifest NAME` | The YAML actually deployed |
| `helm history NAME` | All versions of a release |
| `helm rollback NAME 1` | Go back to revision 1 |
| `helm list -A` | All releases in all namespaces |
| `helm uninstall NAME` | Remove a release |

### Print a value while developing

```yaml
# DEBUG: {{ .Values.replicas | toJson }} is {{ typeOf .Values.replicas }}
```

Or dump all values:

```yaml
# {{ toYaml .Values | nindent 2 }}
```

### Debug workflow for students

1. `helm lint` (is the syntax OK?)
2. `helm template` (is the output what I expected?)
3. `helm install --dry-run --debug` (does the cluster accept it?)
4. `helm install` (deploy)
5. `helm get values NAME --all` (which values were really used?)

---

## 17. Common mistakes

| Mistake / Error | Cause | Fix |
|---|---|---|
| `nil pointer evaluating interface {}.tag` | Parent key (`image`) missing in values | Add a default in `values.yaml` |
| YAML error after `toYaml` | Wrong number in `nindent` | Match the indentation of the line above |
| Version `1.20` shows as `1.2` | YAML read it as a number | Quote: `"1.20"` or `--set-string` |
| `cannot unmarshal number into string` | Number given where text is expected (env values) | Add `\| quote` |
| `--set debug=true` gives a boolean, not text | Helm guesses types | Use `--set-string` if you need text |
| My list override lost the other items | Lists are replaced, not merged | Pass the full list |
| Extra blank lines or broken YAML | Missing `-` in `{{-` | Add `{{-` to trim whitespace |
| Values disappear after `helm upgrade` | Previous `--set` values are not remembered | Pass the same `-f` and `--set` again |
| Template works in `helm template` but fails on install | Cluster rejected the YAML | Use `--dry-run --debug` |
| Inside `range`, `.Release.Name` fails | `.` changed meaning | Use `$.Release.Name` |
| `lookup` returns nothing | It only works against a real cluster | Do not rely on it with `helm template` |

---

## 18. Exercises

### Level 1: Easy

1. Create a chart called `school-site` and run `helm template demo ./school-site`.
2. Change `replicas` to 5 using `--set`. Confirm in the output.
3. Create `values-dev.yaml` with `replicas: 1` and render with `-f`.

### Level 2: Medium

4. Add a value `owner: "Class 10A"` and show it as a label in the Deployment.
5. Add `debug: false`. Add an env variable `DEBUG=true` **only** when `debug` is true (use `if`).
6. Add `LOG_LEVEL` and `SCHOOL_NAME` under `env:` in values, and print them with `range`.
7. Make the image tag default to `.Chart.AppVersion` when `image.tag` is empty.

### Level 3: Challenge

8. Create `service.yaml` that uses the same `fullname` and labels from `_helpers.tpl`.
9. Create an `ingress.yaml` that renders only when `ingress.enabled=true` and fails with a clear message if `ingress.host` is missing (`required`).
10. Add a list `allowedClasses: [9A, 9B, 10A]` and print each class as a key in a ConfigMap using `range`.
11. Add `values.schema.json` so that `replicas` must be an integer between 1 and 10.
12. Add the `checksum/config` annotation so the pods restart when the ConfigMap changes.

### Sample solutions

**Exercise 5**

```yaml
env:
  {{- if .Values.debug }}
  - name: DEBUG
    value: "true"
  {{- end }}
```

**Exercise 7**

```yaml
image: "{{ .Values.image.name }}:{{ .Values.image.tag | default .Chart.AppVersion }}"
```

**Exercise 10**

```yaml
data:
  {{- range .Values.allowedClasses }}
  {{ . | quote }}: "allowed"
  {{- end }}
```

---

## 19. Cheat sheet

### Template syntax

```text
{{ .Values.x }}                       read a value
{{ .Values.x | default "a" }}         fallback
{{ .Values.x | quote }}               add quotes
{{ required "msg" .Values.x }}        fail if empty
{{- if .Values.x }} ... {{- end }}    conditional
{{- with .Values.x }} ... {{- end }}  scope + not-empty check
{{- range .Values.list }} {{ . }} {{- end }}
{{- range $k, $v := .Values.map }} {{ $k }}={{ $v }} {{- end }}
{{ $var := .Values.x }}               local variable
{{ $.Release.Name }}                  root from inside with/range
{{ toYaml .Values.x | nindent 4 }}    paste a block
{{ include "chart.name" . | nindent 4 }}
{{ .Values.n | int }}                 convert type
```

### Passing values

```text
-f file.yaml                  from a file (last file wins)
--set a=b                     one value
--set a.b.c=1                 nested value
--set-string a=1.20           force text
--set 'list={a,b}'            list
--set-file a=./file           value from file content
--set-json 'a={"b":1}'        JSON value
```

### Precedence

```text
values.yaml  <  -f files  <  --set
```

### Main commands

```bash
helm create NAME                       # new chart
helm lint ./chart                      # check
helm template NAME ./chart -f x.yaml   # preview
helm upgrade --install NAME ./chart    # install or upgrade
helm get values NAME --all             # inspect
helm rollback NAME REVISION            # undo
helm uninstall NAME                    # remove
```

### One-line summary

> **Template** = YAML with blanks. **Values** = what fills the blanks. **Helm** = fills them in and deploys the result.
