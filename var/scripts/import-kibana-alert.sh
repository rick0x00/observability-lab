#!/usr/bin/env bash
# upsert kibana alert rule for error spikes
# creates connector if not exists, then recreate rule by name
# usage: import-kibana-alert.sh [kube_context] [alert_file]

set -euo pipefail

kube_context="${1:-${KUBE_CONTEXT:-}}"
alert_file="${2:-elk/kibana-alert-rule.json}"
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
    echo "[import-kibana-alert] required binary not found: ${bin}" >&2
    exit 1
  fi
}

pick_local_port() {
  local start_port=35701
  local end_port=35800
  local port
  for port in $(seq "${start_port}" "${end_port}"); do
    if ! ss -H -ltn "sport = :${port}" 2>/dev/null | grep -q .; then
      echo "${port}"
      return 0
    fi
  done
  echo "[import-kibana-alert] could not find a free local TCP port in range ${start_port}-${end_port}" >&2
  exit 1
}

require_bin kubectl
require_bin curl
require_bin jq
require_bin ss

if [[ ! -f "${alert_file}" ]]; then
  echo "[import-kibana-alert] alert file not found: ${alert_file}" >&2
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
  echo "[import-kibana-alert] could not resolve Elasticsearch/Kibana password" >&2
  exit 1
fi

echo "[import-kibana-alert] Waiting Kibana rollout..."
"${kubectl_cmd[@]}" -n "${namespace}" rollout status "deployment/${deployment_name}" --timeout="${rollout_timeout}"

local_port="${KIBANA_ALERT_LOCAL_PORT:-}"
if [[ -z "${local_port}" ]]; then
  local_port="$(pick_local_port)"
fi

pf_log="$(mktemp /tmp/kibana-alert-pf.XXXXXX.log)"
response_file="$(mktemp /tmp/kibana-alert-response.XXXXXX.json)"
pf_pid=""

cleanup() {
  if [[ -n "${pf_pid}" ]]; then
    kill "${pf_pid}" >/dev/null 2>&1 || true
  fi
  rm -f "${pf_log}" "${response_file}"
}
trap cleanup EXIT INT TERM

echo "[import-kibana-alert] Starting port-forward on localhost:${local_port}..."
"${kubectl_cmd[@]}" -n "${namespace}" port-forward "svc/${service_name}" "${local_port}:5601" >"${pf_log}" 2>&1 &
pf_pid="$!"

for _ in $(seq 1 20); do
  if grep -q "Forwarding from" "${pf_log}" 2>/dev/null; then
    break
  fi
  if ! kill -0 "${pf_pid}" >/dev/null 2>&1; then
    echo "[import-kibana-alert] port-forward process exited unexpectedly" >&2
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
  echo "[import-kibana-alert] Kibana login endpoint did not become ready in time" >&2
  cat "${pf_log}" >&2
  exit 1
fi

api_base="http://127.0.0.1:${local_port}"
auth_args=(-u "${elastic_user}:${elastic_password}")

connector_payload="$(jq -c '.connector' "${alert_file}")"
rule_payload_template="$(jq -c '.rule' "${alert_file}")"
connector_name="$(echo "${connector_payload}" | jq -r '.name')"
rule_name="$(echo "${rule_payload_template}" | jq -r '.name')"

existing_connector_id="$(curl -sS "${auth_args[@]}" -H 'kbn-xsrf: true' "${api_base}/api/actions/connectors" | jq -r --arg name "${connector_name}" '(if type == "array" then . else (.data // []) end) | .[] | select(.name == $name) | .id' | head -n 1)"

if [[ -n "${existing_connector_id}" ]]; then
  connector_id="${existing_connector_id}"
  echo "[import-kibana-alert] Reusing connector: ${connector_id}"
else
  echo "[import-kibana-alert] Creating connector..."
  curl -sS "${auth_args[@]}" -H 'kbn-xsrf: true' -H 'Content-Type: application/json' -X POST "${api_base}/api/actions/connector" -d "${connector_payload}" >"${response_file}"

  connector_id="$(jq -r '.id // empty' "${response_file}")"
  if [[ -z "${connector_id}" ]]; then
    echo "[import-kibana-alert] failed to create connector" >&2
    cat "${response_file}" >&2
    exit 1
  fi
fi

rule_payload="$(echo "${rule_payload_template}" | jq --arg connector_id "${connector_id}" '.actions |= map(if .id == "__CONNECTOR_ID__" then .id = $connector_id else . end)')"

existing_rule_id="$(curl -sS "${auth_args[@]}" -H 'kbn-xsrf: true' --get "${api_base}/api/alerting/rules/_find" --data-urlencode "search_fields=name" --data-urlencode "search=${rule_name}" | jq -r --arg name "${rule_name}" '.data[] | select(.name == $name) | .id' | head -n 1)"

if [[ -n "${existing_rule_id}" ]]; then
  echo "[import-kibana-alert] Deleting existing rule: ${existing_rule_id}"
  delete_code="$(curl -sS "${auth_args[@]}" -H 'kbn-xsrf: true' -o /dev/null -w "%{http_code}" -X DELETE "${api_base}/api/alerting/rule/${existing_rule_id}")"
  if [[ "${delete_code}" != "200" && "${delete_code}" != "204" && "${delete_code}" != "404" ]]; then
    echo "[import-kibana-alert] failed to delete rule ${existing_rule_id} (HTTP ${delete_code})" >&2
    exit 1
  fi
fi

echo "[import-kibana-alert] Creating rule..."
create_code="$(curl -sS "${auth_args[@]}" -H 'kbn-xsrf: true' -H 'Content-Type: application/json' -o "${response_file}" -w "%{http_code}" -X POST "${api_base}/api/alerting/rule" -d "${rule_payload}")"
if [[ "${create_code}" != "200" && "${create_code}" != "201" ]]; then
  echo "[import-kibana-alert] failed to create alert rule (HTTP ${create_code})" >&2
  cat "${response_file}" >&2
  exit 1
fi

rule_id="$(jq -r '.id // empty' "${response_file}")"
if [[ -z "${rule_id}" ]]; then
  echo "[import-kibana-alert] failed to create/update alert rule" >&2
  cat "${response_file}" >&2
  exit 1
fi

echo "[import-kibana-alert] Rule ready: ${rule_id}"
