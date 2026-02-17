#!/usr/bin/env python3
"""Create Jenkins pipeline jobs from Jenkinsfiles via the Jenkins REST API."""

import html
import json
import sys
import urllib.request
import urllib.error
import urllib.parse
from pathlib import Path

JOBS = [
    {
        "name": "kong-api-deploy",
        "file": "Jenkinsfile.deck",
        "desc": "Kong Gateway provisioning via decK",
        "params": [
            ("SPEC_ID", "string", "Database spec ID"),
            ("SPEC_NAME", "string", "Service name/tag"),
            ("SPEC_CONTENT", "text", "Base64-encoded OpenAPI spec"),
            ("ACTION", "string", "Action: deploy or deprovision"),
            ("ENVIRONMENT", "string", "Deployment environment"),
            ("ROUTE_PREFIX", "string", "Path prefix for deck namespace"),
            ("CALLBACK_URL", "string", "Callback URL for status updates"),
            ("KONG_ADMIN_URL", "string", "Kong Admin URL"),
            ("PLATFORM", "string", "Platform slug"),
        ],
    },
    {
        "name": "kong-pulumi-deploy",
        "file": "Jenkinsfile.pulumi",
        "desc": "Kong Gateway provisioning via Pulumi",
        "params": [
            ("SPEC_ID", "string", "Spec ID from database"),
            ("SPEC_NAME", "string", "Sanitized API name (stack name)"),
            ("ENVIRONMENT", "string", "Deployment environment"),
            ("SPEC_CONTENT", "text", "Base64-encoded OpenAPI spec JSON"),
            ("ROUTE_PREFIX", "string", "Route prefix"),
            ("CALLBACK_URL", "string", "Callback URL for status updates"),
            ("ACTION", "string", "Action: deploy or destroy"),
            ("KONG_ADMIN_URL", "string", "Kong Admin URL"),
            ("PLATFORM", "string", "Platform slug"),
        ],
    },
]


def build_params_xml(params: list) -> str:
    xml = ""
    for name, ptype, desc in params:
        if ptype == "text":
            xml += f"""
        <hudson.model.TextParameterDefinition>
          <name>{name}</name>
          <description>{desc}</description>
          <defaultValue></defaultValue>
        </hudson.model.TextParameterDefinition>"""
        else:
            xml += f"""
        <hudson.model.StringParameterDefinition>
          <name>{name}</name>
          <description>{desc}</description>
          <defaultValue></defaultValue>
          <trim>false</trim>
        </hudson.model.StringParameterDefinition>"""
    return xml


def build_job_xml(script: str, desc: str, params: list) -> str:
    escaped = html.escape(script)
    params_xml = build_params_xml(params)
    return f"""<?xml version="1.1" encoding="UTF-8"?>
<flow-definition plugin="workflow-job">
  <description>{desc}</description>
  <keepDependencies>false</keepDependencies>
  <properties>
    <hudson.model.ParametersDefinitionProperty>
      <parameterDefinitions>{params_xml}
      </parameterDefinitions>
    </hudson.model.ParametersDefinitionProperty>
  </properties>
  <definition class="org.jenkinsci.plugins.workflow.cps.CpsFlowDefinition" plugin="workflow-cps">
    <script>{escaped}</script>
    <sandbox>false</sandbox>
  </definition>
  <triggers/>
  <disabled>false</disabled>
</flow-definition>"""


def get_crumb(jenkins_url: str, auth: str) -> tuple[str, str, str]:
    """Get CSRF crumb and session cookie."""
    req = urllib.request.Request(f"{jenkins_url}/crumbIssuer/api/json")
    req.add_header("Authorization", "Basic " + __import__("base64").b64encode(auth.encode()).decode())
    resp = urllib.request.urlopen(req)
    cookie = resp.headers.get("Set-Cookie", "").split(";")[0]
    data = json.loads(resp.read())
    return data["crumbRequestField"], data["crumb"], cookie


