#!/usr/bin/env bash
# Cold-start bootstrap for the local Docker Desktop stack.
#
# Brings everything the api-onboarding portal needs into a runnable state:
#   1. Verifies prerequisites
#   2. Deploys the k8s stack (Kong, Keycloak, Postgres, Jenkins) via deploy.sh
#   3. Waits for Keycloak to be ready
#   4. Provisions the two `master`-realm Keycloak clients the portal needs:
#        - api-onboarding         (SSO login client)
#        - api-onboarding-admin   (service account for Keycloak admin REST)
#      Both are idempotent — existing clients are reused and their secrets
#      reprinted.
#   5. Creates realm roles (admin, approver) + the /approvers group
#   6. Runs Prisma migrations on backstage-ui
#   7. Writes backstage-ui/.env if it doesn't exist, prints values to stdout
#      otherwise (so existing customisations aren't clobbered).
#
# Usage:
#   ./bootstrap-local.sh [--skip-deploy] [--portal-dir <path>] [--keycloak-url <url>]
#
# Env vars (override defaults):
#   KC_ADMIN_USER (default: admin)
#   KC_ADMIN_PASS (default: admin)
#   PORTAL_REDIRECT (default: http://localhost:3000)
#   KEYCLOAK_PORT_FORWARD (default: 1 — port-forward 8080:8080 if not already up)

set -euo pipefail

# ─── Defaults ──────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
PORTAL_DIR="${PORTAL_DIR:-$(cd "$STACK_DIR/../api-onboarding/backstage-ui" 2>/dev/null && pwd || echo "")}"
KEYCLOAK_URL="${KEYCLOAK_URL:-http://localhost:8080}"
KC_ADMIN_USER="${KC_ADMIN_USER:-admin}"
KC_ADMIN_PASS="${KC_ADMIN_PASS:-admin}"
PORTAL_REDIRECT="${PORTAL_REDIRECT:-http://localhost:3000}"
KEYCLOAK_PORT_FORWARD="${KEYCLOAK_PORT_FORWARD:-1}"
SKIP_DEPLOY=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-deploy) SKIP_DEPLOY=1; shift ;;
    --portal-dir) PORTAL_DIR="$2"; shift 2 ;;
    --keycloak-url) KEYCLOAK_URL="$2"; shift 2 ;;
    -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
    *) echo "Unknown flag: $1" >&2; exit 1 ;;
  esac
done

# ─── Output helpers ────────────────────────────────────────────────────────

step()  { printf '\n\033[1;34m▸\033[0m %s\n' "$*"; }
ok()    { printf '\033[1;32m✓\033[0m %s\n' "$*"; }
warn()  { printf '\033[1;33m!\033[0m %s\n' "$*"; }
fail()  { printf '\033[1;31m✗\033[0m %s\n' "$*"; exit 1; }

# ─── Prerequisites ─────────────────────────────────────────────────────────

step "Checking prerequisites"
for cmd in kubectl curl jq; do
  command -v "$cmd" >/dev/null 2>&1 || fail "$cmd is required but not on PATH"
done
if [[ -n "$PORTAL_DIR" && -d "$PORTAL_DIR" ]]; then
  command -v bun >/dev/null 2>&1 || warn "bun not on PATH — Prisma migrations will be skipped"
fi
ok "tools ok"

# ─── k8s deploy ────────────────────────────────────────────────────────────

if [[ $SKIP_DEPLOY -eq 0 ]]; then
  step "Deploying k8s stack (Kong + Keycloak + Postgres + Jenkins)"
  if [[ -x "$SCRIPT_DIR/../deploy.sh" ]]; then
    "$SCRIPT_DIR/../deploy.sh"
  else
    fail "deploy.sh not found or not executable at $SCRIPT_DIR/../deploy.sh"
  fi
else
  warn "--skip-deploy specified, assuming k8s stack already running"
fi

# ─── Keycloak port-forward (best-effort) ───────────────────────────────────

