#!/usr/bin/env bash
# import grafana dashboard via the API
# usage: import-grafana-dashboard.sh [kube_context] [dashboard_file]

set -euo pipefail

kube_context="${1:-${KUBE_CONTEXT:-}}"
dashboard_file="${2:-monitoring/grafana-dashboard.json}"
namespace="${GRAFANA_NAMESPACE:-monitoring}"
service_name="${GRAFANA_SERVICE:-kube-prometheus-stack-grafana}"
deployment_name="${GRAFANA_DEPLOYMENT:-kube-prometheus-stack-grafana}"
grafana_user="${GRAFANA_USER:-admin}"
grafana_password="${GRAFANA_PASSWORD:-}"
grafana_secret="${GRAFANA_SECRET:-kube-prometheus-stack-grafana}"
rollout_timeout="${GRAFANA_ROLLOUT_TIMEOUT:-300s}"

require_bin() {
  local bin="$1"
  if ! command -v "${bin}" >/dev/null 2>&1; then
    echo "[import-grafana-dashboard] required binary not found: ${bin}" >&2
    exit 1
  fi
}

pick_local_port() {
  local start_port=33000
  local end_port=33999
  local port
  for port in $(seq "${start_port}" "${end_port}"); do
    if ! ss -H -ltn "sport = :${port}" 2>/dev/null | grep -q .; then
      echo "${port}"
      return 0
    fi
  done
  echo "[import-grafana-dashboard] could not find a free local TCP port in range ${start_port}-${end_port}" >&2
  exit 1
}

require_bin kubectl
require_bin curl
require_bin jq
require_bin ss

if [[ ! -f "${dashboard_file}" ]]; then
  echo "[import-grafana-dashboard] dashboard file not found: ${dashboard_file}" >&2
  exit 1
fi

kubectl_cmd=(kubectl)
if [[ -n "${kube_context}" ]]; then
  kubectl_cmd+=(--context "${kube_context}")
fi

if [[ -z "${grafana_password}" ]]; then
  grafana_password="$("${kubectl_cmd[@]}" -n "${namespace}" get secret "${grafana_secret}" -o jsonpath='{.data.admin-password}' | base64 -d 2>/dev/null || true)"
fi

if [[ -z "${grafana_password}" ]]; then
  echo "[import-grafana-dashboard] could not resolve Grafana admin password" >&2
  exit 1
fi

echo "[import-grafana-dashboard] Waiting Grafana rollout..."
"${kubectl_cmd[@]}" -n "${namespace}" rollout status "deployment/${deployment_name}" --timeout="${rollout_timeout}"

local_port="${GRAFANA_LOCAL_PORT:-}"
if [[ -z "${local_port}" ]]; then
  local_port="$(pick_local_port)"
fi

pf_log="$(mktemp /tmp/grafana-pf.XXXXXX.log)"
payload_file="$(mktemp /tmp/grafana-dashboard-payload.XXXXXX.json)"
response_file="$(mktemp /tmp/grafana-import-response.XXXXXX.json)"
resolved_dashboard_file="$(mktemp /tmp/grafana-dashboard-resolved.XXXXXX.json)"
pf_pid=""

cleanup() {
  if [[ -n "${pf_pid}" ]]; then
    kill "${pf_pid}" >/dev/null 2>&1 || true
  fi
  rm -f "${pf_log}" "${payload_file}" "${response_file}" "${resolved_dashboard_file}"
}
trap cleanup EXIT INT TERM

echo "[import-grafana-dashboard] Starting port-forward on localhost:${local_port}..."
"${kubectl_cmd[@]}" -n "${namespace}" port-forward "svc/${service_name}" "${local_port}:80" >"${pf_log}" 2>&1 &
pf_pid="$!"

for _ in $(seq 1 20); do
  if grep -q "Forwarding from" "${pf_log}" 2>/dev/null; then
    break
  fi
  if ! kill -0 "${pf_pid}" >/dev/null 2>&1; then
    echo "[import-grafana-dashboard] port-forward process exited unexpectedly" >&2
    cat "${pf_log}" >&2
    exit 1
  fi
  sleep 1
done

ready="false"
for _ in $(seq 1 60); do
  if curl -fsS -u "${grafana_user}:${grafana_password}" "http://127.0.0.1:${local_port}/api/health" >/dev/null; then
    ready="true"
    break
  fi
  sleep 2
done

if [[ "${ready}" != "true" ]]; then
  echo "[import-grafana-dashboard] Grafana API did not become ready in time" >&2
  cat "${pf_log}" >&2
  exit 1
fi

prometheus_uid="$(curl -sS -u "${grafana_user}:${grafana_password}" "http://127.0.0.1:${local_port}/api/datasources" | jq -r '.[] | select(.type=="prometheus") | .uid' | head -n 1)"

if [[ -z "${prometheus_uid}" ]]; then
  echo "[import-grafana-dashboard] could not resolve Prometheus datasource UID from Grafana API" >&2
  exit 1
fi

# replace placeholder datasource with real prometheus uid
jq --arg prom_uid "${prometheus_uid}" '
  (.panels[]?.datasource.uid |= if .=="${DS_PROMETHEUS}" then $prom_uid else . end) |
  (.templating.list[]?.datasource.uid |= if .=="${DS_PROMETHEUS}" then $prom_uid else . end)
' "${dashboard_file}" > "${resolved_dashboard_file}"

jq -c '{dashboard: ., folderId: 0, overwrite: true}' "${resolved_dashboard_file}" > "${payload_file}"

http_code="$(curl -sS -u "${grafana_user}:${grafana_password}" -H "Content-Type: application/json" -o "${response_file}" -w "%{http_code}" -X POST "http://127.0.0.1:${local_port}/api/dashboards/db" --data-binary "@${payload_file}")"

if [[ "${http_code}" != "200" ]]; then
  echo "[import-grafana-dashboard] import failed (HTTP ${http_code})" >&2
  cat "${response_file}" >&2
  exit 1
fi

status="$(jq -r '.status // empty' "${response_file}")"
if [[ "${status}" != "success" ]]; then
  echo "[import-grafana-dashboard] Grafana API returned non-success status" >&2
  cat "${response_file}" >&2
  exit 1
fi

dashboard_uid="$(jq -r '.uid // empty' "${dashboard_file}")"
if [[ -n "${dashboard_uid}" ]]; then
  verify_code="$(curl -sS -u "${grafana_user}:${grafana_password}" -o /dev/null -w "%{http_code}" "http://127.0.0.1:${local_port}/api/dashboards/uid/${dashboard_uid}")"
  if [[ "${verify_code}" != "200" ]]; then
    echo "[import-grafana-dashboard] dashboard verification failed for uid=${dashboard_uid} (HTTP ${verify_code})" >&2
    exit 1
  fi
fi

dashboard_title="$(jq -r '.title // "unknown"' "${dashboard_file}")"
echo "[import-grafana-dashboard] Imported dashboard: ${dashboard_title}"
