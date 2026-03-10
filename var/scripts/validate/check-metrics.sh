#!/usr/bin/env bash
# validate prometheus scraping for app metrics

set -euo pipefail

NS_MONITORING="monitoring"
NS_APP="app"
PROM_LOCAL_PORT=19090
PROM_PF_PID=""
PROM_PF_LOG=""
KUBE_CONTEXT="${KUBE_CONTEXT:-}"

if [[ -z "${KUBE_CONTEXT}" ]]; then
  echo "[check-metrics] KUBE_CONTEXT is required." >&2
  exit 1
fi

cleanup() {
  if [[ -n "${PROM_PF_PID}" ]]; then
    kill "${PROM_PF_PID}" 2>/dev/null || true
  fi
}
trap cleanup EXIT

FAIL=0

echo "[check-metrics] Setting up port-forward to Prometheus..."
PROM_PF_LOG="$(mktemp /tmp/check-metrics-pf.XXXXXX.log)"
kubectl --context "${KUBE_CONTEXT}" port-forward -n "${NS_MONITORING}" svc/kube-prometheus-stack-prometheus "${PROM_LOCAL_PORT}:9090" > "${PROM_PF_LOG}" 2>&1 &
PROM_PF_PID=$!
sleep 3

PROM="http://localhost:${PROM_LOCAL_PORT}"

if ! curl -sf "${PROM}/-/healthy" > /dev/null 2>&1; then
  echo "  [!!]  Prometheus not reachable at ${PROM}"
  exit 1
fi
echo "  [OK]  Prometheus is healthy"

echo "[check-metrics] Checking app scrape target..."
APP_TARGETS=$(curl -sf "${PROM}/api/v1/targets" 2>/dev/null | jq -r '[.data.activeTargets[] | select((.labels.app // "") == "observability-app" and ((.labels.kubernetes_namespace // .labels.namespace // "") == "app"))] | length' 2>/dev/null || echo "0")
if [[ "${APP_TARGETS}" -gt 0 ]]; then
  echo "  [OK]  App pods found in Prometheus active targets"
else
  echo "  [!!]  No app pods found in Prometheus active targets"
  FAIL=$((FAIL + 1))
fi

echo "[check-metrics] Querying Prometheus for app metrics..."

query_len() {
  local query="$1"
  curl -sfG "${PROM}/api/v1/query" --data-urlencode "query=${query}" 2>/dev/null | jq -r '.data.result | length' 2>/dev/null || echo "0"
}

check_metric_any() {
  local name="$1"
  shift
  local result
  local query
  for query in "$@"; do
    result="$(query_len "${query}")"
    if [[ "${result}" -gt 0 ]]; then
      echo "  [OK]  ${name} via '${query}' has ${result} series"
      return 0
    fi
  done

  echo "  [!!]  ${name} returned 0 series for all expected queries"
  FAIL=$((FAIL + 1))
  return 1
}

check_metric_any "request counter" "app_request_total" "http_requests_total"

check_metric_any "latency histogram" "app_request_latency_seconds_bucket" "http_request_duration_seconds_bucket"

check_metric_any "error counter" "app_request_errors_total" "http_requests_total{status=~\"5..\"}" "sum(http_requests_total{status=~\"5..\"}) or vector(0)"

check_metric_any "cpu usage (namespace app)" "container_cpu_usage_seconds_total{namespace=\"${NS_APP}\",pod=~\"observability-app.*\"}" "sum(rate(container_cpu_usage_seconds_total{namespace=\"${NS_APP}\",pod=~\"observability-app.*\"}[5m]))"

echo ""
if [[ ${FAIL} -gt 0 ]]; then
  echo "[check-metrics] FAILED (${FAIL} checks failed)"
  exit 1
else
  echo "[check-metrics] PASSED"
fi
