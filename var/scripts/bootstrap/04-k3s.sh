#!/usr/bin/env bash
# install k3s and setup kubeconfig for root and vagrant
# run as root

set -euo pipefail

echo "[04-k3s] Disabling AppArmor (required for local lab)..."
systemctl disable --now apparmor >/dev/null 2>&1 || true
if command -v aa-teardown >/dev/null 2>&1; then
  aa-teardown >/dev/null 2>&1 || true
fi

echo "[04-k3s] Installing k3s..."

# write-kubeconfig-mode=644 so vagrant user can read it
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--write-kubeconfig-mode=644" sh -

K3S_KUBECONFIG="/etc/rancher/k3s/k3s.yaml"
KUBECTL=(kubectl --kubeconfig "${K3S_KUBECONFIG}")

echo "[04-k3s] Waiting for k3s API and node readiness..."
node_ready="false"
for _ in $(seq 1 100); do
  if "${KUBECTL[@]}" get nodes 2>/dev/null | awk 'NR > 1 && / Ready / { found = 1 } END { exit(found ? 0 : 1) }'; then
    node_ready="true"
    break
  fi
  sleep 3
done

if [ "${node_ready}" != "true" ]; then
  echo "[04-k3s] ERROR: k3s node did not become Ready in time."
  systemctl --no-pager status k3s || true
  journalctl -u k3s --no-pager -n 120 || true
  exit 1
fi
echo "[04-k3s] Node is Ready."

setup_user_kubeconfig() {
  local user_name="$1"
  local user_home="$2"

  mkdir -p "${user_home}/.kube"
  ln -sfn "${K3S_KUBECONFIG}" "${user_home}/.kube/config"
  chmod 700 "${user_home}/.kube"
  chown "${user_name}:${user_name}" "${user_home}/.kube"
  chown -h "${user_name}:${user_name}" "${user_home}/.kube/config" 2>/dev/null || true
}

echo "[04-k3s] Setting up kubeconfig for root and vagrant users..."
setup_user_kubeconfig "root" "/root"

if id -u vagrant >/dev/null 2>&1; then
  setup_user_kubeconfig "vagrant" "/home/vagrant"
fi

cat > /etc/profile.d/observability-lab-kubeconfig.sh <<'EOF'
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
EOF
chmod 0644 /etc/profile.d/observability-lab-kubeconfig.sh

# add kubectl completion to vagrant .bashrc
VAGRANT_BASHRC="/home/vagrant/.bashrc"
if [ -f "${VAGRANT_BASHRC}" ] && ! grep -q 'kubectl completion' "${VAGRANT_BASHRC}" 2>/dev/null; then
  echo 'source <(kubectl completion bash)' >> "${VAGRANT_BASHRC}"
  echo 'complete -o default -F __start_kubectl k' >> "${VAGRANT_BASHRC}"
  chown vagrant:vagrant "${VAGRANT_BASHRC}" || true
fi

echo "[04-k3s] Checking metrics-server..."
# k3s comes with metrics-server, check if its working
sleep 15
if ! "${KUBECTL[@]}" top nodes 2>/dev/null; then
  echo "[04-k3s] metrics-server not ready, deploying standalone..."
  "${KUBECTL[@]}" apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
  # needs insecure tls for local k3s
  "${KUBECTL[@]}" patch deployment metrics-server -n kube-system --type=json -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
  echo "[04-k3s] Waiting for metrics-server to be ready..."
  "${KUBECTL[@]}" rollout status deployment/metrics-server -n kube-system --timeout=60s || true
fi

echo "[04-k3s] Cluster status:"
"${KUBECTL[@]}" get nodes
"${KUBECTL[@]}" get pods -n kube-system

mkdir -p /etc/observability-lab
touch /etc/observability-lab/.k3s-done

echo "[04-k3s] Done."
