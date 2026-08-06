#!/usr/bin/env bash
#
# deploy-helm.sh
#
# Deploy or upgrade a Helm release with a given image and optional extra Helm args.
# The script decodes KUBE_CONFIG_DATA (base64) into a temporary kubeconfig if provided.
# It is idempotent and waits for the release to become ready.
#
# Usage:
#   ./ci-cd/scripts/deploy-helm.sh <release> <chart_path> <image> <namespace> [extra helm args...]
#
# Examples:
#   ./ci-cd/scripts/deploy-helm.sh frontend helm-charts/frontend registry.example.com/project/frontend:abc123 default
#   ./ci-cd/scripts/deploy-helm.sh backend helm-charts/backend registry.example.com/project/backend:abc123 default "--values helm-charts/backend/values-prod.yaml"
#
set -euo pipefail

RELEASE="${1:-}"
CHART_PATH="${2:-}"
IMAGE="${3:-}"
NAMESPACE="${4:-default}"
shift 4 || true

if [[ -z "${RELEASE}" || -z "${CHART_PATH}" || -z "${IMAGE}" ]]; then
  echo "Usage: $0 <release> <chart_path> <image> <namespace> [extra helm args...]"
  exit 2
fi

EXTRA_ARGS=("$@")
KUBECONFIG_FILE="${KUBECONFIG_FILE:-}"
TMP_KUBECONFIG=""
HELM_BIN="${HELM_BIN:-helm}"
TIMEOUT="${HELM_TIMEOUT:-10m}"
WAIT="${HELM_WAIT:-true}"

echo "Deploying Helm release"
echo "  Release: ${RELEASE}"
echo "  Chart: ${CHART_PATH}"
echo "  Image: ${IMAGE}"
echo "  Namespace: ${NAMESPACE}"
if [[ ${#EXTRA_ARGS[@]} -gt 0 ]]; then
  echo "  Extra Helm args: ${EXTRA_ARGS[*]}"
fi

# If KUBE_CONFIG_DATA is provided (base64 kubeconfig), write it to a temp file
if [[ -n "${KUBE_CONFIG_DATA:-}" ]]; then
  TMP_KUBECONFIG="$(mktemp -t kubeconfig.XXXXXX)"
  echo "Decoding KUBE_CONFIG_DATA into ${TMP_KUBECONFIG}"
  echo "${KUBE_CONFIG_DATA}" | base64 -d > "${TMP_KUBECONFIG}"
  chmod 600 "${TMP_KUBECONFIG}"
  export KUBECONFIG="${TMP_KUBECONFIG}"
elif [[ -n "${KUBECONFIG:-}" ]]; then
  echo "Using existing KUBECONFIG: ${KUBECONFIG}"
else
  echo "No KUBECONFIG or KUBE_CONFIG_DATA provided; assuming kubectl/helm are configured in environment."
fi

# Ensure helm exists
if ! command -v "${HELM_BIN}" >/dev/null 2>&1; then
  echo "Helm binary not found at ${HELM_BIN}. Install Helm 3 and re-run."
  exit 3
fi

# Parse image into repository and tag
IMAGE_REPO="${IMAGE%%:*}"
IMAGE_TAG="${IMAGE#*:}"
if [[ "${IMAGE_REPO}" == "${IMAGE_TAG}" ]]; then
  # No tag provided; default to 'latest'
  IMAGE_TAG="latest"
fi

# Build helm --set args for image
SET_ARGS=(--set "image.repository=${IMAGE_REPO}" --set "image.tag=${IMAGE_TAG}")

# Create namespace if not exists
if ! kubectl get namespace "${NAMESPACE}" >/dev/null 2>&1; then
  echo "Namespace ${NAMESPACE} does not exist; creating"
  kubectl create namespace "${NAMESPACE}" || true
fi

# Ensure helm repo update (safe no-op if chart path is local)
echo "Updating Helm repositories (if any)"
helm repo update >/dev/null 2>&1 || true

# Run helm upgrade --install
HELM_CMD=( "${HELM_BIN}" upgrade --install "${RELEASE}" "${CHART_PATH}" --namespace "${NAMESPACE}" --create-namespace "${SET_ARGS[@]}" --timeout "${TIMEOUT}" )

if [[ "${WAIT}" == "true" ]]; then
  HELM_CMD+=( --wait )
fi

# Append extra args if provided
if [[ ${#EXTRA_ARGS[@]} -gt 0 ]]; then
  HELM_CMD+=( "${EXTRA_ARGS[@]}" )
fi

echo "Running: ${HELM_CMD[*]}"
# Use eval to preserve quoted extra args
"${HELM_CMD[@]}"

# Post-deploy checks: wait for deployment(s) to be ready (if any)
echo "Post-deploy: checking deployments in namespace ${NAMESPACE} for release ${RELEASE}"
# Try to find deployments with label app.kubernetes.io/instance=${RELEASE}
DEPLOYMENTS=$(kubectl -n "${NAMESPACE}" get deployments -l "app.kubernetes.io/instance=${RELEASE}" -o jsonpath='{range .items[*]}{.metadata.name}{" "}{end}' || true)

if [[ -n "${DEPLOYMENTS}" ]]; then
  for d in ${DEPLOYMENTS}; do
    echo "Waiting for deployment/${d} to be available"
    kubectl -n "${NAMESPACE}" rollout status deployment/"${d}" --timeout="${TIMEOUT}" || {
      echo "Warning: deployment ${d} did not become ready within ${TIMEOUT}"
    }
  done
else
  echo "No deployments found for release ${RELEASE} (label app.kubernetes.io/instance=${RELEASE}). Skipping rollout checks."
fi

# Cleanup temp kubeconfig if created
if [[ -n "${TMP_KUBECONFIG}" && -f "${TMP_KUBECONFIG}" ]]; then
  rm -f "${TMP_KUBECONFIG}"
fi

echo "Helm deploy finished for ${RELEASE}"
exit 0
