#!/usr/bin/env bash
# install kubectl from the kubernetes apt repo
# run as root

set -euo pipefail

echo "[02-kubectl] Installing kubectl..."

# kubernetes stable repo
KUBE_VERSION="v1.29"

install -m 0755 -d /etc/apt/keyrings
curl -fsSL "https://pkgs.k8s.io/core:/stable:/${KUBE_VERSION}/deb/Release.key" | gpg --batch --yes --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
chmod 644 /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${KUBE_VERSION}/deb/ /" > /etc/apt/sources.list.d/kubernetes.list

apt-get update -qq
apt-get install -y -qq kubectl

echo "[02-kubectl] Verifying kubectl client..."
kubectl version --client

echo "[02-kubectl] Adding bash completion..."
kubectl completion bash > /etc/bash_completion.d/kubectl

echo "[02-kubectl] Done."
