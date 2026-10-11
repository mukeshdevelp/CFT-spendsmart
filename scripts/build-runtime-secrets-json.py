#!/usr/bin/env python3
"""Build jenkins-runtime-secrets.json for bastion-apply-chart-secrets.sh (Jenkins agent)."""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys


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

    pg_secret = f"{args.name_prefix}/postgres"
    ch_secret = f"{args.name_prefix}/clickhouse"

    try:
        pg_pass = sm_password(pg_secret, args.region)
        ch_pass = sm_password(ch_secret, args.region)
    except Exception as e:
        print(f"Failed to read Secrets Manager DB passwords: {e}", file=sys.stderr)
        sys.exit(1)

    cfg = {
        "k8s_namespace": args.namespace,
        "harbor_docker_server": os.environ.get("HARBOR_DOCKER_SERVER", "harbor.ldc.opstree.dev"),
        "harbor_docker_username": os.environ.get("HARBOR_DOCKER_USERNAME", ""),
        "harbor_docker_password": os.environ.get("HARBOR_DOCKER_PASSWORD", ""),
        "encryption_key": os.environ.get("ENCRYPTION_KEY", ""),
        "gemini_api_key": os.environ.get("GEMINI_API_KEY", ""),
        "base_url": os.environ.get("BASE_URL", ""),
        "aws_access_key_id": os.environ.get("APP_AWS_ACCESS_KEY_ID", ""),
        "aws_secret_access_key": os.environ.get("APP_AWS_SECRET_ACCESS_KEY", ""),
        "keycloak_admin": os.environ.get("KEYCLOAK_ADMIN", "admin"),
        "keycloak_admin_password": os.environ.get("KEYCLOAK_ADMIN_PASSWORD", ""),
        "clickhouse": {
            "CLICKHOUSE_HOST": "clickhouse.databases.svc.cluster.local",
            "CLICKHOUSE_PORT": "9000",
            "CLICKHOUSE_USER": "default",
            "CLICKHOUSE_PASSWORD": ch_pass,
            "CLICKHOUSE_DATABASE": "spendsmart",
        },
        "clickhouse_db": {
            "CLICKHOUSE_HOST": "clickhouse.databases.svc.cluster.local",
            "CLICKHOUSE_PORT": "9000",
            "CLICKHOUSE_USER": "default",
            "CLICKHOUSE_PASSWORD": ch_pass,
            "CLICKHOUSE_DATABASE": "spendsmart",
            "CLICKHOUSE_TABLE": os.environ.get("CLICKHOUSE_TABLE", "service_costs"),
        },
        "postgres_config": {
            "POSTGRES_HOST": "postgres.databases.svc.cluster.local",
            "POSTGRES_PORT": "5432",
            "POSTGRES_USER": "dbadmin",
            "POSTGRES_PASSWORD": pg_pass,
            "POSTGRES_DB": "cloudsentry",
        },
    }

    with open(args.out, "w", encoding="utf-8") as f:
        json.dump(cfg, f)
    print(args.out)


if __name__ == "__main__":
    main()
