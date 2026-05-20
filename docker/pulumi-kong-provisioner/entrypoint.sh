#!/bin/bash
set -e

ACTION="${ACTION:-deploy}"
STACK_NAME="${STACK_NAME:-default}"
KONG_ADMIN_URL="${KONG_ADMIN_URL:-http://kong-admin:8001}"
STATE_DIR="${STATE_DIR:-/state}"
KONG_TLS_SKIP_VERIFY="${KONG_TLS_SKIP_VERIFY:-false}"

# State-backend selection. Cloud is the production default; the legacy
# file:// path stays available as a fallback when the Azure vars are
# absent (useful for local development against a workstation Kong).
#
# Required for the cloud backend:
#   AZURE_STORAGE_ACCOUNT     — storage account name (e.g. sttmacshdeuww6dhe001)
#   AZURE_STORAGE_KEY         — account access key (kept in a K8s Secret)
#   AZURE_STORAGE_CONTAINER   — blob container name (defaults to
#                                pulumi-api-onboarding-state)
#   PULUMI_CONFIG_PASSPHRASE  — passphrase used to encrypt config + secrets
#                                stored in stack files
#
# Pulumi's azblob backend natively uses blob leases for state locking,
# so concurrent stack operations are mutually exclusive without any
# extra work here.
AZURE_STORAGE_CONTAINER="${AZURE_STORAGE_CONTAINER:-pulumi-api-onboarding-state}"

# Configure Kong provider env vars
export KONG_ADMIN_ADDR="$KONG_ADMIN_URL"

mkdir -p "$STATE_DIR"
export PULUMI_HOME="$STATE_DIR/.pulumi"

if [ -n "$AZURE_STORAGE_ACCOUNT" ] && [ -n "$AZURE_STORAGE_KEY" ]; then
    echo "Using Azure Blob backend: $AZURE_STORAGE_CONTAINER on $AZURE_STORAGE_ACCOUNT"
    if [ -z "$PULUMI_CONFIG_PASSPHRASE" ]; then
        echo "ERROR: PULUMI_CONFIG_PASSPHRASE must be set when using the cloud backend." >&2
        exit 1
    fi
    # The Azure SDK Pulumi uses reads AZURE_STORAGE_ACCOUNT + AZURE_STORAGE_KEY
    # automatically; we just need to export them so child processes see them.
    export AZURE_STORAGE_ACCOUNT
    export AZURE_STORAGE_KEY
    pulumi login "azblob://${AZURE_STORAGE_CONTAINER}"
else
    echo "WARNING: AZURE_STORAGE_ACCOUNT/KEY not set — falling back to file://${STATE_DIR}"
    echo "         (No locking, no central audit. Only acceptable for local dev.)"
    pulumi login "file://$STATE_DIR"
fi

cd /app

# Helper: configure Kong provider settings for the current stack
configure_kong_provider() {
    pulumi config set kong:kongAdminUri "$KONG_ADMIN_URL" 2>/dev/null || true
    if [ "$KONG_TLS_SKIP_VERIFY" = "true" ]; then
        pulumi config set kong:tlsSkipVerify true 2>/dev/null || true
    fi
}

## Helper: build curl args for Kong Admin API (handles RBAC token + TLS)
kong_curl() {
    local method="${1:-GET}"
    local path="$2"
    local curl_args=(-sf -k -X "$method")
    if [ -n "$KONG_ADMIN_TOKEN" ]; then
        curl_args+=(-H "Kong-Admin-Token: $KONG_ADMIN_TOKEN")
    fi
    curl "${curl_args[@]}" "${KONG_ADMIN_URL}${path}" 2>/dev/null
}

# Helper: clean up legacy Kong resources when Pulumi state is empty but Kong
# already has a service with the same name (e.g. migrating from deck to pulumi,
# or Pulumi state was lost). This lets pulumi up create everything fresh.
cleanup_legacy_kong_resources() {
    local service_name="$1"

    # Check if Pulumi state has any Kong resources
    local has_resources
    has_resources=$(pulumi stack --show-urns --non-interactive 2>/dev/null | grep -c "kong:") || has_resources=0
    if [ "$has_resources" -gt 0 ]; then
        echo "Stack has existing Pulumi state, skipping legacy cleanup"
        return
    fi

    # Check if Kong already has this service
    local service_json
    service_json=$(kong_curl GET "/services/${service_name}" || true)
    if [ -z "$service_json" ]; then
        echo "No existing service '${service_name}' in Kong, proceeding with fresh deploy"
        return
    fi

    echo "=== Cleaning up legacy Kong resources for '${service_name}' ==="

    # Delete plugins on the service
    kong_curl GET "/services/${service_name}/plugins" | \
        python3 -c "import sys,json; [print(p['id']) for p in json.load(sys.stdin).get('data',[])]" 2>/dev/null | \
        while read -r pid; do
            echo "  Removing service plugin: $pid"
            kong_curl DELETE "/plugins/${pid}" || true
        done

    # Delete routes and their plugins
    kong_curl GET "/services/${service_name}/routes" | \
        python3 -c "import sys,json; [print(r['id']) for r in json.load(sys.stdin).get('data',[])]" 2>/dev/null | \
        while read -r rid; do
            # Delete route plugins first
            kong_curl GET "/routes/${rid}/plugins" | \
                python3 -c "import sys,json; [print(p['id']) for p in json.load(sys.stdin).get('data',[])]" 2>/dev/null | \
                while read -r pid; do
                    echo "  Removing route plugin: $pid"
                    kong_curl DELETE "/plugins/${pid}" || true
                done
            echo "  Removing route: $rid"
            kong_curl DELETE "/routes/${rid}" || true
        done

    # Delete the service
    echo "  Removing service: ${service_name}"
    kong_curl DELETE "/services/${service_name}" || true

    # Delete the upstream (Pulumi creates "<service_name>-upstream"). Upstreams
    # are independent of services in Kong's data model, so deleting the service
    # leaves them behind — and a stale upstream will collide with the new
    # target on the next deploy ("UNIQUE violation"). Deleting an upstream
    # cascades to its targets in Kong.
    local upstream_name="${service_name}-upstream"
    if kong_curl GET "/upstreams/${upstream_name}" >/dev/null 2>&1; then
        echo "  Removing upstream: ${upstream_name}"
        kong_curl DELETE "/upstreams/${upstream_name}" || true
    fi

    echo "=== Legacy cleanup complete ==="
}

