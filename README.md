# Kong + Keycloak + Jenkins + Monitoring Stack

Minimal Kong Gateway with Keycloak, Jenkins, Prometheus, and Grafana for local Kubernetes testing.

## Project Structure

```
kong-keycloak-stack/
├── k8s/
│   ├── base/
│   │   ├── kustomization.yaml  # Lists all resources
│   │   ├── namespace.yaml      # kong-system namespace
│   │   ├── postgres.yaml       # PostgreSQL database
│   │   ├── keycloak.yaml       # Keycloak identity provider
│   │   ├── kong.yaml           # Kong gateway
│   │   ├── httpbin.yaml        # httpbin test backend
│   │   ├── jenkins-rbac.yaml   # Jenkins RBAC
│   │   ├── jenkins.yaml        # Jenkins CI/CD server
│   │   ├── prometheus.yaml     # Prometheus metrics collection
│   │   ├── loki.yaml           # Loki log aggregation
│   │   ├── promtail.yaml       # Promtail log collector
│   │   ├── grafana.yaml        # Grafana dashboards & visualization
│   │   └── pulumi-state-pvc.yaml
│   └── overlays/
│       └── local/
│           └── kustomization.yaml  # Local dev overlay
├── argo/
│   └── values/             # Helm values for the Argo stack
│       ├── argo-cd.yaml
│       ├── argo-workflows.yaml
│       └── argo-rollouts.yaml
├── scripts/                # See scripts/README.md
│   ├── deploy.sh           # Deploy the whole stack — main entrypoint
│   ├── port-forward.sh     # Start port-forwards — main entrypoint
│   ├── teardown.sh         # Remove the stack — main entrypoint
│   ├── lib/                # Helpers invoked by deploy.sh (don't run directly)
│   │   ├── install-argo.sh
│   │   ├── create-keycloak-realm.sh
│   │   └── create-jenkins-jobs.py
│   └── utils/              # Standalone utilities (run occasionally)
│       ├── configure-auth.sh
│       ├── manage-keys.sh
│       ├── bootstrap-local.sh
│       ├── build-keycloak-theme.sh
│       └── set-login-theme.sh
└── README.md
```

## Quick Start

**Prerequisites:** a local Kubernetes cluster (Docker Desktop), `kubectl`, and
`helm`. `deploy.sh` brings up the full stack — Kong, Keycloak, Jenkins,
monitoring (Prometheus/Loki/Grafana), **and the Argo stack (Argo CD, Argo
Workflows, Argo Rollouts)** — so a new teammate can clone and run one command.

```bash
# Deploy the stack
./scripts/deploy.sh

# Start port-forwards
./scripts/port-forward.sh

# Configure Kong with httpbin service, API key auth, and Prometheus plugin
./scripts/utils/configure-auth.sh

# Test the API
curl -H 'apikey: my-api-key-123' http://localhost:8000/api/httpbin/get
```

## Services

| Service | URL | Credentials |
|---------|-----|-------------|
| Keycloak | http://localhost:8080 | admin/admin |
| Kong Manager | http://localhost:8002 | - |
| Kong Proxy | http://localhost:8000 | - |
| Kong Admin API | http://localhost:8001 | - |
| Jenkins | http://localhost:8081 | admin/admin |
| PostgreSQL | localhost:5433 | (see below) |
| httpbin | http://localhost:8082 | - |
| Prometheus | http://localhost:9090 | - |
| Grafana | http://localhost:3001 | admin/admin |
| Argo CD | http://localhost:8083 | admin / (see below) |
| Argo Workflows | http://localhost:2746 | - |

## Argo (GitOps, Workflows, Rollouts)

The Argo stack is installed via Helm (`argo-helm` charts) by
`scripts/lib/install-argo.sh`, which `deploy.sh` runs automatically. It is
idempotent (`helm upgrade --install`), so re-running `deploy.sh` is safe.

| Component | Namespace | Chart |
|-----------|-----------|-------|
| Argo CD | `argocd` | `argo/argo-cd` |
| Argo Workflows | `argo` | `argo/argo-workflows` |
| Argo Rollouts | `argo-rollouts` | `argo/argo-rollouts` |

- **Pinned versions** live at the top of `scripts/lib/install-argo.sh`; bump them
  deliberately to track production. Per-app config is in `argo/values/`.
