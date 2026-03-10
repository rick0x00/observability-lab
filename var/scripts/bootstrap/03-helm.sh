#!/usr/bin/env bash
# install Helm 3 using the official install script
# run as root

set -euo pipefail

echo "[03-helm] Installing Helm 3..."

curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | HELM_INSTALL_DIR=/usr/local/bin bash

echo "[03-helm] Verifying Helm..."
helm version

echo "[03-helm] Adding common Helm repos..."
# kube-prometheus-stack
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
# Elastic stack
helm repo add elastic https://helm.elastic.co

helm repo update

echo "[03-helm] Done."
