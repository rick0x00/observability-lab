#!/usr/bin/env bash
# map ENV to kube context, KUBE_CONTEXT overides if set
# usage: resolve-kube-context.sh <env> [kube_context_override]

set -euo pipefail

env_name="${1:-${ENV:-}}"
override="${2:-${KUBE_CONTEXT:-}}"

if [[ -n "${override}" ]]; then
  echo "${override}"
  exit 0
fi

case "${env_name}" in
  dev)  echo "default" ;;
  stag) echo "k3s-stag" ;;
  prod) echo "k8s-prod" ;;
  *)
    echo "error: cannot resolve kube context for ENV='${env_name}'. set KUBE_CONTEXT explicitly." >&2
    exit 1
    ;;
esac
