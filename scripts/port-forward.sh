#!/bin/bash

echo "Starting port-forwards for Kong + Keycloak + Jenkins + Monitoring stack..."
echo ""

# Kill any existing port-forwards on these ports
pkill -f "port-forward.*kong-system" 2>/dev/null || true

# Start port-forwards in background
kubectl port-forward -n kong-system --address 0.0.0.0 svc/keycloak 8080:8080 &
kubectl port-forward -n kong-system svc/kong-proxy 8000:8000 &
kubectl port-forward -n kong-system svc/kong-admin 8001:8001 &
kubectl port-forward -n kong-system svc/kong-manager 8002:8002 &
kubectl port-forward -n kong-system svc/jenkins 8081:8081 &
# kubectl port-forward -n kong-system svc/postgres 5433:5432 &
kubectl port-forward -n kong-system svc/httpbin 8082:80 &
kubectl port-forward -n kong-system svc/prometheus 9090:9090 &
kubectl port-forward -n kong-system svc/loki 3100:3100 &
kubectl port-forward -n kong-system svc/grafana 3002:3001 &

sleep 2

echo "Port-forwards started:"
echo "  - Keycloak:     http://localhost:8080 (admin/admin)"
echo "  - Kong Proxy:   http://localhost:8000"
echo "  - Kong Admin:   http://localhost:8001"
echo "  - Kong Manager: http://localhost:8002"
echo "  - Jenkins:      http://localhost:8081"
echo "  - PostgreSQL:   localhost:5433"
echo "  - httpbin:      http://localhost:8082"
echo "  - Prometheus:   http://localhost:9090"
echo "  - Loki:         http://localhost:3100"
echo "  - Grafana:      http://localhost:3002 (admin/admin)"
echo ""
echo "PostgreSQL Databases:"
echo "  - Kong DB:      postgres://kong:kongpass@localhost:5433/kong"
echo "  - App DB:       postgres://appuser:apppass@localhost:5433/appdb"
echo ""
echo "To stop all port-forwards: pkill -f 'port-forward.*kong-system'"
echo ""
echo "Press Ctrl+C to stop all port-forwards..."

# Wait for all background jobs
wait
