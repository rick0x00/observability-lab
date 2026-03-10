#!/usr/bin/env bash
# install kind (kubernetes-in-docker)
# needs write acces to /usr/local/bin

set -euo pipefail

echo "[06-kind] Installing kind..."

KIND_VERSION="v0.23.0"
KIND_BIN="/usr/local/bin/kind"

curl -fsSL "https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-linux-amd64" -o "${KIND_BIN}"
chmod +x "${KIND_BIN}"

kind --version

echo "[06-kind] Done."
