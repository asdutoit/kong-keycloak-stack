"""
Pulumi program for Kong Gateway API provisioning.

Reads an OpenAPI spec (with x-kong-* extensions) from OPENAPI_SPEC_JSON
environment variable and creates Kong services, routes, and plugins.
"""

import json
import os
import re
from urllib.parse import urlparse

import pulumi
import pulumi_kong as kong
from pulumiverse_grafana import Provider as GrafanaProvider
from pulumiverse_grafana.oss import Dashboard as GrafanaDashboard
from pulumiverse_grafana.alerting import (
    RuleGroup as GrafanaRuleGroup,
    RuleGroupRuleArgs,
    RuleGroupRuleDataArgs,
    RuleGroupRuleDataRelativeTimeRangeArgs,
)


def sanitize_name(name: str) -> str:
    """Sanitize name for Kong (alphanumeric, dots, hyphens, underscores, tildes)."""
    sanitized = name.lower().replace(" ", "-")
    sanitized = re.sub(r"[^a-zA-Z0-9._~-]", "", sanitized).strip("-")
    return sanitized or "unnamed"


def sanitize_resource_name(name: str) -> str:
    """Sanitize for Pulumi resource names (more restrictive)."""
    sanitized = re.sub(r"[^a-zA-Z0-9-]", "-", name.lower())
    sanitized = re.sub(r"-+", "-", sanitized).strip("-")
    return sanitized or "unnamed"


def generate_prefix_strip_lua(prefix: str) -> str:
    """Generate Lua code for pre-function plugin to strip prefix from path."""
    prefix_len = len(prefix)
    return f"""
local prefix = "{prefix}"
local path = kong.request.get_path()
if path:sub(1, {prefix_len}) == prefix then
  local new_path = path:sub({prefix_len + 1})
  if new_path == "" then new_path = "/" end
  kong.service.request.set_path(new_path)
end
""".strip()


# Load OpenAPI spec from file (preferred, DinD-safe) or environment variable
spec_file = os.environ.get("OPENAPI_SPEC_FILE")
if spec_file and os.path.exists(spec_file):
    with open(spec_file) as f:
        spec_json = f.read()
else:
    spec_json = os.environ.get("OPENAPI_SPEC_JSON", "{}")
spec = json.loads(spec_json)

# Extract metadata
info = spec.get("info", {})
api_title = info.get("title", "unnamed-api")
api_version = info.get("version", "1.0.0")

# Environment suffix: -dev, -test, -acc, none for prod
environment = os.environ.get("ENVIRONMENT", "dev")
env_suffix = "" if environment in ("prod", "production") else f"-{environment}"

# Spec ID (used for tagging, not for naming — uniqueness enforced at app level per platform)
spec_id = os.environ.get("SPEC_ID", "")

# Sanitize names (with environment suffix only — clean URLs like /httpbin-dev)
api_name = sanitize_name(api_title) + env_suffix
resource_name = sanitize_resource_name(api_title) + env_suffix

# Get service configuration
# Per-environment upstream URL override (set by Jenkins from promotion request)
upstream_url_override = os.environ.get("UPSTREAM_URL")
service_defaults = spec.get("x-kong-service-defaults", {})
if upstream_url_override:
    upstream_url = upstream_url_override
else:
    upstream_url = service_defaults.get("url") or (
        spec.get("servers", [{}])[0].get("url", "http://localhost:8080")
    )

# Parse URL
parsed = urlparse(upstream_url)
protocol = parsed.scheme or "http"
host = parsed.hostname or parsed.netloc
port = parsed.port or (443 if protocol == "https" else 80)
upstream_path = parsed.path.rstrip("/") or ""

# Validate that we have a host
if not host:
    raise ValueError(
        f"No host found in upstream URL '{upstream_url}'. "
        "Configure x-kong-service-defaults.url with a full URL"
    )

# Build service tags with owner metadata (makes it easy to identify owners in Kong)
service_tags = [api_name, f"v{api_version}"]
owner_name = os.environ.get("OWNER_NAME")
owner_email = os.environ.get("OWNER_EMAIL")
team_name = os.environ.get("TEAM_NAME")
if spec_id:
    service_tags.append(f"spec-id:{spec_id}")
if owner_email:
    service_tags.append(f"owner:{owner_email}")
if owner_name:
    service_tags.append(f"owner-name:{owner_name}")
if team_name:
    service_tags.append(f"team:{team_name}")