- **Argo CD admin password**:
  ```bash
  kubectl -n argocd get secret argocd-initial-admin-secret \
    -o jsonpath='{.data.password}' | base64 -d
  ```
- **Argo CD runs insecure (HTTP)** for convenient local port-forwarding —
  fine for a workstation, not for shared environments.
- **Argo Rollouts dashboard**: `kubectl argo rollouts dashboard`.

> **Existing clusters**: if a cluster already has Argo installed via raw
> manifests (`kubectl apply -f install.yaml`), Helm will refuse to adopt those
> resources. Remove them first — `kubectl delete ns argocd argo argo-rollouts`
> — then run `deploy.sh`. Fresh workstations need no such step.

## Monitoring

### Prometheus

Prometheus scrapes Kong metrics every 15s. After running `scripts/utils/configure-auth.sh`, the global Prometheus plugin is enabled on Kong.

- **UI**: http://localhost:9090
- **Kong metrics endpoint**: http://localhost:8001/metrics
- **Data retention**: 7 days
- **Storage**: 2Gi PVC

Useful PromQL queries:

```promql
# Request rate by status code
sum(rate(kong_http_requests_total[5m])) by (code)

# P99 latency
histogram_quantile(0.99, sum(rate(kong_request_latency_ms_bucket[5m])) by (le))

# Error rate percentage
sum(rate(kong_http_requests_total{code=~"5.."}[5m])) / sum(rate(kong_http_requests_total[5m])) * 100
```

### Grafana

Grafana comes pre-configured with a Prometheus datasource and a Kong Gateway Overview dashboard.

- **UI**: http://localhost:3001
- **Credentials**: admin/admin
- **Pre-loaded dashboard**: Kong Gateway Overview (9 panels)
- **Storage**: 1Gi PVC

The Kong Gateway Overview dashboard includes:
- Request rate by status code
- Latency distribution (p50/p95/p99)
- Error rate (5xx %)
- Upstream health
- Requests by service
- Rate limiting (429s)
- Bandwidth
- Active connections
- Request logs (Loki)

### Logs (Loki)

Container logs are collected cluster-wide by a Promtail DaemonSet and pushed to
Loki, which is wired into Grafana as a datasource. Browse them in Grafana →
**Explore** → Loki, or via the **Request logs** panels on the dashboards.

Kong also runs a structured-logging plugin that emits one JSON object per
request — including request/response **headers**, `service`, `route`,
`consumer`, `client_ip` and `latencies`. Bodies are **not** captured by default
(see below).

Logging is enabled two ways, so every API is always covered:

- **Globally** by the `kong-bootstrap-plugins` Job (catches all traffic,
  including unmatched routes and the Admin API).
- **Per API** by the Pulumi/Jenkins onboarding pipeline
  (`jenkins/Jenkinsfile.pulumi`), which auto-injects an `x-kong-plugin-file-log`
  into every spec — exactly like it does for `x-kong-plugin-prometheus` — so
  logging is baked into each API's provisioned (Pulumi-managed) config and does
  not depend on the global Job existing in that environment. Set
  `LOG_HTTP_ENDPOINT` on the pipeline to inject `http-log` to a collector
  instead, and a spec that already declares any `*-log` plugin is left untouched.

Useful LogQL queries:

```logql
# All Kong logs
{namespace="kong-system", container="kong"}

# Structured request logs, parsed
{namespace="kong-system", container="kong"} | json | source="kong"

# Errors for a specific onboarded API (matches the per-service dashboard panel)
{namespace="kong-system", container="kong"} | json | service_name="my-api" | response_status >= 500

# Filter by a request header
{namespace="kong-system", container="kong"} | json | request_headers_host="api.example.com"
```

#### Log transport

The global log plugin is provisioned by the `kong-bootstrap-plugins` Job and is
configurable via the `LOG_PLUGIN` env var on that Job:

| `LOG_PLUGIN`      | Behaviour                                                        | Required env                  |
| ----------------- | --------------------------------------------------------------- | ----------------------------- |
| `file-log`        | JSON to `/dev/stdout` → tailed by Promtail into Loki (default)   | —                             |
| `http-log`        | POST JSON to an external collector (prod-style)                  | `LOG_HTTP_ENDPOINT`           |
| `tcp-log`         | Stream JSON to a TCP sink (e.g. Logstash)                        | `LOG_TCP_HOST`, `LOG_TCP_PORT` |
| `off`             | No log plugin                                                   | —                             |

