#!/usr/bin/env bash
# docker hub login with env token or sops encrypted token

set -euo pipefail

requested_user="${1:-${DOCKERHUB_USER:-rick0x00}}"
DOCKERHUB_USER="${DOCKERHUB_USER:-${requested_user}}"
DOCKERHUB_SOPS_FILE="${DOCKERHUB_SOPS_FILE:-ci/secrets/dockerhub.enc.sops.yaml}"

if [[ -z "${DOCKERHUB_TOKEN:-}" && -f "${DOCKERHUB_SOPS_FILE}" ]]; then
  if ! command -v sops >/dev/null 2>&1; then
    echo "sops not found and DOCKERHUB_TOKEN is empty" >&2
    exit 1
  fi
  if [[ -f "var/scripts/with-sops-gcp.sh" ]]; then
    DOCKERHUB_TOKEN="$(bash var/scripts/with-sops-gcp.sh sops --decrypt --extract '["DOCKERHUB_TOKEN"]' "${DOCKERHUB_SOPS_FILE}" 2>/dev/null || true)"
    user_from_sops="$(bash var/scripts/with-sops-gcp.sh sops --decrypt --extract '["DOCKERHUB_USER"]' "${DOCKERHUB_SOPS_FILE}" 2>/dev/null || true)"
  else
    DOCKERHUB_TOKEN="$(sops --decrypt --extract '["DOCKERHUB_TOKEN"]' "${DOCKERHUB_SOPS_FILE}" 2>/dev/null || true)"
    user_from_sops="$(sops --decrypt --extract '["DOCKERHUB_USER"]' "${DOCKERHUB_SOPS_FILE}" 2>/dev/null || true)"
  fi
  if [[ -n "${user_from_sops}" ]]; then
    DOCKERHUB_USER="${user_from_sops}"
  fi
fi

if [[ -z "${DOCKERHUB_TOKEN:-}" ]]; then
  echo "DOCKERHUB_TOKEN is required (env or ${DOCKERHUB_SOPS_FILE})" >&2
  exit 1
fi

if [[ "${DOCKERHUB_LOGIN_DRY_RUN:-0}" == "1" ]]; then
  echo "dockerhub credentials resolved for user ${DOCKERHUB_USER}"
  exit 0
fi

echo "${DOCKERHUB_TOKEN}" | docker login -u "${DOCKERHUB_USER}" --password-stdin
