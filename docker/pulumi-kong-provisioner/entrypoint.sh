#!/bin/bash
set -e

ACTION="${ACTION:-deploy}"
STACK_NAME="${STACK_NAME:-default}"
KONG_ADMIN_URL="${KONG_ADMIN_URL:-http://kong-admin:8001}"
STATE_DIR="${STATE_DIR:-/state}"

# Configure Kong provider
export KONG_ADMIN_ADDR="$KONG_ADMIN_URL"

# Login to local state (stored in mounted volume)
mkdir -p "$STATE_DIR"
export PULUMI_HOME="$STATE_DIR/.pulumi"
pulumi login "file://$STATE_DIR"

cd /app

case "$ACTION" in
    deploy)
        echo "=== Deploying stack: $STACK_NAME ==="

        # Select or create stack
        pulumi stack select "$STACK_NAME" --create 2>/dev/null || pulumi stack init "$STACK_NAME"

        # Run pulumi up
        pulumi up --yes --non-interactive

        # Output results
        echo "=== Deployment Outputs ==="
        pulumi stack output --json > /tmp/outputs.json
        cat /tmp/outputs.json

        # Copy outputs to state dir for retrieval
        cp /tmp/outputs.json "$STATE_DIR/outputs-$STACK_NAME.json"
        ;;

    destroy)
        echo "=== Destroying stack: $STACK_NAME ==="

        # Select stack
        if pulumi stack select "$STACK_NAME" 2>/dev/null; then
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

        # Run preview
        pulumi preview
        ;;

    *)
        echo "Unknown action: $ACTION"
        echo "Valid actions: deploy, destroy, preview"
        exit 1
        ;;
esac
