#!/usr/bin/env python3
"""Fetch AlbDnsName and app URLs from CloudFormation stack outputs."""
from __future__ import annotations

import argparse
import json
import subprocess
import sys


def stack_outputs(stack_name: str, region: str) -> dict[str, str]:
    out = subprocess.check_output(
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
    return {o["OutputKey"]: o["OutputValue"] for o in json.loads(out)}


def public_url(host: str, port: int) -> str:
    if port in (80, 443):
        return f"http://{host}"
    return f"http://{host}:{port}"


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--stack-name", default=None, help="default: CFN_STACK_NAME env or spendsmart-dev")
    p.add_argument("--region", default=None, help="default: AWS_REGION env or us-east-1")
    p.add_argument("--frontend-port", type=int, default=8080)
    p.add_argument("--backend-port", type=int, default=8081)
    p.add_argument("--keycloak-port", type=int, default=8083)
    p.add_argument("--json", action="store_true", help="print JSON to stdout")
    args = p.parse_args()

    import os

    stack = args.stack_name or os.environ.get("CFN_STACK_NAME", "spendsmart-dev")
    region = args.region or os.environ.get("AWS_REGION", "us-east-1")
    outs = stack_outputs(stack, region)

    alb = outs.get("AlbDnsName", "").strip()
    if not alb:
        print(f"AlbDnsName missing on stack {stack}", file=sys.stderr)
        sys.exit(1)

    urls = {
        "albDns": alb,
        "frontendUrl": outs.get("SpendSmartFrontendUrl") or public_url(alb, args.frontend_port),
        "backendUrl": outs.get("SpendSmartBackendUrl") or public_url(alb, args.backend_port),
        "keycloakUrl": outs.get("SpendSmartKeycloakUrl") or public_url(alb, args.keycloak_port),
    }

    if args.json:
        print(json.dumps(urls, indent=2))
    else:
        for k, v in urls.items():
            print(f"{k}={v}")


if __name__ == "__main__":
    main()
