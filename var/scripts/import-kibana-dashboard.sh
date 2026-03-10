#!/usr/bin/env bash
# import kibana saved objects via the import API
# delete exsiting objects first to avoid conflicts
# usage: import-kibana-dashboard.sh [kube_context] [dashboard_file]

set -euo pipefail

kube_context="${1:-${KUBE_CONTEXT:-}}"
dashboard_file="${2:-elk/kibana-dashboard.json}"
namespace="${KIBANA_NAMESPACE:-logging}"
service_name="${KIBANA_SERVICE:-kibana-kibana}"
deployment_name="${KIBANA_DEPLOYMENT:-kibana-kibana}"
credentials_secret="${ELASTIC_CREDENTIALS_SECRET:-observability-lab-master-credentials}"
elastic_user="${ELASTIC_USER:-}"
elastic_password="${ELASTIC_PASSWORD:-}"
rollout_timeout="${KIBANA_ROLLOUT_TIMEOUT:-300s}"

require_bin() {
  local bin="$1"
  if ! command -v "${bin}" >/dev/null 2>&1; then
    echo "[import-kibana-dashboard] required binary not found: ${bin}" >&2
    exit 1
  fi
}

pick_local_port() {
  local start_port=35601
  local end_port=35700
  local port
  for port in $(seq "${start_port}" "${end_port}"); do
    if ! ss -H -ltn "sport = :${port}" 2>/dev/null | grep -q .; then
      echo "${port}"
      return 0
    fi
  done
  echo "[import-kibana-dashboard] could not find a free local TCP port in range ${start_port}-${end_port}" >&2
  exit 1
}

require_bin kubectl
require_bin curl
require_bin jq
require_bin ss

if [[ ! -f "${dashboard_file}" ]]; then
  echo "[import-kibana-dashboard] dashboard file not found: ${dashboard_file}" >&2
  exit 1
fi

kubectl_cmd=(kubectl)
if [[ -n "${kube_context}" ]]; then
  kubectl_cmd+=(--context "${kube_context}")
fi

if [[ -z "${elastic_user}" ]]; then
  elastic_user="$("${kubectl_cmd[@]}" -n "${namespace}" get secret "${credentials_secret}" -o jsonpath='{.data.username}' | base64 -d 2>/dev/null || true)"
fi
if [[ -z "${elastic_password}" ]]; then
  elastic_password="$("${kubectl_cmd[@]}" -n "${namespace}" get secret "${credentials_secret}" -o jsonpath='{.data.password}' | base64 -d 2>/dev/null || true)"
fi

if [[ -z "${elastic_user}" ]]; then
  elastic_user="elastic"
fi
if [[ -z "${elastic_password}" ]]; then
  echo "[import-kibana-dashboard] could not resolve Elasticsearch/Kibana password" >&2
  exit 1
fi

echo "[import-kibana-dashboard] Waiting Kibana rollout..."
"${kubectl_cmd[@]}" -n "${namespace}" rollout status "deployment/${deployment_name}" --timeout="${rollout_timeout}"

local_port="${KIBANA_LOCAL_PORT:-}"
if [[ -z "${local_port}" ]]; then
  local_port="$(pick_local_port)"
fi

pf_log="$(mktemp /tmp/kibana-pf.XXXXXX.log)"
ndjson_file="$(mktemp /tmp/kibana-import.XXXXXX.ndjson)"
response_file="$(mktemp /tmp/kibana-import-response.XXXXXX.json)"
verify_file="$(mktemp /tmp/kibana-find-response.XXXXXX.json)"
pf_pid=""

cleanup() {
  if [[ -n "${pf_pid}" ]]; then
    kill "${pf_pid}" >/dev/null 2>&1 || true
  fi
  rm -f "${pf_log}" "${ndjson_file}" "${response_file}" "${verify_file}"
}
trap cleanup EXIT INT TERM

echo "[import-kibana-dashboard] Starting port-forward on localhost:${local_port}..."
"${kubectl_cmd[@]}" -n "${namespace}" port-forward "svc/${service_name}" "${local_port}:5601" >"${pf_log}" 2>&1 &
pf_pid="$!"

