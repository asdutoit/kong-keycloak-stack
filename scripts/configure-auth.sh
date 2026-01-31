#!/bin/bash

# IMPORTANT: Before running this script, start the port-forward:
# ./scripts/port-forward.sh
# Or: kubectl port-forward -n kong-system svc/kong-admin 8001:8001

KONG_ADMIN="http://localhost:8001"

# Check if Kong Admin API is reachable
if ! curl -s "$KONG_ADMIN/status" > /dev/null 2>&1; then
  echo "ERROR: Cannot reach Kong Admin API at $KONG_ADMIN"
  echo ""
  echo "Please run this first:"
  echo "  ./scripts/port-forward.sh"
  echo "Or:"
  echo "  kubectl port-forward -n kong-system svc/kong-admin 8001:8001 &"
  echo ""
  exit 1
fi

echo "Adding httpbin service to Kong..."

# 1. Create Service
echo "Creating service..."
curl -s -X POST $KONG_ADMIN/services \
  --data "name=httpbin" \
  --data "url=http://httpbin.kong-system.svc.cluster.local" | jq .

# 2. Create Route
echo "Creating route..."
curl -s -X POST $KONG_ADMIN/services/httpbin/routes \
  --data "name=httpbin-route" \
  --data "paths[]=/api/httpbin" \
  --data "strip_path=true" | jq .

echo -e "\n=== API Key Authentication ==="

# 3. Enable API Key plugin
echo "Enabling key-auth plugin..."
curl -s -X POST $KONG_ADMIN/services/httpbin/plugins \
  --data "name=key-auth" | jq .

# 4. Create consumer and API key
echo "Creating consumer..."
curl -s -X POST $KONG_ADMIN/consumers \
  --data "username=demo-user" | jq .

echo "Creating API key..."
curl -s -X POST $KONG_ADMIN/consumers/demo-user/key-auth \
  --data "key=my-api-key-123" | jq .

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Test with:"
echo "  curl -H 'apikey: my-api-key-123' http://localhost:8000/api/httpbin/get"
echo ""
echo "Without API key (should return 401):"
echo "  curl http://localhost:8000/api/httpbin/get"

echo -e "\n\n=== JWT Authentication (Alternative) ==="
echo "To switch from API Key to JWT authentication:"
echo ""
echo "# 1. List and remove the key-auth plugin:"
echo "curl -s $KONG_ADMIN/services/httpbin/plugins | jq '.data[] | select(.name==\"key-auth\") | .id'"
echo "curl -X DELETE $KONG_ADMIN/plugins/{plugin-id}"
echo ""
echo "# 2. Add JWT plugin:"
echo "curl -X POST $KONG_ADMIN/services/httpbin/plugins --data 'name=jwt'"
echo ""
echo "# 3. Create JWT credential for the consumer:"
echo "curl -X POST $KONG_ADMIN/consumers/demo-user/jwt"

echo -e "\n\n=== Keycloak Integration (JWT-based) ==="
echo "For Keycloak integration with Kong OSS, use JWT plugin with Keycloak tokens:"
echo ""
echo "# 1. In Keycloak, create a realm and client"
echo "# 2. Get the realm's public key from:"
echo "#    http://localhost:8080/realms/{realm}/.well-known/openid-configuration"
echo ""
echo "# 3. Create a consumer with JWT credentials using Keycloak's issuer:"
echo "curl -X POST $KONG_ADMIN/consumers/keycloak-user/jwt \\"
echo "  --data 'algorithm=RS256' \\"
echo "  --data 'key=http://keycloak.kong-system.svc.cluster.local:8080/realms/{realm}' \\"
echo "  --data 'rsa_public_key=-----BEGIN PUBLIC KEY-----...-----END PUBLIC KEY-----'"