# Create Service
service = kong.Service(
    f"{resource_name}-service",
    name=api_name,
    protocol=protocol,
    host=host,
    port=port,
    path=upstream_path or "/",
    connect_timeout=service_defaults.get("connect_timeout", 60000),
    write_timeout=service_defaults.get("write_timeout", 60000),
    read_timeout=service_defaults.get("read_timeout", 60000),
    tags=service_tags,
)

# Get route prefix configuration
route_prefix_config = spec.get("x-kong-route-prefix", {})
# Default prefix uses resource_name which already has env suffix
route_prefix = route_prefix_config.get("prefix", f"/{resource_name}").rstrip("/")
# If a custom prefix is set, append env suffix to it
if route_prefix_config.get("prefix") and env_suffix:
    route_prefix = route_prefix + env_suffix
strip_prefix = route_prefix_config.get("stripPrefix", True)

# For per-endpoint routes with prefix stripping, we use pre-function plugin
# instead of Kong's strip_path (which strips the entire matched path)
use_prefix_strip_plugin = strip_prefix and route_prefix

# Service-level plugins (from x-kong-plugin-* at spec root)
for key, value in spec.items():
    if not key.startswith("x-kong-plugin-") or not isinstance(value, dict):
        continue
    plugin_name = key.replace("x-kong-plugin-", "")
    plugin_config = value.get("config", {})

    kong.Plugin(
        f"{resource_name}-svc-{plugin_name}",
        name=plugin_name,
        service_id=service.id,
        config_json=pulumi.Output.json_dumps(plugin_config) if plugin_config else None,
        tags=[api_name, f"v{api_version}", "service-level"],
    )

# HTTP methods mapping
HTTP_METHODS = ["get", "post", "put", "patch", "delete", "head", "options"]

# Create routes and plugins per endpoint
paths = spec.get("paths", {})
routes_created = []

# Generate prefix strip Lua code once if needed
prefix_strip_lua = generate_prefix_strip_lua(route_prefix) if use_prefix_strip_plugin else None

for path, path_item in paths.items():
    if not isinstance(path_item, dict):
        continue

    # Path-level plugins (apply to all methods on this path)
    path_plugins = {}
    for key, value in path_item.items():
        if key.startswith("x-kong-plugin-") and isinstance(value, dict):
            plugin_name = key.replace("x-kong-plugin-", "")
            path_plugins[plugin_name] = value.get("config", {})

    for method in HTTP_METHODS:
        operation = path_item.get(method)
        if not operation or not isinstance(operation, dict):
            continue

        # Create route name from path and method
        path_slug = sanitize_resource_name(
            path.replace("/", "-").replace("{", "").replace("}", "")
        )
        route_name = f"{api_name}-{method}-{path_slug}".strip("-")
        route_resource_name = f"{resource_name}-{method}-{path_slug}".strip("-")

        # Kong route path = prefix + original path
        kong_path = f"{route_prefix}{path}"

        # Sanitize path for tags (no slashes allowed)
        path_tag = path.replace("/", "-").strip("-") or "root"

        # Create route for this endpoint
        # Note: strip_path=False because we use pre-function plugin to strip only the prefix
        route = kong.Route(
            route_resource_name,
            name=route_name,
            service_id=service.id,
            protocols=["http", "https"],
            paths=[kong_path],
            methods=[method.upper(), "OPTIONS"],
            strip_path=False,  # We handle prefix stripping via pre-function plugin
            tags=[api_name, f"v{api_version}", method, f"path:{path_tag}"],
        )
        routes_created.append(route_name)

        # Add pre-function plugin to strip prefix if needed
        if use_prefix_strip_plugin:
            kong.Plugin(
                f"{route_resource_name}-prefix-strip",
                name="pre-function",
                route_id=route.id,
                config_json=pulumi.Output.json_dumps({
                    "access": [prefix_strip_lua],
                }),
                tags=[api_name, f"v{api_version}", "prefix-strip"],
            )

        # Collect operation-level plugins
        operation_plugins = dict(path_plugins)  # Start with path-level plugins
        for key, value in operation.items():
            if key.startswith("x-kong-plugin-") and isinstance(value, dict):
                plugin_name = key.replace("x-kong-plugin-", "")
                operation_plugins[plugin_name] = value.get("config", {})

        # Create plugins for this route
        for plugin_name, plugin_config in operation_plugins.items():
            kong.Plugin(
                f"{route_resource_name}-{plugin_name}",
                name=plugin_name,
                route_id=route.id,
                config_json=(
                    pulumi.Output.json_dumps(plugin_config) if plugin_config else None
                ),
                tags=[api_name, f"v{api_version}", method, f"path:{path_tag}"],
            )

