#!/usr/bin/env bash
# ensure elastic credentials from k8s secret are valid
# if auth fails, restart elasticsearch statefulset and check again

set -euo pipefail

KUBE_CONTEXT="${1:-${KUBE_CONTEXT:-}}"
NAMESPACE="${ELK_NAMESPACE:-logging}"
SECRET_NAME="${ELASTIC_CREDENTIALS_SECRET:-observability-lab-master-credentials}"
SERVICE_NAME="${ELASTIC_SERVICE_NAME:-observability-lab-master}"
STATEFULSET_NAME="${ELASTIC_STATEFULSET_NAME:-observability-lab-master}"
ROLLOUT_TIMEOUT="${ELASTIC_ROLLOUT_TIMEOUT:-600s}"
LOCAL_PORT="${ELASTIC_CHECK_PORT:-39200}"

if [[ -z "${KUBE_CONTEXT}" ]]; then
  echo "[ensure-elasticsearch-auth] KUBE_CONTEXT is required" >&2
  exit 1
fi

kubectl_cmd=(kubectl --context "${KUBE_CONTEXT}" -n "${NAMESPACE}")

if ! "${kubectl_cmd[@]}" get secret "${SECRET_NAME}" >/dev/null 2>&1; then
  echo "[ensure-elasticsearch-auth] missing secret ${SECRET_NAME} in namespace ${NAMESPACE}" >&2
  exit 1
fi

elastic_user="$("${kubectl_cmd[@]}" get secret "${SECRET_NAME}" -o jsonpath='{.data.username}' | base64 -d 2>/dev/null || true)"
elastic_pass="$("${kubectl_cmd[@]}" get secret "${SECRET_NAME}" -o jsonpath='{.data.password}' | base64 -d 2>/dev/null || true)"

if [[ -z "${elastic_user}" || -z "${elastic_pass}" ]]; then
  echo "[ensure-elasticsearch-auth] could not read username/password from ${SECRET_NAME}" >&2
  exit 1
fi

check_auth() {
  local pf_pid=""
  local status=""
  local payload_file
  payload_file="$(mktemp /tmp/es-auth-check.XXXXXX.json)"

  cleanup_check() {
    if [[ -n "${pf_pid}" ]]; then
      kill "${pf_pid}" >/dev/null 2>&1 || true
    fi
    rm -f "${payload_file}"
  }
  trap cleanup_check RETURN

  "${kubectl_cmd[@]}" port-forward "svc/${SERVICE_NAME}" "${LOCAL_PORT}:9200" >/tmp/es-auth-pf.log 2>&1 &
  pf_pid=$!
  sleep 2

  status="$(curl -sSk --connect-timeout 5 --max-time 20 -u "${elastic_user}:${elastic_pass}" -o "${payload_file}" -w "%{http_code}" "https://127.0.0.1:${LOCAL_PORT}/_security/_authenticate" || true)"
  if [[ "${status}" == "200" ]]; then
    return 0
  fi

  return 1
}

echo "[ensure-elasticsearch-auth] checking elastic auth..."
if check_auth; then
  echo "[ensure-elasticsearch-auth] auth ok"
  exit 0
fi

echo "[ensure-elasticsearch-auth] auth failed, restarting statefulset ${STATEFULSET_NAME}..."
"${kubectl_cmd[@]}" rollout restart "statefulset/${STATEFULSET_NAME}"
"${kubectl_cmd[@]}" rollout status "statefulset/${STATEFULSET_NAME}" --timeout="${ROLLOUT_TIMEOUT}"

for _ in $(seq 1 20); do
  if check_auth; then
    echo "[ensure-elasticsearch-auth] auth ok after restart"
    exit 0
  fi
  sleep 5
done

echo "[ensure-elasticsearch-auth] auth still failing after restart" >&2
exit 1
