#!/usr/bin/env bash
# Build the api-portal Keycloak login theme and bake it into a local image.
#
# For Docker Desktop K8s the cluster shares the local docker image store, so a
# plain `docker build` is enough — no push / no kind load. After building, the
# keycloak Deployment (k8s/base/keycloak.yaml) references keycloak-api-portal:reg
# with imagePullPolicy: IfNotPresent, so a rollout restart picks it up.
#
# Usage: ./scripts/utils/build-keycloak-theme.sh [image-tag]   (default: keycloak-api-portal:reg)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
THEME_DIR="$(cd "$SCRIPT_DIR/../../keycloak-theme" && pwd)"
IMAGE="${1:-keycloak-api-portal:reg}"

echo "=== Building Keycloakify theme (requires Node + Maven) ==="
cd "$THEME_DIR"
npm run build-keycloak-theme

echo "=== Extracting theme dir from the built JAR ==="
# keycloakify reliably emits only the JAR in dist_keycloak/ — the extracted
# theme/<name> dir is not guaranteed to be left behind. The Dockerfile COPYs
# dist_keycloak/theme/api-portal, so recreate it from the JAR every build.
rm -rf dist_keycloak/theme
( cd dist_keycloak && unzip -qo keycloak-theme-for-kc-all-other-versions.jar 'theme/*' )
# unzip preserves the JAR's stored perms, which under a strict umask can be
# 0600 (owner-only). The Dockerfile COPYs these as root, but Keycloak runs as
# uid 1000 — owner-only files then 500 with "Permission denied" and the login
# page renders blank/unstyled. Force world-readable (dirs 755 / files 644).
chmod -R a+rX dist_keycloak/theme

echo "=== Building image $IMAGE (theme baked as a raw themes/ dir) ==="
docker build -f Dockerfile.local -t "$IMAGE" .

echo "Done: $IMAGE"
echo ""
echo "NOTE: Docker Desktop K8s caches images by TAG — a rollout restart will NOT"
echo "pick up a rebuilt same-tag image (imagePullPolicy IfNotPresent reuses the"
echo "cached one). On a meaningful theme change, BUMP THE TAG, e.g.:"
echo "  ./scripts/utils/build-keycloak-theme.sh keycloak-api-portal:reg2"
echo "  kubectl -n kong-system set image deploy/keycloak keycloak=keycloak-api-portal:reg2"
echo "  (and update k8s/base/keycloak.yaml to match)"
echo "Scope theme to client:  ./scripts/utils/set-login-theme.sh"
