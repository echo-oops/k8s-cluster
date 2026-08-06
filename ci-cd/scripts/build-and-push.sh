#!/usr/bin/env bash
#
# build-and-push.sh
#
# Build a Docker image and push it to a container registry.
# Works both locally (docker) and in CI (Kaniko). Detects environment and uses the best available builder.
#
# Usage:
#   ./ci-cd/scripts/build-and-push.sh <image> <tag> [--context <path>] [--dockerfile <path>] [--push-only]
#
# Examples:
#   ./ci-cd/scripts/build-and-push.sh registry.example.com/project/frontend abc123
#   ./ci-cd/scripts/build-and-push.sh registry.example.com/project/backend abc123 --context ./backend --dockerfile ./backend/Dockerfile
#
# Environment variables:
#   CI_REGISTRY            - registry host (optional)
#   CI_REGISTRY_USER       - registry username (optional)
#   CI_REGISTRY_PASSWORD   - registry password (optional)
#   DOCKER_BUILDKIT        - if set, enables BuildKit for local docker builds
#   KANIKO_EXECUTOR        - path to kaniko executor (default: /kaniko/executor)
#
set -euo pipefail

# Defaults
IMAGE="${1:-}"
TAG="${2:-}"
CONTEXT="."
DOCKERFILE="Dockerfile"
PUSH_ONLY=false
KANIKO_EXECUTOR="${KANIKO_EXECUTOR:-/kaniko/executor}"
DOCKER_CMD="${DOCKER_CMD:-docker}"

if [[ -z "${IMAGE}" || -z "${TAG}" ]]; then
  echo "Usage: $0 <image> <tag> [--context <path>] [--dockerfile <path>] [--push-only]"
  exit 2
fi

shift 2
while [[ $# -gt 0 ]]; do
  case "$1" in
    --context) CONTEXT="$2"; shift 2;;
    --dockerfile) DOCKERFILE="$2"; shift 2;;
    --push-only) PUSH_ONLY=true; shift 1;;
    *) echo "Unknown argument: $1"; exit 2;;
  esac
done

FULL_IMAGE="${IMAGE}:${TAG}"
LATEST_IMAGE="${IMAGE}:latest"

echo "Build-and-push starting"
echo "  Image: ${FULL_IMAGE}"
echo "  Context: ${CONTEXT}"
echo "  Dockerfile: ${DOCKERFILE}"
echo "  Push-only: ${PUSH_ONLY}"

# Helper: login to registry if credentials provided
registry_login() {
  if [[ -n "${CI_REGISTRY:-}" && -n "${CI_REGISTRY_USER:-}" && -n "${CI_REGISTRY_PASSWORD:-}" ]]; then
    echo "Logging into registry ${CI_REGISTRY} using CI credentials"
    if command -v docker >/dev/null 2>&1; then
      echo "${CI_REGISTRY_PASSWORD}" | docker login -u "${CI_REGISTRY_USER}" --password-stdin "${CI_REGISTRY}"
    else
      # For Kaniko, write config.json
      mkdir -p /kaniko/.docker
      echo "{\"auths\":{\"${CI_REGISTRY}\":{\"username\":\"${CI_REGISTRY_USER}\",\"password\":\"${CI_REGISTRY_PASSWORD}\"}}}" > /kaniko/.docker/config.json
      chmod 600 /kaniko/.docker/config.json
    fi
  else
    echo "No CI registry credentials detected in environment; assuming local docker is already authenticated or registry is public."
  fi
}

# Helper: push image using docker
docker_push() {
  local img="$1"
  echo "Pushing ${img} with docker"
  docker push "${img}"
}

# Helper: build with docker (BuildKit if available)
docker_build() {
  local img="$1"
  echo "Building ${img} with docker"
  export DOCKER_BUILDKIT=${DOCKER_BUILDKIT:-1}
  docker build --progress=plain -t "${img}" -f "${DOCKERFILE}" "${CONTEXT}"
}

# Helper: build with kaniko
kaniko_build() {
  local img="$1"
  echo "Building ${img} with Kaniko at ${KANIKO_EXECUTOR}"
  # Ensure /kaniko/.docker/config.json exists if registry auth required
  if [[ -n "${CI_REGISTRY:-}" && -n "${CI_REGISTRY_USER:-}" && -n "${CI_REGISTRY_PASSWORD:-}" ]]; then
    mkdir -p /kaniko/.docker
    echo "{\"auths\":{\"${CI_REGISTRY}\":{\"username\":\"${CI_REGISTRY_USER}\",\"password\":\"${CI_REGISTRY_PASSWORD}\"}}}" > /kaniko/.docker/config.json
    chmod 600 /kaniko/.docker/config.json
  fi

  # Kaniko flags: context can be local path or git URL; use --context dir:// for local
  if [[ -d "${CONTEXT}" ]]; then
    CONTEXT_URI="dir://${CONTEXT}"
  else
    CONTEXT_URI="${CONTEXT}"
  fi

  "${KANIKO_EXECUTOR}" \
    --context "${CONTEXT_URI}" \
    --dockerfile "${DOCKERFILE}" \
    --destination "${img}" \
    --cache=true \
    --cache-repo "${IMAGE}/cache" \
    --verbosity info
}

# Decide builder: prefer Kaniko in CI (presence of /kaniko/executor or CI env), otherwise docker
detect_builder() {
  if [[ "${PUSH_ONLY}" == "true" ]]; then
    echo "Push-only mode: skipping build"
    return 0
  fi

  if [[ -n "${CI_REGISTRY:-}" && -f "${KANIKO_EXECUTOR}" ]]; then
    echo "Detected Kaniko executor and CI registry - will use Kaniko"
    BUILDER="kaniko"
  elif command -v docker >/dev/null 2>&1; then
    echo "Docker available - will use docker build"
    BUILDER="docker"
  elif [[ -f "${KANIKO_EXECUTOR}" ]]; then
    echo "Kaniko executor found at ${KANIKO_EXECUTOR} - will use Kaniko"
    BUILDER="kaniko"
  else
    echo "No supported builder found (docker or kaniko). Install docker or provide Kaniko executor."
    exit 3
  fi
}

# Main flow
registry_login
detect_builder

if [[ "${PUSH_ONLY}" != "true" ]]; then
  if [[ "${BUILDER:-}" == "kaniko" ]]; then
    kaniko_build "${FULL_IMAGE}"
  else
    docker_build "${FULL_IMAGE}"
  fi
fi

# Tag latest if desired and push both tags
if [[ "${BUILDER:-}" == "docker" && "${PUSH_ONLY}" != "true" ]]; then
  echo "Tagging ${FULL_IMAGE} as ${LATEST_IMAGE}"
  docker tag "${FULL_IMAGE}" "${LATEST_IMAGE}" || true
fi

# Push images
if [[ "${BUILDER:-}" == "kaniko" ]]; then
  # Kaniko already pushed the built tag; push latest via docker if available
  if command -v docker >/dev/null 2>&1; then
    echo "Tagging and pushing latest tag via docker"
    docker pull "${FULL_IMAGE}"
    docker tag "${FULL_IMAGE}" "${LATEST_IMAGE}" || true
    docker_push "${LATEST_IMAGE}"
  else
    echo "Docker not available to push latest tag; skipping latest tag push"
  fi
else
  docker_push "${FULL_IMAGE}"
  # push latest if exists
  if docker image inspect "${LATEST_IMAGE}" >/dev/null 2>&1; then
    docker_push "${LATEST_IMAGE}"
  fi
fi

echo "Build and push completed: ${FULL_IMAGE}"
exit 0
