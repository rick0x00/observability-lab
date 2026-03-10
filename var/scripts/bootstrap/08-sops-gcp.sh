#!/usr/bin/env bash
# install sops and gcloud sdk
# run as root

set -euo pipefail

echo "[08-sops-gcp] Installing deps..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq ca-certificates curl gnupg apt-transport-https

echo "[08-sops-gcp] Installing sops..."
SOPS_VERSION="v3.9.4"
curl -fsSL "https://github.com/getsops/sops/releases/download/${SOPS_VERSION}/sops-${SOPS_VERSION}.linux.amd64" -o /usr/local/bin/sops
chmod +x /usr/local/bin/sops
sops --version

echo "[08-sops-gcp] Installing gcloud sdk..."
install -m 0755 -d /etc/apt/keyrings
if [ ! -f /etc/apt/keyrings/cloud.google.gpg ]; then
  curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | gpg --dearmor -o /etc/apt/keyrings/cloud.google.gpg
fi

echo "deb [signed-by=/etc/apt/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" >/etc/apt/sources.list.d/google-cloud-sdk.list

apt-get update -qq
apt-get install -y -qq google-cloud-cli google-cloud-cli-gke-gcloud-auth-plugin

gcloud --version | head -n 1

mkdir -p /etc/observability-lab
touch /etc/observability-lab/.sops-gcp-done

echo "[08-sops-gcp] Done."
