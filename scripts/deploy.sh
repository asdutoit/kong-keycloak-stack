#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS_DIR="$SCRIPT_DIR/../manifests"

echo "Deploying Kong + Keycloak + Jenkins stack..."

# Apply namespace first
kubectl apply -f "$MANIFESTS_DIR/namespace.yaml"

# Deploy PostgreSQL (required for Kong)
echo "Deploying PostgreSQL..."
kubectl apply -f "$MANIFESTS_DIR/postgres.yaml"
kubectl wait --for=condition=available --timeout=120s deployment/postgres -n kong-system

# Deploy Keycloak
echo "Deploying Keycloak..."
kubectl apply -f "$MANIFESTS_DIR/keycloak.yaml"

# Deploy Kong (migrations run as init container)
echo "Deploying Kong..."
kubectl apply -f "$MANIFESTS_DIR/kong.yaml"

# Deploy httpbin
echo "Deploying httpbin..."
kubectl apply -f "$MANIFESTS_DIR/httpbin.yaml"

# Deploy Jenkins
echo "Deploying Jenkins..."
kubectl apply -f "$MANIFESTS_DIR/jenkins.yaml"

echo "Waiting for services to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/keycloak -n kong-system
kubectl wait --for=condition=available --timeout=300s deployment/kong -n kong-system
kubectl wait --for=condition=available --timeout=120s deployment/httpbin -n kong-system
kubectl wait --for=condition=available --timeout=300s deployment/jenkins -n kong-system

echo ""
echo "=== Deployment Complete ==="
echo ""
echo "Next steps:"
echo "  1. Run: ./scripts/port-forward.sh"
echo "  2. Run: ./scripts/configure-auth.sh"
echo "  3. Test: curl -H 'apikey: my-api-key-123' http://localhost:8000/api/httpbin/get"