# Exports
pulumi.export("api_name", api_name)
pulumi.export("api_version", api_version)
pulumi.export("environment", environment)
pulumi.export("env_suffix", env_suffix)
pulumi.export("service_id", service.id)
pulumi.export("route_prefix", route_prefix)
pulumi.export("routes_created", routes_created)
pulumi.export("routes_count", len(routes_created))


# ─── Grafana Dashboard & Alert Provisioning ───────────────────────────────────
# Enabled when GRAFANA_URL, GRAFANA_API_KEY, and GRAFANA_DASHBOARD_ENABLED are set.
# This provisions the same 6-panel dashboard and alert rules that lib/grafana.ts
# previously created via the Grafana HTTP API.

grafana_url = os.environ.get("GRAFANA_URL")
grafana_api_key = os.environ.get("GRAFANA_API_KEY")
dashboard_enabled = os.environ.get("GRAFANA_DASHBOARD_ENABLED", "false") == "true"

# Platform from env (set by Jenkinsfile from deploy.yaml)
# Note: environment is already read at the top for env_suffix
platform = os.environ.get("PLATFORM", "local")


def build_dashboard(service_name: str, plat: str, env: str) -> dict:
    """Build the 6-panel Grafana dashboard JSON (mirrors lib/grafana.ts)."""
    uid = re.sub(r"[^a-zA-Z0-9-]", "-", f"{service_name}-{plat}-{env}")
    title = f"{service_name} — {plat}/{env}"
    datasource = {"type": "prometheus", "uid": "prometheus"}

    return {
        "uid": uid,
        "title": title,
        "tags": ["auto-provisioned", "tapir-flow", plat, env],
        "timezone": "browser",
        "refresh": "30s",
        "time": {"from": "now-1h", "to": "now"},
        "panels": [
            {
                "title": "Request Rate",
                "type": "timeseries",
                "gridPos": {"h": 8, "w": 12, "x": 0, "y": 0},
                "datasource": datasource,
                "targets": [
                    {
                        "expr": f'rate(kong_http_requests_total{{service="{service_name}"}}[5m])',
                        "legendFormat": "{{code}}",
                    }
                ],
            },
            {
                "title": "Latency Distribution (p50/p95/p99)",
                "type": "timeseries",
                "gridPos": {"h": 8, "w": 12, "x": 12, "y": 0},
                "datasource": datasource,
                "targets": [
                    {
                        "expr": f'histogram_quantile(0.50, rate(kong_request_latency_ms_bucket{{service="{service_name}"}}[5m]))',
                        "legendFormat": "p50",
                    },
                    {
                        "expr": f'histogram_quantile(0.95, rate(kong_request_latency_ms_bucket{{service="{service_name}"}}[5m]))',
                        "legendFormat": "p95",
                    },
                    {
                        "expr": f'histogram_quantile(0.99, rate(kong_request_latency_ms_bucket{{service="{service_name}"}}[5m]))',
                        "legendFormat": "p99",
                    },
                ],
                "fieldConfig": {"defaults": {"unit": "ms"}},
            },
            {
                "title": "Error Rate (5xx)",
                "type": "timeseries",
                "gridPos": {"h": 8, "w": 12, "x": 0, "y": 8},
                "datasource": datasource,
                "targets": [
                    {
                        "expr": f'rate(kong_http_requests_total{{service="{service_name}",code=~"5.."}}[5m]) / rate(kong_http_requests_total{{service="{service_name}"}}[5m]) * 100',
                        "legendFormat": "error %",
                    }
                ],
                "fieldConfig": {
                    "defaults": {
                        "unit": "percent",
                        "thresholds": {
                            "steps": [
                                {"value": 0, "color": "green"},
                                {"value": 5, "color": "red"},
                            ]
                        },
                    }
                },
            },
            {
                "title": "Upstream Health",
                "type": "stat",
                "gridPos": {"h": 8, "w": 12, "x": 12, "y": 8},
                "datasource": datasource,
                "targets": [
                    {
                        "expr": f'kong_upstream_target_health{{upstream="{service_name}"}}',
                        "legendFormat": "{{target}} — {{state}}",
                    }
                ],
            },
            {
                "title": "Consumer Traffic",
                "type": "timeseries",
                "gridPos": {"h": 8, "w": 12, "x": 0, "y": 16},
                "datasource": datasource,
                "targets": [
                    {
                        "expr": f'rate(kong_http_requests_total{{service="{service_name}"}}[5m])',
                        "legendFormat": "{{consumer}}",
                    }
                ],
            },
            {
                "title": "Rate Limiting (429s)",
                "type": "timeseries",
                "gridPos": {"h": 8, "w": 12, "x": 12, "y": 16},
                "datasource": datasource,
                "targets": [
                    {
                        "expr": f'rate(kong_http_requests_total{{service="{service_name}",code="429"}}[5m])',
                        "legendFormat": "429 rate-limited",
                    }
                ],
            },
        ],
    }


