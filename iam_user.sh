#!/usr/bin/env bash
# Create a Kubernetes user (client certificate) + group and grant
# get/list (read-only) access to ONE namespace, then validate.
#
# Usage:
#   ./k8s-readonly-user.sh [USER] [GROUP] [NAMESPACE] [CERT_DAYS]
# Example:
#   ./k8s-readonly-user.sh ram dev-team dev 30
#
# Requires: kubectl (cluster-admin), openssl, base64

set -euo pipefail

USER_NAME="${1:-ram}"
GROUP_NAME="${2:-dev-team}"
NAMESPACE="${3:-dev}"
CERT_DAYS="${4:-30}"

ROLE_NAME="${NAMESPACE}-readonly"
BINDING_NAME="${GROUP_NAME}-${NAMESPACE}-readonly"
WORKDIR="${HOME}/k8s-users/${USER_NAME}"
KUBECONFIG_OUT="${WORKDIR}/${USER_NAME}.kubeconfig"
EXPIRY_SECONDS=$((CERT_DAYS * 86400))

log() { printf '\n==> %s\n' "$*"; }

# ---------- 0. Pre-checks ----------
for bin in kubectl openssl base64; do
  command -v "$bin" >/dev/null || { echo "ERROR: $bin not found"; exit 1; }
done
kubectl cluster-info >/dev/null || { echo "ERROR: cannot reach cluster"; exit 1; }

mkdir -p "$WORKDIR"
cd "$WORKDIR"

# ---------- 1. Namespace ----------
log "Creating namespace: ${NAMESPACE}"
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# ---------- 2. Key + CSR (CN = user, O = group) ----------
log "Generating private key and CSR for ${USER_NAME} (group: ${GROUP_NAME})"
[ -f "${USER_NAME}.key" ] || openssl genrsa -out "${USER_NAME}.key" 2048
openssl req -new -key "${USER_NAME}.key" -out "${USER_NAME}.csr" \
  -subj "/CN=${USER_NAME}/O=${GROUP_NAME}"

# ---------- 3. Submit CertificateSigningRequest ----------
log "Submitting CertificateSigningRequest"
kubectl delete csr "$USER_NAME" --ignore-not-found >/dev/null
CSR_B64=$(base64 < "${USER_NAME}.csr" | tr -d '\n')

cat <<EOF | kubectl apply -f -
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: ${USER_NAME}
spec:
  request: ${CSR_B64}
  signerName: kubernetes.io/kube-apiserver-client
  expirationSeconds: ${EXPIRY_SECONDS}
  usages:
  - client auth
EOF

# ---------- 4. Approve + fetch signed certificate ----------
log "Approving CSR"
kubectl certificate approve "$USER_NAME"

log "Waiting for certificate to be issued"
for _ in $(seq 1 15); do
  CERT=$(kubectl get csr "$USER_NAME" -o jsonpath='{.status.certificate}')
  [ -n "$CERT" ] && break
  sleep 1
done
[ -n "${CERT:-}" ] || { echo "ERROR: certificate was not issued"; exit 1; }
echo "$CERT" | base64 -d > "${USER_NAME}.crt"
openssl x509 -in "${USER_NAME}.crt" -noout -subject -dates

# ---------- 5. Build kubeconfig ----------
log "Building kubeconfig: ${KUBECONFIG_OUT}"
SERVER=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
CLUSTER=$(kubectl config view --minify -o jsonpath='{.clusters[0].name}')
kubectl config view --raw --minify \
  -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' | base64 -d > ca.crt

rm -f "$KUBECONFIG_OUT"
kubectl config set-cluster "$CLUSTER" \
  --server="$SERVER" --certificate-authority=ca.crt --embed-certs=true \
  --kubeconfig="$KUBECONFIG_OUT" >/dev/null
kubectl config set-credentials "$USER_NAME" \
  --client-certificate="${USER_NAME}.crt" --client-key="${USER_NAME}.key" --embed-certs=true \
  --kubeconfig="$KUBECONFIG_OUT" >/dev/null
kubectl config set-context "${USER_NAME}-ctx" \
  --cluster="$CLUSTER" --user="$USER_NAME" --namespace="$NAMESPACE" \
  --kubeconfig="$KUBECONFIG_OUT" >/dev/null
