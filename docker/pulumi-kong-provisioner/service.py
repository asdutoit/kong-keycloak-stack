"""Create the Kong service resource."""

import pulumi_kong as kong

from spec_loader import SpecMetadata


def create_service(meta: SpecMetadata) -> kong.Service:
    """Create a Kong service from spec metadata and return the resource."""
    return kong.Service(
        f"{meta.resource_name}-service",
        name=meta.api_name,
        protocol=meta.protocol,
        host=meta.host,
        port=meta.port,
        path=meta.upstream_path or "/",
        connect_timeout=meta.service_defaults.get("connect_timeout", 60000),
        write_timeout=meta.service_defaults.get("write_timeout", 60000),
        read_timeout=meta.service_defaults.get("read_timeout", 60000),
        tags=meta.service_tags,
    )
