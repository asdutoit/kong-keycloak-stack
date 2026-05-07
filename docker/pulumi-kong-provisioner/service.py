"""Create the Kong Upstream + Targets + Service resources.

We always route through a Kong Upstream (never the direct `host` shortcut)
so that adding or removing targets later is additive and so that health
checks and load-balancing algorithms are always configurable.
"""

from __future__ import annotations

import pulumi
import pulumi_kong as kong

from spec_loader import SpecMetadata, UpstreamMeta


def _create_upstream(meta: SpecMetadata) -> kong.Upstream:
    up: UpstreamMeta = meta.upstream
    kwargs: dict = {
        "name": up.name,
        "tags": meta.service_tags,
    }

    # NOTE: pulumi-kong 4.5.x doesn't expose Kong's `algorithm` field on the
    # Upstream resource — only `hash_on` (for consistent-hashing config).
    # Kong defaults to round-robin, which is what we want for the common case.
    # The UI still collects the algorithm preference so it's ready the moment
    # the provider catches up (or we switch to a raw-admin-API approach).
    if up.healthchecks:
        # Pass through whatever shape the spec provided; Kong will validate.
        kwargs["healthchecks"] = up.healthchecks

    return kong.Upstream(f"{meta.resource_name}-upstream", **kwargs)


def _create_targets(meta: SpecMetadata, upstream: kong.Upstream) -> list[kong.Target]:
    created: list[kong.Target] = []
    for idx, t in enumerate(meta.upstream.targets):
        # Resource name must be unique within the stack — derive from index + host
        safe = t.target.replace(":", "-").replace(".", "-")
        resource = f"{meta.resource_name}-target-{idx}-{safe}"
        created.append(
            kong.Target(
                resource,
                target=t.target,
                upstream_id=upstream.id,
                weight=t.weight,
                tags=meta.service_tags,
                # Kong rejects two targets with the same address:port on the
                # same upstream (409 UNIQUE violation), so Pulumi's default
                # create-replacement-then-delete-original order can't apply
                # tag changes here. Force delete-then-create instead. Brief
                # gap (~ms) where the upstream has no target — acceptable for
                # tag-only or weight changes; do not use this path for true
                # backend cutovers.
                opts=pulumi.ResourceOptions(delete_before_replace=True),
            )
        )
    return created


def create_service(meta: SpecMetadata) -> kong.Service:
    """Create a Kong Upstream + Targets + Service. Returns the Service."""
    upstream = _create_upstream(meta)
    targets = _create_targets(meta, upstream)

    service = kong.Service(
        f"{meta.resource_name}-service",
        name=meta.api_name,
        protocol=meta.upstream.protocol,
        # Point the Service at the upstream name — Kong resolves that to the
        # Upstream's target pool at request time.
        host=meta.upstream.name,
        port=443 if meta.upstream.protocol == "https" else 80,
        path=meta.upstream.upstream_path or "/",
        connect_timeout=meta.service_defaults.get("connect_timeout", 60000),
        write_timeout=meta.service_defaults.get("write_timeout", 60000),
        read_timeout=meta.service_defaults.get("read_timeout", 60000),
        tags=meta.service_tags,
        opts=pulumi.ResourceOptions(depends_on=[upstream, *targets]),
    )

    pulumi.export("upstream_name", upstream.name)
    pulumi.export("target_count", len(targets))

    return service
