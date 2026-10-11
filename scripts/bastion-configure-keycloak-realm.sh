#!/usr/bin/env bash
# Create realm + public OIDC client for the SpendSmart frontend (idempotent).
set -euo pipefail
export KUBECONFIG="${KUBECONFIG:-/home/ec2-user/.kube/config}"

NAMESPACE="${KEYCLOAK_NAMESPACE:-spendsmart}"
KEYCLOAK_ADMIN="${KEYCLOAK_ADMIN:-admin}"
KEYCLOAK_ADMIN_PASSWORD="${KEYCLOAK_ADMIN_PASSWORD:?}"
KEYCLOAK_REALM="${KEYCLOAK_REALM:-spendsmart}"
KEYCLOAK_CLIENT_ID="${KEYCLOAK_CLIENT_ID:-spendsmart-frontend}"
FRONTEND_BASE_URL="${FRONTEND_BASE_URL:-}"

if [ -z "$FRONTEND_BASE_URL" ]; then
  echo "FRONTEND_BASE_URL not set; skipping Keycloak realm bootstrap"
  exit 0
fi

python3 - <<'PY'
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

ns = os.environ["KEYCLOAK_NAMESPACE"]
admin = os.environ["KEYCLOAK_ADMIN"]
password = os.environ["KEYCLOAK_ADMIN_PASSWORD"]
realm = os.environ["KEYCLOAK_REALM"]
client_id = os.environ["KEYCLOAK_CLIENT_ID"]
frontend = os.environ["FRONTEND_BASE_URL"].rstrip("/")

pf = subprocess.Popen(
    ["kubectl", "-n", ns, "port-forward", "svc/keycloak", "18080:8080"],
    stdout=subprocess.DEVNULL,
    stderr=subprocess.DEVNULL,
)
time.sleep(3)
base = "http://127.0.0.1:18080"

def req(method, path, body=None, token=None):
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    data = None
    if body is not None:
        data = json.dumps(body).encode()
    r = urllib.request.Request(base + path, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(r, timeout=30) as resp:
            raw = resp.read()
            return resp.status, json.loads(raw) if raw else None
    except urllib.error.HTTPError as e:
        raw = e.read()
        try:
            payload = json.loads(raw) if raw else {}
        except json.JSONDecodeError:
            payload = {"raw": raw.decode(errors="replace")}
        return e.code, payload

try:
    for _ in range(30):
        code, _ = req("GET", "/realms/master")
        if code == 200:
            break
        time.sleep(5)
    else:
        sys.exit("Keycloak not reachable via port-forward")

    form = urllib.parse.urlencode(
        {
            "client_id": "admin-cli",
            "username": admin,
            "password": password,
            "grant_type": "password",
        }
    ).encode()
    tok_req = urllib.request.Request(
        base + "/realms/master/protocol/openid-connect/token",
        data=form,
        method="POST",
    )
    with urllib.request.urlopen(tok_req, timeout=30) as resp:
        token = json.load(resp)["access_token"]

    code, _ = req("GET", f"/admin/realms/{realm}", token=token)
    if code == 404:
        code, err = req(
            "POST",
            "/admin/realms",
            {"realm": realm, "enabled": True},
            token=token,
        )
        if code not in (201, 409):
            sys.exit(f"create realm failed: {code} {err}")
        print(f"Realm {realm} created or exists")
    elif code == 200:
        print(f"Realm {realm} already exists")
    else:
        sys.exit(f"realm check failed: {code}")

    redirect_uris = [f"{frontend}/*", frontend + "/"]
    web_origins = [frontend, "+"]
    client_body = {
        "clientId": client_id,
        "name": client_id,
        "enabled": True,
        "publicClient": True,
        "standardFlowEnabled": True,
        "directAccessGrantsEnabled": True,
        "redirectUris": redirect_uris,
        "webOrigins": web_origins,
        "attributes": {"post.logout.redirect.uris": "+"},
    }

    code, existing = req(
        "GET",
        f"/admin/realms/{realm}/clients?clientId={urllib.parse.quote(client_id)}",
        token=token,
    )
    if code != 200:
        sys.exit(f"list clients failed: {code} {existing}")

    if existing:
        cid = existing[0]["id"]
        code, err = req(
            "PUT",
            f"/admin/realms/{realm}/clients/{cid}",
            client_body,
            token=token,
        )
        if code not in (204, 200):
            sys.exit(f"update client failed: {code} {err}")
        print(f"Updated client {client_id}")
    else:
        code, err = req(
            "POST",
            f"/admin/realms/{realm}/clients",
            client_body,
            token=token,
        )
        if code not in (201, 409):
            sys.exit(f"create client failed: {code} {err}")
        print(f"Created client {client_id}")

finally:
    pf.terminate()
    pf.wait(timeout=10)
PY
