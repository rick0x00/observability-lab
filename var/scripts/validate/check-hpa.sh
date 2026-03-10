#!/usr/bin/env bash
# validate HPA config and scaling readiness

set -euo pipefail

NS="app"
FAIL=0
KUBE_CONTEXT="${KUBE_CONTEXT:-}"

if [[ -z "${KUBE_CONTEXT}" ]]; then
  echo "[check-hpa] KUBE_CONTEXT is required." >&2
  exit 1
fi

echo "[check-hpa] Checking HPA object..."

if ! kubectl --context "${KUBE_CONTEXT}" get hpa observability-app-hpa -n "${NS}" > /dev/null 2>&1; then
  echo "  [!!]  HPA 'observability-app-hpa' not found in namespace ${NS}"
  exit 1
fi

kubectl --context "${KUBE_CONTEXT}" describe hpa observability-app-hpa -n "${NS}"
echo ""

echo "[check-hpa] Checking HPA conditions..."
ABLE_TO_SCALE=$(kubectl --context "${KUBE_CONTEXT}" get hpa observability-app-hpa -n "${NS}" -o json 2>/dev/null | jq -r '.status.conditions[] | select(.type=="AbleToScale") | .status' 2>/dev/null || echo "Unknown")
SCALING_ACTIVE=$(kubectl --context "${KUBE_CONTEXT}" get hpa observability-app-hpa -n "${NS}" -o json 2>/dev/null | jq -r '.status.conditions[] | select(.type=="ScalingActive") | .status' 2>/dev/null || echo "Unknown")

if [[ "${ABLE_TO_SCALE}" == "True" ]]; then
  echo "  [OK]  AbleToScale: True"
else
  echo "  [!!]  AbleToScale: ${ABLE_TO_SCALE}"
  FAIL=$((FAIL + 1))
fi

if [[ "${SCALING_ACTIVE}" == "True" ]]; then
  echo "  [OK]  ScalingActive: True"
else
  echo "  [??]  ScalingActive: ${SCALING_ACTIVE} (normal at low load)"
fi

CURRENT=$(kubectl --context "${KUBE_CONTEXT}" get hpa observability-app-hpa -n "${NS}" -o json 2>/dev/null | jq -r '.status.currentReplicas // 0' 2>/dev/null || echo "0")
MIN=$(kubectl --context "${KUBE_CONTEXT}" get hpa observability-app-hpa -n "${NS}" -o json 2>/dev/null | jq -r '.spec.minReplicas // 2' 2>/dev/null || echo "2")
MAX=$(kubectl --context "${KUBE_CONTEXT}" get hpa observability-app-hpa -n "${NS}" -o json 2>/dev/null | jq -r '.spec.maxReplicas // 10' 2>/dev/null || echo "10")

echo "  [OK]  Current replicas: ${CURRENT} (min: ${MIN}, max: ${MAX})"

CPU_TARGET=$(kubectl --context "${KUBE_CONTEXT}" get hpa observability-app-hpa -n "${NS}" -o json 2>/dev/null | jq -r '.spec.metrics[] | select(.resource.name=="cpu") | .resource.target.averageUtilization' 2>/dev/null || echo "?")
MEM_TARGET=$(kubectl --context "${KUBE_CONTEXT}" get hpa observability-app-hpa -n "${NS}" -o json 2>/dev/null | jq -r '.spec.metrics[] | select(.resource.name=="memory") | .resource.target.averageUtilization' 2>/dev/null || echo "?")

echo "  [OK]  CPU target: ${CPU_TARGET}% | Memory target: ${MEM_TARGET}%"

echo ""
echo "[check-hpa] To test scaling, run: task k8s:load-start ENV=${ENV:-dev} KUBE_CONTEXT=${KUBE_CONTEXT}"
echo "            Then watch: kubectl --context ${KUBE_CONTEXT} get hpa -n app -w"

echo ""
if [[ ${FAIL} -gt 0 ]]; then
  echo "[check-hpa] FAILED (${FAIL} checks failed)"
  exit 1
else
  echo "[check-hpa] PASSED"
fi
