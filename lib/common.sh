#!/usr/bin/env bash
# lib/common.sh — shared helpers for devmux scripts.
# Source this file; do not execute directly.

# ── Capability checks ────────────────────────────────────────────
_has_gum() { command -v gum &>/dev/null; }

# ── Output ────────────────────────────────────────────────────────
die()  { echo "Error: $*" >&2; exit 1; }
info() { echo "$*" >&2; }

# Styled section header (falls back to plain text)
header() {
    local text="$*"
    if _has_gum; then
        gum style --bold --border rounded --padding "0 1" --border-foreground 212 "$text" >&2
    else
        info ""
        info "=== $text ==="
    fi
}

# Spinner wrapper: spin "message" command [args...]
spin() {
    local title="$1"; shift
    if _has_gum; then
        gum spin --spinner dot --title "$title" -- "$@"
    else
        info "$title"
        "$@"
    fi
}

# Free-text input: input "prompt" [placeholder]
input() {
    local prompt="$1"
    local placeholder="${2:-}"
    if _has_gum; then
        gum input --prompt "$prompt " --placeholder "$placeholder"
    else
        local answer
        read -rp "$prompt " answer
        echo "$answer"
    fi
}

# ── Config variable lookup ────────────────────────────────────────
# Get a config variable by name (supports dynamic variable names).
get_var() {
    local name="$1"
    echo "${!name:-}"
}

# ── Interactive pickers ───────────────────────────────────────────
# Pick one item from a list.
# Priority: gum → fzf → termux-dialog → numbered menu
# Usage: pick "prompt" item1 item2 ...
pick() {
    local prompt="$1"; shift
    local items=("$@")

    if [[ ${#items[@]} -eq 0 ]]; then
        die "No items to choose from."
    fi
    if [[ ${#items[@]} -eq 1 ]]; then
        echo "${items[0]}"
        return
    fi

    if _has_gum; then
        if [[ ${#items[@]} -le 10 ]]; then
            gum choose --header "$prompt" "${items[@]}"
        else
            printf '%s\n' "${items[@]}" | gum filter --header "$prompt"
        fi
    elif command -v fzf &>/dev/null; then
        printf '%s\n' "${items[@]}" | fzf --prompt="$prompt " --height=~20 --reverse
    elif command -v termux-dialog &>/dev/null 2>&1; then
        # Termux:API touch-friendly picker
        local csv
        csv=$(printf '%s,' "${items[@]}")
        csv="${csv%,}"
        local result
        result=$(termux-dialog sheet -t "$prompt" -v "$csv" 2>/dev/null) || true
        if [[ -n "$result" ]]; then
            local picked
            picked=$(echo "$result" | sed -n 's/.*"text": *"\([^"]*\)".*/\1/p')
            if [[ -n "$picked" ]]; then
                echo "$picked"
                return
            fi
        fi
        # Fall through to numbered menu if termux-dialog fails
        _pick_numbered "$prompt" "${items[@]}"
    else
        _pick_numbered "$prompt" "${items[@]}"
    fi
}

_pick_numbered() {
    local prompt="$1"; shift
    local items=("$@")
    echo "$prompt" >&2
    local i
    for i in "${!items[@]}"; do
        echo "  $((i+1))) ${items[$i]}" >&2
    done
    while true; do
        read -rp "#? " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#items[@]} )); then
            echo "${items[$((choice-1))]}"
            return
        fi
        echo "Invalid choice. Enter 1-${#items[@]}." >&2
    done
}

# Pick multiple items from a list. Returns newline-separated selections on stdout.
# Empty selection is not an error.
# Priority: gum → fzf → termux-dialog → numbered menu
# Usage: multi_pick "prompt" item1 item2 ...
multi_pick() {
    local prompt="$1"; shift
    local items=("$@")

    if [[ ${#items[@]} -eq 0 ]]; then
        return
    fi

    if _has_gum; then
        gum choose --no-limit --header "$prompt" "${items[@]}" || true
    elif command -v fzf &>/dev/null; then
        printf '%s\n' "${items[@]}" | fzf --multi --prompt="$prompt " --height=~20 --reverse || true
    elif command -v termux-dialog &>/dev/null 2>&1; then
        local csv
        csv=$(printf '%s,' "${items[@]}")
        csv="${csv%,}"
        local result
        result=$(termux-dialog checkbox -t "$prompt" -v "$csv" 2>/dev/null) || true
        if [[ -n "$result" ]]; then
            # termux-dialog checkbox returns JSON with "values" array
            echo "$result" | sed -n 's/.*"values":\[//p' | tr -d '[]"' | tr ',' '\n' | while IFS= read -r val; do
                val=$(echo "$val" | sed 's/^ *//;s/ *$//')
                [[ -n "$val" ]] && echo "$val"
            done
        fi
    else
        _multi_pick_numbered "$prompt" "${items[@]}"
    fi
}

_multi_pick_numbered() {
    local prompt="$1"; shift
    local items=("$@")
    echo "$prompt (space-separated numbers, empty=none)" >&2
    local i
    for i in "${!items[@]}"; do
        echo "  $((i+1))) ${items[$i]}" >&2
    done
    while true; do
        read -rp "#? " choices
        [[ -z "$choices" ]] && return
        local valid=true
        local nums
        read -ra nums <<< "$choices"
        for n in "${nums[@]}"; do
            if ! [[ "$n" =~ ^[0-9]+$ ]] || (( n < 1 || n > ${#items[@]} )); then
                echo "Invalid: $n. Enter numbers 1-${#items[@]}." >&2
                valid=false
                break
            fi
        done
        if $valid; then
            echo "" >&2
            echo "Selected:" >&2
            for n in "${nums[@]}"; do
                echo "  - ${items[$((n-1))]}" >&2
            done
            if confirm "  Confirm?"; then
                for n in "${nums[@]}"; do
                    echo "${items[$((n-1))]}"
                done
                return
            fi
        fi
    done
}

# ── Yes/No prompt ────────────────────────────────────────────────
# Usage: confirm "Do something?" && do_it
confirm() {
    local prompt="${1:-Continue?}"
    if _has_gum; then
        gum confirm "$prompt"
    else
        read -rp "$prompt [y/N] " answer
        [[ "$answer" =~ ^[Yy]$ ]]
    fi
}
