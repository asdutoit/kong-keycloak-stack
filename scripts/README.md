# Scripts

## Entrypoints (run these)

| Script | What it does |
|--------|--------------|
| `deploy.sh` | Deploys the whole stack: Kustomize base (Kong, Keycloak, Jenkins, monitoring) + the Argo stack via Helm + Keycloak realm + Jenkins jobs. Idempotent. |
| `port-forward.sh` | Starts local port-forwards for all the stack UIs (always targets `docker-desktop`). |
| `teardown.sh` | Removes the stack. `--delete-data` also deletes PVCs and the namespaces. |

## `lib/` — helpers invoked by `deploy.sh`

Not meant to be run directly; `deploy.sh` calls them with the right arguments.

| Script | What it does |
|--------|--------------|
| `install-argo.sh` | Installs Argo CD / Workflows / Rollouts via Helm (versions + values pinned). |
| `create-keycloak-realm.sh` | Provisions the Keycloak realm/clients. |
| `create-jenkins-jobs.py` | Creates/updates the Jenkins pipeline jobs. |

## `utils/` — standalone utilities

Run occasionally, on their own, for specific tasks.

| Script | What it does |
|--------|--------------|
| `configure-auth.sh` | Configures Kong routes, API-key auth, and the Prometheus plugin. |
| `manage-keys.sh` | Create/list Kong consumers and API keys. |
| `bootstrap-local.sh` | Cold-start orchestrator: runs `deploy.sh`, then wires up the local api-onboarding portal + Keycloak. |
| `build-keycloak-theme.sh` | Builds the api-portal Keycloak login theme into a local image. |
| `set-login-theme.sh` | Scopes the login theme to a Keycloak client. |
