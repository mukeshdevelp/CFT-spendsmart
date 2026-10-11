#!/usr/bin/env python3
"""Merge client-a-values.yaml with infra URLs from CloudFormation outputs."""
from __future__ import annotations

import argparse
import os
import subprocess
import sys

import yaml


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-values", default="client-a-values.yaml")
    parser.add_argument("--out", default="helm-values-rendered.yaml")
    parser.add_argument("--stack-name", required=True)
    parser.add_argument("--region", required=True)
    parser.add_argument(
        "--keycloak-url",
        default="auto",
        help="Frontend VITE Keycloak URL; 'auto' → http://keycloak.<namespace>.svc.cluster.local:8080",
    )
    parser.add_argument("--namespace", default="spendsmart")
    parser.add_argument(
        "--context-out",
        default="helm-deploy-context.env",
        help="Shell exports for bastion (FRONTEND_BASE_URL, KEYCLOAK_REALM, etc.)",
    )
    args = parser.parse_args()

    browser_url = os.environ.get("KEYCLOAK_BROWSER_URL", "").strip()
    if browser_url:
        keycloak_url = browser_url
    elif not args.keycloak_url or args.keycloak_url == "auto":
        keycloak_url = f"http://keycloak.{args.namespace}.svc.cluster.local:8080"
    else:
        keycloak_url = args.keycloak_url.replace("{namespace}", args.namespace)

    out_json = subprocess.check_output(
        [
            "aws",
            "cloudformation",
            "describe-stacks",
            "--stack-name",
            args.stack_name,
            "--region",
            args.region,
            "--query",
            "Stacks[0].Outputs",
            "--output",
            "json",
        ],
        text=True,
    )
    import json

    outputs = {o["OutputKey"]: o["OutputValue"] for o in json.loads(out_json)}
    alb = outputs.get("AlbDnsName", "")
    if not alb:
        print("Warning: AlbDnsName missing from stack outputs", file=sys.stderr)
    api_url = f"http://{alb}" if alb else ""

    with open(args.base_values, encoding="utf-8") as f:
        content = f.read()

    replacements = {
        "PLACEHOLDER_API_URL": api_url,
        "PLACEHOLDER_CLOUDSENTRY_URL": os.environ.get("CLOUDSENTRY_URL", ""),
        "PLACEHOLDER_KEYCLOAK_URL": keycloak_url,
    }
    for key, val in replacements.items():
        content = content.replace(key, val)

    data = yaml.safe_load(content) or {}
    Path = __import__("pathlib").Path
    Path(args.out).write_text(yaml.safe_dump(data, default_flow_style=False), encoding="utf-8")
    print(f"Wrote {args.out}")

    realm = os.environ.get("KEYCLOAK_REALM", "spendsmart")
    client_id = os.environ.get("KEYCLOAK_CLIENT_ID", "spendsmart-frontend")
    Path(args.context_out).write_text(
        "\n".join(
            [
                f"export FRONTEND_BASE_URL={api_url}",
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
