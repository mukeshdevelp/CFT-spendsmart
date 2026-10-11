#!/usr/bin/env python3
"""Render Helm values: client-a-values.yaml + optional ALB / Keycloak URLs from CloudFormation."""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from copy import deepcopy
from pathlib import Path

import yaml


def stack_outputs(stack_name: str, region: str) -> dict[str, str]:
    out_json = subprocess.check_output(
        [
            "aws",
            "cloudformation",
            "describe-stacks",
            "--stack-name",
            stack_name,
            "--region",
            region,
            "--query",
            "Stacks[0].Outputs",
            "--output",
            "json",
        ],
        text=True,
    )
    return {o["OutputKey"]: o["OutputValue"] for o in json.loads(out_json)}


def public_http_url(host: str, port: int) -> str:
    host = (host or "").strip()
    if not host:
        return ""
    if port in (80, 0):
        return f"http://{host}"
    return f"http://{host}:{port}"


def deep_merge(base: dict, patch: dict) -> dict:
    out = deepcopy(base)
    for key, val in patch.items():
        if key in out and isinstance(out[key], dict) and isinstance(val, dict):
            out[key] = deep_merge(out[key], val)
        else:
            out[key] = val
    return out


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-values", default="client-a-values.yaml")
    parser.add_argument("--out", default="helm-values-rendered.yaml")
    parser.add_argument("--stack-name", required=True)
    parser.add_argument("--region", required=True)
    parser.add_argument(
        "--alb-listener-port",
        type=int,
        default=int(os.environ.get("ALB_LISTENER_PORT", "80")),
        help="Public ALB listener port (browser URL); infra default 80",
    )
    parser.add_argument(
        "--alb-target-port",
        type=int,
        default=int(os.environ.get("ALB_TARGET_PORT", "30080")),
        help="NodePort on workers registered with ALB target group; infra default 30080",
    )
    parser.add_argument(
        "--inject-urls",
        action="store_true",
        help="Set VITE_* from stack AlbDnsName and Keycloak settings",
    )
    parser.add_argument(
        "--keycloak-url",
        default="auto",
        help="VITE_KEYCLOAK_URL when inject-urls; auto = in-cluster Service DNS",
    )
    parser.add_argument("--namespace", default="spendsmart")
    parser.add_argument(
        "--context-out",
        default="helm-deploy-context.env",
        help="Shell exports for bastion (FRONTEND_BASE_URL, ALB_TARGET_PORT, etc.)",
    )
    args = parser.parse_args()

    with open(args.base_values, encoding="utf-8") as f:
        data = yaml.safe_load(f) or {}

    outputs = stack_outputs(args.stack_name, args.region) if args.inject_urls else {}
    alb = outputs.get("AlbDnsName", "") if args.inject_urls else ""
    frontend_url = public_http_url(alb, args.alb_listener_port) if args.inject_urls else ""

    if args.inject_urls and not alb:
        print("Warning: AlbDnsName missing from stack outputs; VITE URLs left empty", file=sys.stderr)

    realm = os.environ.get("KEYCLOAK_REALM", "spendsmart")
    client_id = os.environ.get("KEYCLOAK_CLIENT_ID", "spendsmart-frontend")
    browser_kc = os.environ.get("KEYCLOAK_BROWSER_URL", "").strip()
    if browser_kc:
        keycloak_url = browser_kc
    elif not args.keycloak_url or args.keycloak_url == "auto":
        keycloak_url = f"http://keycloak.{args.namespace}.svc.cluster.local:8080"
    else:
        keycloak_url = args.keycloak_url.replace("{namespace}", args.namespace)

    cloudsentry_url = os.environ.get("CLOUDSENTRY_URL", "").strip()

    if args.inject_urls:
        patch: dict = {
            "frontend": {
                "service": {
                    "type": "NodePort",
                    "port": 80,
                    "targetPort": 80,
                },
                "configMap": {
                    "data": {
                        "VITE_API_BASE_URL": frontend_url,
                        "VITE_CLOUD_SENTRY_API_BASE_URL": cloudsentry_url,
                        "VITE_KEYCLOAK_CLIENT_ID": client_id,
                        "VITE_KEYCLOAK_REALM": realm,
                        "VITE_KEYCLOAK_URL": keycloak_url,
                    },
                },
            },
        }
        if frontend_url:
            existing = (
                data.get("frontend", {})
                .get("nginx", {})
                .get("csp", {})
                .get("connectSrc", [])
            )
            if isinstance(existing, list) and frontend_url not in existing:
                patch.setdefault("frontend", {}).setdefault("nginx", {}).setdefault("csp", {})[
                    "connectSrc"
                ] = existing + [frontend_url]
        data = deep_merge(data, patch)

    Path(args.out).write_text(yaml.safe_dump(data, default_flow_style=False), encoding="utf-8")
    print(f"Wrote {args.out}")

    Path(args.context_out).write_text(
        "\n".join(
            [
                f"export FRONTEND_BASE_URL={frontend_url}",
                f"export FRONTEND_PUBLIC_URL={frontend_url}",
                f"export ALB_DNS_NAME={alb}",
                f"export ALB_LISTENER_PORT={args.alb_listener_port}",
                f"export ALB_TARGET_PORT={args.alb_target_port}",
                f"export KEYCLOAK_REALM={realm}",
                f"export KEYCLOAK_CLIENT_ID={client_id}",
                f"export NAMESPACE={args.namespace}",
                "",
            ]
        ),
        encoding="utf-8",
    )
    print(f"Wrote {args.context_out}")


if __name__ == "__main__":
    main()
