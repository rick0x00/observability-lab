#!/usr/bin/env bash
# find kubeconfig: try KUBECONFIG env, then k3s path, then ~/.kube/config

set -euo pipefail

if [[ -n "${KUBECONFIG:-}" ]]; then
  echo "${KUBECONFIG}"
  exit 0
fi

for candidate in "/etc/rancher/k3s/k3s.yaml" "${HOME}/.kube/config"; do
  if [[ -f "${candidate}" ]]; then
    echo "${candidate}"
    exit 0
  fi
done

# nothing found, kubectl will use its own defaults
echo ""
