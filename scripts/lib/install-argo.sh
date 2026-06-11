#!/bin/bash
# Install the Argo stack (Argo CD, Argo Workflows, Argo Rollouts) via Helm.
#
# Idempotent — safe to re-run (uses `helm upgrade --install`). Targets the
# current kubectl context, so deploy.sh's context selection is honoured.
#
# Pinned chart versions below; bump them deliberately to track production.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALUES_DIR="$SCRIPT_DIR/../../argo/values"

# ─── Pinned chart versions (argo-helm) ───────────────────────────────────────
ARGOCD_CHART_VERSION="9.5.20"          # app v3.4.3
ARGO_WORKFLOWS_CHART_VERSION="1.0.14"  # app v4.0.5
ARGO_ROLLOUTS_CHART_VERSION="2.41.0"   # app v1.9.0

HELM_TIMEOUT="10m"

command -v helm >/dev/null 2>&1 || {
  echo "ERROR: helm is required — https://helm.sh/docs/intro/install/" >&2
  exit 1
}

echo "Installing Argo stack into context: $(kubectl config current-context)"

helm repo add argo https://argoproj.github.io/argo-helm >/dev/null 2>&1 || true
helm repo update argo >/dev/null

install_chart() {
  local release="$1" chart="$2" version="$3" namespace="$4" values="$5"
  echo "→ ${release} (${chart} ${version}) → namespace/${namespace}"
  helm upgrade --install "$release" "argo/${chart}" \
    --version "$version" \
    --namespace "$namespace" --create-namespace \
    --values "$values" \
    --wait --timeout "$HELM_TIMEOUT"
}

install_chart argocd         argo-cd        "$ARGOCD_CHART_VERSION"         argocd        "$VALUES_DIR/argo-cd.yaml"
install_chart argo-workflows argo-workflows "$ARGO_WORKFLOWS_CHART_VERSION" argo          "$VALUES_DIR/argo-workflows.yaml"
install_chart argo-rollouts  argo-rollouts  "$ARGO_ROLLOUTS_CHART_VERSION"  argo-rollouts "$VALUES_DIR/argo-rollouts.yaml"

echo
echo "Argo stack installed:"
echo "  • Argo CD        → kubectl -n argocd port-forward svc/argocd-server 8080:443"
echo "    admin password → kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
echo "  • Argo Workflows → kubectl -n argo port-forward svc/argo-workflows-server 2746:2746"
echo "  • Argo Rollouts  → kubectl argo rollouts dashboard"
