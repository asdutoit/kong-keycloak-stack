# Pulumi Kong Provisioner

Docker image for provisioning Kong Gateway resources via Pulumi.

## Build

```bash
docker build -t pulumi-kong-provisioner:latest .
```

## Usage

The container reads an OpenAPI spec (with `x-kong-*` extensions) from the `OPENAPI_SPEC_JSON` environment variable and provisions Kong services, routes, and plugins.

### Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `OPENAPI_SPEC_JSON` | Yes | - | JSON string of the OpenAPI spec |
| `ACTION` | No | `deploy` | Action: `deploy`, `destroy`, `preview`, or `refresh` |
| `STACK_NAME` | No | `default` | Pulumi stack name — see [Stack naming](#stack-naming) |
| `KONG_ADMIN_URL` | No | `http://kong-admin:8001` | Kong Admin API URL |
| `STATE_DIR` | No | `/state` | Local cache dir for run-time artifacts (outputs, etc.). No longer holds Pulumi state when the Azure backend is configured. |
| `AZURE_STORAGE_ACCOUNT` | Cloud backend | - | Storage account holding state (e.g. `sttmacshdeuww6dhe001`) |
| `AZURE_STORAGE_KEY` | Cloud backend | - | Account access key — mount via K8s Secret |
| `AZURE_STORAGE_CONTAINER` | No | `pulumi-api-onboarding-state` | Blob container that holds the stacks |
| `PULUMI_CONFIG_PASSPHRASE` | Cloud backend | - | Passphrase used to encrypt stack secrets in the blob |

### Deploy

```bash
docker run --rm \
  -e OPENAPI_SPEC_JSON="$(cat spec.json)" \
  -e STACK_NAME="my-api" \
  -e KONG_ADMIN_URL="http://kong-admin:8001" \
  -e ACTION="deploy" \
  -v pulumi-kong-state:/state \
  pulumi-kong-provisioner:latest
```

### Destroy

```bash
docker run --rm \
  -e STACK_NAME="my-api" \
  -e KONG_ADMIN_URL="http://kong-admin:8001" \
  -e ACTION="destroy" \
  -v pulumi-kong-state:/state \
  pulumi-kong-provisioner:latest
```

### Preview

```bash
docker run --rm \
  -e OPENAPI_SPEC_JSON="$(cat spec.json)" \
  -e STACK_NAME="my-api" \
  -e ACTION="preview" \
  -v pulumi-kong-state:/state \
  pulumi-kong-provisioner:latest
```

## State Persistence

Production deployments use an Azure Blob Storage backend with blob-lease
locking. Set the cloud backend env vars and the provisioner persists state
in the configured container; no Docker volume is needed.

```bash
docker run --rm \
  -e OPENAPI_SPEC_JSON="$(cat spec.json)" \
  -e STACK_NAME="ew-mc-dev-httpbin" \
  -e KONG_ADMIN_URL="http://kong-admin:8001" \
  -e AZURE_STORAGE_ACCOUNT="sttmacshdeuww6dhe001" \
  -e AZURE_STORAGE_KEY="$(az storage account keys list -n sttmacshdeuww6dhe001 \
        -g rg-tmac-shd-euw-w6dhe-001 --query '[0].value' -o tsv)" \
  -e PULUMI_CONFIG_PASSPHRASE="$PULUMI_PASSPHRASE" \
  pulumi-kong-provisioner:latest
```

If the Azure vars are absent the provisioner falls back to
`file:///state` so workstation runs against a local Kong keep working —
but that path is **not** suitable for shared / org infrastructure.

### Stack naming

Use the convention `<platform>-<env>-<api>`, e.g. `ew-mc-dev-httpbin` or
`ns-bc-acc-payments`. Each unique tuple gets its own Pulumi stack file
inside the container, giving you one isolated state per (platform,
environment, API) deployment.

### Creating the container

```bash
az storage container create \
  --account-name sttmacshdeuww6dhe001 \
  --name pulumi-api-onboarding-state \
  --auth-mode key
```

Enable soft-delete + versioning on the storage account for state recovery:

```bash
az storage account blob-service-properties update \
  --account-name sttmacshdeuww6dhe001 \
  --resource-group rg-tmac-shd-euw-w6dhe-001 \
  --enable-versioning true \
  --enable-delete-retention true \
  --delete-retention-days 30
```

## OpenAPI Extensions

The provisioner recognizes these Kong-specific extensions:

- `x-kong-service-defaults` - Service configuration (url, timeouts)
- `x-kong-route-prefix` - Route prefix configuration
- `x-kong-plugin-*` - Plugin configurations at service, path, or operation level

See the main project README for full documentation on these extensions.
