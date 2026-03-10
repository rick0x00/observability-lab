#!/usr/bin/env bash
# create kind cluster, skip if already exists

set -euo pipefail

CLUSTER_NAME="${KIND_CLUSTER_NAME:-kind-local}"
KIND_NODE_IMAGE="${KIND_NODE_IMAGE:-kindest/node:v1.29.4}"

if ! command -v kind >/dev/null 2>&1; then
  echo "[07-kind-cluster] kind not found. Run 06-kind.sh first." >&2
  exit 1
fi

if ! command -v kubectl >/dev/null 2>&1; then
  echo "[07-kind-cluster] kubectl not found. Install kubectl first." >&2
  exit 1
fi

echo "[07-kind-cluster] target cluster: ${CLUSTER_NAME}"

if kind get clusters 2>/dev/null | grep -qx "${CLUSTER_NAME}"; then
  echo "[07-kind-cluster] cluster ${CLUSTER_NAME} already exists."
else
  cfg_file="$(mktemp)"
  cat > "${cfg_file}" <<CFG
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
    extraPortMappings:
      - containerPort: 30080
        hostPort: 8080
        protocol: TCP
      - containerPort: 30443
        hostPort: 8443
        protocol: TCP
CFG

  kind create cluster --name "${CLUSTER_NAME}" --image "${KIND_NODE_IMAGE}" --config "${cfg_file}"

  rm -f "${cfg_file}"
fi

echo "[07-kind-cluster] verifying cluster access..."
kubectl --context "kind-${CLUSTER_NAME}" get nodes

echo "[07-kind-cluster] Done. Context: kind-${CLUSTER_NAME}"
