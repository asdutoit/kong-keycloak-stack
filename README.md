# Kong + Keycloak + Jenkins Stack

Minimal Kong Gateway with Keycloak and Jenkins for local Kubernetes testing.

## Project Structure

```
kong-keycloak-stack/
├── manifests/
│   ├── namespace.yaml      # kong-system namespace
│   ├── postgres.yaml       # PostgreSQL database
│   ├── keycloak.yaml       # Keycloak identity provider
│   ├── kong.yaml           # Kong gateway
│   ├── jenkins.yaml        # Jenkins CI/CD server
│   └── httpbin.yaml        # httpbin test backend
├── scripts/
│   ├── deploy.sh           # Deploy all services
│   ├── teardown.sh         # Remove all services
│   ├── port-forward.sh     # Start port-forwards
│   ├── configure-auth.sh   # Configure Kong routes & auth
│   └── manage-keys.sh      # API key management
└── README.md
```

## Quick Start

```bash
# Deploy the stack
./scripts/deploy.sh

# Start port-forwards
./scripts/port-forward.sh

# Configure Kong with httpbin service and API key auth
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
2. Click your username (top right) → **Configure**
3. Scroll to **API Token** section
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
# Remove services but keep PostgreSQL and Jenkins data
./scripts/teardown.sh

# Remove everything including all data
./scripts/teardown.sh --delete-data
```

PostgreSQL and Jenkins data are persisted in PersistentVolumeClaims and survive normal teardowns.
