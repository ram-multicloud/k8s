# Helm 2 vs Helm 3 vs Helm 4: Explained in Detail with Diagrams

> **Status check (15 Nov 2026):** the Helm documentation site currently lists **Helm 4.3.1** as the current release, **Helm 3.22.1** as the last Helm 3 line, and **Helm 2.17.0** as the final Helm 2 release. Helm 2 has been unsupported since 2020. Helm 3 had its final, limited feature release on **9 Sep 2026** and receives **security fixes only until 10 Feb 2027**. After that date, Helm 3 gets no updates of any kind.

How to read this file: every section starts with a diagram, then explains it. Diagrams are plain text, so they render in any editor.

---

## 1. At a Glance

| | **Helm 2** | **Helm 3** | **Helm 4** |
|---|---|---|---|
| Era | 2016 to 2020 | Nov 2019 to now (winding down) | GA 12 Nov 2025 to now |
| Support status | Unsupported (since 2020) | Security fixes only, until 10 Feb 2027 | Current, actively developed |
| Architecture | Client + **Tiller** server inside the cluster | **Client only** (no Tiller) | Client only, with a new plugin system and SDK |
| Talks to cluster as | Tiller's service account | **You** (your kubeconfig) | **You** (your kubeconfig) |
| Release data stored in | ConfigMaps in Tiller's namespace (`kube-system`) | **Secrets** in the release's own namespace | Same Secrets as Helm 3 (no migration) |
| Release names | Unique across the whole cluster | Unique **per namespace** | Per namespace |
| How changes are applied | Two-way merge | **Three-way strategic merge patch** | **Server-side apply** for new releases (latches to the old method for existing ones) |
| Chart `apiVersion` | `v1` | `v2` | `v2` works unchanged; `v3` is experimental |
| Dependencies file | `requirements.yaml` | In `Chart.yaml` (`dependencies:`) | In `Chart.yaml` |
| Chart storage | HTTP repositories | HTTP repositories + **OCI registries** (stable since 3.8) | OCI-first, digest installs |
| Plugins | Shell-based | Shell-based | Shell-based **and optional WebAssembly (Wasm)** |
| `--wait` | Polling | Polling | **kstatus** watcher |
| Go SDK import | `k8s.io/helm` | `helm.sh/helm/v3` | `helm.sh/helm/v4` |

---

## 2. Timeline

```text
2016            2019 Nov         2020              2025 Nov 12        2026 Sep 9         2027 Feb 10
 |                |               |                    |                  |                  |
 v                v               v                    v                  v                  v
Helm 2 -------> Helm 3.0 ------> Helm 2 EOL -------> Helm 4.0 GA ----> Last Helm 3 ----> Helm 3 gets
(Tiller)        (no Tiller)      (unsupported)        (KubeCon NA,       feature release   NO updates at
                                                       Atlanta)          (k8s client       all (not even
                                                                         libs only)        security)

            |<================ Helm 3 supported period =======================>|
                                                       |<=== Helm 4 supported, current ===============>
```

What each date means:

| Date | Event |
|---|---|
| Nov 2019 | Helm 3.0.0 released: Tiller removed |
| 2020 | Helm 2 and the old `charts` project become unsupported |
| 12 Nov 2025 | Helm 4.0.0 released at KubeCon + CloudNativeCon North America. First new major version in six years |
| 9 Sep 2026 | Final, limited Helm 3 feature release (Kubernetes client-library updates only) |
| 10 Feb 2027 | End of Helm 3 security support (extended from the original Nov 2026) |

> Older blog posts still quote bug-fix and security dates of 8 Jul 2026 and 11 Nov 2026. The project extended those in June 2026, so use the dates above.

---

## 3. Core Concepts (the same in every version)

```text
  CHART  (package of templates + defaults)
    |
    |  helm install <name> <chart> -f my-values.yaml
    v
  RELEASE  (one running instance of a chart in a cluster)
    |-- revision 1  (first install)
    |-- revision 2  (after upgrade)
    '-- revision 3  (after rollback creates a new revision)

  REPOSITORY / REGISTRY  (where charts are stored and downloaded from)
```

| Term | Meaning |
|---|---|
| Chart | Templates, default values and metadata for one application |
| Values | Settings that fill the templates (`values.yaml`, `-f`, `--set`) |
| Release | An installed chart. The same chart can be installed many times |
| Revision | One version of a release's history. Every install, upgrade or rollback adds one |
| Repository | An HTTP server hosting `index.yaml` and `.tgz` charts |
| Registry (OCI) | An OCI container registry that also stores charts |

**What does not change across versions:** the chart folder layout (`Chart.yaml`, `values.yaml`, `templates/`), the Go-template language with Sprig functions, `helm create`, `helm lint`, `helm template` and the idea of releases and rollbacks. Charts you write for Helm 3 deploy with Helm 4.

---

## 4. Helm 2: The Tiller Era

