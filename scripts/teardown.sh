#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS_DIR="$SCRIPT_DIR/../manifests"

DELETE_DATA=false
if [ "$1" = "--delete-data" ]; then
  DELETE_DATA=true
fi

echo "Removing Kong + Keycloak + Jenkins stack..."

# Delete deployments and services (but not PVC)
kubectl delete deployment jenkins kong keycloak postgres httpbin -n kong-system --ignore-not-found
kubectl delete service jenkins kong-proxy kong-admin kong-manager keycloak postgres httpbin -n kong-system --ignore-not-found
kubectl delete configmap jenkins-casc jenkins-plugins postgres-init -n kong-system --ignore-not-found

if [ "$DELETE_DATA" = true ]; then
  echo "Deleting persistent data and namespace..."
  kubectl delete pvc postgres-data jenkins-home -n kong-system --ignore-not-found
  kubectl delete -f "$MANIFESTS_DIR/namespace.yaml" --ignore-not-found
  echo ""
  echo "Teardown complete. All data deleted."
else
  echo ""
  echo "Teardown complete."
  echo ""
  echo "PostgreSQL and Jenkins data preserved. To redeploy: ./scripts/deploy.sh"
  echo "To delete everything including data: ./scripts/teardown.sh --delete-data"
fi