def jenkins_request(url: str, data: bytes, auth: str, crumb_field: str, crumb_value: str, cookie: str) -> int:
    """Make a Jenkins API request, return HTTP status."""
    req = urllib.request.Request(url, data=data, method="POST")
    req.add_header("Content-Type", "application/xml")
    req.add_header("Authorization", "Basic " + __import__("base64").b64encode(auth.encode()).decode())
    req.add_header(crumb_field, crumb_value)
    if cookie:
        req.add_header("Cookie", cookie)
    try:
        resp = urllib.request.urlopen(req)
        return resp.status
    except urllib.error.HTTPError as e:
        return e.code


def main():
    jenkins_dir = Path(sys.argv[1])
    jenkins_url = sys.argv[2]
    auth = sys.argv[3]

    for job in JOBS:
        jenkinsfile = jenkins_dir / job["file"]
        if not jenkinsfile.exists():
            print(f"  Skipping {job['name']}: {jenkinsfile} not found")
            continue

        script = jenkinsfile.read_text()
        config_xml = build_job_xml(script, job["desc"], job["params"])
        xml_bytes = config_xml.encode("utf-8")

        crumb_field, crumb_value, cookie = get_crumb(jenkins_url, auth)

        # Check if job exists
        check_req = urllib.request.Request(f"{jenkins_url}/job/{job['name']}/api/json")
        check_req.add_header("Authorization", "Basic " + __import__("base64").b64encode(auth.encode()).decode())
        try:
            urllib.request.urlopen(check_req)
            exists = True
        except urllib.error.HTTPError:
            exists = False

        if exists:
            # Delete and recreate (update via config.xml can fail with 500)
            crumb_field, crumb_value, cookie = get_crumb(jenkins_url, auth)
            del_req = urllib.request.Request(f"{jenkins_url}/job/{job['name']}/doDelete", method="POST", data=b"")
            del_req.add_header("Authorization", "Basic " + __import__("base64").b64encode(auth.encode()).decode())
            del_req.add_header(crumb_field, crumb_value)
            if cookie:
                del_req.add_header("Cookie", cookie)
            try:
                urllib.request.urlopen(del_req)
            except urllib.error.HTTPError:
                pass
            # Fresh crumb after delete
            crumb_field, crumb_value, cookie = get_crumb(jenkins_url, auth)

        status = jenkins_request(
            f"{jenkins_url}/createItem?name={job['name']}",
            xml_bytes, auth, crumb_field, crumb_value, cookie,
        )

        if status in (200, 201):
            print(f"  Jenkins job '{job['name']}' configured successfully.")
        else:
            print(f"  WARNING: Failed to configure '{job['name']}' (HTTP {status}).")

    # Approve all pending scripts (non-sandboxed pipelines require approval)
    approve_pending_scripts(jenkins_url, auth)


def approve_pending_scripts(jenkins_url: str, auth: str):
    """Approve all pending pipeline scripts via the Jenkins script console."""
    crumb_field, crumb_value, cookie = get_crumb(jenkins_url, auth)
    groovy = (
        "org.jenkinsci.plugins.scriptsecurity.scripts.ScriptApproval.get()"
        ".pendingScripts.collect { it.hash }.each { "
        "org.jenkinsci.plugins.scriptsecurity.scripts.ScriptApproval.get()"
        '.approveScript(it) }; println("approved")'
    )
    data = urllib.parse.urlencode({"script": groovy}).encode()
    req = urllib.request.Request(f"{jenkins_url}/scriptText", data=data, method="POST")
    req.add_header("Authorization", "Basic " + __import__("base64").b64encode(auth.encode()).decode())
    req.add_header(crumb_field, crumb_value)
    if cookie:
        req.add_header("Cookie", cookie)
    try:
        resp = urllib.request.urlopen(req)
        result = resp.read().decode().strip()
        if "approved" in result:
            print("  All pending pipeline scripts approved.")
        else:
            print(f"  Script approval result: {result}")
    except urllib.error.HTTPError as e:
        print(f"  WARNING: Failed to approve scripts (HTTP {e.code}).")


if __name__ == "__main__":
    main()
