#!/usr/bin/env bash
# scripts/show-key.sh — print your SSH public key as a single line, safe to paste.
#
# Usage:
#   bash scripts/show-key.sh
#
# On WSL, this also copies the key to the Windows clipboard (via clip.exe) if available.
set -euo pipefail

PUB_KEY_PATH="${PUB_KEY_PATH:-$HOME/.ssh/id_ed25519.pub}"

if [[ ! -f "$PUB_KEY_PATH" ]]; then
    echo "Error: public key not found: $PUB_KEY_PATH" >&2
    echo "Run: bash setup.sh" >&2
    exit 1
fi

# Normalize whitespace/newlines to a single space.
KEY="$(tr -s '[:space:]' ' ' <"$PUB_KEY_PATH" | sed -e 's/^ *//' -e 's/ *$//')"

echo "$KEY"

if command -v clip.exe >/dev/null 2>&1; then
    printf '%s' "$KEY" | clip.exe
    echo ""
    echo "Copied to Windows clipboard."
fi

