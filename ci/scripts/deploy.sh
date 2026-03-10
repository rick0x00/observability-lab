#!/usr/bin/env bash
# decode kubeconfig if provided and run k8s:apply
set -euo pipefail

ENVIRONMENT="${ENV:-dev}"
KUBE_CONTEXT="${KUBE_CONTEXT:-default}"
IMAGE_TAG="${IMAGE_TAG:-${GITHUB_SHA:-${CI_COMMIT_SHA:-latest}}}"
DOCKERHUB_USER="${DOCKERHUB_USER:-rick0x00}"
TEMP_FILES=()

cleanup() {
  for f in "${TEMP_FILES[@]:-}"; do
    [[ -n "${f}" && -f "${f}" ]] && rm -f "${f}"
  done
}
trap cleanup EXIT

# KUBECONFIG_B64 is from CI secrets, its a base64 kubeconfig
if [[ -n "${KUBECONFIG_B64:-}" ]]; then
  mkdir -p "${HOME}/.kube"
  echo "${KUBECONFIG_B64}" | base64 --decode > "${HOME}/.kube/config"
  chmod 600 "${HOME}/.kube/config"
fi

# Optional: service account key for SOPS + GCP KMS in CI
if [[ -n "${GCP_SA_KEY_B64:-}" ]]; then
  sa_tmp="$(mktemp /tmp/gcp-sa.XXXXXX.json)"
  TEMP_FILES+=("${sa_tmp}")
  echo "${GCP_SA_KEY_B64}" | base64 --decode > "${sa_tmp}"
  chmod 600 "${sa_tmp}"
  export GOOGLE_APPLICATION_CREDENTIALS="${sa_tmp}"
fi

task k8s:apply ENV="${ENVIRONMENT}" KUBE_CONTEXT="${KUBE_CONTEXT}" DOCKERHUB_USER="${DOCKERHUB_USER}" IMAGE_TAG="${IMAGE_TAG}"
