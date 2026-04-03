"""Service-level Kong plugin creation."""

from __future__ import annotations

from dataclasses import dataclass, field

import pulumi
import pulumi_kong as kong

from spec_loader import SpecMetadata


@dataclass
class DeferredServerless:
    """Pre/post-function configs that are deferred to route-level creation.

    Kong only runs the most-specific plugin scope — a route-level pre-function
    would shadow a service-level one. So we collect them here and merge them
    into every route in routes.py.
    """

    pre_function: dict = field(default_factory=dict)
    post_function: dict = field(default_factory=dict)


def create_service_plugins(
    meta: SpecMetadata,
    service: kong.Service,
) -> DeferredServerless:
    """Iterate spec-root x-kong-plugin-* extensions and create service-level plugins.

    Pre-function and post-function plugins are *not* created here — they are
    returned in a DeferredServerless so routes.py can merge them per-route.
    """
    deferred = DeferredServerless()

    for key, value in meta.spec.items():
        if not key.startswith("x-kong-plugin-") or not isinstance(value, dict):
            continue

        plugin_name = key.replace("x-kong-plugin-", "")
        plugin_config = value.get("config", {})

        if plugin_name == "pre-function":
            deferred.pre_function = plugin_config
            continue
        if plugin_name == "post-function":
            deferred.post_function = plugin_config
            continue

        kong.Plugin(
            f"{meta.resource_name}-svc-{plugin_name}",
            name=plugin_name,
            service_id=service.id,
            config_json=pulumi.Output.json_dumps(plugin_config) if plugin_config else None,
            tags=[meta.api_name, f"v{meta.api_version}", "service-level"],
        )

    return deferred