case "$ACTION" in
    deploy)
        echo "=== Deploying stack: $STACK_NAME ==="

        # Select or create stack
        pulumi stack select "$STACK_NAME" --create 2>/dev/null || pulumi stack init "$STACK_NAME"

        # Set Kong provider config (TLS, admin URI)
        configure_kong_provider

        # Clean up legacy Kong resources if this is a fresh stack (prevents 409 conflicts).
        # Compute the expected Kong service name the same way __main__.py does:
        #   sanitize(info.title) + env_suffix
        COMPUTED_API_NAME=$(python3 -c "
import json, os, re
spec_file = os.environ.get('OPENAPI_SPEC_FILE', '')
if spec_file and os.path.exists(spec_file):
    spec = json.load(open(spec_file))
else:
    spec = json.loads(os.environ.get('OPENAPI_SPEC_JSON', '{}'))
title = spec.get('info', {}).get('title', 'unnamed-api')
name = re.sub(r'[^a-zA-Z0-9._~-]', '', title.lower().replace(' ', '-')).strip('-') or 'unnamed'
env = os.environ.get('ENVIRONMENT', 'dev')
env_sfx = '' if env in ('prod', 'production') else f'-{env}'
print(name + env_sfx)
" 2>/dev/null || echo "")
        if [ -n "$COMPUTED_API_NAME" ]; then
            cleanup_legacy_kong_resources "$COMPUTED_API_NAME"
        fi

        # Refresh state to sync with actual Kong resources (prevents stale state issues)
        echo "=== Refreshing state ==="
        pulumi refresh --yes --non-interactive 2>&1 || echo "Warning: refresh failed (may be first deploy), continuing..."

        # Run pulumi up
        pulumi up --yes --non-interactive

        # Output results
        echo "=== Deployment Outputs ==="
        pulumi stack output --json > /tmp/outputs.json
        cat /tmp/outputs.json
        # Machine-readable single-line JSON for Jenkinsfile log parsing
        echo "PULUMI_OUTPUTS_JSON=$(python3 -c 'import json; print(json.dumps(json.load(open("/tmp/outputs.json"))))')"

        # Copy outputs to state dir for retrieval
        cp /tmp/outputs.json "$STATE_DIR/outputs-$STACK_NAME.json"
        ;;

    destroy)
        echo "=== Destroying stack: $STACK_NAME ==="

        # Select stack
        if pulumi stack select "$STACK_NAME" 2>/dev/null; then
            configure_kong_provider

            # Run pulumi destroy (skip-preview since resources may already be gone)
            pulumi destroy --yes --non-interactive --skip-preview || true

            # Remove the stack to clean up state
            pulumi stack rm "$STACK_NAME" --yes || true
        else
            echo "Stack $STACK_NAME not found, nothing to destroy"
        fi

        echo "=== Resources Destroyed ==="
        ;;

    preview)
        echo "=== Previewing stack: $STACK_NAME ==="

        # Select or create stack
        pulumi stack select "$STACK_NAME" --create 2>/dev/null || pulumi stack init "$STACK_NAME"

        configure_kong_provider

        # Run preview
        pulumi preview
        ;;

    refresh)
        echo "=== Refreshing stack: $STACK_NAME ==="

        # Select stack
        if pulumi stack select "$STACK_NAME" 2>/dev/null; then
            configure_kong_provider
            pulumi refresh --yes --non-interactive
            echo "=== State Refreshed ==="
        else
            echo "Stack $STACK_NAME not found, nothing to refresh"
        fi
        ;;

    *)
        echo "Unknown action: $ACTION"
        echo "Valid actions: deploy, destroy, preview, refresh"
        exit 1
        ;;
esac
