#!/usr/bin/env bash
# helmfile operation for ingress controller
# detects k3s builtin traefik and skip if its already there
# usage: ingress-op.sh <env> <controller> <kube_context_override> <sync|diff|destroy>

set -euo pipefail

SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"

env_name="$1"
controller="$2"
kube_context_override="$3"
helmfile_cmd="$4"

kubeconfig="$(bash "${SCRIPTS_DIR}/resolve-kubeconfig.sh")"
if [ -n "${kubeconfig}" ]; then export KUBECONFIG="${kubeconfig}"; fi
kube_context="$(bash "${SCRIPTS_DIR}/resolve-kube-context.sh" "${env_name}" "${kube_context_override}")"

if [ "${controller}" != "nginx" ] && [ "${controller}" != "traefik" ]; then
  echo "invalid CONTROLLER='${controller}'. use nginx or traefik." >&2
  exit 1
fi

echo "env:          ${env_name}"
echo "kube_context: ${kube_context}"
echo "controller:   ${controller}"

if [ "${controller}" = "traefik" ]; then
  existing_ns="$(kubectl --context "${kube_context}" get ingressclass traefik -o jsonpath='{.metadata.annotations.meta\.helm\.sh/release-namespace}' 2>/dev/null || true)"
  if [ "${existing_ns}" = "kube-system" ]; then
    echo "detected k3s built-in traefik (kube-system), skipping helmfile ${helmfile_cmd}."
    exit 0
  fi
fi

helmfile -f var/ingress/helmfile.yaml.gotmpl -e "${env_name}" --state-values-set kubeContext="${kube_context}" --state-values-set controller="${controller}" "${helmfile_cmd}"
