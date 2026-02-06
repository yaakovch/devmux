#!/usr/bin/env bash
# install-host-wsl.sh — install devmux-remote on a WSL/Linux host.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BIN_DIR="${HOME}/.local/bin"

echo "Installing devmux-remote on this host..."

# ── Ensure tmux is installed ──────────────────────────────────────
if ! command -v tmux &>/dev/null; then
    echo "  tmux not found. Installing..."
    if command -v apt-get &>/dev/null; then
        sudo apt-get update -qq && sudo apt-get install -y -qq tmux
    elif command -v pacman &>/dev/null; then
        sudo pacman -Sy --noconfirm tmux
    elif command -v brew &>/dev/null; then
        brew install tmux
    else
        echo "  ERROR: Cannot install tmux automatically. Install it manually." >&2
        exit 1
    fi
fi
echo "  tmux: $(tmux -V)"

# ── Install devmux-remote ────────────────────────────────────────
mkdir -p "$BIN_DIR"
cp "$REPO_DIR/scripts/devmux-remote" "$BIN_DIR/devmux-remote"
chmod +x "$BIN_DIR/devmux-remote"
echo "  Installed devmux-remote → $BIN_DIR/devmux-remote"

# ── Ensure ~/projects exists ─────────────────────────────────────
mkdir -p "$HOME/projects"
echo "  Ensured ~/projects directory exists."

# ── PATH check ────────────────────────────────────────────────────
if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
    echo ""
    echo "  NOTE: $BIN_DIR is not in your PATH."
    echo "  Add this to your shell profile (~/.bashrc or ~/.zshrc):"
    echo "    export PATH=\"\$HOME/.local/bin:\$PATH\""
fi

echo ""
echo "Done! This host is ready to receive devmux connections."
