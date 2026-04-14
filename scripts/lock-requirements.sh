#!/usr/bin/env bash
# Generate a cross-platform lock file from the flexible root requirements.txt.
#
# Usage:
#   bash scripts/lock-requirements.sh
#
# Produces: requirements.lock
#
# Re-run this only when root requirements change. Participants DO NOT need to
# run this — they install from requirements.txt. The lock is checked in so CI
# and reproducibility-minded users can do `pip install -r requirements.lock`.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

if ! python3 -m pip show pip-tools >/dev/null 2>&1; then
    echo "==> Installing pip-tools"
    python3 -m pip install --quiet pip-tools
fi

echo "==> Compiling requirements.txt -> requirements.lock"
# --strip-extras: drop [extras] markers (not supported by plain pip)
# --no-emit-index-url: keep the lock PyPI-agnostic
# --resolver=backtracking: the default modern resolver
python3 -m piptools compile \
    --strip-extras \
    --no-emit-index-url \
    --output-file requirements.lock \
    requirements.txt

echo "==> Done: $(wc -l < requirements.lock) lines pinned."
echo "   Commit requirements.lock alongside requirements.txt."
