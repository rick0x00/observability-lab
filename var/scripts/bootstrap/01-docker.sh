#!/usr/bin/env bash
# install Docker CE from official debian repo
# run as root

set -euo pipefail

echo "[01-docker] Installing Docker CE..."

# remove old packages that might conflict
for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do
  apt-get remove -y "$pkg" 2>/dev/null || true
done

# add docker gpg key
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

# add docker apt repo
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $(. /etc/os-release && echo "${VERSION_CODENAME}") stable" > /etc/apt/sources.list.d/docker.list

apt-get update -qq

docker_packages=(
  docker-ce
  docker-ce-cli
  containerd.io
  docker-buildx-plugin
  docker-compose-plugin
)
apt-get install -y -qq "${docker_packages[@]}"

echo "[01-docker] Enabling Docker service..."
systemctl enable docker
systemctl start docker

echo "[01-docker] Adding vagrant user to docker group..."
usermod -aG docker vagrant

echo "[01-docker] Verifying instalation..."
docker --version

echo "[01-docker] Done. vagrant user needs to log out and back in (or run newgrp docker)."
