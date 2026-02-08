#!/usr/bin/env bash
# scripts/bootstrap.sh — update repo + run setup deterministically on Linux/WSL/Termux.
#
# Usage:
#   bash scripts/bootstrap.sh [--no-stash] [--stash-message <msg>]
#
# This script is intentionally low-risk:
# - Auto-stashes local changes by default so updates don't fail on "dirty" clones (common on Termux).
# - Never drops your stash; you can restore it later.
# - Always runs `setup.sh --regen-config` so config matches machines.conf
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd -P)"

usage() {
    cat <<'EOF'
Usage: bash scripts/bootstrap.sh [OPTIONS]

Options:
  --no-stash              Fail if the repo has local changes (do not auto-stash)
  --stash-message <msg>   Custom stash message (default: devmux-auto-stash <timestamp>)
  -h, --help              Show this help
EOF
}

NO_STASH=false
STASH_MESSAGE=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --no-stash) NO_STASH=true; shift ;;
        --stash-message) STASH_MESSAGE="${2:-}"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
done

cd "$REPO_DIR"

STASH_ENTRY=""
on_err() {
    echo "ERROR: bootstrap failed." >&2
    if command -v git >/dev/null 2>&1; then
        if git rev-parse --git-dir >/dev/null 2>&1; then
            echo "If a rebase is in progress, you may need: git rebase --abort" >&2
            if [[ -n "$STASH_ENTRY" ]]; then
                echo "Your local changes were stashed: $STASH_ENTRY" >&2
            fi
        fi
    fi
}
trap on_err ERR

if command -v git >/dev/null 2>&1; then
    if git rev-parse --git-dir >/dev/null 2>&1; then
        dirty=false
        if ! git diff --quiet || ! git diff --cached --quiet; then
            dirty=true
        elif [[ -n "$(git ls-files --others --exclude-standard 2>/dev/null)" ]]; then
            dirty=true
        fi

        if $dirty; then
            if $NO_STASH; then
                echo "ERROR: Repo has local changes. Commit/stash them, or re-run without --no-stash." >&2
                exit 2
            fi

            ts="$(date +%Y%m%d-%H%M%S 2>/dev/null || date)"
            if [[ -z "$STASH_MESSAGE" ]]; then
                STASH_MESSAGE="devmux-auto-stash $ts"
            fi

            echo "Repo has local changes; stashing before pull..." >&2
            git stash push -u -m "$STASH_MESSAGE" >/dev/null
            STASH_ENTRY="$(git stash list -n 1 | head -n 1 || true)"
            if [[ -n "$STASH_ENTRY" ]]; then
                echo "Stashed: $STASH_ENTRY" >&2
            fi
        fi

        git pull --rebase
    fi
fi

bash "$REPO_DIR/setup.sh" --regen-config

if [[ -n "$STASH_ENTRY" ]]; then
    echo "" >&2
    echo "Local changes are stashed. To restore them later:" >&2
    echo "  cd \"$REPO_DIR\" && git stash pop" >&2
fi
