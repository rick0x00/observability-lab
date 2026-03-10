#!/usr/bin/env sh
set -eu

PODINFO_PORT="${PODINFO_PORT:-9898}"

# run podinfo in backround, shim runs in foreground
/home/app/podinfo --port "${PODINFO_PORT}" &
podinfo_pid="$!"

cleanup() {
  kill "${podinfo_pid}" 2>/dev/null || true
  wait "${podinfo_pid}" 2>/dev/null || true
}

trap cleanup INT TERM

python3 /home/app/podinfo_shim.py
status="$?"
cleanup
exit "${status}"
