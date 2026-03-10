#!/usr/bin/env bash
# install hadolint, yq, task, k9s, stern, helmfile, helm-diff
# run as root

set -euo pipefail

echo "[05-tools] Installing shellcheck..."
apt-get install -y -qq shellcheck

echo "[05-tools] Installing hadolint..."
HADOLINT_VERSION="v2.12.0"
HADOLINT_BIN="/usr/local/bin/hadolint"
curl -fsSL "https://github.com/hadolint/hadolint/releases/download/${HADOLINT_VERSION}/hadolint-Linux-x86_64" -o "${HADOLINT_BIN}"
chmod +x "${HADOLINT_BIN}"
hadolint --version

echo "[05-tools] Installing yq..."
YQ_VERSION="v4.40.5"
curl -fsSL "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_amd64" -o /usr/local/bin/yq
chmod +x /usr/local/bin/yq
yq --version

echo "[05-tools] Installing Task (go-task)..."
sh -c "$(curl --location https://taskfile.dev/install.sh)" -- -d -b /usr/local/bin
task --version

echo "[05-tools] Installing k9s..."
K9S_VERSION="v0.32.4"
curl -fsSL "https://github.com/derailed/k9s/releases/download/${K9S_VERSION}/k9s_Linux_amd64.tar.gz" -o /tmp/k9s.tar.gz
tar -xzf /tmp/k9s.tar.gz -C /usr/local/bin k9s
rm /tmp/k9s.tar.gz
k9s version 2>/dev/null || true

echo "[05-tools] Installing stern (usefull for log tailing)..."
STERN_VERSION="1.28.0"
curl -fsSL "https://github.com/stern/stern/releases/download/v${STERN_VERSION}/stern_${STERN_VERSION}_linux_amd64.tar.gz" -o /tmp/stern.tar.gz
tar -xzf /tmp/stern.tar.gz -C /usr/local/bin stern
rm /tmp/stern.tar.gz
stern --version 2>/dev/null || true

echo "[05-tools] Installing helmfile..."
HELMFILE_VERSION="0.167.1"
curl -fsSL "https://github.com/helmfile/helmfile/releases/download/v${HELMFILE_VERSION}/helmfile_${HELMFILE_VERSION}_linux_amd64.tar.gz" -o /tmp/helmfile.tar.gz
tar -xzf /tmp/helmfile.tar.gz -C /usr/local/bin helmfile
rm /tmp/helmfile.tar.gz
helmfile --version

echo "[05-tools] Installing helm-diff plugin..."
helm plugin list 2>/dev/null | grep -q '^diff' || helm plugin install https://github.com/databus23/helm-diff

if id -u vagrant >/dev/null 2>&1; then
  runuser -u vagrant -- bash -c 'helm plugin list 2>/dev/null | grep -q "^diff" || helm plugin install https://github.com/databus23/helm-diff' || echo "[05-tools] WARN: helm-diff install for vagrant failed; continuing."
fi

echo "[05-tools] Root helm plugins:"
helm plugin list || true

mkdir -p /etc/observability-lab
touch /etc/observability-lab/.tools-done

echo "[05-tools] Done."