### 4.1 Architecture

```text
 YOUR LAPTOP                         KUBERNETES CLUSTER
+-----------+                   +--------------------------------------------+
|           |   gRPC :44134     |  namespace: kube-system                    |
| helm CLI  | ----------------> |  +----------+          +-----------------+ |
| (client)  |                   |  |  TILLER  | -------> | Kubernetes API  | |
|           |                   |  | (server) |          |     server      | |
+-----------+                   |  +----+-----+          +-----------------+ |
      |                         |       |                                    |
      | charts                  |       v                                    |
      v                         |  release records stored as ConfigMaps     |
 repositories                   |  (in kube-system)                          |
 (stable, incubator)            +--------------------------------------------+
```

### 4.2 How an install worked

```text
 helm install --name web stable/nginx
        |
        | 1. client renders nothing: it sends the CHART + VALUES to Tiller
        v
     TILLER (inside the cluster)
        | 2. renders templates on the server
        | 3. creates resources through the Kubernetes API using Tiller's own identity
        | 4. stores the release as a ConfigMap
        v
   Kubernetes API server
```

### 4.3 Key traits and why they hurt

| Trait | Consequence |
|---|---|
| Tiller ran with broad permissions (often `cluster-admin`) | Anyone who could reach Tiller could deploy anything, **bypassing your own RBAC**. The "who did this" answer was always Tiller |
| Tiller had to be installed first (`helm init`) | Extra setup, extra component to secure (TLS, service accounts) and upgrade |
| Release names were global | You could not reuse `web` in two namespaces |
| Release data in ConfigMaps in `kube-system` | Mixed with system objects, size-limited and not scoped to the app's namespace |
| `helm install` without `--name` generated a random name | Unpredictable release names |
| Two-way merge on upgrade | Manual changes made with `kubectl edit` were not noticed (see 5.4) |
| `requirements.yaml` and chart `apiVersion: v1` | A separate file for dependencies |
| No chart `values.schema.json` | No validation of user input |
| Charts only from HTTP repositories | No OCI registry support |

### 4.4 Helm 2 commands you may still see in old tutorials

```bash
helm init                                  # install Tiller
helm install --name web stable/nginx
helm ls
helm delete web                            # release still stored
helm delete web --purge                    # remove completely
helm fetch stable/nginx
helm search nginx
```

> Do not use Helm 2 today. It has been unsupported since 2020 and its Tiller model is a security risk.

---

## 5. Helm 3: Tiller Removed

### 5.1 Architecture

```text
 YOUR LAPTOP / CI RUNNER                          KUBERNETES CLUSTER
+-------------------------+   HTTPS + YOUR       +--------------------------------+
|        helm CLI         |   kubeconfig         |        Kubernetes API          |
|                         |   credentials        |            server              |
|  - renders templates    | -------------------> |                                |
|  - computes the patch   |                      |   namespace: dev               |
|  - talks to the API     |                      |   +--------------------------+ |
+-----------+-------------+                      |   | Deployment, Service ...  | |
            |                                    |   | Secret                   | |
   charts   |                                    |   |  sh.helm.release.v1      | |
            v                                    |   |  .web.v1  .web.v2 ...    | |
  HTTP repos / OCI registry                      |   +--------------------------+ |
                                                 +--------------------------------+
```

The Helm client now does all the work (rendering and diffing) and talks straight to the Kubernetes API, using the same credentials as `kubectl`.

### 5.2 What changed from Helm 2 and why it matters

| Change | Details | Benefit |
|---|---|---|
| **No Tiller** | The client uses your kubeconfig | Standard Kubernetes RBAC applies to Helm. No privileged server in the cluster |
| **Releases are namespaced** | `helm install web` can exist in `dev` and `prod` | Same names in different namespaces |
| **Release info in Secrets** | Named `sh.helm.release.v1.<release>.v<revision>`, stored in the release's namespace | Scoped and protected like other Secrets |
| **Three-way merge** | Compares old chart, live cluster and new chart | Respects manual or controller changes (section 5.4) |
| **`apiVersion: v2` charts** | Dependencies move into `Chart.yaml` | One file describes the chart |
| **Library charts** | `type: library` | Share helper templates |
| **`values.schema.json`** | JSON-Schema validation of values | Catch bad input early |
| **`crds/` directory** | CRDs installed before templates | Cleaner CRD handling |
| **OCI registries** | Store and pull charts like images (stable since 3.8) | Reuse existing registries (ECR, ACR, GHCR, Docker Hub) |
| **Install needs a name** | Or use `--generate-name` | Predictable naming |
| **Namespace is not auto-created** | Use `--create-namespace` (added in Helm 3.2) | Explicit control |
| **Simplified commands** | `uninstall`, `pull`, `search repo`, `search hub` | Clearer verbs |
| **No `helm init`, no default `stable` repo** | You add the repos you want | Less hidden setup |
| **Stricter `helm lint` / `helm template` without a server** | `helm template` works offline | Better CI usage |

