#!/usr/bin/env bash
# Snapshot spendsmart namespace (images, secret *keys*, configmap data, helm values).
# Secrets values are never written — only key names and non-sensitive configmap fields.
# Usage: ./scripts/export-spendsmart-cluster-spec.sh [namespace] [out-file]
set -euo pipefail
NS="${1:-spendsmart}"
OUT="${2:-deploy/spendsmart-cluster-spec.json}"

command -v kubectl >/dev/null
command -v python3 >/dev/null
kubectl get ns "$NS" >/dev/null

python3 - "$NS" "$OUT" <<'PY'
import json
import os
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

ns, out_path = sys.argv[1], sys.argv[2]

def kubectl_json(args: list[str]):
    return json.loads(
        subprocess.check_output(["kubectl", "-n", ns, *args], text=True)
    )

def secret_keys(name: str) -> list[str]:
    try:
        data = kubectl_json(["get", "secret", name, "-o", "json"])["data"]
        return sorted(data.keys())
    except subprocess.CalledProcessError:
        return []

def deploy_images() -> dict[str, str]:
    out = {}
    for kind in ("deploy", "cronjob"):
        items = kubectl_json(["get", kind, "-o", "json"]).get("items", [])
        for obj in items:
            name = obj["metadata"]["name"]
            containers = obj["spec"].get("template", {}).get("spec", {}).get("containers", [])
            if not containers and kind == "cronjob":
                containers = (
                    obj["spec"]["jobTemplate"]["spec"]["template"]["spec"].get("containers", [])
                )
            if containers:
                out[f"{kind}/{name}"] = containers[0]["image"]
    return out

def configmaps() -> dict[str, dict]:
    cms = {}
    for name in ("uniteconpro-frontend", "spendsmart-frontend-nginx"):
        try:
            cm = kubectl_json(["get", "configmap", name, "-o", "json"])
        except subprocess.CalledProcessError:
            continue
        data = cm.get("data") or {}
        if name == "uniteconpro-frontend":
            cms[name] = {k: data.get(k, "") for k in sorted(data)}
        else:
            cms[name] = {"default.conf": f"<nginx config, {len(data.get('default.conf', ''))} chars>"}
    return cms

helm_values = ""
try:
    helm_values = subprocess.check_output(
        ["helm", "get", "values", "spendsmart", "-n", ns, "-o", "yaml"],
        text=True,
        stderr=subprocess.DEVNULL,
    )
except (subprocess.CalledProcessError, FileNotFoundError):
    helm_values = ""

alb_urls = {}
stack = os.environ.get("CFN_STACK_NAME", "spendsmart-dev")
region = os.environ.get("AWS_REGION", "us-east-1")
fetch = Path(__file__).resolve().parent / "cfn-fetch-alb-dns.py"
if fetch.is_file():
    try:
        alb_urls = json.loads(
            subprocess.check_output(
                [str(fetch), "--stack-name", stack, "--region", region, "--json"],
                text=True,
                stderr=subprocess.DEVNULL,
            )
        )
    except (subprocess.CalledProcessError, json.JSONDecodeError):
        alb_urls = {}

spec = {
    "generatedAt": datetime.now(timezone.utc).isoformat(),
    "namespace": ns,
    "context": subprocess.check_output(["kubectl", "config", "current-context"], text=True).strip(),
    "awsAlbUrls": alb_urls,
    "requiredSecrets": [
        "harbor-ldc-coe-regcred",
        "encryption-key",
        "clickhouse",
        "clickhouse-db",
    ],
    "secretKeys": {s: secret_keys(s) for s in [
        "harbor-ldc-coe-regcred",
        "encryption-key",
        "clickhouse",
        "clickhouse-db",
    ]},
    "configMaps": configmaps(),
    "workloadImages": deploy_images(),
    "helmRelease": {
        "name": "spendsmart",
        "valuesYaml": helm_values,
    },
    "notes": [
        "encryption-key: local cluster uses GPG_KEY (not ENCRYPTION_KEY).",
        "clickhouse Deployment in spendsmart ns is Minikube-only; EKS uses databases ns + ExternalName service.",
    ],
}

with open(out_path, "w", encoding="utf-8") as f:
    json.dump(spec, f, indent=2)
    f.write("\n")
print(f"Wrote {out_path}")
PY
