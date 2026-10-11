#!/usr/bin/env python3
"""Build jenkins-runtime-secrets.json — Harbor guide parity (steps 6, 12–14 only)."""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys

# EKS: ClickHouse runs in namespace `databases` (infra bootstrap), not Minikube step 7–11.
CH_HOST = os.environ.get("CLICKHOUSE_HOST", "clickhouse.databases.svc.cluster.local")
CH_PORT = os.environ.get("CLICKHOUSE_PORT", "8123")
CH_USER = os.environ.get("CLICKHOUSE_USER", "default")
CH_DATABASE = os.environ.get("CLICKHOUSE_DATABASE", "spendsmart")
CH_TABLE = os.environ.get("CLICKHOUSE_TABLE", "service_costs")


def sm_password(secret_id: str, region: str) -> str:
    out = subprocess.check_output(
        [
            "aws",
            "secretsmanager",
            "get-secret-value",
            "--secret-id",
            secret_id,
            "--region",
            region,
            "--query",
            "SecretString",
            "--output",
            "text",
        ],
        text=True,
    )
    return json.loads(out)["password"]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", default="jenkins-runtime-secrets.json")
    parser.add_argument("--region", default=os.environ.get("AWS_DEFAULT_REGION", "us-east-1"))
    parser.add_argument("--name-prefix", default="spendsmart-dev")
    parser.add_argument("--namespace", default="spendsmart")
    args = parser.parse_args()

    ch_secret = f"{args.name_prefix}/clickhouse"
    try:
        ch_pass = sm_password(ch_secret, args.region)
    except Exception as e:
        print(f"Failed to read Secrets Manager ClickHouse password: {e}", file=sys.stderr)
        sys.exit(1)

    cfg = {
        "k8s_namespace": args.namespace,
        "harbor_docker_server": os.environ.get("HARBOR_DOCKER_SERVER", "harbor.ldc.opstree.dev"),
        "harbor_docker_username": os.environ.get("HARBOR_DOCKER_USERNAME", ""),
        "harbor_docker_password": os.environ.get("HARBOR_DOCKER_PASSWORD", ""),
        "encryption_key": os.environ.get("ENCRYPTION_KEY", ""),
        "clickhouse": {
            "CLICKHOUSE_HOST": CH_HOST,
            "CLICKHOUSE_PORT": CH_PORT,
            "CLICKHOUSE_USER": CH_USER,
            "CLICKHOUSE_PASSWORD": ch_pass,
            "CLICKHOUSE_DATABASE": CH_DATABASE,
            "CLICKHOUSE_TABLE": CH_TABLE,
            "CLICKHOUSE_TLS": "false",
        },
        "clickhouse_db": {
            "CLICKHOUSE_HOST": CH_HOST,
            "CLICKHOUSE_PORT": CH_PORT,
            "CLICKHOUSE_USER": CH_USER,
            "CLICKHOUSE_PASSWORD": ch_pass,
            "CLICKHOUSE_DATABASE": CH_DATABASE,
            "CLICKHOUSE_TABLE": CH_TABLE,
        },
    }

    with open(args.out, "w", encoding="utf-8") as f:
        json.dump(cfg, f)
    print(args.out)


if __name__ == "__main__":
    main()