### 5.3 Helm 2 vs Helm 3 command map

| Task | Helm 2 | Helm 3 |
|---|---|---|
| Set up | `helm init` | not needed |
| Install | `helm install --name web stable/nginx` | `helm install web bitnami/nginx` |
| Random name | automatic | `helm install bitnami/nginx --generate-name` |
| Remove | `helm delete web --purge` | `helm uninstall web` |
| Download chart | `helm fetch` | `helm pull` |
| Search | `helm search nginx` | `helm search repo nginx` / `helm search hub nginx` |
| New namespace | created automatically | `--create-namespace` |
| Dependencies | `requirements.yaml` + `helm dep update` | `dependencies:` in `Chart.yaml` + `helm dep update` |

### 5.4 The three-way merge (why upgrades behave better)

```text
 Helm 2: TWO-WAY                           Helm 3: THREE-WAY
 (old chart vs new chart)                  (old chart + LIVE state + new chart)

 +-----------+     +-----------+           +-----------+  +-----------+  +-----------+
 | old       |     | new       |           | old       |  | live in   |  | new       |
 | manifest  |     | manifest  |           | manifest  |  | cluster   |  | manifest  |
 +-----+-----+     +-----+-----+           +-----+-----+  +-----+-----+  +-----+-----+
       \               /                         \             |             /
        \             /                           \            |            /
         v           v                             v           v           v
       patch = difference                        patch = changes needed so that live
                                                 state matches new manifest, while
   Live state is IGNORED                         keeping other people's edits
```

Example scenario:

| Step | What happens | Helm 2 result | Helm 3 result |
|---|---|---|---|
| 1 | `helm install web` with `replicas: 3` | 3 replicas | 3 replicas |
| 2 | Someone runs `kubectl scale --replicas=5` | live = 5 | live = 5 |
| 3 | `helm upgrade web` with a new image, `replicas` still 3 in the chart | Old and new chart both say 3, so no replica change is sent: **stays 5** (drift not noticed) | Live (5) differs from desired (3) and is corrected: **back to 3** (or keeps edits to fields Helm never set) |

The key point: Helm 3 knows the live state, so it can detect and handle drift and edits instead of ignoring them.

### 5.5 Where Helm 3 releases live

```text
 kubectl get secrets -n dev -l owner=helm

 NAME                          TYPE                 
 sh.helm.release.v1.web.v1     helm.sh/release.v1   <- revision 1
 sh.helm.release.v1.web.v2     helm.sh/release.v1   <- revision 2
 sh.helm.release.v1.web.v3     helm.sh/release.v1   <- revision 3 (current)
```

Each revision is one Secret holding the compressed release data. Helm keeps a limited number of old revisions; set it with `--history-max`.

### 5.6 Migrating Helm 2 to Helm 3 (historical)

The `helm-2to3` plugin converted Helm 2 releases and config to Helm 3. **It is now unsupported**, so for any leftover Helm 2 releases the safe approach is:

1. Export the live manifests (`helm get manifest`, or `kubectl get ... -o yaml`).
2. Install the same chart with Helm 3 in a test namespace and compare.
3. Re-create the release with Helm 3 and clean up Tiller.

---

## 6. Helm 4: The Current Generation

### 6.1 Big picture

```text
 +----------------------------------------------------------------------+
 |                            HELM 4 CLIENT                             |
 |                                                                      |
 |  +-------------+   +--------------+   +---------------------------+  |
 |  | Renderer    |   | Apply engine |   | Status watcher (kstatus)  |  |
 |  | (templates, |-->| Server-Side  |-->| waits until resources are |  |
 |  |  values)    |   | Apply (SSA)  |   | really ready              |  |
 |  +------+------+   +------+-------+   +-------------+-------------+  |
 |         |                 |                         |                |
 |         v                 v                         v                |
 |  +-----------------------------------------------------------------+ |
 |  |                      PLUGIN SYSTEM (new)                        | |
 |  |   CLI plugins | Getter plugins | Post-renderer plugins          | |
 |  |   runtimes:  subprocess  or  WebAssembly (Wasm, sandboxed)      | |
 |  +-----------------------------------------------------------------+ |
 +-----------------------------+----------------------------------------+
                               |  your kubeconfig credentials
                               v
                  Kubernetes API server   (release Secrets: same format as Helm 3)
```

Helm 4 keeps the Helm 3 architecture (client only, no server) and modernises the internals. The project's own words: charts deployable with Helm 3 should deploy with Helm 4, and releases managed by Helm 3 should generally upgrade with Helm 4 **with no migration step**.

### 6.2 What is new, feature by feature

