# Kong + Keycloak + Jenkins + Monitoring Stack

Minimal Kong Gateway with Keycloak, Jenkins, Prometheus, and Grafana for local Kubernetes testing.

## Project Structure

```
kong-keycloak-stack/
├── manifests/
│   ├── namespace.yaml      # kong-system namespace
│   ├── postgres.yaml       # PostgreSQL database
│   ├── keycloak.yaml       # Keycloak identity provider
│   ├── kong.yaml           # Kong gateway
│   ├── jenkins.yaml        # Jenkins CI/CD server
│   ├── httpbin.yaml        # httpbin test backend
│   ├── prometheus.yaml     # Prometheus metrics collection
│   └── grafana.yaml        # Grafana dashboards & visualization
├── scripts/
│   ├── deploy.sh           # Deploy all services
│   ├── teardown.sh         # Remove all services
│   ├── port-forward.sh     # Start port-forwards
│   ├── configure-auth.sh   # Configure Kong routes, auth & Prometheus plugin
│   └── manage-keys.sh      # API key management
└── README.md
```

## Quick Start

```bash
# Deploy the stack
./scripts/deploy.sh

# Start port-forwards
./scripts/port-forward.sh

# Configure Kong with httpbin service, API key auth, and Prometheus plugin
./scripts/configure-auth.sh

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

## Monitoring

### Prometheus

Prometheus scrapes Kong metrics every 15s. After running `configure-auth.sh`, the global Prometheus plugin is enabled on Kong.

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
- **Pre-loaded dashboard**: Kong Gateway Overview (8 panels)
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
./scripts/manage-keys.sh create-consumer myuser

# Create an API key (auto-generated)
./scripts/manage-keys.sh create-key myuser

# Create an API key (custom)
./scripts/manage-keys.sh create-key myuser my-custom-key

# List keys
./scripts/manage-keys.sh list-keys myuser
```

## Keycloak JWT Integration

For Kong OSS + Keycloak integration, use the JWT plugin:

1. Create a realm and client in Keycloak
2. Get the realm's public key from the OIDC config endpoint
3. Configure Kong JWT plugin with Keycloak's issuer

See `./scripts/configure-auth.sh` for detailed instructions.

## Cleanup

```bash
# Remove services but keep PostgreSQL, Jenkins, Prometheus, and Grafana data
./scripts/teardown.sh

# Remove everything including all data
./scripts/teardown.sh --delete-data
```

PostgreSQL, Jenkins, Prometheus, and Grafana data are persisted in PersistentVolumeClaims and survive normal teardowns.