if grafana_url and grafana_api_key and dashboard_enabled:
    grafana_provider = GrafanaProvider(
        "grafana",
        url=grafana_url,
        auth=grafana_api_key,
    )

    dashboard_json = build_dashboard(api_name, platform, environment)

    dashboard_resource = GrafanaDashboard(
        "service-dashboard",
        config_json=json.dumps(dashboard_json),
        overwrite=True,
        opts=pulumi.ResourceOptions(provider=grafana_provider),
    )

    pulumi.export("grafana_dashboard_url", dashboard_resource.url)
    pulumi.export("grafana_dashboard_uid", dashboard_resource.uid)

    # Alert rules (conditional on threshold env vars)
    error_threshold = os.environ.get("ALERT_ERROR_RATE_THRESHOLD")
    latency_threshold = os.environ.get("ALERT_P99_LATENCY_MS")
    notify_channel = os.environ.get("ALERT_NOTIFY_CHANNEL", f"#{api_name}-alerts")

    if error_threshold or latency_threshold:
        alert_rules = []

        if error_threshold:
            alert_rules.append(
                RuleGroupRuleArgs(
                    name=f"{api_name} — High Error Rate",
                    condition="C",
                    for_="5m",
                    labels={"service": api_name, "severity": "warning"},
                    annotations={
                        "summary": f"Error rate for {api_name} exceeds {error_threshold}%",
                    },
                    datas=[
                        RuleGroupRuleDataArgs(
                            ref_id="A",
                            relative_time_range=RuleGroupRuleDataRelativeTimeRangeArgs(
                                from_=300,
                                to=0,
                            ),
                            datasource_uid="prometheus",
                            model=json.dumps({
                                "expr": f'rate(kong_http_requests_total{{service="{api_name}",code=~"5.."}}[5m]) / rate(kong_http_requests_total{{service="{api_name}"}}[5m]) * 100',
                                "refId": "A",
                            }),
                        ),
                        RuleGroupRuleDataArgs(
                            ref_id="C",
                            relative_time_range=RuleGroupRuleDataRelativeTimeRangeArgs(
                                from_=300,
                                to=0,
                            ),
                            datasource_uid="__expr__",
                            model=json.dumps({
                                "type": "threshold",
                                "expression": "A",
                                "conditions": [
                                    {"evaluator": {"type": "gt", "params": [int(error_threshold)]}},
                                ],
                                "refId": "C",
                            }),
                        ),
                    ],
                )
            )

        if latency_threshold:
            alert_rules.append(
                RuleGroupRuleArgs(
                    name=f"{api_name} — High P99 Latency",
                    condition="C",
                    for_="5m",
                    labels={"service": api_name, "severity": "warning"},
                    annotations={
                        "summary": f"P99 latency for {api_name} exceeds {latency_threshold}ms",
                    },
                    datas=[
                        RuleGroupRuleDataArgs(
                            ref_id="A",
                            relative_time_range=RuleGroupRuleDataRelativeTimeRangeArgs(
                                from_=300,
                                to=0,
                            ),
                            datasource_uid="prometheus",
                            model=json.dumps({
                                "expr": f'histogram_quantile(0.99, rate(kong_request_latency_ms_bucket{{service="{api_name}"}}[5m]))',
                                "refId": "A",
                            }),
                        ),
                        RuleGroupRuleDataArgs(
                            ref_id="C",
                            relative_time_range=RuleGroupRuleDataRelativeTimeRangeArgs(
                                from_=300,
                                to=0,
                            ),
                            datasource_uid="__expr__",
                            model=json.dumps({
                                "type": "threshold",
                                "expression": "A",
                                "conditions": [
                                    {"evaluator": {"type": "gt", "params": [int(latency_threshold)]}},
                                ],
                                "refId": "C",
                            }),
                        ),
                    ],
                )
            )

        GrafanaRuleGroup(
            "service-alert-rules",
            name=f"tapir-{api_name}",
            folder_uid="tapir-flow-alerts",
            interval_seconds=60,
            rules=alert_rules,
            opts=pulumi.ResourceOptions(provider=grafana_provider),
        )
