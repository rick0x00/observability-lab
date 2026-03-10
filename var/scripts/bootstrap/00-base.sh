#!/usr/bin/env bash
# base packages, timezone, PATH setup for vagrant user
# run as root (ansible become: true)

set -euo pipefail

echo "[00-base] Updating apt cache and upgrading packages..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get upgrade -y -qq

echo "[00-base] Installing base packages..."
base_packages=(
  curl
  wget
  git
  vim
  nano
  jq
  ca-certificates
  gnupg
  lsb-release
  unzip
  tar
  make
  bash-completion
  htop
  tree
  dnsutils
  net-tools
  iproute2
  apt-transport-https
  software-properties-common
  gettext-base
  python3
  python3-pip
)
apt-get install -y -qq "${base_packages[@]}"

echo "[00-base] Configuring timezone to UTC..."
timedatectl set-timezone UTC 2>/dev/null || true

echo "[00-base] Setting up ~/.local/bin for vagrant user..."
VAGRANT_HOME="/home/vagrant"
mkdir -p "${VAGRANT_HOME}/.local/bin"
chown vagrant:vagrant "${VAGRANT_HOME}/.local/bin"

# add local bin to PATH if not there yet
BASHRC="${VAGRANT_HOME}/.bashrc"
if ! grep -q '\.local/bin' "${BASHRC}" 2>/dev/null; then
  echo 'export PATH="$HOME/.local/bin:$PATH"' >> "${BASHRC}"
fi

# kubectl aliases and bash completion
if ! grep -q 'alias k=' "${BASHRC}" 2>/dev/null; then
  cat >> "${BASHRC}" <<'EOF'

# lab aliases
alias k='kubectl'
alias kgp='kubectl get pods'
alias kga='kubectl get pods -A'
alias kgn='kubectl get nodes'
alias kgs='kubectl get svc'
alias ll='ls -lah'
EOF
fi

echo "[00-base] Creating state marker so ansible skip this next time..."
mkdir -p /etc/observability-lab
touch /etc/observability-lab/.base-done

echo "[00-base] Done."
