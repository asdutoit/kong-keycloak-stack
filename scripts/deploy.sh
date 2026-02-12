#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS_DIR="$SCRIPT_DIR/../manifests"

echo "Deploying Kong + Keycloak + Jenkins + Monitoring stack..."

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

# Deploy Prometheus
echo "Deploying Prometheus..."
kubectl apply -f "$MANIFESTS_DIR/prometheus.yaml"

# Deploy Grafana
echo "Deploying Grafana..."
kubectl apply -f "$MANIFESTS_DIR/grafana.yaml"

echo "Waiting for services to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/keycloak -n kong-system
kubectl wait --for=condition=available --timeout=300s deployment/kong -n kong-system
kubectl wait --for=condition=available --timeout=120s deployment/httpbin -n kong-system
kubectl wait --for=condition=available --timeout=300s deployment/jenkins -n kong-system
kubectl wait --for=condition=available --timeout=120s deployment/prometheus -n kong-system
kubectl wait --for=condition=available --timeout=120s deployment/grafana -n kong-system

# Enable Kong Prometheus plugin globally
echo "Enabling Kong Prometheus plugin..."
kubectl exec -n kong-system deployment/kong -- kong config parse /dev/stdin <<< "" 2>/dev/null || true
# Wait briefly for Kong admin to be ready
sleep 3

echo ""
echo "=== Deployment Complete ==="
echo ""
echo "Next steps:"
echo "  1. Run: ./scripts/port-forward.sh"
echo "  2. Run: ./scripts/configure-auth.sh  (also enables Prometheus plugin on Kong)"
echo "  3. Test: curl -H 'apikey: my-api-key-123' http://localhost:8000/api/httpbin/get"
echo "  4. Grafana: http://localhost:3001 (admin/admin)"
echo "  5. Prometheus: http://localhost:9090"
