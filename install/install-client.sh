#!/usr/bin/env bash
# install-client.sh — install devmux on a client machine (Linux/WSL/Termux).
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BIN_DIR="${HOME}/.local/bin"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/devmux"
SHORTCUT_DIR="${HOME}/.shortcuts"

echo "Installing devmux client..."

# ── Install scripts to ~/.local/bin ────────────────────────────────
mkdir -p "$BIN_DIR"
cp "$REPO_DIR/scripts/devmux" "$BIN_DIR/devmux"
chmod +x "$BIN_DIR/devmux"
echo "  Installed devmux → $BIN_DIR/devmux"

# ── Install config if missing ─────────────────────────────────────
mkdir -p "$CONFIG_DIR"
if [[ ! -f "$CONFIG_DIR/devmux.conf" ]]; then
    cp "$REPO_DIR/config/devmux.example.conf" "$CONFIG_DIR/devmux.conf"
    echo "  Created config → $CONFIG_DIR/devmux.conf (edit this!)"
else
    echo "  Config already exists → $CONFIG_DIR/devmux.conf (skipped)"
fi

# ── Termux shortcuts ──────────────────────────────────────────────
if [[ -d "/data/data/com.termux" ]] || [[ "${TERMUX_VERSION:-}" ]]; then
    mkdir -p "$SHORTCUT_DIR"
    cp "$REPO_DIR/termux/shortcuts/devmux" "$SHORTCUT_DIR/devmux"
    chmod +x "$SHORTCUT_DIR/devmux"
    echo "  Installed Termux shortcut → $SHORTCUT_DIR/devmux"
    echo "  (Requires Termux:Widget app for home-screen shortcut)"
fi

# ── PATH check ────────────────────────────────────────────────────
if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
    echo ""
    echo "  NOTE: $BIN_DIR is not in your PATH."
    echo "  Add this to your shell profile (~/.bashrc or ~/.zshrc):"
    echo "    export PATH=\"\$HOME/.local/bin:\$PATH\""
fi

echo ""
echo "Done! Next steps:"
echo "  1. Edit ~/.config/devmux/devmux.conf with your hosts/tools."
echo "  2. Run 'devmux' to launch."