for _ in $(seq 1 20); do
  if grep -q "Forwarding from" "${pf_log}" 2>/dev/null; then
    break
  fi
  if ! kill -0 "${pf_pid}" >/dev/null 2>&1; then
    echo "[import-kibana-dashboard] port-forward process exited unexpectedly" >&2
    cat "${pf_log}" >&2
    exit 1
  fi
  sleep 1
done

ready="false"
for _ in $(seq 1 120); do
  login_code="$(curl -sS -o /dev/null -w "%{http_code}" "http://127.0.0.1:${local_port}/login" || true)"
  if [[ "${login_code}" == "200" || "${login_code}" == "302" ]]; then
    ready="true"
    break
  fi
  sleep 2
done

if [[ "${ready}" != "true" ]]; then
  echo "[import-kibana-dashboard] Kibana login endpoint did not become ready in time" >&2
  cat "${pf_log}" >&2
  exit 1
fi

status_ready="false"
core_migration_version=""
for _ in $(seq 1 180); do
  status_payload="$(curl -sS --connect-timeout 5 --max-time 20 -u "${elastic_user}:${elastic_password}" -H "kbn-xsrf: true" "http://127.0.0.1:${local_port}/api/status" || true)"
  level="$(printf '%s' "${status_payload}" | jq -r '.status.overall.level // empty' 2>/dev/null || true)"
  if [[ "${level}" == "available" ]]; then
    core_migration_version="$(printf '%s' "${status_payload}" | jq -r '.version.number // empty' 2>/dev/null || true)"
    status_ready="true"
    break
  fi
  sleep 2
done

if [[ "${status_ready}" != "true" ]]; then
  echo "[import-kibana-dashboard] Kibana status API did not reach 'available' in time" >&2
  exit 1
fi

if [[ -z "${core_migration_version}" ]]; then
  core_migration_version="$(curl -sS --connect-timeout 5 --max-time 20 -u "${elastic_user}:${elastic_password}" -H "kbn-xsrf: true" "http://127.0.0.1:${local_port}/api/status" | jq -r '.version.number // empty' || true)"
fi

dashboard_migration_version="8.5.0"
if [[ -n "${core_migration_version}" ]]; then
  major_minor="$(printf '%s' "${core_migration_version}" | awk -F. '{print $1 "." $2}')"
  if [[ "${major_minor}" =~ ^[0-9]+\.[0-9]+$ ]]; then
    dashboard_migration_version="${major_minor}.0"
  fi
else
  core_migration_version="8.5.1"
fi

# clean old objects first, make import more stable
stale_objects=(
  "dashboard/observability-logs-dashboard"
  "visualization/observability-log-volume-by-level"
  "visualization/observability-top-endpoints"
  "visualization/observability-errors-over-time"
  "visualization/observability-latency-histogram"
  "search/observability-log-explorer"
  "alert/observability-error-spike-alert"
  "index-pattern/app-logs-staging"
  "index-pattern/app-logs-all"
)
for stale_object in "${stale_objects[@]}"; do
  curl -sS --connect-timeout 5 --max-time 20 -u "${elastic_user}:${elastic_password}" -H "kbn-xsrf: true" -o /dev/null -X DELETE "http://127.0.0.1:${local_port}/api/saved_objects/${stale_object}" || true
done

