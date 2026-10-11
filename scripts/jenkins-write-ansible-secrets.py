#!/usr/bin/env python3
"""Write ansible/group_vars/secrets.yml from environment (Jenkins credentials)."""
from __future__ import annotations

import os
from pathlib import Path

import yaml

OUT = Path(os.environ.get("ANSIBLE_SECRETS_FILE", "ansible/group_vars/secrets.yml"))

data = {
    "harbor_docker_username": os.environ.get("HARBOR_DOCKER_USERNAME", ""),
    "harbor_docker_password": os.environ.get("HARBOR_DOCKER_PASSWORD", ""),
    "encryption_key": os.environ.get("ENCRYPTION_KEY", ""),
    "keycloak_admin_password": os.environ.get("KEYCLOAK_ADMIN_PASSWORD", ""),
    "gemini_api_key": os.environ.get("GEMINI_API_KEY", ""),
    "base_url": os.environ.get("BASE_URL", ""),
    "app_aws_access_key_id": os.environ.get("APP_AWS_ACCESS_KEY_ID", ""),
    "app_aws_secret_access_key": os.environ.get("APP_AWS_SECRET_ACCESS_KEY", ""),
}

OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_text(yaml.safe_dump(data, default_flow_style=False), encoding="utf-8")
print(OUT)