| Feature | What it means |
|---|---|
| **Server-Side Apply (SSA)** | Helm sends the desired state and Kubernetes tracks which tool owns which field |
| **kstatus watcher for `--wait`** | Helm watches real resource status instead of simple polling |
| **Plugin system overhaul** | New plugin types, optional Wasm runtime, signing and packaging |
| **Post-renderers are plugins** | Pass a plugin name instead of an executable path |
| **OCI digest installs** | `helm install myapp oci://registry/charts/app@sha256:...` |
| **Multi-document values** | Layer several YAML documents of values (useful per environment) |
| **Custom template functions** | Plugins can add functions to the template engine |
| **Content-based chart caching, faster dependency resolution** | Faster builds and repeated commands |
| **Better registry auth** | Improved OAuth and token support for private registries |
| **Clearer error messages** | Easier troubleshooting |
| **Stable Go SDK** | New import path `helm.sh/helm/v4`; breaking API changes are done |
| **Chart API v3 (experimental)** | Early development; off by default |
| **Modernised internals** | `slog` logging, newer Go, dependency clean-up |

### 6.3 Server-Side Apply versus the old method

```text
 CLIENT-SIDE APPLY (Helm 3)                SERVER-SIDE APPLY (Helm 4)

 Helm computes a patch locally             Helm sends the DESIRED STATE
 (three-way merge) and sends it            to the API server, labelled with
                                           a "field manager" name
        |                                          |
        v                                          v
 +---------------+                          +----------------------------+
 | API server    |                          | API server                 |
 | applies patch |                          | tracks WHO owns each field |
 +---------------+                          |  spec.replicas -> hpa      |
                                            |  spec.image    -> helm     |
  Conflicts with other tools                |  metadata.labels -> argocd |
  (HPA, Argo CD, operators) are             +----------------------------+
  easy to cause and hard to see             Conflicts are detected by the
                                            server and reported clearly
```

How Helm 4 chooses the apply method:

```text
                 helm install (new release)
                           |
                           v
                 Use SERVER-SIDE apply   ----------------------+
                                                               |
 helm upgrade / rollback of an EXISTING release                |
                           |                                   |
           "latching": follow the method the release used last |
                           |                                   |
        +------------------+-------------------+               |
        v                                      v               |
 release made by Helm 3                 release made by Helm 4 |
 -> stays CLIENT-side                   -> stays SERVER-side <-+
        |
        v
  override anytime with the --server-side flag (for example --server-side=false)
```

Practical meaning:

- **All releases created by Helm 3 keep using client-side apply after you switch binaries.** Nothing changes behind your back.
- **New releases made by Helm 4 use server-side apply.** This is where resource ownership improves.
- You can force either behaviour per command with `--server-side`.

### 6.4 `--wait` with kstatus

```text
 Helm 3 --wait (polling)                    Helm 4 --wait (kstatus watcher)

 helm upgrade --wait                        helm upgrade --wait
        |                                          |
        v                                          v
 Check pods/Deployments every few           Watch every resource's status through the
 seconds with fixed rules                   Kubernetes API (events, conditions)
        |                                          |
        v                                          v
 "Looks ready" can be reported while        Reports ready only when the resource's
 old pods are still running or a            own status says Current/Complete, and
 custom resource has no clear signal        reports failures with a clearer reason
```

Notes:

- The kstatus integration gives more detailed status on whether your deployments are really done, and the docs recommend testing it on complex applications.
- The accepted values of `--wait` (including a legacy polling mode) can differ between 4.x releases, so run `helm install --help` on your installed version.
- Pipelines that previously **passed** because `--wait` was lenient can now wait longer or fail. This is the most common surprise after upgrading, so test your CI first.

### 6.5 The plugin system

```text
 HELM 3 PLUGINS                             HELM 4 PLUGINS

 plugin.yaml  --> a command line            plugin.yaml  (apiVersion: v1)
 that Helm runs as a                              |
 SUBPROCESS on your machine                       v
 (full access to your OS)                  +--------------------------+
                                           | runtime                  |
 Types: CLI sub-commands, downloaders      |  - subprocess (as before)|
 (getters) and, separately, the            |  - Wasm  (sandboxed)     |
 --post-renderer EXECUTABLE flag           +------------+-------------+
                                                        |
                                           Types: cli/v1   getter/v1   postrenderer/v1
                                           (+ a system for adding more types later)
                                           Plugins can be packaged, signed and verified
```

- **Existing Helm 3 plugins continue to work**, though the plugin docs include a migration guide for plugin authors.
- The **Wasm runtime is optional** and recommended for enhanced security, because a Wasm plugin runs in a sandbox instead of with your full user permissions.
- **Post-renderers now must be plugins.**

Post-renderer before and after:

```bash
# Helm 3: pass an executable
helm install myapp ./chart --post-renderer ./kustomize-wrapper.sh

# Helm 4: install a post-renderer plugin, then pass its NAME
helm plugin install <post-renderer-plugin-source>
helm install myapp ./chart --post-renderer <plugin-name>
```

### 6.6 OCI improvements: install by digest

