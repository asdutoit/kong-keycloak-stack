"""Grafana dashboard and alert rule provisioning.

Enabled when GRAFANA_URL, GRAFANA_API_KEY, and GRAFANA_DASHBOARD_ENABLED are set.
Provisions a 6-panel dashboard and optional alert rules for the Kong service.
"""

from __future__ import annotations

import json
import os
import re

import pulumi
from pulumiverse_grafana import Provider as GrafanaProvider
from pulumiverse_grafana.oss import Dashboard as GrafanaDashboard
from pulumiverse_grafana.alerting import (
    RuleGroup as GrafanaRuleGroup,
    RuleGroupRuleArgs,
    RuleGroupRuleDataArgs,
    RuleGroupRuleDataRelativeTimeRangeArgs,
)


def provision_grafana(api_name: str, environment: str) -> None:
    """Create Grafana dashboard and alert rules if env vars are configured."""
    grafana_url = os.environ.get("GRAFANA_URL")
    grafana_api_key = os.environ.get("GRAFANA_API_KEY")
    dashboard_enabled = os.environ.get("GRAFANA_DASHBOARD_ENABLED", "false") == "true"

    if not (grafana_url and grafana_api_key and dashboard_enabled):
        return

    platform = os.environ.get("PLATFORM", "local")

    grafana_provider = GrafanaProvider(
        "grafana",
        url=grafana_url,
        auth=grafana_api_key,
    )

    dashboard_json = _build_dashboard(api_name, platform, environment)

    dashboard_resource = GrafanaDashboard(
        "service-dashboard",
        config_json=json.dumps(dashboard_json),
        overwrite=True,
        opts=pulumi.ResourceOptions(provider=grafana_provider),
    )

    pulumi.export("grafana_dashboard_url", dashboard_resource.url)
    pulumi.export("grafana_dashboard_uid", dashboard_resource.uid)

    _provision_alerts(api_name, grafana_provider)


def _build_dashboard(service_name: str, platform: str, environment: str) -> dict:
    """Build the 6-panel Grafana dashboard JSON."""
    uid = re.sub(r"[^a-zA-Z0-9-]", "-", f"{service_name}-{platform}-{environment}")
    title = f"{service_name} — {platform}/{environment}"
    datasource = {"type": "prometheus", "uid": "prometheus"}

    return {
        "uid": uid,
        "title": title,
        "tags": ["auto-provisioned", "tapir-flow", platform, environment],
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


def _provision_alerts(api_name: str, grafana_provider: GrafanaProvider) -> None:
    """Create Grafana alert rules if threshold env vars are set."""
    error_threshold = os.environ.get("ALERT_ERROR_RATE_THRESHOLD")
    latency_threshold = os.environ.get("ALERT_P99_LATENCY_MS")

    if not error_threshold and not latency_threshold:
        return

    alert_rules: list[RuleGroupRuleArgs] = []

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
                        relative_time_range=RuleGroupRuleDataRelativeTimeRangeArgs(from_=300, to=0),
                        datasource_uid="prometheus",
                        model=json.dumps({
                            "expr": f'rate(kong_http_requests_total{{service="{api_name}",code=~"5.."}}[5m]) / rate(kong_http_requests_total{{service="{api_name}"}}[5m]) * 100',
                            "refId": "A",
                        }),
                    ),
                    RuleGroupRuleDataArgs(
                        ref_id="C",
                        relative_time_range=RuleGroupRuleDataRelativeTimeRangeArgs(from_=300, to=0),
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
                        relative_time_range=RuleGroupRuleDataRelativeTimeRangeArgs(from_=300, to=0),
                        datasource_uid="prometheus",
                        model=json.dumps({
                            "expr": f'histogram_quantile(0.99, rate(kong_request_latency_ms_bucket{{service="{api_name}"}}[5m]))',
                            "refId": "A",
                        }),
                    ),
                    RuleGroupRuleDataArgs(
                        ref_id="C",
                        relative_time_range=RuleGroupRuleDataRelativeTimeRangeArgs(from_=300, to=0),
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
