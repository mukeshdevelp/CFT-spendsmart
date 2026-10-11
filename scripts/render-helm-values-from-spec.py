#!/usr/bin/env python3
"""Build Helm values YAML for AWS from deploy/spendsmart-cluster-spec.json + ALB URLs."""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path

import yaml


def alb_urls_from_stack(stack: str, region: str) -> dict[str, str]:
    out = subprocess.check_output(
        [str(Path(__file__).resolve().parent / "cfn-fetch-alb-dns.py"),
         "--stack-name", stack, "--region", region, "--json"],
        text=True,
    )
    data = json.loads(out)
    return {
        "frontend": data["frontendUrl"],
        "backend": data["backendUrl"],
        "keycloak": data["keycloakUrl"],
        "alb": data["albDns"],
    }


def main() -> None:
    p = argparse.ArgumentParser(
        description="Helm values from local cluster spec + ALB URLs (from CFN stack or flags).",
    )
    p.add_argument("--spec", default="deploy/spendsmart-cluster-spec.json")
    p.add_argument("--out", default="deploy/helm-values-from-local.yaml")
    p.add_argument(
        "--stack-name",
        default=None,
        help="Fetch AlbDnsName from this stack (default: CFN_STACK_NAME or spendsmart-dev)",
    )
    p.add_argument("--region", default=None, help="AWS region (default: AWS_REGION or us-east-1)")
    p.add_argument("--api-url", default="", help="override backend/VITE_API_BASE_URL")
    p.add_argument("--keycloak-url", default="", help="override VITE_KEYCLOAK_URL")
    p.add_argument("--frontend-url", default="", help="optional, for nginx CSP connectSrc")
    args = p.parse_args()

    stack = args.stack_name or os.environ.get("CFN_STACK_NAME", "spendsmart-dev")
    region = args.region or os.environ.get("AWS_REGION", "us-east-1")

    if args.api_url and args.keycloak_url:
        api_url, keycloak_url, frontend_url = args.api_url, args.keycloak_url, args.frontend_url or ""
    else:
        urls = alb_urls_from_stack(stack, region)
        api_url = args.api_url or urls["backend"]
        keycloak_url = args.keycloak_url or urls["keycloak"]
        frontend_url = args.frontend_url or urls["frontend"]
        print(f"Using ALB from stack {stack}: {urls['alb']}", file=sys.stderr)
        print(f"  frontend={urls['frontend']} backend={api_url} keycloak={keycloak_url}", file=sys.stderr)

    spec = json.loads(Path(args.spec).read_text(encoding="utf-8"))
    hv = spec.get("helmRelease", {}).get("valuesYaml", "")
    base = yaml.safe_load(hv) if hv.strip() else {}

    images = spec.get("workloadImages", {})
    be_img = images.get("deployment/spendsmart-backend", "")
    fe_img = images.get("deployment/spendsmart-frontend", "")
    eng_img = images.get("cronjob/refresh-days", "")

    def split_image(ref: str) -> dict[str, str]:
        if not ref or "/" not in ref:
            return {}
        repo, tag = ref.rsplit(":", 1) if ":" in ref else (ref, "latest")
        return {"repository": repo, "tag": tag}

    fe_cm = (spec.get("configMaps") or {}).get("uniteconpro-frontend") or {}
    keycloak_client = fe_cm.get("VITE_KEYCLOAK_CLIENT_ID", "spendsmart-frontend")
    keycloak_realm = fe_cm.get("VITE_KEYCLOAK_REALM", "spendsmart")

    nginx_csp = (base.get("frontend") or {}).get("nginx", {}).get("csp") or {}
    connect = list(nginx_csp.get("connectSrc") or ["'self'", "wss:"])
    if api_url and api_url not in connect:
        connect.append(api_url)
    if keycloak_url and keycloak_url not in connect:
        connect.append(keycloak_url)
    if frontend_url and frontend_url not in connect:
        connect.append(frontend_url)

    values = {
        "imagePullSecrets": [{"name": "harbor-ldc-coe-regcred"}],
        "backend": {
            "enabled": True,
            "image": split_image(be_img) or {
                "repository": "harbor.ldc.opstree.dev/coe/uniteconpro-backend-prod",
                "tag": "latest",
            },
            "nodeSelector": {"spendsmart.io/workload": "backend"},
            "service": {"type": "NodePort"},
            "annotations": {},
        },
        "frontend": {
            "enabled": True,
            "image": split_image(fe_img) or {
                "repository": "harbor.ldc.opstree.dev/coe/uniteconpro-frontend-prod",
                "tag": "latest",
            },
            "nodeSelector": {"spendsmart.io/workload": "frontend"},
            "service": {"type": "NodePort"},
            "configMap": {
                "name": "uniteconpro-frontend",
                "data": {
                    "VITE_API_BASE_URL": api_url,
                    "VITE_CLOUD_SENTRY_API_BASE_URL": fe_cm.get("VITE_CLOUD_SENTRY_API_BASE_URL", ""),
                    "VITE_KEYCLOAK_CLIENT_ID": keycloak_client,
                    "VITE_KEYCLOAK_REALM": keycloak_realm,
                    "VITE_KEYCLOAK_URL": keycloak_url,
                },
            },
            "nginx": {
                "enabled": True,
                "configMap": {"name": "spendsmart-frontend-nginx"},
                "csp": {"connectSrc": connect, "frameSrc": nginx_csp.get("frameSrc", ["'self'", "https:"])},
            },
            "annotations": {},
        },
        "cloudsentry": {"enabled": False},
        "engine": {
            "enabled": bool(eng_img),
            "image": split_image(eng_img) or {
                "repository": "harbor.ldc.opstree.dev/coe/uniteconpro-engine-dev",
                "tag": "latest",
            },
            "schedule": (base.get("engine") or {}).get("schedule", "5 11,23 * * *"),
            "nodeSelector": {"spendsmart.io/workload": "backend"},
        },
    }

    Path(args.out).write_text(yaml.safe_dump(values, default_flow_style=False), encoding="utf-8")
    print(f"Wrote {args.out}")


if __name__ == "__main__":
    main()
