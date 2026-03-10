#!/usr/bin/env bash
# build the image, optionaly push if BUILD_PUSH=1
set -euo pipefail

IMAGE_TAG="${IMAGE_TAG:-local}"
DOCKERHUB_USER="${DOCKERHUB_USER:-rick0x00}"
IMAGE_REF="${IMAGE_REF:-docker.io/${DOCKERHUB_USER}/observability-lab:${IMAGE_TAG}}"
CACHE_REF="${CACHE_REF:-docker.io/${DOCKERHUB_USER}/observability-lab:buildcache}"
LATEST_REF="docker.io/${DOCKERHUB_USER}/observability-lab:latest"
BUILD_PUSH="${BUILD_PUSH:-0}"
EXTRA_TAGS="${EXTRA_TAGS:-}"

if ! docker buildx inspect ci-builder >/dev/null 2>&1; then
  docker buildx create --name ci-builder --driver docker-container --use
else
  docker buildx use ci-builder
fi

build_args=(
  buildx build
  --build-arg PORT=8080
  --tag "${IMAGE_REF}"
)

# optional extra tags, space separated
if [[ -n "${EXTRA_TAGS}" ]]; then
  for tag in ${EXTRA_TAGS}; do
    build_args+=(--tag "${tag}")
  done
fi

# use cache if avalable, speeds up builds
if docker buildx imagetools inspect "${CACHE_REF}" >/dev/null 2>&1; then
  build_args+=(--cache-from "type=registry,ref=${CACHE_REF}")
fi

if [[ "${BUILD_PUSH}" == "1" ]]; then
  build_args+=(
    --tag "${LATEST_REF}"
    --cache-to "type=registry,ref=${CACHE_REF},mode=max"
    --push
  )
else
  build_args+=(--load)
fi

docker "${build_args[@]}" .
