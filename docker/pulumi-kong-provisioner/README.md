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
| `ACTION` | No | `deploy` | Action: `deploy`, `destroy`, or `preview` |
| `STACK_NAME` | No | `default` | Pulumi stack name (usually the API name) |
| `KONG_ADMIN_URL` | No | `http://kong-admin:8001` | Kong Admin API URL |
| `STATE_DIR` | No | `/state` | Directory for Pulumi state persistence |

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

Pulumi state is stored in the mounted `/state` volume. Use a Docker volume or persistent storage to maintain state across deployments:

```bash
# Create volume
docker volume create pulumi-kong-state

# Use in deployments
-v pulumi-kong-state:/state
```

## OpenAPI Extensions

The provisioner recognizes these Kong-specific extensions:

- `x-kong-service-defaults` - Service configuration (url, timeouts)
- `x-kong-route-prefix` - Route prefix configuration
- `x-kong-plugin-*` - Plugin configurations at service, path, or operation level

See the main project README for full documentation on these extensions.
