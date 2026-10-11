#!/usr/bin/env bash
# Apply SpendSmart app secrets on bastion. Usage: bastion-apply-app-secrets.sh <secrets.json>
set -euo pipefail
export KUBECONFIG="${KUBECONFIG:-/home/ec2-user/.kube/config}"
SECRETS_JSON="${1:?secrets json path}"
NS="${K8S_NAMESPACE:-spendsmart}"

python3 - "$SECRETS_JSON" "$NS" <<'PY'
import json, subprocess, sys

path, ns = sys.argv[1], sys.argv[2]
with open(path) as f:
    cfg = json.load(f)

def apply_yaml(yaml: str) -> None:
    subprocess.run(["kubectl", "apply", "-f", "-"], input=yaml, text=True, check=True)

ns_yaml = subprocess.check_output(
    ["kubectl", "create", "namespace", ns, "--dry-run=client", "-o", "yaml"], text=True
)
apply_yaml(ns_yaml)

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

def apply_generic(name: str, literals: dict) -> None:
    items = {k: v for k, v in literals.items() if v}
    if not items:
        return
    cmd = ["kubectl", "create", "secret", "generic", name, "-n", ns]
    for k, v in items.items():
        cmd.extend([f"--from-literal={k}={v}"])
    yaml = subprocess.check_output(cmd + ["--dry-run=client", "-o", "yaml"], text=True)
    apply_yaml(yaml)

apply_generic("encryption-key", {"ENCRYPTION_KEY": cfg.get("encryption_key") or ""})
apply_generic("gemini-key", {"GEMINI_API_KEY": cfg.get("gemini_api_key") or ""})
apply_generic("base-url", {"BASE_URL": cfg.get("base_url") or ""})
ak = (cfg.get("aws_access_key_id") or "").strip()
sk = cfg.get("aws_secret_access_key") or ""
if ak and sk:
    apply_generic("aws-access", {"AWS_ACCESS_KEY_ID": ak, "AWS_SECRET_ACCESS_KEY": sk})

subprocess.run(["kubectl", "get", "secrets", "-n", ns], check=False)
PY
