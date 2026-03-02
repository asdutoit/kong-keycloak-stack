#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OVERLAY_DIR="$SCRIPT_DIR/../k8s/overlays/local"

# ─── Select Kubernetes Context ───────────────────────────────────────────────
CONTEXTS=($(kubectl config get-contexts -o name))

if [ ${#CONTEXTS[@]} -eq 0 ]; then
  echo "Error: No Kubernetes contexts found. Configure a cluster first."
  exit 1
fi

echo "Available Kubernetes contexts:"
for i in "${!CONTEXTS[@]}"; do
  current=""
  if [ "${CONTEXTS[$i]}" = "$(kubectl config current-context)" ]; then
    current=" (current)"
  fi
  echo "  $((i + 1))) ${CONTEXTS[$i]}$current"
done

echo ""
read -rp "Select context [1-${#CONTEXTS[@]}]: " selection

if ! [[ "$selection" =~ ^[0-9]+$ ]] || [ "$selection" -lt 1 ] || [ "$selection" -gt ${#CONTEXTS[@]} ]; then
  echo "Error: Invalid selection."
  exit 1
fi

SELECTED_CONTEXT="${CONTEXTS[$((selection - 1))]}"
echo "Switching to context: $SELECTED_CONTEXT"
kubectl config use-context "$SELECTED_CONTEXT"
echo ""

# ─── Deploy Stack ────────────────────────────────────────────────────────────
echo "Deploying Kong + Keycloak + Jenkins + Monitoring stack..."

# Apply all resources via Kustomize
kubectl apply -k "$OVERLAY_DIR"

echo "Waiting for services to be ready..."
kubectl wait --for=condition=available --timeout=120s deployment/postgres -n kong-system
kubectl wait --for=condition=available --timeout=300s deployment/keycloak -n kong-system
kubectl wait --for=condition=available --timeout=300s deployment/kong -n kong-system
kubectl wait --for=condition=available --timeout=120s deployment/httpbin -n kong-system
kubectl wait --for=condition=available --timeout=300s deployment/jenkins -n kong-system
kubectl wait --for=condition=available --timeout=120s deployment/prometheus -n kong-system
kubectl wait --for=condition=available --timeout=120s deployment/loki -n kong-system
kubectl wait --for=condition=available --timeout=120s deployment/grafana -n kong-system

# Enable Kong Prometheus plugin globally
echo "Enabling Kong Prometheus plugin..."
kubectl exec -n kong-system deployment/kong -- kong config parse /dev/stdin <<< "" 2>/dev/null || true
# Wait briefly for Kong admin to be ready
sleep 3

# Port-forward Grafana temporarily for API access
kubectl port-forward -n kong-system svc/grafana 3199:3001 &>/dev/null &
GRAFANA_PF_PID=$!
sleep 2

GRAFANA_URL="http://localhost:3199"
GRAFANA_AUTH="admin:admin"

# Create Grafana service account and store token as K8s secret
if kubectl get secret grafana-credentials -n kong-system &>/dev/null; then
  echo "Grafana credentials secret already exists, skipping..."
  GRAFANA_TOKEN=$(kubectl get secret grafana-credentials -n kong-system -o jsonpath='{.data.api-key}' | base64 -d)
else
  echo "Creating Grafana service account and API token..."

  # Create service account
  SA_RESPONSE=$(curl -sf -u "$GRAFANA_AUTH" \
    -H "Content-Type: application/json" \
    -d '{"name":"k8s-automation","role":"Admin"}' \
    "$GRAFANA_URL/api/serviceaccounts")
  SA_ID=$(echo "$SA_RESPONSE" | grep -o '"id":[0-9]*' | head -1 | cut -d: -f2)

  if [ -n "$SA_ID" ]; then
    # Generate token for the service account
    TOKEN_RESPONSE=$(curl -sf -u "$GRAFANA_AUTH" \
      -H "Content-Type: application/json" \
      -d '{"name":"k8s-automation-token"}' \
      "$GRAFANA_URL/api/serviceaccounts/$SA_ID/tokens")
    GRAFANA_TOKEN=$(echo "$TOKEN_RESPONSE" | grep -o '"key":"[^"]*"' | cut -d'"' -f4)

    if [ -n "$GRAFANA_TOKEN" ]; then
      kubectl create secret generic grafana-credentials \
        --namespace kong-system \
        --from-literal=api-key="$GRAFANA_TOKEN"
      echo "Grafana credentials secret created."
    else
      echo "WARNING: Failed to create Grafana API token."
    fi
  else
    echo "WARNING: Failed to create Grafana service account."
  fi
fi

# Create tapir-flow-alerts folder (runs on every deploy, idempotent)
if [ -n "$GRAFANA_TOKEN" ]; then
  FOLDER_STATUS=$(curl -sf -o /dev/null -w "%{http_code}" \
    -H "Authorization: Bearer $GRAFANA_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"uid":"tapir-flow-alerts","title":"Tapir Flow Alerts"}' \
    "$GRAFANA_URL/api/folders")
  if [ "$FOLDER_STATUS" = "200" ]; then
    echo "Grafana folder 'Tapir Flow Alerts' created."
  elif [ "$FOLDER_STATUS" = "409" ]; then
    echo "Grafana folder 'Tapir Flow Alerts' already exists."
  else
    echo "WARNING: Failed to create Grafana folder (HTTP $FOLDER_STATUS)."
  fi
fi

kill $GRAFANA_PF_PID 2>/dev/null || true

# ─── Provision Keycloak Realm ─────────────────────────────────────────────────
# Port-forward Keycloak temporarily for API access
kubectl port-forward -n kong-system svc/keycloak 8198:8080 &>/dev/null &
KC_PF_PID=$!
sleep 2

echo "Provisioning Keycloak realm..."
"$SCRIPT_DIR/create-keycloak-realm.sh" "http://localhost:8198" "admin:admin"

kill $KC_PF_PID 2>/dev/null || true

# ─── Create Jenkins Pipeline Jobs ────────────────────────────────────────────
JENKINS_DIR="$SCRIPT_DIR/../jenkins"
JENKINS_AUTH="admin:admin"

# Port-forward Jenkins temporarily for API access
kubectl port-forward -n kong-system svc/jenkins 8199:8081 &>/dev/null &
JENKINS_PF_PID=$!
sleep 3

JENKINS_URL="http://localhost:8199"

# Wait for Jenkins to be fully ready (it can take a while after the pod is "available")
echo "Waiting for Jenkins API to be ready..."
for i in $(seq 1 30); do
  if curl -sf -u "$JENKINS_AUTH" "$JENKINS_URL/api/json" &>/dev/null; then
    echo "Jenkins API is ready."
    break
  fi
  if [ "$i" = "30" ]; then
    echo "WARNING: Jenkins API not ready after 60s, skipping job creation."
    kill $JENKINS_PF_PID 2>/dev/null || true
  fi
  sleep 2
done

# Generate job config XML files and create/update jobs via Jenkins API
python3 "$SCRIPT_DIR/create-jenkins-jobs.py" "$JENKINS_DIR" "$JENKINS_URL" "$JENKINS_AUTH"

kill $JENKINS_PF_PID 2>/dev/null || true

echo ""
echo "=== Deployment Complete ==="
echo ""
echo "Next steps:"
echo "  1. Run: ./scripts/port-forward.sh"
echo "  2. Run: ./scripts/configure-auth.sh  (also enables Prometheus plugin on Kong)"
echo "  3. Test: curl -H 'apikey: my-api-key-123' http://localhost:8000/api/httpbin/get"
echo "  4. Grafana: http://localhost:3001 (admin/admin)"
echo "  5. Prometheus: http://localhost:9090"
echo "  6. Loki:       http://localhost:3100 (via Grafana Explore)"
