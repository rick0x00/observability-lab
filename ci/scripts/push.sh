#!/usr/bin/env bash
# login to dockerhub and push, optionaly push to ghcr too
set -euo pipefail

IMAGE_TAG="${IMAGE_TAG:-local}"
DOCKERHUB_USER="${DOCKERHUB_USER:-rick0x00}"
IMAGE_REF="${IMAGE_REF:-docker.io/${DOCKERHUB_USER}/observability-lab:${IMAGE_TAG}}"
CACHE_REF="${CACHE_REF:-docker.io/${DOCKERHUB_USER}/observability-lab:buildcache}"
ENABLE_GHCR_PUSH="${ENABLE_GHCR_PUSH:-0}"
GHCR_USER="${GHCR_USER:-${DOCKERHUB_USER}}"
GHCR_IMAGE_REF_INPUT="${GHCR_IMAGE_REF:-}"
GHCR_IMAGE_REF="${GHCR_IMAGE_REF_INPUT:-ghcr.io/${GHCR_USER}/observability-lab:${IMAGE_TAG}}"
REGISTRY_SOPS_FILE="${REGISTRY_SOPS_FILE:-${DOCKERHUB_SOPS_FILE:-ci/secrets/dockerhub.enc.sops.yaml}}"

read_sops_value() {
  local key="$1"
  if [[ ! -f "${REGISTRY_SOPS_FILE}" ]]; then
    return 0
  fi
  if [[ ! -f "var/scripts/with-sops-gcp.sh" ]]; then
    sops --decrypt --extract "[\"${key}\"]" "${REGISTRY_SOPS_FILE}" 2>/dev/null || true
    return 0
  fi
  bash var/scripts/with-sops-gcp.sh sops --decrypt --extract "[\"${key}\"]" "${REGISTRY_SOPS_FILE}" 2>/dev/null || true
}

if [[ -z "${DOCKERHUB_TOKEN:-}" ]]; then
  echo "DOCKERHUB_TOKEN not set, trying SOPS file..."
fi

bash ci/scripts/dockerhub-login.sh "${DOCKERHUB_USER}"

EXTRA_TAGS=""
if [[ "${ENABLE_GHCR_PUSH}" == "1" ]]; then
  if [[ -z "${GHCR_USER:-}" ]]; then
    GHCR_USER="$(read_sops_value GHCR_USER)"
  fi
  if [[ -n "${GHCR_USER:-}" && -z "${GHCR_IMAGE_REF_INPUT}" ]]; then
    GHCR_IMAGE_REF="ghcr.io/${GHCR_USER}/observability-lab:${IMAGE_TAG}"
  fi
  if [[ -z "${GHCR_TOKEN:-}" ]]; then
    GHCR_TOKEN="$(read_sops_value GHCR_TOKEN)"
  fi
  if [[ -z "${GHCR_TOKEN:-}" ]]; then
    echo "GHCR_TOKEN is required when ENABLE_GHCR_PUSH=1 (env or ${REGISTRY_SOPS_FILE})" >&2
    exit 1
  fi
  if [[ -z "${GHCR_USER:-}" ]]; then
    echo "GHCR_USER is required when ENABLE_GHCR_PUSH=1" >&2
    exit 1
  fi
  echo "${GHCR_TOKEN}" | docker login ghcr.io -u "${GHCR_USER}" --password-stdin
  EXTRA_TAGS="${GHCR_IMAGE_REF}"
fi

BUILD_PUSH=1 IMAGE_REF="${IMAGE_REF}" CACHE_REF="${CACHE_REF}" EXTRA_TAGS="${EXTRA_TAGS}" bash ci/scripts/build.sh
