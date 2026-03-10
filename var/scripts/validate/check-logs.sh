#!/usr/bin/env bash
# check if logs are flowing to elasticsearch
# try https first, fall back to http (security is off in lab)

set -euo pipefail

NS_LOGGING="logging"
NS_APP="app"
ES_LOCAL_PORT=19200
ES_PF_PID=""
ES_PF_LOG=""
APP_LOCAL_PORT=18082
APP_PF_PID=""
KUBE_CONTEXT="${KUBE_CONTEXT:-}"
ES_CREDENTIALS_SECRET="observability-lab-master-credentials"

if [[ -z "${KUBE_CONTEXT}" ]]; then
  echo "[check-logs] KUBE_CONTEXT is required." >&2
  exit 1
fi

cleanup() {
  if [[ -n "${ES_PF_PID}" ]]; then
    kill "${ES_PF_PID}" 2>/dev/null || true
  fi
  if [[ -n "${APP_PF_PID}" ]]; then
    kill "${APP_PF_PID}" 2>/dev/null || true
  fi
}
trap cleanup EXIT

FAIL=0

seed_app_logs() {
  echo "[check-logs] Seeding app logs..."
  kubectl --context "${KUBE_CONTEXT}" port-forward -n "${NS_APP}" svc/observability-app "${APP_LOCAL_PORT}:8080" > /tmp/check-logs-app-pf.log 2>&1 &
  APP_PF_PID=$!
  sleep 2
  for _ in $(seq 1 5); do
    curl -sf "http://localhost:${APP_LOCAL_PORT}/request" > /dev/null 2>&1 || true
    curl -sf "http://localhost:${APP_LOCAL_PORT}/slow" > /dev/null 2>&1 || true
    curl -s "http://localhost:${APP_LOCAL_PORT}/error" > /dev/null 2>&1 || true
  done
  kill "${APP_PF_PID}" 2>/dev/null || true
  APP_PF_PID=""
  sleep 6
}

echo "[check-logs] Setting up port-forward to Elasticsearch..."
ES_PF_LOG="$(mktemp /tmp/check-logs-es-pf.XXXXXX.log)"
kubectl --context "${KUBE_CONTEXT}" port-forward -n "${NS_LOGGING}" svc/observability-lab-master "${ES_LOCAL_PORT}:9200" > "${ES_PF_LOG}" 2>&1 &
ES_PF_PID=$!
sleep 3

ES="https://localhost:${ES_LOCAL_PORT}"
CURL_ARGS=(-sSkf)
AUTH_ARGS=()

if kubectl --context "${KUBE_CONTEXT}" -n "${NS_LOGGING}" get secret "${ES_CREDENTIALS_SECRET}" >/dev/null 2>&1; then
  ES_USER=$(kubectl --context "${KUBE_CONTEXT}" -n "${NS_LOGGING}" get secret "${ES_CREDENTIALS_SECRET}" -o jsonpath='{.data.username}' | base64 -d 2>/dev/null || echo "")
  ES_PASS=$(kubectl --context "${KUBE_CONTEXT}" -n "${NS_LOGGING}" get secret "${ES_CREDENTIALS_SECRET}" -o jsonpath='{.data.password}' | base64 -d 2>/dev/null || echo "")
  if [[ -n "${ES_USER}" && -n "${ES_PASS}" ]]; then
    AUTH_ARGS=(-u "${ES_USER}:${ES_PASS}")
  fi
fi

if ! curl "${CURL_ARGS[@]}" "${AUTH_ARGS[@]}" "${ES}/_cluster/health" > /dev/null 2>&1; then
  ES="http://localhost:${ES_LOCAL_PORT}"
  CURL_ARGS=(-sf)
  AUTH_ARGS=()
fi

if ! curl "${CURL_ARGS[@]}" "${AUTH_ARGS[@]}" "${ES}/_cluster/health" > /dev/null 2>&1; then
  echo "  [!!]  Elasticsearch not reachable at ${ES}"
  exit 1
fi

CLUSTER_STATUS=$(curl "${CURL_ARGS[@]}" "${AUTH_ARGS[@]}" "${ES}/_cluster/health" | jq -r '.status' 2>/dev/null || echo "unknown")
echo "  [OK]  Elasticsearch is reachable (cluster status: ${CLUSTER_STATUS})"
if [[ "${CLUSTER_STATUS}" == "red" ]]; then
  echo "  [!!]  Cluster is RED"
  FAIL=$((FAIL + 1))
