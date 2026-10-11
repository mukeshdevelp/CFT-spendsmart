#!/usr/bin/env bash
# Apply all SpendSmart chart secrets from JSON (see build-runtime-secrets-json.py).
set -euo pipefail
export KUBECONFIG="${KUBECONFIG:-/home/ec2-user/.kube/config}"
SECRETS_JSON="${1:?secrets json path}"

python3 - "$SECRETS_JSON" <<'PY'
import json, subprocess, sys

with open(sys.argv[1]) as f:
    cfg = json.load(f)

ns = cfg.get("k8s_namespace") or "spendsmart"

def apply_yaml(yaml: str) -> None:
    subprocess.run(["kubectl", "apply", "-f", "-"], input=yaml, text=True, check=True)

def ensure_ns() -> None:
    yaml = subprocess.check_output(
        ["kubectl", "create", "namespace", ns, "--dry-run=client", "-o", "yaml"], text=True
    )
    apply_yaml(yaml)

def apply_generic(name: str, literals: dict) -> None:
    items = {k: str(v) for k, v in literals.items() if v is not None and str(v) != ""}
    if not items:
        return
    cmd = ["kubectl", "create", "secret", "generic", name, "-n", ns]
    for k, v in items.items():
        cmd.extend([f"--from-literal={k}={v}"])
    yaml = subprocess.check_output(cmd + ["--dry-run=client", "-o", "yaml"], text=True)
    apply_yaml(yaml)

ensure_ns()

server = cfg.get("harbor_docker_server") or "harbor.ldc.opstree.dev"
user = (cfg.get("harbor_docker_username") or "").strip()
password = cfg.get("harbor_docker_password") or ""
if user and password:
    yaml = subprocess.check_output([
        "kubectl", "create", "secret", "docker-registry", "harbor-ldc-coe-regcred",
        f"--docker-server={server}", f"--docker-username={user}", f"--docker-password={password}",
        "-n", ns, "--dry-run=client", "-o", "yaml",
    ], text=True)
    apply_yaml(yaml)

apply_generic("encryption-key", {"ENCRYPTION_KEY": cfg.get("encryption_key") or ""})

for key, secret_name in [
    ("clickhouse", "clickhouse"),
    ("clickhouse_db", "clickhouse-db"),
]:
    block = cfg.get(key) or {}
    if block:
        apply_generic(secret_name, block)

subprocess.run(["kubectl", "get", "secrets", "-n", ns], check=False)
PY
