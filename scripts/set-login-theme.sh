#!/usr/bin/env bash
# Scope the api-portal login theme to the api-onboarding client only (master realm),
# so nothing else in Keycloak changes — not even the KC admin login.
#
# Idempotent. Requires the keycloak port-forward on :8080 and admin creds.
# Usage: ./scripts/set-login-theme.sh [theme-name]   (default: api-portal)
set -euo pipefail

KC="${KC_URL:-http://localhost:8080}"
REALM="${KC_REALM:-master}"
CLIENT_ID="${KC_CLIENT_ID:-api-onboarding}"
THEME="${1:-api-portal}"
ADMIN_USER="${KC_ADMIN_USER:-admin}"
ADMIN_PASS="${KC_ADMIN_PASS:-admin}"

TOKEN=$(curl -s "$KC/realms/master/protocol/openid-connect/token" \
  -d client_id=admin-cli -d "username=$ADMIN_USER" -d "password=$ADMIN_PASS" \
  -d grant_type=password | python3 -c "import sys,json;print(json.load(sys.stdin)['access_token'])")

UUID=$(curl -s "$KC/admin/realms/$REALM/clients?clientId=$CLIENT_ID" \
  -H "Authorization: Bearer $TOKEN" | python3 -c "import sys,json;c=json.load(sys.stdin);print(c[0]['id'] if c else '')")
[ -z "$UUID" ] && { echo "client $CLIENT_ID not found in realm $REALM"; exit 1; }

REP=$(curl -s "$KC/admin/realms/$REALM/clients/$UUID" -H "Authorization: Bearer $TOKEN")
echo "$REP" | python3 -c "
import sys,json
c=json.load(sys.stdin); c.setdefault('attributes',{})['login_theme']='$THEME'
open('/tmp/_kc_client.json','w').write(json.dumps(c))
"
curl -s -o /dev/null -w "set login_theme=$THEME on $CLIENT_ID -> %{http_code}\n" \
  -X PUT "$KC/admin/realms/$REALM/clients/$UUID" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" --data @/tmp/_kc_client.json
rm -f /tmp/_kc_client.json