fi

echo "[check-logs] Looking for app-logs indices..."
INDICES=$(curl "${CURL_ARGS[@]}" "${AUTH_ARGS[@]}" "${ES}/_cat/indices/app-logs-*?h=index" 2>/dev/null || echo "")
if [[ -n "${INDICES}" ]]; then
  echo "  [OK]  Found indices:"
  echo "${INDICES}" | while read -r idx; do echo "        ${idx}"; done
else
  echo "  [!!]  No app-logs-* indices found"
  FAIL=$((FAIL + 1))
fi

if [[ -n "${INDICES}" ]]; then
  DOC_COUNT=$(curl "${CURL_ARGS[@]}" "${AUTH_ARGS[@]}" "${ES}/app-logs-*/_count" 2>/dev/null | jq -r '.count' 2>/dev/null || echo "0")
  if [[ "${DOC_COUNT}" -gt 0 ]]; then
    echo "  [OK]  ${DOC_COUNT} documents in app-logs-* indices"
  else
    echo "  [!!]  0 documents in app-logs-*"
    FAIL=$((FAIL + 1))
  fi

  APP_DOC_COUNT=$(curl "${CURL_ARGS[@]}" "${AUTH_ARGS[@]}" "${ES}/app-logs-*/_count?q=kubernetes.namespace:app" 2>/dev/null | jq -r '.count' 2>/dev/null || echo "0")
  if [[ "${APP_DOC_COUNT}" -eq 0 ]]; then
    seed_app_logs
    APP_DOC_COUNT=$(curl "${CURL_ARGS[@]}" "${AUTH_ARGS[@]}" "${ES}/app-logs-*/_count?q=kubernetes.namespace:app" 2>/dev/null | jq -r '.count' 2>/dev/null || echo "0")
  fi
  if [[ "${APP_DOC_COUNT}" -gt 0 ]]; then
    echo "  [OK]  ${APP_DOC_COUNT} documents from namespace app"
  else
    echo "  [!!]  No documents from namespace app in app-logs-*"
    FAIL=$((FAIL + 1))
  fi

  echo "[check-logs] Checking key fields in a sample app document..."
  SAMPLE=$(curl "${CURL_ARGS[@]}" "${AUTH_ARGS[@]}" "${ES}/app-logs-*/_search?q=kubernetes.namespace:app%20AND%20kubernetes.labels.app:observability-app&size=1&sort=@timestamp:desc" 2>/dev/null)

  sample_hits=$(echo "${SAMPLE}" | jq -r '.hits.hits | length' 2>/dev/null || echo "0")
  if [[ "${sample_hits}" -eq 0 ]]; then
    SAMPLE=$(curl "${CURL_ARGS[@]}" "${AUTH_ARGS[@]}" "${ES}/app-logs-*/_search?q=kubernetes.namespace:app&size=1&sort=@timestamp:desc" 2>/dev/null)
  fi

  check_field() {
    local name="$1"
    local jq_expr="$2"
    local value
    value=$(echo "${SAMPLE}" | jq -r "${jq_expr}" 2>/dev/null || echo "")
    if [[ -n "${value}" && "${value}" != "null" ]]; then
      echo "  [OK]  '${name}' field found"
    else
      echo "  [!!]  '${name}' field missing"
      FAIL=$((FAIL + 1))
    fi
  }

  check_field "timestamp" '.hits.hits[0]._source.ts // .hits.hits[0]._source.timestamp // .hits.hits[0]._source["@timestamp"] // empty'
  check_field "level" '.hits.hits[0]._source.level // empty'
  check_field "endpoint" '.hits.hits[0]._source.endpoint // empty'
  check_field "latency" '.hits.hits[0]._source.latency // empty'
  check_field "message" '.hits.hits[0]._source.msg // .hits.hits[0]._source.message // empty'
  check_field "APP_ENV" '.hits.hits[0]._source.APP_ENV // empty'
  check_field "kubernetes.namespace" '.hits.hits[0]._source.kubernetes.namespace // empty'
fi

echo ""
if [[ ${FAIL} -gt 0 ]]; then
  echo "[check-logs] FAILED (${FAIL} checks failed)"
  exit 1
else
  echo "[check-logs] PASSED"
fi
