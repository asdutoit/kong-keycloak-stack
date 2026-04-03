"""Load OpenAPI spec and extract Kong-related metadata."""

from __future__ import annotations

import json
import os
from dataclasses import dataclass, field
from urllib.parse import urlparse

from utils import sanitize_name, sanitize_resource_name


@dataclass
class SpecMetadata:
    """All derived metadata needed by downstream modules."""

    spec: dict
    api_title: str
    api_version: str
    environment: str
    env_suffix: str
    api_name: str
    resource_name: str
    upstream_url: str
    protocol: str
    host: str
    port: int
    upstream_path: str
    service_defaults: dict
    route_prefix: str
    strip_prefix: bool
    spec_id: str
    service_tags: list[str] = field(default_factory=list)


def load_spec() -> dict:
    """Load OpenAPI spec from file (preferred, DinD-safe) or environment variable."""
    spec_file = os.environ.get("OPENAPI_SPEC_FILE")
    if spec_file and os.path.exists(spec_file):
        with open(spec_file) as f:
            return json.loads(f.read())
    return json.loads(os.environ.get("OPENAPI_SPEC_JSON", "{}"))


def extract_metadata(spec: dict) -> SpecMetadata:
    """Parse spec and environment variables into a single metadata object."""
    info = spec.get("info", {})
    api_title = info.get("title", "unnamed-api")
    api_version = info.get("version", "1.0.0")

    environment = os.environ.get("ENVIRONMENT", "dev")
    env_suffix = "" if environment in ("prod", "production") else f"-{environment}"
    spec_id = os.environ.get("SPEC_ID", "")

    api_name = sanitize_name(api_title) + env_suffix
    resource_name = sanitize_resource_name(api_title) + env_suffix

    # Upstream URL — per-environment override takes priority
    upstream_url_override = os.environ.get("UPSTREAM_URL")
    service_defaults = spec.get("x-kong-service-defaults", {})
    if upstream_url_override:
        upstream_url = upstream_url_override
    else:
        upstream_url = service_defaults.get("url") or (
            spec.get("servers", [{}])[0].get("url", "http://localhost:8080")
        )

    parsed = urlparse(upstream_url)
    protocol = parsed.scheme or "http"
    host = parsed.hostname or parsed.netloc
    port = parsed.port or (443 if protocol == "https" else 80)
    upstream_path = parsed.path.rstrip("/") or ""

    if not host:
        raise ValueError(
            f"No host found in upstream URL '{upstream_url}'. "
            "Configure x-kong-service-defaults.url with a full URL"
        )

    # Route prefix
    route_prefix_config = spec.get("x-kong-route-prefix", {})
    route_prefix = route_prefix_config.get("prefix", f"/{resource_name}").rstrip("/")
    if route_prefix_config.get("prefix") and env_suffix:
        route_prefix = route_prefix + env_suffix
    strip_prefix = route_prefix_config.get("stripPrefix", True)

    # Service tags with owner metadata
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

    return SpecMetadata(
        spec=spec,
        api_title=api_title,
        api_version=api_version,
        environment=environment,
        env_suffix=env_suffix,
        api_name=api_name,
        resource_name=resource_name,
        upstream_url=upstream_url,
        protocol=protocol,
        host=host,
        port=port,
        upstream_path=upstream_path,
        service_defaults=service_defaults,
        route_prefix=route_prefix,
        strip_prefix=strip_prefix,
        spec_id=spec_id,
        service_tags=service_tags,
    )
