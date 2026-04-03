"""Per-endpoint Kong route and route-level plugin creation."""

from __future__ import annotations

import pulumi
import pulumi_kong as kong

from plugins import DeferredServerless
from spec_loader import SpecMetadata
from utils import generate_prefix_strip_lua, sanitize_resource_name

HTTP_METHODS = ["get", "post", "put", "patch", "delete", "head", "options"]


def create_routes(
    meta: SpecMetadata,
    service: kong.Service,
    deferred: DeferredServerless,
) -> list[str]:
    """Create a Kong route (and associated plugins) for every path+method.

    Returns the list of route names that were created.
    """
    use_prefix_strip = meta.strip_prefix and meta.route_prefix
    prefix_strip_lua = generate_prefix_strip_lua(meta.route_prefix) if use_prefix_strip else None

    paths = meta.spec.get("paths", {})
    routes_created: list[str] = []

    for path, path_item in paths.items():
        if not isinstance(path_item, dict):
            continue

        # Collect path-level plugin overrides (e.g. x-kong-plugin-request-transformer-advanced)
        path_plugins = _collect_path_plugins(path_item)

        for method in HTTP_METHODS:
            operation = path_item.get(method)
            if not operation or not isinstance(operation, dict):
                continue

            path_slug = sanitize_resource_name(
                path.replace("/", "-").replace("{", "").replace("}", "")
            )
            route_name = f"{meta.api_name}-{method}-{path_slug}".strip("-")
            route_resource_name = f"{meta.resource_name}-{method}-{path_slug}".strip("-")
            kong_path = f"{meta.route_prefix}{path}"
            path_tag = path.replace("/", "-").strip("-") or "root"

            route = kong.Route(
                route_resource_name,
                name=route_name,
                service_id=service.id,
                protocols=["http", "https"],
                paths=[kong_path],
                methods=[method.upper(), "OPTIONS"],
                strip_path=False,
                tags=[meta.api_name, f"v{meta.api_version}", method, f"path:{path_tag}"],
            )
            routes_created.append(route_name)

            # Pre-function plugin (prefix stripping + service-level pre-functions)
            _attach_pre_function(
                route, route_resource_name, meta,
                deferred.pre_function, use_prefix_strip, prefix_strip_lua,
            )

            # Post-function plugin
            if deferred.post_function:
                kong.Plugin(
                    f"{route_resource_name}-post-function",
                    name="post-function",
                    route_id=route.id,
                    config_json=pulumi.Output.json_dumps(deferred.post_function),
                    tags=[meta.api_name, f"v{meta.api_version}", "post-function"],
                )

            # Path-level + operation-level plugins
            operation_plugins = dict(path_plugins)
            for key, value in operation.items():
                if key.startswith("x-kong-plugin-") and isinstance(value, dict):
                    plugin_name = key.replace("x-kong-plugin-", "")
                    operation_plugins[plugin_name] = value.get("config", {})

            for plugin_name, plugin_config in operation_plugins.items():
                kong.Plugin(
                    f"{route_resource_name}-{plugin_name}",
                    name=plugin_name,
                    route_id=route.id,
                    config_json=(
                        pulumi.Output.json_dumps(plugin_config) if plugin_config else None
                    ),
                    tags=[meta.api_name, f"v{meta.api_version}", method, f"path:{path_tag}"],
                )

    return routes_created


def _collect_path_plugins(path_item: dict) -> dict[str, dict]:
    """Extract x-kong-plugin-* extensions from a path item."""
    plugins: dict[str, dict] = {}
    for key, value in path_item.items():
        if key.startswith("x-kong-plugin-") and isinstance(value, dict):
            plugin_name = key.replace("x-kong-plugin-", "")
            plugins[plugin_name] = value.get("config", {})
    return plugins


def _attach_pre_function(
    route: kong.Route,
    route_resource_name: str,
    meta: SpecMetadata,
    svc_pre_function_config: dict,
    use_prefix_strip: bool,
    prefix_strip_lua: str | None,
) -> None:
    """Merge prefix-strip Lua and service-level pre-functions into a single route plugin."""
    if not use_prefix_strip and not svc_pre_function_config:
        return

    access_fns: list[str] = []
    if use_prefix_strip and prefix_strip_lua:
        access_fns.append(prefix_strip_lua)

    # Wrap each user function with an OPTIONS guard so CORS preflight
    # requests pass through to the CORS plugin instead of being blocked
    for fn_code in svc_pre_function_config.get("access", []):
        wrapped = (
            'if kong.request.get_method() == "OPTIONS" then return end\n'
            + fn_code
        )
        access_fns.append(wrapped)

    pre_fn_config: dict = {}
    if access_fns:
        pre_fn_config["access"] = access_fns
    for phase in ("header_filter", "body_filter", "log"):
        phase_fns = svc_pre_function_config.get(phase, [])
        if phase_fns:
            pre_fn_config[phase] = phase_fns

    kong.Plugin(
        f"{route_resource_name}-pre-function",
        name="pre-function",
        route_id=route.id,
        config_json=pulumi.Output.json_dumps(pre_fn_config),
        tags=[meta.api_name, f"v{meta.api_version}", "pre-function"],
    )
