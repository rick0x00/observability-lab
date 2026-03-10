#!/usr/bin/env bash
# run hadolint on Dockerfile and shellcheck on scripts
set -euo pipefail

hadolint Dockerfile
find var/scripts -type f \( -name "*.sh" -o -name "lab-load" -o -name "lab-validate" \) -print0 | xargs -0 shellcheck --severity=warning
find ci/scripts -type f -name "*.sh" -print0 | xargs -0 shellcheck --severity=warning
