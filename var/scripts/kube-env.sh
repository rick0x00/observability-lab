#!/usr/bin/env bash
# source this to get env_name and kube_context in the calling shell
# usage: . var/scripts/kube-env.sh <env> [kube_context_override]

env_name="${1:-}"
_cfg="$(bash var/scripts/resolve-kubeconfig.sh)"
if [ -n "${_cfg}" ]; then export KUBECONFIG="${_cfg}"; fi
kube_context="$(bash var/scripts/resolve-kube-context.sh "${env_name}" "${2:-}")"
echo "env:          ${env_name}"
echo "kube_context: ${kube_context}"
unset _cfg
