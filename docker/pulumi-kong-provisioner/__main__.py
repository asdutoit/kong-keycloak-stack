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
    # Escape special Lua pattern characters in prefix
    escaped_prefix = prefix.replace("-", "%%-").replace(".", "%%.")
    return f"""
local prefix = "{prefix}"
local path = kong.request.get_path()
if path:sub(1, #{len(prefix)}) == prefix then
  local new_path = path:sub({len(prefix) + 1})
  if new_path == "" then new_path = "/" end
  kong.service.request.set_path(new_path)
end
""".strip()


# Load OpenAPI spec from environment
spec_json = os.environ.get("OPENAPI_SPEC_JSON", "{}")
spec = json.loads(spec_json)

# Extract metadata
info = spec.get("info", {})
api_title = info.get("title", "unnamed-api")
api_version = info.get("version", "1.0.0")

# Sanitize names
api_name = sanitize_name(api_title)
resource_name = sanitize_resource_name(api_title)

# Get service configuration
service_defaults = spec.get("x-kong-service-defaults", {})
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
    tags=[api_name, f"v{api_version}"],
)

# Get route prefix configuration
route_prefix_config = spec.get("x-kong-route-prefix", {})
route_prefix = route_prefix_config.get("prefix", f"/{resource_name}").rstrip("/")
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
            methods=[method.upper()],
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
pulumi.export("service_id", service.id)
pulumi.export("route_prefix", route_prefix)
pulumi.export("routes_created", routes_created)
pulumi.export("routes_count", len(routes_created))