if [[ "$KEYCLOAK_PORT_FORWARD" == "1" && "$KEYCLOAK_URL" == http://localhost:8080 ]]; then
  if ! curl -sf -o /dev/null "$KEYCLOAK_URL/realms/master"; then
    step "Starting Keycloak port-forward (8080 → svc/keycloak:8080)"
    kubectl -n kong-system port-forward --address 0.0.0.0 svc/keycloak 8080:8080 \
      >/tmp/bootstrap-keycloak-pf.log 2>&1 &
    PF_PID=$!
    trap 'kill '"$PF_PID"' 2>/dev/null || true' EXIT
    sleep 2
  fi
fi

# ─── Wait for Keycloak ─────────────────────────────────────────────────────

step "Waiting for Keycloak at $KEYCLOAK_URL"
for i in $(seq 1 60); do
  if curl -sf -o /dev/null "$KEYCLOAK_URL/realms/master"; then
    ok "Keycloak responding"
    break
  fi
  if [[ $i -eq 60 ]]; then
    fail "Keycloak did not become ready within 5 minutes"
  fi
  sleep 5
done

# ─── Admin token ───────────────────────────────────────────────────────────

step "Acquiring admin token"
TOKEN_RESP=$(curl -sk -X POST "$KEYCLOAK_URL/realms/master/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=password" \
  -d "client_id=admin-cli" \
  -d "username=$KC_ADMIN_USER" \
  -d "password=$KC_ADMIN_PASS")
TOKEN=$(echo "$TOKEN_RESP" | jq -r '.access_token // empty')
[[ -n "$TOKEN" ]] || fail "Could not authenticate as $KC_ADMIN_USER (response: $TOKEN_RESP)"
ok "admin token acquired"

# Helpers that close over $TOKEN + $KEYCLOAK_URL
kc_get()    { curl -sk -H "Authorization: Bearer $TOKEN" "$KEYCLOAK_URL$1"; }
kc_post()   { curl -sk -o /dev/null -w "%{http_code}" -X POST -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" --data "$2" "$KEYCLOAK_URL$1"; }
kc_put()    { curl -sk -o /dev/null -w "%{http_code}" -X PUT -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" --data "$2" "$KEYCLOAK_URL$1"; }

# ─── Realm roles ───────────────────────────────────────────────────────────

ensure_realm_role() {
  local name="$1" desc="$2"
  if kc_get "/admin/realms/master/roles/$name" | jq -e '.name' >/dev/null 2>&1; then
    return 0
  fi
  kc_post "/admin/realms/master/roles" \
    "{\"name\":\"$name\",\"description\":\"$desc\"}" >/dev/null
}

step "Ensuring realm roles (admin, approver)"
ensure_realm_role admin    "Portal admin — Nuke button, Access Requests, Settings"
ensure_realm_role approver "Portal approver — approve/reject deployments"
ok "realm roles in place"

# ─── /approvers group with approver role mapping ───────────────────────────

step "Ensuring /approvers group"
APPROVERS_GID=$(kc_get "/admin/realms/master/groups?search=approvers&exact=true" | jq -r '.[0].id // empty')
if [[ -z "$APPROVERS_GID" ]]; then
  kc_post "/admin/realms/master/groups" '{"name":"approvers"}' >/dev/null
  APPROVERS_GID=$(kc_get "/admin/realms/master/groups?search=approvers&exact=true" | jq -r '.[0].id')
fi

# Idempotent role-mapping: GET existing realm-role mappings on the group,
# only POST if "approver" isn't already there.
HAS_APPROVER=$(kc_get "/admin/realms/master/groups/$APPROVERS_GID/role-mappings/realm" | jq -r '[.[] | .name] | index("approver")')
if [[ "$HAS_APPROVER" == "null" ]]; then
  APPROVER_ROLE=$(kc_get "/admin/realms/master/roles/approver")
  kc_post "/admin/realms/master/groups/$APPROVERS_GID/role-mappings/realm" "[$APPROVER_ROLE]" >/dev/null
fi
ok "/approvers group ready (id=$APPROVERS_GID)"

# ─── SSO client: api-onboarding ────────────────────────────────────────────

step "Provisioning api-onboarding (SSO) client"
SSO_PK=$(kc_get "/admin/realms/master/clients?clientId=api-onboarding" | jq -r '.[0].id // empty')
if [[ -z "$SSO_PK" ]]; then
  kc_post "/admin/realms/master/clients" "$(jq -nc \
    --arg redir "$PORTAL_REDIRECT" \
    '{
      clientId: "api-onboarding",
      name: "API Onboarding Internal Portal",
      enabled: true,
      protocol: "openid-connect",
      publicClient: false,
      standardFlowEnabled: true,
      directAccessGrantsEnabled: true,
      serviceAccountsEnabled: false,
      redirectUris: [($redir + "/api/auth/callback/keycloak"), ($redir + "/*")],
      webOrigins: [$redir],
      attributes: {}
    }')" >/dev/null
  SSO_PK=$(kc_get "/admin/realms/master/clients?clientId=api-onboarding" | jq -r '.[0].id')
fi
SSO_SECRET=$(kc_get "/admin/realms/master/clients/$SSO_PK/client-secret" | jq -r '.value')
ok "api-onboarding ready (id=$SSO_PK)"

# ─── Admin client: api-onboarding-admin ───────────────────────────────────

step "Provisioning api-onboarding-admin (service-account) client"
ADMIN_PK=$(kc_get "/admin/realms/master/clients?clientId=api-onboarding-admin" | jq -r '.[0].id // empty')
if [[ -z "$ADMIN_PK" ]]; then
  kc_post "/admin/realms/master/clients" '{
    "clientId": "api-onboarding-admin",
    "name": "API Onboarding Admin (service account)",
    "description": "Service-account-only client used by api-onboarding to call the Keycloak admin REST API.",
    "enabled": true,
    "protocol": "openid-connect",
    "publicClient": false,
    "standardFlowEnabled": false,
    "directAccessGrantsEnabled": false,
    "implicitFlowEnabled": false,
    "serviceAccountsEnabled": true
  }' >/dev/null
  ADMIN_PK=$(kc_get "/admin/realms/master/clients?clientId=api-onboarding-admin" | jq -r '.[0].id')
fi
ADMIN_SECRET=$(kc_get "/admin/realms/master/clients/$ADMIN_PK/client-secret" | jq -r '.value')

# Grant master-realm client roles needed for user provisioning. Diff against
# what's already there so the script is safe to re-run.
SA_ID=$(kc_get "/admin/realms/master/clients/$ADMIN_PK/service-account-user" | jq -r '.id')
MR_CLIENT=$(kc_get "/admin/realms/master/clients?clientId=master-realm" | jq -r '.[0].id')
EXISTING_NAMES=$(kc_get "/admin/realms/master/users/$SA_ID/role-mappings/clients/$MR_CLIENT" | jq -r '[.[].name] // []')
WANTED=(manage-users view-users query-users query-groups)
TO_GRANT='[]'
for role in "${WANTED[@]}"; do
  if ! echo "$EXISTING_NAMES" | jq -e --arg r "$role" 'index($r)' >/dev/null; then
    R=$(kc_get "/admin/realms/master/clients/$MR_CLIENT/roles/$role")
    TO_GRANT=$(jq -c --argjson r "$R" '. + [$r]' <<<"$TO_GRANT")
  fi
done
if [[ $(jq 'length' <<<"$TO_GRANT") -gt 0 ]]; then
  kc_post "/admin/realms/master/users/$SA_ID/role-mappings/clients/$MR_CLIENT" "$TO_GRANT" >/dev/null
fi
ok "api-onboarding-admin ready (id=$ADMIN_PK, sa=$SA_ID)"

# ─── Portal: migrations + .env ─────────────────────────────────────────────

ENV_FILE="$PORTAL_DIR/.env"
AUTH_SECRET="$(openssl rand -hex 32 2>/dev/null || echo "CHANGEME-$(date +%s)")"
DB_URL="postgresql://appuser:apppass@localhost:5434/appdb"

ENV_TEMPLATE=$(cat <<EOF
DATABASE_URL=$DB_URL
AUTH_SECRET=$AUTH_SECRET
AUTH_URL=$PORTAL_REDIRECT
AUTH_TRUST_HOST=true
NEXT_PUBLIC_APP_URL=$PORTAL_REDIRECT
KEYCLOAK_URL=$KEYCLOAK_URL
KEYCLOAK_REALM=master
KEYCLOAK_CLIENT_ID=api-onboarding
KEYCLOAK_CLIENT_SECRET=$SSO_SECRET
KEYCLOAK_ADMIN_CLIENT_ID=api-onboarding-admin
KEYCLOAK_ADMIN_CLIENT_SECRET=$ADMIN_SECRET
ADMIN_ROLE=admin
# Fill these in before /request-access auto-approve will email:
ACCESS_REQUESTS_TO=
MS_GRAPH_TENANT_ID=
MS_GRAPH_CLIENT_ID=
MS_GRAPH_CLIENT_SECRET=
MS_GRAPH_SENDER_EMAIL=
EOF
)

if [[ -n "$PORTAL_DIR" && -d "$PORTAL_DIR" ]]; then
  if [[ -f "$ENV_FILE" ]]; then
    step "Existing .env detected at $ENV_FILE — printing values, not overwriting"
    echo
    echo "$ENV_TEMPLATE" | sed 's/^/  /'
    echo
    warn "Manually merge the lines above into $ENV_FILE"
  else
    step "Writing $ENV_FILE"
    printf '%s\n' "$ENV_TEMPLATE" > "$ENV_FILE"
    chmod 600 "$ENV_FILE"
    ok "wrote $ENV_FILE"
  fi

  if command -v bun >/dev/null 2>&1; then
    step "Running Prisma migrations"
    (cd "$PORTAL_DIR" && bun install --silent && bunx prisma migrate deploy)
    ok "migrations applied"
  else
    warn "bun missing — run \`cd $PORTAL_DIR && bun install && bunx prisma migrate deploy\` manually"
  fi
else
  warn "Portal dir not found — pass --portal-dir <path> next time, or set PORTAL_DIR. Skipping migrations + .env."
  echo
  echo "$ENV_TEMPLATE"
fi

# ─── Done ──────────────────────────────────────────────────────────────────

cat <<EOF

──────────────────────────────────────────────────────────────────────────
Bootstrap complete. Secrets you'll need:

  KEYCLOAK_CLIENT_SECRET=$SSO_SECRET
  KEYCLOAK_ADMIN_CLIENT_SECRET=$ADMIN_SECRET

Next steps:
  1. Add yourself to the realm role 'admin' in Keycloak (or to /approvers
     group for approver-only access).
  2. (If port-forwards weren't set up) run scripts/port-forward.sh in a
     separate terminal.
  3. cd $PORTAL_DIR && bun run dev
  4. Open $PORTAL_REDIRECT, sign in, verify /settings shows the
     'Auto-approve access requests' panel.

──────────────────────────────────────────────────────────────────────────
EOF
