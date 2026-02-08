#!/usr/bin/env bash
# scripts/bootstrap.sh — update repo + run setup deterministically on Linux/WSL/Termux.
#
# Usage:
#   bash scripts/bootstrap.sh
#
# This script is intentionally non-destructive:
# - Only pulls if the repo is clean (no local changes)
# - Always runs `setup.sh --regen-config` so config matches machines.conf
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd -P)"

cd "$REPO_DIR"

if command -v git >/dev/null 2>&1; then
    if git diff --quiet && git diff --cached --quiet; then
        git pull --rebase
    else
        echo "NOTE: Repo has local changes; skipping git pull." >&2
    fi
fi

bash "$REPO_DIR/setup.sh" --regen-config

