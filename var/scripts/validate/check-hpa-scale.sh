#!/usr/bin/env bash
# run load and check if hpa scaled above start replicas

set -euo pipefail

NS="app"
KUBE_CONTEXT="${KUBE_CONTEXT:-}"
DURATION="${DURATION:-90}"
LOAD_PID=""
BURN_TIMEOUT="${BURN_TIMEOUT:-120}"

if [[ -z "${KUBE_CONTEXT}" ]]; then
  echo "[check-hpa-scale] KUBE_CONTEXT is required." >&2
  exit 1
fi

cleanup() {
  if [[ -n "${LOAD_PID}" ]]; then
    kill "${LOAD_PID}" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

start_replicas=$(kubectl --context "${KUBE_CONTEXT}" get hpa observability-app-hpa -n "${NS}" -o jsonpath='{.status.currentReplicas}' 2>/dev/null || echo "0")
max_replicas="${start_replicas}"

echo "[check-hpa-scale] Start replicas: ${start_replicas}"
echo "[check-hpa-scale] Running load for ${DURATION}s..."

KUBE_CONTEXT="${KUBE_CONTEXT}" bash var/scripts/lab-load --duration "${DURATION}" > /tmp/check-hpa-scale-load.log 2>&1 &
LOAD_PID=$!

while kill -0 "${LOAD_PID}" 2>/dev/null; do
  current=$(kubectl --context "${KUBE_CONTEXT}" get hpa observability-app-hpa -n "${NS}" -o jsonpath='{.status.currentReplicas}' 2>/dev/null || echo "0")
  if [[ "${current}" -gt "${max_replicas}" ]]; then
    max_replicas="${current}"
  fi
  sleep 5
done

wait "${LOAD_PID}" || true
LOAD_PID=""

echo "[check-hpa-scale] Max replicas seen: ${max_replicas}"

if [[ "${max_replicas}" -le "${start_replicas}" ]]; then
  echo "[check-hpa-scale] No scale-out from HTTP load, trying in-pod CPU burn..."
  mapfile -t pods < <(kubectl --context "${KUBE_CONTEXT}" get pods -n "${NS}" -l app=observability-app -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}')

  if [[ "${#pods[@]}" -eq 0 ]]; then
    echo "[check-hpa-scale] FAILED (no app pods found for CPU burn)." >&2
    exit 1
  fi

  for pod in "${pods[@]}"; do
    kubectl --context "${KUBE_CONTEXT}" exec -n "${NS}" "${pod}" -- env BURN_TIMEOUT="${BURN_TIMEOUT}" sh -c \
      '(yes >/dev/null 2>&1 || while :; do :; done) & p1=$!; (yes >/dev/null 2>&1 || while :; do :; done) & p2=$!; sleep "${BURN_TIMEOUT}"; kill $p1 $p2 >/dev/null 2>&1 || true' >/tmp/check-hpa-scale-burn.log 2>&1 &
  done

  burn_deadline=$((SECONDS + BURN_TIMEOUT))
  while [[ "${SECONDS}" -lt "${burn_deadline}" ]]; do
    current=$(kubectl --context "${KUBE_CONTEXT}" get hpa observability-app-hpa -n "${NS}" -o jsonpath='{.status.currentReplicas}' 2>/dev/null || echo "0")
    if [[ "${current}" -gt "${max_replicas}" ]]; then
      max_replicas="${current}"
    fi
    sleep 5
  done

  echo "[check-hpa-scale] Max replicas after CPU burn: ${max_replicas}"
fi

if [[ "${max_replicas}" -gt "${start_replicas}" ]]; then
  echo "[check-hpa-scale] PASSED"
  exit 0
fi

echo "[check-hpa-scale] FAILED (no scale-out observed)."
echo "[check-hpa-scale] Tip: increase DURATION or app cpu load."
exit 1
