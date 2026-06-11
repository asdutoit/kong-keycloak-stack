#!/bin/bash
# Provisions the tapir-flow Keycloak realm, client, roles, and seed users.
# Idempotent — safe to run multiple times.
#
# Usage: ./create-keycloak-realm.sh <KEYCLOAK_URL> [ADMIN_USER:ADMIN_PASS] [CLIENT_SECRET]
#
# Arguments:
#   KEYCLOAK_URL   - e.g. http://localhost:8080
#   ADMIN_CREDS    - admin:admin (default)
#   CLIENT_SECRET  - client secret for tapir-flow-ui (default: 1NBikfXSJNQAaZSukEPoKQzKRvDPU6N8)

set -euo pipefail

KEYCLOAK_URL="${1:?Usage: $0 <KEYCLOAK_URL> [admin:pass] [client_secret]}"
ADMIN_CREDS="${2:-admin:admin}"
CLIENT_SECRET="${3:-1NBikfXSJNQAaZSukEPoKQzKRvDPU6N8}"
REALM="tapir-flow"
CLIENT_ID="tapir-flow-ui"

ADMIN_USER="${ADMIN_CREDS%%:*}"
ADMIN_PASS="${ADMIN_CREDS#*:}"

# --- Get admin token ---
get_token() {
  curl -sf -X POST "$KEYCLOAK_URL/realms/master/protocol/openid-connect/token" \
    -d "grant_type=password&client_id=admin-cli&username=$ADMIN_USER&password=$ADMIN_PASS" \
    | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])"
}

TOKEN=$(get_token)
AUTH="Authorization: Bearer $TOKEN"

# --- Helper: POST with conflict handling ---
kc_post() {
  local path="$1" data="$2" label="$3"
  local status
  status=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$KEYCLOAK_URL/admin/$path" \
    -H "$AUTH" -H "Content-Type: application/json" -d "$data")
  if [ "$status" = "201" ]; then
    echo "  Created: $label"
  elif [ "$status" = "409" ]; then
    echo "  Exists:  $label"
  else
    echo "  WARN:    $label (HTTP $status)"
  fi
}

echo "=== Provisioning Keycloak realm: $REALM ==="

# 1. Create realm
kc_post "realms" "{
  \"realm\": \"$REALM\",
  \"enabled\": true,
  \"displayName\": \"Tapir Flow\",
  \"registrationAllowed\": false,
  \"loginWithEmailAllowed\": true,
  \"duplicateEmailsAllowed\": false
}" "realm $REALM"

# Refresh token (realm creation can take a moment)
TOKEN=$(get_token)
AUTH="Authorization: Bearer $TOKEN"

# 2. Create client
kc_post "realms/$REALM/clients" "{
  \"clientId\": \"$CLIENT_ID\",
  \"name\": \"Tapir Flow UI\",
  \"enabled\": true,
  \"protocol\": \"openid-connect\",
  \"publicClient\": false,
  \"secret\": \"$CLIENT_SECRET\",
  \"directAccessGrantsEnabled\": true,
  \"standardFlowEnabled\": true,
  \"redirectUris\": [\"http://localhost:3000/*\", \"*\"],
  \"webOrigins\": [\"http://localhost:3000\", \"*\"],
  \"attributes\": {
    \"post.logout.redirect.uris\": \"http://localhost:3000/*\"
  }
}" "client $CLIENT_ID"

# 3. Add protocol mapper so realm roles appear in id_token/userinfo
#    (NextAuth reads roles from profile.realm_access.roles)
CLIENT_UUID=$(curl -sf "$KEYCLOAK_URL/admin/realms/$REALM/clients?clientId=$CLIENT_ID" \
  -H "$AUTH" | python3 -c "import sys,json; clients=json.load(sys.stdin); print(clients[0]['id'] if clients else '')")

if [ -n "$CLIENT_UUID" ]; then
  kc_post "realms/$REALM/clients/$CLIENT_UUID/protocol-mappers/models" '{
    "name": "realm roles",
    "protocol": "openid-connect",
    "protocolMapper": "oidc-usermodel-realm-role-mapper",
    "config": {
      "multivalued": "true",
      "claim.name": "realm_access.roles",
      "jsonType.label": "String",
      "id.token.claim": "true",
      "access.token.claim": "true",
      "userinfo.token.claim": "true"
    }
  }' "realm roles mapper"
fi

# 4. Create realm roles
for ROLE in developer approver; do
  kc_post "realms/$REALM/roles" "{\"name\": \"$ROLE\", \"description\": \"$ROLE role for Tapir Flow\"}" "role $ROLE"
done

# 5. Create seed users and assign roles
create_user_with_role() {
  local username="$1" email="$2" first="$3" last="$4" role="$5"

  kc_post "realms/$REALM/users" "{
    \"username\": \"$username\",
    \"email\": \"$email\",
    \"firstName\": \"$first\",
    \"lastName\": \"$last\",
    \"enabled\": true,
    \"emailVerified\": true,
    \"credentials\": [{\"type\": \"password\", \"value\": \"$username\", \"temporary\": false}]
  }" "user $username"

  # Assign role (need user ID + role representation)
  local user_id role_json
  user_id=$(curl -sf "$KEYCLOAK_URL/admin/realms/$REALM/users?username=$username&exact=true" \
    -H "$AUTH" | python3 -c "import sys,json; users=json.load(sys.stdin); print(users[0]['id'] if users else '')")

  if [ -n "$user_id" ]; then
    role_json=$(curl -sf "$KEYCLOAK_URL/admin/realms/$REALM/roles/$role" -H "$AUTH")
    local status
    status=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
      "$KEYCLOAK_URL/admin/realms/$REALM/users/$user_id/role-mappings/realm" \
      -H "$AUTH" -H "Content-Type: application/json" -d "[$role_json]")
    if [ "$status" = "204" ] || [ "$status" = "200" ]; then
      echo "  Assigned: role $role -> $username"
    else
      echo "  WARN:    role assignment $role -> $username (HTTP $status)"
    fi
  fi
}

create_user_with_role "developer" "developer@tapir.local" "Dev" "User" "developer"
create_user_with_role "approver" "approver@tapir.local" "Approver" "User" "approver"

echo "=== Keycloak provisioning complete ==="
echo "  Users: developer/developer, approver/approver"
echo "  Client: $CLIENT_ID (secret: $CLIENT_SECRET)"