```text
 TAG-BASED (can change)                          DIGEST-BASED (immutable)

 oci://registry.example.com/charts/app:1.2.0     oci://registry.example.com/charts/app@sha256:<hash>
        |                                                 |
 A tag can be re-pushed with different content   The digest IS the content hash: if the
 and you would never notice                      downloaded chart does not match, Helm refuses
                                                 to install it
```

```bash
helm install myapp oci://registry.example.com/charts/app@sha256:<digest>
```

This gives better supply-chain security for pipelines.

`helm registry login` also changed: use only the **domain name** (no path).

```bash
# Helm 3 (a path could be included)        # Helm 4 (domain only)
helm registry login registry.example.com/charts      ->      helm registry login registry.example.com
```

### 6.7 Multi-document values and custom template functions

- **Multi-document values** let you split or layer values across YAML documents, useful for keeping per-environment configuration tidy. Check `helm install --help` and the Helm 4 docs on your version for the exact behaviour, then test it before relying on it.
- **Custom template functions** are provided by plugins, for organisation-specific templating.

### 6.8 Chart API v3 (experimental)

Charts v3 is in early development and may change before release. It is off unless you opt in:

```bash
export HELM_EXPERIMENTAL_CHART_V3=1
helm create --chart-api-version=v3 mychart
```

Keep using `apiVersion: v2` charts for anything real. They continue to work unchanged in Helm 4.

### 6.9 Breaking and deprecated changes (the checklist)

| Area | Helm 3 | Helm 4 | Action |
|---|---|---|---|
| Atomic installs | `--atomic` | `--rollback-on-failure` (old flag still works but warns) | Update scripts |
| Force replace | `--force` | `--force-replace` (old flag still works but warns) | Update scripts |
| Post-renderer | `--post-renderer ./script` | `--post-renderer <plugin-name>` | Convert to a plugin |
| Registry login | accepted a path | **domain only** | Fix login commands |
| Go SDK | `helm.sh/helm/v3/...` | `helm.sh/helm/v4/...` (chart types under `chart/v2`) | Update imports |
| `helm template` flags | `--hide-notes`, `--render-subchart-notes` | Deprecated, no effect, to be removed in Helm 5 | Stop using |
| Plugins | Helm 3 plugin format | Existing plugins keep working; new format available | Test all plugins |
| `--wait` | Polling | kstatus | Re-test pipelines |
| New releases | Client-side apply | Server-side apply | Test with Argo CD, operators, HPAs |

**What did not break:** your chart files, templates and values, release history, repositories and everyday commands like `install`, `upgrade`, `rollback`, `uninstall`, `list`, `template`, `lint`, `repo`, `pull` and `dependency`.

**Not solved in Helm 4:** CRD lifecycle management. Helm still installs CRDs from the `crds/` folder only once and does not upgrade or delete them, so keep a separate process for CRD updates.

---

## 7. Side-by-Side Detailed Comparison

### 7.1 Architecture and security

| Topic | Helm 2 | Helm 3 | Helm 4 |
|---|---|---|---|
| Server component | Tiller (a Pod with high privileges) | None | None |
| Permissions model | Tiller's identity (often cluster-admin) | Your Kubernetes RBAC | Your Kubernetes RBAC |
| Audit trail in Kubernetes | Shows Tiller | Shows the real user or CI identity | Shows the real user or CI identity |
| Release data | ConfigMaps in `kube-system` | Secrets in the release namespace | Same as Helm 3 |
| Plugin isolation | None | None | Optional Wasm sandbox |
| Chart integrity | Provenance files (`helm package --sign`) | Provenance files + OCI | Provenance + digest installs + signed plugins |
| Network exposure | gRPC port 44134 on Tiller | None | None |

### 7.2 Charts and templates

| Topic | Helm 2 | Helm 3 | Helm 4 |
|---|---|---|---|
| `Chart.yaml` `apiVersion` | `v1` | `v2` | `v2` (and experimental `v3`) |
| Dependencies | `requirements.yaml` | `Chart.yaml` `dependencies:` | `Chart.yaml` `dependencies:` |
| Library charts | No | Yes (`type: library`) | Yes |
| Values validation | None | `values.schema.json` | `values.schema.json` |
| CRDs | `crd-install` hook | `crds/` directory | `crds/` directory (lifecycle still limited) |
| Template language | Go templates + Sprig | Go templates + Sprig | Go templates + Sprig, plus plugin-provided functions |
| `helm create` output | Basic chart | Modern chart layout | Modern chart layout |

### 7.3 Releases and upgrades

