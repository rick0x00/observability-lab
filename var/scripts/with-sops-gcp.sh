#!/usr/bin/env bash
# run a command with GOOGLE_APPLICATION_CREDENTIALS ready for sops
# first use existing env var, then local key file, then gcloud adc file

set -euo pipefail

if [[ "$#" -eq 0 ]]; then
  echo "usage: with-sops-gcp.sh <command...>" >&2
  exit 1
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../.." && pwd)"

to_abs_path() {
  local candidate="$1"
  if [[ -z "${candidate}" || ! -f "${candidate}" ]]; then
    return 1
  fi
  readlink -f "${candidate}" 2>/dev/null || echo "${candidate}"
}

export_credentials_and_exec() {
  local source_file="$1"
  shift
  local abs_file
  abs_file="$(to_abs_path "${source_file}" || true)"
  if [[ -z "${abs_file}" || ! -f "${abs_file}" ]]; then
    return 1
  fi
  export GOOGLE_APPLICATION_CREDENTIALS="${abs_file}"
  exec "$@"
}

if [[ -n "${GOOGLE_APPLICATION_CREDENTIALS:-}" ]]; then
  export_credentials_and_exec "${GOOGLE_APPLICATION_CREDENTIALS}" "$@"
fi

plain_file="${SOPS_GCP_SA_PLAIN_FILE:-${repo_root}/keys/gcp-service-account.json}"
if [[ -f "${plain_file}" ]]; then
  export_credentials_and_exec "${plain_file}" "$@"
fi

auto_plain_file="$(find "${repo_root}/keys" -maxdepth 1 -type f -name '*.json' 2>/dev/null | head -n 1 || true)"
if [[ -n "${auto_plain_file}" && -f "${auto_plain_file}" ]]; then
  export_credentials_and_exec "${auto_plain_file}" "$@"
fi

hidden_plain_file="${SOPS_GCP_SA_HIDDEN_FILE:-${repo_root}/.keys/gcp-service-account.json}"
if [[ -f "${hidden_plain_file}" ]]; then
  export_credentials_and_exec "${hidden_plain_file}" "$@"
fi

auto_hidden_file="$(find "${repo_root}/.keys" -maxdepth 1 -type f -name '*.json' 2>/dev/null | head -n 1 || true)"
if [[ -n "${auto_hidden_file}" && -f "${auto_hidden_file}" ]]; then
  export_credentials_and_exec "${auto_hidden_file}" "$@"
fi

adc_file="${SOPS_GCP_ADC_FILE:-}"
if [[ -z "${adc_file}" ]]; then
  adc_file="$(find "${HOME}/.config/gcloud/legacy_credentials" -maxdepth 2 -type f -name adc.json 2>/dev/null | head -n 1 || true)"
fi
if [[ -n "${adc_file}" && -f "${adc_file}" ]]; then
  export_credentials_and_exec "${adc_file}" "$@"
fi

echo "no gcp credentials found. set GOOGLE_APPLICATION_CREDENTIALS or keys/gcp-service-account.json" >&2
exit 1
