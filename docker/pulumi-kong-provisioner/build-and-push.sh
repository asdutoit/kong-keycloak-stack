#!/bin/bash
set -e

REGISTRY="tcr.paas.local:7001"
DOCKERHUB_USER="asdutoit"
IMAGE_NAME="tmac/pulumi-kong-provisioner"
DOCKERHUB_IMAGE="${DOCKERHUB_USER}/pulumi-kong-provisioner"
TAG="${1:-latest}"
TARGET="${2:-all}"

FULL_IMAGE="$REGISTRY/$IMAGE_NAME:$TAG"

# ─── Local (arm64 for Docker Desktop K8s) ───
if [ "$TARGET" = "all" ] || [ "$TARGET" = "local" ]; then
  echo "=== Building local arm64 image ==="
  docker build -t "${DOCKERHUB_IMAGE}:${TAG}" .
  echo "Done: ${DOCKERHUB_IMAGE}:${TAG} (local arm64)"
fi

# ─── Org (amd64 for TCR / org K8s clusters) ───
if [ "$TARGET" = "all" ] || [ "$TARGET" = "org" ]; then
  echo "=== Building org amd64 image ==="
  docker build --platform linux/amd64 -t "$FULL_IMAGE" .
  echo "Pushing $FULL_IMAGE ..."
  docker push "$FULL_IMAGE"
  echo "Done: $FULL_IMAGE (org amd64)"
fi

echo "=== Build complete ==="
