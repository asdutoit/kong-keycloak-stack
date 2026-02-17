#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OVERLAY_DIR="$SCRIPT_DIR/../k8s/overlays/local"

DELETE_DATA=false
if [ "$1" = "--delete-data" ]; then
  DELETE_DATA=true
fi

echo "Removing Kong + Keycloak + Jenkins + Monitoring stack..."

# Delete all Kustomize-managed resources
kubectl delete -k "$OVERLAY_DIR" --ignore-not-found

if [ "$DELETE_DATA" = true ]; then
  echo "Deleting persistent data..."
  kubectl delete pvc postgres-data jenkins-home prometheus-data loki-data grafana-data -n kong-system --ignore-not-found
  kubectl delete namespace kong-system --ignore-not-found
  echo ""
  echo "Teardown complete. All data deleted."
else
  echo ""
  echo "Teardown complete."
  echo ""
  echo "PostgreSQL and Jenkins data preserved. To redeploy: ./scripts/deploy.sh"
  echo "To delete everything including data: ./scripts/teardown.sh --delete-data"
fi
