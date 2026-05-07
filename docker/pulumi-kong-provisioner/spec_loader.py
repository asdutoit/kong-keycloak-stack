"""Load OpenAPI spec and extract Kong-related metadata."""

from __future__ import annotations

import json
import os
from dataclasses import dataclass, field
from urllib.parse import urlparse

from utils import sanitize_name, sanitize_resource_name


@dataclass
class TargetMeta:
    """A single backend target for a Kong Upstream."""

    target: str  # host:port
    weight: int = 100


@dataclass
class UpstreamMeta:
    """Kong Upstream config — always present, at least one target."""

    name: str  # Kong Upstream resource name (also what Service.host points at)
    protocol: str  # http | https (Kong Service protocol)
    algorithm: str  # round-robin | least-connections | consistent-hashing
    targets: list[TargetMeta]
    upstream_path: str  # path prefix forwarded to targets; usually ""
    healthchecks: dict | None = None


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
    upstream: UpstreamMeta
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


def _build_upstream_meta(spec: dict, resource_name: str) -> UpstreamMeta:
    """Produce an UpstreamMeta from the spec.

    Priority order:
      1. `x-kong-upstream` (new canonical shape) — multi-target + scheme + algorithm.
      2. UPSTREAM_URL env var (per-environment deploy override).
      3. `x-kong-service-defaults.url` (legacy single URL).
      4. `servers[0].url` (legacy OpenAPI fallback).

    Back-compat (2-4) is converted into a single-target UpstreamMeta.
    """
    upstream_ext = spec.get("x-kong-upstream") or {}
    raw_targets = upstream_ext.get("targets") if isinstance(upstream_ext, dict) else None
    upstream_url_override = os.environ.get("UPSTREAM_URL")
    service_defaults = spec.get("x-kong-service-defaults", {}) or {}

    upstream_name = f"{resource_name}-upstream"

    if isinstance(raw_targets, list) and raw_targets:
        protocol = "https" if upstream_ext.get("scheme") == "https" else "http"
        algorithm = upstream_ext.get("algorithm", "round-robin")
        targets = [
            TargetMeta(
                target=str(t.get("target")).strip(),
                weight=int(t.get("weight", 100)),
            )
            for t in raw_targets
            if isinstance(t, dict) and t.get("target")
        ]
        if not targets:
            raise ValueError("x-kong-upstream.targets contains no valid entries")
        return UpstreamMeta(
            name=upstream_name,
            protocol=protocol,
            algorithm=algorithm,
            targets=targets,
            upstream_path="",
            healthchecks=upstream_ext.get("healthchecks"),
        )

    # Legacy single-URL path — convert to a one-target upstream.
    legacy_url = (
        upstream_url_override
        or service_defaults.get("url")
        or (spec.get("servers", [{}])[0].get("url") if spec.get("servers") else None)
    )
    if not legacy_url:
        raise ValueError(
            "No upstream configured. Provide `x-kong-upstream.targets` or a legacy "
            "`x-kong-service-defaults.url` / `servers[0].url`."
        )

    parsed = urlparse(legacy_url)
    protocol = parsed.scheme or "http"
    host = parsed.hostname or parsed.netloc
    port = parsed.port or (443 if protocol == "https" else 80)
    if not host:
        raise ValueError(
            f"No host found in upstream URL '{legacy_url}'. "
            "Provide a full URL (http://host:port) or use x-kong-upstream.targets."
        )
    upstream_path = parsed.path.rstrip("/") or ""
    return UpstreamMeta(
        name=upstream_name,
        protocol=protocol,
        algorithm="round-robin",
        targets=[TargetMeta(target=f"{host}:{port}", weight=100)],
        upstream_path=upstream_path,
        healthchecks=None,
    )


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

    upstream = _build_upstream_meta(spec, resource_name)
    service_defaults = spec.get("x-kong-service-defaults", {}) or {}

    # Route prefix. The env suffix on the path is only useful when multiple
    # envs share one Kong (single-cluster docker-desktop test setup) — set
    # PATH_INCLUDES_ENV_SUFFIX=true for that case. Real org platforms run a
    # separate cluster per env, where the gateway host already disambiguates,
    # and a path suffix would just diverge dev/prd URLs for no benefit.
    path_includes_suffix = os.environ.get("PATH_INCLUDES_ENV_SUFFIX", "false").lower() == "true"
    path_env_suffix = env_suffix if path_includes_suffix else ""

    route_prefix_config = spec.get("x-kong-route-prefix", {})
    rp_service = route_prefix_config.get("serviceName", "")
    rp_version = route_prefix_config.get("version", "")
    if rp_service:
        suffixed = f"{rp_service}{path_env_suffix}" if path_env_suffix else rp_service
        route_prefix = f"/{suffixed}"
        if rp_version:
            route_prefix += f"/{rp_version}"
    else:
        # Legacy specs that only have `prefix` (no structured serviceName/version)
        # — fall back to the original behaviour of suffixing the whole prefix.
        route_prefix = route_prefix_config.get("prefix", f"/{resource_name}").rstrip("/")
        if route_prefix_config.get("prefix") and path_env_suffix:
            route_prefix = route_prefix + path_env_suffix
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
        upstream=upstream,
        service_defaults=service_defaults,
        route_prefix=route_prefix,
        strip_prefix=strip_prefix,
        spec_id=spec_id,
        service_tags=service_tags,
    )
