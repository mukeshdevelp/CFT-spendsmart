#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
for f in vm.env gpg.env gemini.env harbor.env db.env; do
  if [[ -f "${ROOT}/deploy/${f}" ]]; then
    set -a
    # shellcheck source=/dev/null
    source "${ROOT}/deploy/${f}"
    set +a
  fi
done