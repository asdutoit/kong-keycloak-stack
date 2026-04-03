"""
Pulumi program for Kong Gateway API provisioning.

Reads an OpenAPI spec (with x-kong-* extensions) from OPENAPI_SPEC_JSON
environment variable and creates Kong services, routes, and plugins.
"""

import pulumi

from spec_loader import load_spec, extract_metadata
from service import create_service
from plugins import create_service_plugins
from routes import create_routes
from grafana import provision_grafana

# ─── Load spec and derive metadata ───────────────────────────────────────────
spec = load_spec()
meta = extract_metadata(spec)

# ─── Kong resources ──────────────────────────────────────────────────────────
service = create_service(meta)
deferred = create_service_plugins(meta, service)
routes_created = create_routes(meta, service, deferred)

# ─── Pulumi exports ──────────────────────────────────────────────────────────
pulumi.export("api_name", meta.api_name)
pulumi.export("api_version", meta.api_version)
pulumi.export("environment", meta.environment)
pulumi.export("env_suffix", meta.env_suffix)
pulumi.export("service_id", service.id)
pulumi.export("route_prefix", meta.route_prefix)
pulumi.export("routes_created", routes_created)
pulumi.export("routes_count", len(routes_created))

# ─── Grafana (optional) ─────────────────────────────────────────────────────
provision_grafana(meta.api_name, meta.environment)