kubectl config use-context "${USER_NAME}-ctx" --kubeconfig="$KUBECONFIG_OUT" >/dev/null
chmod 600 "$KUBECONFIG_OUT" "${USER_NAME}.key"

# ---------- 6. Role (get, list only) ----------
log "Creating Role ${ROLE_NAME} in namespace ${NAMESPACE}"
cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: ${ROLE_NAME}
  namespace: ${NAMESPACE}
rules:
- apiGroups: [""]
  resources: ["pods", "pods/log", "services", "endpoints", "configmaps", "persistentvolumeclaims", "events"]
  verbs: ["get", "list"]
- apiGroups: ["apps"]
  resources: ["deployments", "replicasets", "statefulsets", "daemonsets"]
  verbs: ["get", "list"]
- apiGroups: ["batch"]
  resources: ["jobs", "cronjobs"]
  verbs: ["get", "list"]
- apiGroups: ["networking.k8s.io"]
  resources: ["ingresses"]
  verbs: ["get", "list"]
EOF

# ---------- 7. RoleBinding to the GROUP ----------
log "Creating RoleBinding ${BINDING_NAME}"
cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: ${BINDING_NAME}
  namespace: ${NAMESPACE}
subjects:
- kind: Group
  name: ${GROUP_NAME}
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: ${ROLE_NAME}
  apiGroup: rbac.authorization.k8s.io
EOF

# ---------- 8. Validate ----------
PASS=0; FAIL=0
check() {  # check <expected yes|no> <description> <kubectl auth can-i args...>
  local expected="$1" desc="$2"; shift 2
  local got
  got=$(kubectl auth can-i "$@" --as="$USER_NAME" --as-group="$GROUP_NAME" 2>/dev/null || true)
  if [ "$got" = "$expected" ]; then
    printf '  PASS  %-45s (%s)\n' "$desc" "$got"; PASS=$((PASS+1))
  else
    printf '  FAIL  %-45s (expected %s, got %s)\n' "$desc" "$expected" "$got"; FAIL=$((FAIL+1))
  fi
}

log "Validating with impersonation"
check yes "get pods in ${NAMESPACE}"           get pods -n "$NAMESPACE"
check yes "list pods in ${NAMESPACE}"          list pods -n "$NAMESPACE"
check yes "list deployments in ${NAMESPACE}"   list deployments.apps -n "$NAMESPACE"
check no  "create pods in ${NAMESPACE}"        create pods -n "$NAMESPACE"
check no  "delete pods in ${NAMESPACE}"        delete pods -n "$NAMESPACE"
check no  "update deployments in ${NAMESPACE}" update deployments.apps -n "$NAMESPACE"
check no  "get secrets in ${NAMESPACE}"        get secrets -n "$NAMESPACE"
check no  "list pods in default"               list pods -n default
check no  "list pods in kube-system"           list pods -n kube-system
check no  "list nodes (cluster-wide)"          list nodes
check no  "list namespaces (cluster-wide)"     list namespaces

log "Validating with the real user kubeconfig"
echo "  whoami:"
kubectl --kubeconfig="$KUBECONFIG_OUT" auth whoami 2>/dev/null | sed 's/^/    /' || echo "    (kubectl auth whoami needs K8s 1.28+)"
echo "  get pods -n ${NAMESPACE}:"
kubectl --kubeconfig="$KUBECONFIG_OUT" get pods -n "$NAMESPACE" 2>&1 | sed 's/^/    /'
echo "  get pods -n default (should be Forbidden):"
kubectl --kubeconfig="$KUBECONFIG_OUT" get pods -n default 2>&1 | sed 's/^/    /' || true

log "Result: ${PASS} passed, ${FAIL} failed"
cat <<EOF

Done.
  User       : ${USER_NAME}
  Group      : ${GROUP_NAME}
  Namespace  : ${NAMESPACE}
  Kubeconfig : ${KUBECONFIG_OUT}
  Valid for  : ${CERT_DAYS} days

Use it:
  export KUBECONFIG=${KUBECONFIG_OUT}
  kubectl get pods

Remove access:
  kubectl delete rolebinding ${BINDING_NAME} -n ${NAMESPACE}
  kubectl delete role ${ROLE_NAME} -n ${NAMESPACE}
  kubectl delete csr ${USER_NAME}
EOF

[ "$FAIL" -eq 0 ]