| Topic | Helm 2 | Helm 3 | Helm 4 |
|---|---|---|---|
| Release scope | Cluster-wide names | Per namespace | Per namespace |
| Upgrade merge | Two-way | Three-way strategic merge | Server-side apply (new releases); three-way for latched existing releases |
| Field ownership | Not tracked by Helm | Not tracked by Helm | Tracked by Kubernetes (SSA field managers) |
| Rollback | `helm rollback` | `helm rollback` | `helm rollback` (follows the release's apply method) |
| Failure handling | `--atomic` | `--atomic` | `--rollback-on-failure` |
| Waiting | Polling | Polling | kstatus watcher |
| History limit | Manual | `--history-max` | `--history-max` |

### 7.4 Distribution

| Topic | Helm 2 | Helm 3 | Helm 4 |
|---|---|---|---|
| HTTP chart repositories | Yes (default `stable` repo) | Yes (no default repo) | Yes |
| OCI registries | No | Yes (stable since 3.8) | Yes, plus install by digest and better auth |
| Search | `helm search` | `helm search repo` / `hub` | same as Helm 3 |
| Caching | Basic | Basic | Content-based chart caching |
| Dependency resolution | Normal | Normal | Faster |

### 7.5 Tooling and SDK

| Topic | Helm 2 | Helm 3 | Helm 4 |
|---|---|---|---|
| Go module | `k8s.io/helm` | `helm.sh/helm/v3` | `helm.sh/helm/v4` |
| SDK stability | n/a | Stable within v3 | Breaking changes complete, now stable |
| Logging | Older style | `log` based | Modern `slog` |
| Embedding the CLI | Hard | Possible | Easier (commands refactored for library use) |

---

## 8. Command Comparison

| Task | Helm 2 | Helm 3 | Helm 4 |
|---|---|---|---|
| Initialise | `helm init` | not needed | not needed |
| Install | `helm install --name web chart/` | `helm install web chart/` | `helm install web chart/` |
| Install in new namespace | auto | `--namespace dev --create-namespace` | same |
| Generate a name | default | `--generate-name` | same |
| Upgrade or install | `helm upgrade --install web chart/` | `helm upgrade -i web chart/` | same |
| Roll back on failure | `--atomic` | `--atomic` | `--rollback-on-failure` |
| Force resource replacement | `--force` | `--force` | `--force-replace` |
| Wait for readiness | `--wait` | `--wait --timeout 5m` | `--wait --timeout 5m` (kstatus) |
| Choose apply method | n/a | n/a | `--server-side` |
| List releases | `helm ls` | `helm list -A` | `helm list -A` |
| Uninstall | `helm delete web --purge` | `helm uninstall web` | `helm uninstall web` |
| Download a chart | `helm fetch` | `helm pull` | `helm pull` |
| Search repos | `helm search nginx` | `helm search repo nginx` | `helm search repo nginx` |
| Search Artifact Hub | n/a | `helm search hub nginx` | `helm search hub nginx` |
| OCI push | n/a | `helm push chart.tgz oci://host/path` | same, plus install by `@sha256:` digest |
| Registry login | n/a | `helm registry login host` (path allowed) | `helm registry login host` (domain only) |
| Post-renderer | n/a | `--post-renderer ./script` | `--post-renderer <plugin>` |

---

## 9. Same Chart, Three Eras (side-by-side files)

### 9.1 `Chart.yaml`

```yaml
# Helm 2 (apiVersion v1)               # Helm 3 and 4 (apiVersion v2)
apiVersion: v1                         apiVersion: v2
name: web                              name: web
version: 0.1.0                         version: 0.1.0
appVersion: "1.0"                      appVersion: "1.0"
                                       type: application
                                       dependencies:
                                         - name: redis
                                           version: "x.y.z"
                                           repository: https://example.com/charts
# dependencies were in a separate file:
# requirements.yaml
# dependencies:
#   - name: redis
#     version: x.y.z
#     repository: https://example.com/charts
```

### 9.2 Deployment commands

```bash
# Helm 2
helm init
helm install --name web ./web --namespace dev
helm upgrade web ./web
helm delete web --purge

# Helm 3
helm install web ./web --namespace dev --create-namespace
helm upgrade web ./web --namespace dev
helm uninstall web --namespace dev

# Helm 4  (same as Helm 3, plus the renamed flags)
helm install web ./web --namespace dev --create-namespace --rollback-on-failure --wait --timeout 5m
helm upgrade web ./web --namespace dev --rollback-on-failure
helm uninstall web --namespace dev
```

---

## 10. Migration Guides

### 10.1 Helm 2 to Helm 3 (legacy)

```text
 Helm 2 releases (ConfigMaps in kube-system, managed by Tiller)
        |
        |  (the 2to3 plugin did this, but it is unsupported now)
        v
 Helm 3 releases (Secrets in each release namespace)
        |
        v
 Remove Tiller and old Helm 2 data
```

Safe manual approach for what is left:

1. Back up: `helm get all <release>` and `kubectl get <resources> -o yaml`.
2. Convert charts: `apiVersion: v1` to `v2`, move `requirements.yaml` into `Chart.yaml`.
3. Test the converted chart with Helm 3 in a throw-away namespace: `helm install --dry-run --debug`.
4. Adopt or recreate the release with Helm 3, then uninstall Tiller.

### 10.2 Helm 3 to Helm 4 (the one you need now)

```text
 +----------------+   +-------------------+   +-----------------+   +-------------+
 | 1. Install     |-->| 2. Test charts    |-->| 3. Fix CI/CD    |-->| 4. Switch   |
 | Helm 4 side by |   | and releases in   |   | scripts, flags, |   | production  |
 | side as helm4  |   | a non-prod        |   | post-renderers, |   | binary and  |
 |                |   | cluster           |   | registry login  |   | monitor     |
 +----------------+   +-------------------+   +-----------------+   +-------------+
        no release migration step is needed: Helm 4 reads Helm 3's release Secrets
```

**Step 1: install both binaries side by side**

```bash
# rename so both can coexist
mv /usr/local/bin/helm /usr/local/bin/helm3
# install Helm 4 from the official releases, then:
mv /usr/local/bin/helm /usr/local/bin/helm4

helm3 version
helm4 version
```

**Step 2: test your existing charts**

```bash
helm4 lint ./mychart
helm4 template web ./mychart -f values-prod.yaml > /tmp/helm4.yaml
helm3 template web ./mychart -f values-prod.yaml > /tmp/helm3.yaml
diff /tmp/helm3.yaml /tmp/helm4.yaml            # rendered output should match
```

**Step 3: read an existing release with Helm 4 (non-prod first)**

```bash
helm4 list -A
helm4 status web -n dev
helm4 get values web -n dev
helm4 upgrade web ./mychart -n dev --dry-run
```

**Step 4: fix your scripts**

```bash
# find old flags in your repositories
grep -rn -- "--atomic\|--force\b\|--post-renderer\|registry login" .

# examples of the fixes
sed -i 's/--atomic/--rollback-on-failure/g' deploy.sh
sed -i 's/--force\b/--force-replace/g' deploy.sh
```

Review each match by hand. A blind `sed` can hit unrelated text.

**Step 5: server-side apply check**

```bash
# a release Helm 3 created keeps client-side apply after upgrading with Helm 4.
# to opt in explicitly for one upgrade:
helm4 upgrade web ./mychart -n dev --server-side

# see which managers own fields (look for the Helm entries)
kubectl get deploy web -n dev -o yaml --show-managed-fields | less
```

If another tool (Argo CD, an HPA, an operator) also edits the same object, test that combination before turning SSA on for existing releases.

**Step 6: roll out**

1. Update CI images and developer machines to Helm 4.
2. Keep Helm 3 available as a fallback during the first weeks.
3. Move all pipelines before **10 Feb 2027**, when Helm 3 stops receiving security patches.

### 10.3 Pre-flight checklist

- [ ] All charts pass `helm lint` and `helm template` with Helm 4 and match Helm 3 output
- [ ] Renamed flags updated in every script and pipeline
- [ ] Post-renderers converted to plugins
- [ ] `helm registry login` uses domain names only
- [ ] Plugins tested (CLI, getter and post-renderer types)
- [ ] `--wait` timeouts reviewed (kstatus can be stricter)
- [ ] Argo CD, operators and HPAs tested with server-side apply
- [ ] Go tooling using the Helm SDK moved to `helm.sh/helm/v4`
- [ ] CRD upgrades handled outside Helm
- [ ] Rollback plan: keep the `helm3` binary available

---

## 11. Which Version Should You Use?

```text
                       Starting a new project or pipeline?
                                     |
                      +--------------+---------------+
                     yes                             no
                      |                               |
                      v                               v
                 Use HELM 4              Do you have releases managed by Helm 2?
                                                      |
                                      +---------------+---------------+
                                     yes                              no
                                      |                                |
                                      v                                v
                          Migrate to Helm 3 first,           Running Helm 3 today?
                          then to Helm 4                               |
                                                    +------------------+-----------------+
                                                   yes                                    no
                                                    |                                      |
                                      Plan the move to Helm 4                      Install Helm 4
                                      before 10 Feb 2027
                                      (test in non-prod first)
```

| Situation | Recommendation |
|---|---|
| Learning Helm | Start with **Helm 4**. The templates and concepts are the same as Helm 3 |
| New cluster or pipeline | **Helm 4** |
| Existing Helm 3 pipelines | Test and move to Helm 4 before the 10 Feb 2027 Helm 3 security cut-off |
| Helm 2 anywhere | Stop using it. Unsupported since 2020 |
| Using Helm from Go code | Plan a code change to `helm.sh/helm/v4` |
| Using Argo CD, Flux or operators on the same objects | Test server-side apply carefully before enabling it on existing releases |
| Managed platform (for example an internal platform or CI image) | Check which Helm version it bundles and its own support dates |

---

## 12. Common Questions

**Do I have to rewrite my charts for Helm 4?**
No. `apiVersion: v2` charts work unchanged. Only scripts using renamed flags, post-renderers and registry logins need changes.

**Can Helm 4 manage releases created by Helm 3?**
Yes, with no migration step. The release Secrets use the same format.

**Can I use Helm 3 and Helm 4 on the same release?**
It is possible while you transition, but pick one binary per pipeline. Mixing apply methods can confuse who owns which fields.

**Is server-side apply forced on my existing releases?**
No. Helm 4 follows the apply method the release used before (latching). Only new releases default to server-side apply.

**What is the main reason a pipeline breaks after the upgrade?**
Most often `--wait` behaves more strictly (kstatus), or scripts use `--atomic`, `--force`, `--post-renderer ./script` or a full URL in `helm registry login`.

**Is Helm 4 only for large teams?**
No. Everyday commands are unchanged, and the new features (digest installs, better status, server-side apply) help small teams too.

**What happened to Tiller?**
It was removed in Helm 3 and has never returned.

**Where do class notes fit?**
Notes that say "Helm 2 has Tiller, Helm 3 does not" describe the first transition. Helm 4 keeps the Helm 3 architecture and changes the internals, flags, plugins and apply method.

---

## 13. Quiz

1. What was Tiller and why was it removed in Helm 3?
2. Where does Helm 3 store release information, and what is a typical Secret name?
3. In what way does Helm 3's three-way merge improve on Helm 2's upgrade?
4. Name three headline features of Helm 4.
5. Why does Helm 4 not change apply method for existing Helm 3 releases?
6. Rewrite for Helm 4: `helm upgrade -i web ./web --atomic --force`.
7. What must you change when a script passes `--post-renderer ./patch.sh`?
8. What is wrong with `helm registry login registry.example.com/charts` in Helm 4?
9. Which Helm versions are supported on 15 Nov 2026, and until when?
10. What does a digest-based install protect against?

<details>
<summary>Answers</summary>

1. Tiller was Helm 2's server component inside the cluster, running with broad permissions. Helm 3 removed it so Helm uses the caller's own Kubernetes RBAC.
2. In Secrets in the release's namespace, named like `sh.helm.release.v1.<release>.v<revision>`.
3. It compares the old chart, the live cluster state and the new chart, so manual changes and drift are taken into account.
4. Any of: server-side apply, kstatus-based `--wait`, the plugin overhaul with optional Wasm, post-renderers as plugins, OCI digest installs, multi-document values, a stable Go SDK.
5. It "latches" to the previous apply method so existing releases keep behaving the same until you opt in.
6. `helm upgrade -i web ./web --rollback-on-failure --force-replace`.
7. Convert the script into a post-renderer plugin and pass the plugin's name.
8. Helm 4 accepts only a domain name, so use `helm registry login registry.example.com`.
9. Helm 4 is current and supported. Helm 3 gets security fixes only until 10 Feb 2027, after its final limited feature release on 9 Sep 2026. Helm 2 is unsupported.
10. A tag being re-pushed with different content. The digest is the content hash, and Helm refuses a chart that does not match it.
</details>

---

## 14. Cheat Sheet

```text
HELM 2   client + Tiller | cluster-wide names | ConfigMaps | two-way merge | v1 charts
HELM 3   client only     | per-namespace names| Secrets    | three-way merge | v2 charts | OCI
HELM 4   client only     | Helm 3 compatible  | Secrets    | server-side apply (new releases)
         kstatus --wait | Wasm plugins | digest installs | --rollback-on-failure | --force-replace
```

```bash
# Helm 4 everyday
helm install web ./web -n dev --create-namespace --rollback-on-failure --wait --timeout 5m
helm upgrade -i web ./web -n dev -f values-prod.yaml --rollback-on-failure
helm list -A
helm history web -n dev
helm rollback web 1 -n dev
helm uninstall web -n dev
helm install app oci://registry.example.com/charts/app@sha256:<digest>
helm registry login registry.example.com
```

---

## 15. References

- Helm 4 Overview: https://helm.sh/docs/overview
- Helm 4 full changelog: https://helm.sh/docs/changelog
- Helm 4 Released (blog): https://helm.sh/blog/helm-4-released
- Helm 3 End of Life (blog): https://helm.sh/blog/helm-v3-end-of-life
- Path to Helm v4: https://helm.sh/blog/path-to-helm-v4
- Helm 3 documentation: https://helm.sh/docs/v3/
- Helm 2 documentation (archived): https://helm.sh/docs/v2/
- HIP-0012 Helm 4 development process: https://helm.sh/community/hips/hip-0012
- HIP-0022 kstatus: https://helm.sh/community/hips/hip-0022/
- HIP-0026 plugin system: https://helm.sh/community/hips/hip-0026
- Helm 4 example plugins: https://github.com/scottrigby/h4-example-plugins
- Migrate v3 plugins to Helm 4: https://helm.sh/docs/plugins/migrate
- Helm 2 to Helm 3 migration (historic): https://helm.sh/blog/migrate-from-helm-v2-to-helm-v3
