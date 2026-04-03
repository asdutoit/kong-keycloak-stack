"""Utility functions for name sanitisation and Lua code generation."""

import re


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