Switching transports leaves the previous global plugin in place; remove it via
the Admin API (`DELETE /plugins/{id}`) before re-running the Job.

#### Capturing request/response bodies (per API)

Bodies are opt-in per API because of size/PII/performance concerns. Add an
`x-kong-plugin-post-function` to the API's OpenAPI spec — the provisioner
attaches it per route, and the captured values appear in the structured log
object (`request.body` / `response.body`). Validated recipe:

```yaml
x-kong-plugin-post-function:
  config:
    access:
      # Buffer the upstream response so its body is readable later, and
      # capture the request body (available in the access phase).
      - "kong.service.request.enable_buffering()"
      - "kong.log.set_serialize_value('request.body', kong.request.get_raw_body())"
    header_filter:
      # Read the buffered upstream response body.
      - "kong.log.set_serialize_value('response.body', kong.service.response.get_raw_body())"
```

> Note: `enable_buffering()` disables response streaming for that route. Only
> capture bodies where you need them, and beware of logging sensitive data.

#### Production parity

This local stack runs Kong OSS (`kong/kong:3.9.1`); production runs Kong Gateway
Enterprise (`3.14.0.3`). The logging setup above is portable — it uses only
bundled plugins (`file-log`/`http-log`/`tcp-log`, `post-function`) and stable
PDK calls present in both editions. Differences to account for in prod:

- **Delivery**: plugins are managed via decK (see `jenkins/Jenkinsfile.deck`),
  not an Admin API bootstrap Job — declare the global log plugin and per-API
  `post-function` in decK config / the OpenAPI specs.
- **Transport**: prefer `http-log`/`tcp-log` to a real collector over
  `file-log` → stdout (set `LOG_PLUGIN` accordingly).
- **Admin API**: Enterprise enforces RBAC and workspaces — Admin API calls need
  a `Kong-Admin-Token` and the target workspace; provision the plugin in the
  correct workspace.

## PostgreSQL Database

Two databases are available:

| Database | User | Password | Purpose |
|----------|------|----------|---------|
| kong | kong | kongpass | Kong Gateway |
| appdb | appuser | apppass | Your applications |

### Next.js Configuration

Add to your `.env.local`:

```env
DATABASE_URL="postgresql://appuser:apppass@localhost:5433/appdb"
```

Or with individual variables:

```env
POSTGRES_HOST=localhost
POSTGRES_PORT=5433
POSTGRES_DB=appdb
POSTGRES_USER=appuser
POSTGRES_PASSWORD=apppass
```

### Connection String

```
postgresql://appuser:apppass@localhost:5433/appdb
```

## Jenkins Setup

Jenkins is configured with security enabled via Configuration as Code (JCasC).

- **URL**: http://localhost:8081
- **Username**: admin
- **Password**: admin

### Creating an API Token

1. Log in to Jenkins at http://localhost:8081
2. Click your username (top right) → **Security**
3. Scroll to **Security** section
4. Click **Add new Token** → give it a name → **Generate**
5. Copy the token (it won't be shown again)

### Using the API Token

```bash
# With curl
curl -u admin:YOUR_TOKEN http://localhost:8081/api/json

# Trigger a build
curl -X POST -u admin:YOUR_TOKEN http://localhost:8081/job/JOB_NAME/build
```

## API Key Management

```bash
# Create a consumer
./scripts/utils/manage-keys.sh create-consumer myuser

# Create an API key (auto-generated)
./scripts/utils/manage-keys.sh create-key myuser

# Create an API key (custom)
./scripts/utils/manage-keys.sh create-key myuser my-custom-key

# List keys
./scripts/utils/manage-keys.sh list-keys myuser
```

## Keycloak JWT Integration

For Kong OSS + Keycloak integration, use the JWT plugin:

1. Create a realm and client in Keycloak
2. Get the realm's public key from the OIDC config endpoint
3. Configure Kong JWT plugin with Keycloak's issuer

See `./scripts/utils/configure-auth.sh` for detailed instructions.

## Cleanup

```bash
# Remove services but keep PostgreSQL, Jenkins, Prometheus, and Grafana data
./scripts/teardown.sh

# Remove everything including all data
./scripts/teardown.sh --delete-data
```

PostgreSQL, Jenkins, Prometheus, and Grafana data are persisted in PersistentVolumeClaims and survive normal teardowns.
