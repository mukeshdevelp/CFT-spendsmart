#!/usr/bin/env python3
"""Write ansible/group_vars/secrets.yml — Harbor, encryption only (deploy guide)."""
from __future__ import annotations

import os
from pathlib import Path

import yaml

OUT = Path(os.environ.get("ANSIBLE_SECRETS_FILE", "ansible/group_vars/secrets.yml"))

data = {
    "harbor_docker_username": os.environ.get("HARBOR_DOCKER_USERNAME", ""),
    "harbor_docker_password": os.environ.get("HARBOR_DOCKER_PASSWORD", ""),
    "encryption_key": os.environ.get("ENCRYPTION_KEY", ""),
}

OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_text(yaml.safe_dump(data, default_flow_style=False), encoding="utf-8")
print(OUT)