if jq -e 'type=="array"' "${dashboard_file}" >/dev/null 2>&1; then
  skipped_count="$(jq '[.[] | select(.type == "alert" or .type == "action")] | length' "${dashboard_file}")"
  if [[ "${skipped_count}" != "0" ]]; then
    echo "[import-kibana-dashboard] WARN: skipping ${skipped_count} saved object(s) with non-importable predefined IDs (types: alert/action)."
  fi
  jq -c --arg dashboard_migration "${dashboard_migration_version}" --arg core_migration "${core_migration_version}" '
    def normalize_dashboard:
      if .type != "dashboard" then
        .
      else
        if (.migrationVersion.dashboard? // "") == "" then
            .migrationVersion = ((.migrationVersion // {}) + {dashboard: $dashboard_migration})
          else
            .
          end
        | if (.coreMigrationVersion? // "") == "" then
            .coreMigrationVersion = $core_migration
          else
            .
          end
      end;
    .[]
    | select(.type != "alert" and .type != "action")
    | normalize_dashboard
  ' "${dashboard_file}" > "${ndjson_file}"
else
  cp "${dashboard_file}" "${ndjson_file}"
fi

imported="false"
last_http_code=""
for _ in $(seq 1 45); do
  last_http_code="$(curl -sS --connect-timeout 5 --max-time 20 -u "${elastic_user}:${elastic_password}" -H "kbn-xsrf: true" -o "${response_file}" -w "%{http_code}" -X POST "http://127.0.0.1:${local_port}/api/saved_objects/_import?overwrite=true" -F "file=@${ndjson_file};type=application/ndjson" || true)"

  if [[ "${last_http_code}" == "200" ]] && [[ "$(jq -r '.success // false' "${response_file}" 2>/dev/null || echo false)" == "true" ]]; then
    imported="true"
    break
  fi

  sleep 4
done

if [[ "${imported}" != "true" ]]; then
  echo "[import-kibana-dashboard] import failed after retries (last HTTP ${last_http_code:-unknown})" >&2
  if [[ -f "${response_file}" ]]; then
    cat "${response_file}" >&2
  fi
  exit 1
fi

dashboard_id=""
dashboard_title=""
search_id=""
if jq -e 'type=="array"' "${dashboard_file}" >/dev/null 2>&1; then
  dashboard_id="$(jq -r '[.[] | select(.type=="dashboard")][0].id // empty' "${dashboard_file}")"
  dashboard_title="$(jq -r '[.[] | select(.type=="dashboard")][0].attributes.title // empty' "${dashboard_file}")"
  search_id="$(jq -r '[.[] | select(.type=="search")][0].id // empty' "${dashboard_file}")"
fi

if [[ -n "${dashboard_title}" ]]; then
  encoded_title="$(jq -nr --arg val "${dashboard_title}" '$val|@uri')"
  curl -sS --connect-timeout 5 --max-time 20 -u "${elastic_user}:${elastic_password}" -H "kbn-xsrf: true" "http://127.0.0.1:${local_port}/api/saved_objects/_find?type=dashboard&search_fields=title&search=${encoded_title}" > "${verify_file}"
  if [[ "$(jq -r '.total // 0' "${verify_file}")" == "0" ]]; then
    echo "[import-kibana-dashboard] dashboard verification failed for title='${dashboard_title}'" >&2
    exit 1
  fi
fi

if [[ -n "${dashboard_id}" ]]; then
  curl -sS --connect-timeout 5 --max-time 20 -u "${elastic_user}:${elastic_password}" -H "kbn-xsrf: true" "http://127.0.0.1:${local_port}/api/saved_objects/dashboard/${dashboard_id}" > "${verify_file}"

  missing_panel_refs="$(comm -23 <(jq -r '.attributes.panelsJSON | fromjson[] | .panelRefName // empty' "${verify_file}" | sort -u) <(jq -r '.references[]? | .name' "${verify_file}" | sort -u) || true)"

  if [[ -n "${missing_panel_refs}" ]]; then
    echo "[import-kibana-dashboard] dashboard reference integrity check failed for id='${dashboard_id}'" >&2
    echo "[import-kibana-dashboard] missing panel references: ${missing_panel_refs//$'\n'/, }" >&2
    exit 1
  fi
fi

if [[ -n "${search_id}" ]]; then
  search_code="$(curl -sS --connect-timeout 5 --max-time 20 -u "${elastic_user}:${elastic_password}" -H "kbn-xsrf: true" -o /dev/null -w "%{http_code}" "http://127.0.0.1:${local_port}/api/saved_objects/search/${search_id}")"
  if [[ "${search_code}" != "200" ]]; then
    echo "[import-kibana-dashboard] search verification failed for id='${search_id}' (HTTP ${search_code})" >&2
    exit 1
  fi
fi

echo "[import-kibana-dashboard] Imported saved objects successfully."
