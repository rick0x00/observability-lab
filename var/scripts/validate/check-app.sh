#!/usr/bin/env bash
# check mandatory endpoints and pod status

set -euo pipefail

NS="app"
PORT_FWD_PID=""
LOCAL_PORT=18080
KUBE_CONTEXT="${KUBE_CONTEXT:-}"

if [[ -z "${KUBE_CONTEXT}" ]]; then
  echo "[check-app] KUBE_CONTEXT is required." >&2
  exit 1
fi

cleanup() {
  if [[ -n "${PORT_FWD_PID}" ]]; then
    kill "${PORT_FWD_PID}" 2>/dev/null || true
  fi
}
trap cleanup EXIT

echo "[check-app] Setting up port-forward..."
kubectl --context "${KUBE_CONTEXT}" port-forward svc/observability-app -n "${NS}" "${LOCAL_PORT}:8080" > /tmp/check-app-pf.log 2>&1 &
PORT_FWD_PID=$!
sleep 3

BASE="http://localhost:${LOCAL_PORT}"
FAIL=0

check_endpoint() {
  local path="$1"
  local expected_status="${2:-200}"
  local status
  status=$(curl -s -o /dev/null -w "%{http_code}" "${BASE}${path}")
  if [[ "${status}" == "${expected_status}" ]]; then
    echo "  [OK]  ${path} -> ${status}"
  else
    echo "  [!!]  ${path} -> ${status} (expected ${expected_status})"
    FAIL=$((FAIL + 1))
  fi
}

echo "[check-app] Testing mandatory endpoints..."
check_endpoint "/health"
check_endpoint "/ready"
check_endpoint "/metrics"
check_endpoint "/request"
check_endpoint "/slow"
check_endpoint "/error" "500"

echo ""
echo "[check-app] Checking pod status..."
RUNNING=$(kubectl --context "${KUBE_CONTEXT}" get pods -n "${NS}" -l app=observability-app --no-headers 2>/dev/null | grep -c Running || echo 0)
EXPECTED=2

if [[ "${RUNNING}" -ge "${EXPECTED}" ]]; then
  echo "  [OK]  ${RUNNING} app pods Running (expected >= ${EXPECTED})"
else
  echo "  [!!]  Only ${RUNNING} app pods Running (expected ${EXPECTED})"
  FAIL=$((FAIL + 1))
fi

echo ""
echo "[check-app] Checking metrics content..."
METRICS=$(curl -sf "${BASE}/metrics" 2>/dev/null || echo "")
if echo "${METRICS}" | grep -q "app_request_total"; then
  echo "  [OK]  app_request_total metric present"
else
  if echo "${METRICS}" | grep -q "http_request_duration_seconds"; then
    echo "  [OK]  http_request_duration_seconds metric present"
  else
    echo "  [!!]  expected request metric not found in /metrics output"
    FAIL=$((FAIL + 1))
  fi
fi

echo ""
if [[ ${FAIL} -gt 0 ]]; then
  echo "[check-app] FAILED (${FAIL} checks failed)"
  exit 1
else
  echo "[check-app] PASSED"
fi
