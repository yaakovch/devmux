#!/usr/bin/env bash
# setup-host.sh — Self-contained terminal environment provisioning for devmux.
# Can be piped over SSH to hosts without the repo.
#
# Usage:
#   setup-host.sh [--all | --only tmux,starship,aliases,tools,zoxide | --skip tools]
#                 [--interactive] [--uninstall aliases,zoxide] [--dry-run] [-h]
set -euo pipefail

# ── Output helpers (self-contained) ────────────────────────────────
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'; BOLD='\033[1m'
info()  { echo -e "${BLUE}▸${NC} $*" >&2; }
ok()    { echo -e "${GREEN}✓${NC} $*" >&2; }
warn()  { echo -e "${YELLOW}⚠${NC} $*" >&2; }
step()  { echo -e "\n${BOLD}━━━ $* ━━━${NC}\n" >&2; }
die()   { echo "Error: $*" >&2; exit 1; }

# ── Privilege helpers (self-contained) ─────────────────────────────
is_root() { [[ "${EUID:-$(id -u)}" -eq 0 ]]; }

sudo_run() {
    if is_root; then
        "$@"
        return
    fi

    if ! command -v sudo >/dev/null 2>&1; then
        die "Need root privileges but sudo is not installed. Re-run as root or install sudo."
    fi

    # When piping over SSH (no TTY), sudo will fail if it needs a password.
    if ! sudo -n true >/dev/null 2>&1; then
        if [[ ! -t 0 ]]; then
            die "sudo needs a password but no TTY is available. Re-run with a TTY (e.g. ssh -t) or configure passwordless sudo for this user."
        fi
    fi

    sudo "$@"
}

# ── Managed block helpers (self-contained) ─────────────────────────
# Write a managed block in a file. Replaces existing block with same suffix.
# Usage: write_managed_block <file> <suffix> <content>
write_managed_block() {
    local file="$1" suffix="$2" content="$3"
    local begin="# BEGIN devmux-managed-${suffix}"
    local end="# END devmux-managed-${suffix}"

    mkdir -p "$(dirname "$file")"
    touch "$file"

    local tmpfile
    tmpfile=$(mktemp)
    local in_block=false

    while IFS= read -r line; do
        if [[ "$line" == "$begin" ]]; then
            in_block=true
            continue
        fi
        if [[ "$line" == "$end" ]]; then
            in_block=false
            continue
        fi
        if ! $in_block; then
            echo "$line"
        fi
    done < "$file" > "$tmpfile"

    {
        if [[ -s "$tmpfile" ]]; then
            [[ "$(tail -c 1 "$tmpfile" 2>/dev/null)" != "" ]] && echo ""
        fi
        echo "$begin"
        echo "$content"
        echo "$end"
    } >> "$tmpfile"

    mv "$tmpfile" "$file"
}

# Remove a managed block from a file.
# Usage: remove_managed_block <file> <suffix>
remove_managed_block() {
    local file="$1" suffix="$2"
    local begin="# BEGIN devmux-managed-${suffix}"
    local end="# END devmux-managed-${suffix}"

    [[ -f "$file" ]] || return 0

    local tmpfile
    tmpfile=$(mktemp)
    local in_block=false

    while IFS= read -r line; do
        if [[ "$line" == "$begin" ]]; then
            in_block=true
            continue
        fi
        if [[ "$line" == "$end" ]]; then
            in_block=false
            continue
        fi
        if ! $in_block; then
            echo "$line"
        fi
    done < "$file" > "$tmpfile"

    mv "$tmpfile" "$file"
}

# ── Package manager detection ──────────────────────────────────────
detect_pkg_manager() {
    if [[ -n "${TERMUX_VERSION:-}" ]] || [[ -d "/data/data/com.termux" ]]; then
        echo "pkg"
    elif command -v apt-get &>/dev/null; then
        echo "apt"
    elif command -v pacman &>/dev/null; then
        echo "pacman"
    elif command -v brew &>/dev/null; then
        echo "brew"
    else
        echo "none"
    fi
}

# ── CLI args ───────────────────────────────────────────────────────
ALL_FEATURES=(tmux starship aliases tools zoxide)
FEATURES=()
SKIP=()
UNINSTALL=()
DRY_RUN=false
INTERACTIVE=false

usage() {
    cat <<'EOF'
Usage: setup-host.sh [OPTIONS]

Provision terminal environment on a devmux host.

Options:
  --all                 Install all features (default if no --only)
  --only <list>         Comma-separated features: tmux,starship,aliases,tools,zoxide
  --skip <list>         Comma-separated features to skip
  --interactive         Prompt before each feature
  --uninstall <list>    Remove managed blocks for listed features
  --dry-run             Show what would be done without making changes
  -h, --help            Show this help
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --all)
            FEATURES=("${ALL_FEATURES[@]}")
            shift ;;
        --only)
            IFS=',' read -ra FEATURES <<< "$2"
            shift 2 ;;
        --skip)
            IFS=',' read -ra SKIP <<< "$2"
            shift 2 ;;
        --uninstall)
            IFS=',' read -ra UNINSTALL <<< "$2"
            shift 2 ;;
        --dry-run)
            DRY_RUN=true
            shift ;;
        --interactive)
            INTERACTIVE=true
            shift ;;
        -h|--help)
            usage; exit 0 ;;
        *)
            die "Unknown option: $1" ;;
    esac
done

# Default to all features if nothing specified
if [[ ${#FEATURES[@]} -eq 0 && ${#UNINSTALL[@]} -eq 0 ]]; then
FEATURES=("${ALL_FEATURES[@]}")
fi

# Remove skipped features
if [[ ${#SKIP[@]} -gt 0 ]]; then
    _filtered_features=()
    for f in "${FEATURES[@]}"; do
        _skip_it=false
        for s in "${SKIP[@]}"; do
            [[ "$f" == "$s" ]] && _skip_it=true
        done
        $_skip_it || _filtered_features+=("$f")
    done
    FEATURES=("${_filtered_features[@]}")
fi

has_feature() {
    local target="$1"
    for f in "${FEATURES[@]}"; do
        [[ "$f" == "$target" ]] && return 0
    done
    return 1
}

# ── Handle --uninstall ─────────────────────────────────────────────
if [[ ${#UNINSTALL[@]} -gt 0 ]]; then
    step "Uninstalling managed blocks"
    _bashrc="$HOME/.bashrc"
    for feat in "${UNINSTALL[@]}"; do
        case "$feat" in
            path|starship|aliases|zoxide)
                if $DRY_RUN; then
                    info "Would remove devmux-managed-${feat} from $_bashrc"
                else
                    remove_managed_block "$_bashrc" "$feat"
                    ok "Removed devmux-managed-${feat} from $_bashrc"
                fi
                ;;
            tmux)
                if $DRY_RUN; then
                    info "Would remove ~/.config/tmux/tmux.conf"
                else
                    rm -f "$HOME/.config/tmux/tmux.conf"
                    ok "Removed ~/.config/tmux/tmux.conf"
                fi
                ;;
            tools)
                warn "Cannot uninstall CLI tools automatically — remove them via your package manager"
                ;;
            *)
                warn "Unknown feature: $feat"
                ;;
        esac
    done
    [[ ${#FEATURES[@]} -eq 0 ]] && exit 0
fi

PKG_MGR=$(detect_pkg_manager)
BASHRC="$HOME/.bashrc"
LOCAL_BIN="$HOME/.local/bin"
mkdir -p "$LOCAL_BIN"

ensure_local_bin_on_path() {
    # Make tools installed to ~/.local/bin usable during this run and in future shells.
    case ":${PATH:-}:" in
        *":$LOCAL_BIN:"*) ;;
        *) export PATH="$LOCAL_BIN:${PATH:-}" ;;
    esac

    if $DRY_RUN; then
        info "Would ensure $LOCAL_BIN is on PATH via $BASHRC"
        return
    fi

    write_managed_block "$BASHRC" "path" \
'# Ensure ~/.local/bin is on PATH (so tools installed by devmux are found)
export PATH="$HOME/.local/bin:$PATH"'
    ok "Ensured $LOCAL_BIN is on PATH via $BASHRC"
}

if has_feature tools || has_feature starship || has_feature aliases || has_feature zoxide; then
    ensure_local_bin_on_path
fi

info "Package manager: $PKG_MGR"
info "Features: ${FEATURES[*]}"
$DRY_RUN && info "DRY RUN — no changes will be made"

# ── Helper: confirm in interactive mode ────────────────────────────
maybe_confirm() {
    local msg="$1"
    if $INTERACTIVE; then
        read -rp "  $msg [Y/n] " answer >&2
        [[ -z "$answer" || "$answer" =~ ^[Yy]$ ]]
    else
        return 0
    fi
}

# ── Feature: CLI tools ─────────────────────────────────────────────
install_tools() {
    step "CLI tools"

    case "$PKG_MGR" in
        apt)
            local apt_updated=false
            _apt_update() {
                $apt_updated && return 0

                info "Updating apt cache..."
                if $DRY_RUN; then
                    apt_updated=true
                    return 0
                fi

                if sudo_run apt-get update -qq; then
                    apt_updated=true
                    return 0
                fi
                warn "apt-get update failed"
                return 1
            }
            _apt_install() {
                local pkg="$1"
                if dpkg -s "$pkg" &>/dev/null; then
                    ok "$pkg already installed"
                    return 0
                fi

                _apt_update || return 1
                info "Installing $pkg..."
                if $DRY_RUN; then
                    ok "$pkg"
                    return 0
                fi

                if sudo_run apt-get install -y -qq "$pkg"; then
                    ok "$pkg"
                    return 0
                fi
                warn "Failed to install $pkg"
                return 1
            }

            # starship — not in default apt, use curl installer
            if command -v starship &>/dev/null; then
                ok "starship already installed"
            else
                info "Installing starship via curl installer..."
                if ! $DRY_RUN; then
                    curl -sS https://starship.rs/install.sh | sh -s -- --yes --bin-dir "$LOCAL_BIN" 2>/dev/null
                fi
                ok "starship → $LOCAL_BIN/starship"
            fi

            # eza — not in default Ubuntu apt, try cargo or eza apt repo
            if command -v eza &>/dev/null; then
                ok "eza already installed"
            else
                # Try distro repos first (present on some distros).
                if _apt_install eza; then
                    :
                elif command -v cargo &>/dev/null; then
                    info "Installing eza via cargo..."
                    if $DRY_RUN; then
                        info "Would run: cargo install eza"
                    else
                        cargo install eza 2>/dev/null
                    fi
                    ok "eza (via cargo)"
                elif $INTERACTIVE && maybe_confirm "Add third-party eza apt repo (deb.gierens.de) and install?"; then
                    info "Adding eza apt repository..."
                    if ! $DRY_RUN; then
                        if ! command -v gpg &>/dev/null; then
                            _apt_install gpg || _apt_install gnupg || warn "gpg not available; skipping eza apt repo."
                        fi
                        if command -v gpg &>/dev/null; then
                            sudo_run mkdir -p /etc/apt/keyrings
                            if curl -fsSL https://raw.githubusercontent.com/eza-community/eza/main/deb.asc | sudo_run gpg --dearmor -o /etc/apt/keyrings/eza.gpg 2>/dev/null; then
                                echo "deb [signed-by=/etc/apt/keyrings/eza.gpg] https://deb.gierens.de stable main" | sudo_run tee /etc/apt/sources.list.d/eza.list >/dev/null
                                apt_updated=false
                                _apt_install eza
                            else
                                warn "Could not add eza repository — install eza manually"
                            fi
                        else
                            warn "Skipping eza apt repo (gpg unavailable)."
                        fi
                    else
                        info "Would add eza apt repo and install"
                    fi
                else
                    warn "eza not installed (not found in default repos). Install it manually, or re-run with --interactive to opt into adding a third-party repo."
                fi
            fi

            # bat — Ubuntu installs as batcat
            _apt_install bat || _apt_install batcat || true
            if command -v batcat &>/dev/null && ! command -v bat &>/dev/null; then
                if $DRY_RUN; then
                    info "Would symlink bat → batcat"
                else
                    ln -sf "$(command -v batcat)" "$LOCAL_BIN/bat"
                fi
                ok "Symlinked bat → batcat"
            fi

            _apt_install ripgrep

            # fd-find — Ubuntu installs as fdfind
            _apt_install fd-find || true
            if command -v fdfind &>/dev/null && ! command -v fd &>/dev/null; then
                if $DRY_RUN; then
                    info "Would symlink fd → fdfind"
                else
                    ln -sf "$(command -v fdfind)" "$LOCAL_BIN/fd"
                fi
                ok "Symlinked fd → fdfind"
            fi

            # zoxide — not in all Ubuntu versions, use curl installer
            if command -v zoxide &>/dev/null; then
                ok "zoxide already installed"
            else
                info "Installing zoxide via curl installer..."
                if ! $DRY_RUN; then
                    curl -sS https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | bash 2>/dev/null
                fi
                ok "zoxide"
            fi

            _apt_install fzf

            # yazi - terminal file manager (not in default apt, use cargo or binary)
            if command -v yazi &>/dev/null; then
                ok "yazi already installed"
            else
                info "Installing yazi..."
                if ! $DRY_RUN; then
                    # Try installing via cargo first (if available)
                    if command -v cargo &>/dev/null; then
                        cargo install yazi-fm yazi-cli 2>/dev/null && ok "yazi (via cargo)" || warn "Could not install yazi via cargo"
                    else
                        # Fallback to downloading prebuilt binary
                        local yazi_version="0.3.3"
                        local yazi_arch
                        yazi_arch=$(uname -m)
                        case "$yazi_arch" in
                            x86_64) yazi_arch="x86_64-unknown-linux-gnu" ;;
                            aarch64) yazi_arch="aarch64-unknown-linux-gnu" ;;
                            *) yazi_arch="" ;;
                        esac
                        if [[ -n "$yazi_arch" ]]; then
                            local yazi_url="https://github.com/sxyazi/yazi/releases/download/v${yazi_version}/yazi-${yazi_arch}.zip"
                            local yazi_tmp
                            yazi_tmp=$(mktemp -d)
                            if curl -sSL "$yazi_url" -o "$yazi_tmp/yazi.zip" 2>/dev/null; then
                                if command -v unzip &>/dev/null; then
                                    unzip -q "$yazi_tmp/yazi.zip" -d "$yazi_tmp"
                                    cp "$yazi_tmp/yazi-${yazi_arch}/yazi" "$LOCAL_BIN/yazi" 2>/dev/null
                                    chmod +x "$LOCAL_BIN/yazi" 2>/dev/null
                                    ok "yazi → $LOCAL_BIN/yazi"
                                else
                                    warn "unzip not available, cannot extract yazi"
                                fi
                            else
                                warn "Could not download yazi"
                            fi
                            rm -rf "$yazi_tmp"
                        else
                            warn "Unsupported architecture for yazi binary: $(uname -m)"
                        fi
                    fi
                else
                    info "Would install yazi"
                fi
            fi
            ;;

        pkg)
            # Termux
            local pkg_tools=(starship eza bat ripgrep fd zoxide fzf yazi)
            for tool in "${pkg_tools[@]}"; do
                if command -v "$tool" &>/dev/null; then
                    ok "$tool already installed"
                else
                    info "Installing $tool..."
                    if $DRY_RUN; then
                        info "Would run: pkg install -y $tool"
                    else
                        pkg install -y "$tool"
                    fi
                    ok "$tool"
                fi
            done
            ;;

        pacman)
            local pacman_tools=(starship eza bat ripgrep fd zoxide fzf yazi)
            local missing=()
            for tool in "${pacman_tools[@]}"; do
                if command -v "$tool" &>/dev/null; then
                    ok "$tool already installed"
                else
                    missing+=("$tool")
                fi
            done
            if [[ ${#missing[@]} -gt 0 ]]; then
                info "Installing: ${missing[*]}"
                if $DRY_RUN; then
                    info "Would run: pacman -Syu --needed ${missing[*]}"
                else
                    sudo_run pacman -Syu --noconfirm --needed "${missing[@]}"
                fi
                for tool in "${missing[@]}"; do ok "$tool"; done
            fi
            ;;

        brew)
            local brew_tools=(starship eza bat ripgrep fd zoxide fzf yazi)
            for tool in "${brew_tools[@]}"; do
                if command -v "$tool" &>/dev/null; then
                    ok "$tool already installed"
                else
                    info "Installing $tool..."
                    if $DRY_RUN; then
                        info "Would run: brew install $tool"
                    else
                        brew install "$tool"
                    fi
                    ok "$tool"
                fi
            done
            ;;

        none)
            warn "No package manager detected. Install tools manually:"
            warn "  starship, eza, bat, ripgrep, fd-find, zoxide, fzf, yazi"
            ;;
    esac
}

# ── Feature: tmux config ──────────────────────────────────────────
install_tmux() {
    step "tmux config"

    local tmux_conf="$HOME/.config/tmux/tmux.conf"

    if $DRY_RUN; then
        info "Would write $tmux_conf"
        info "Would clone TPM if missing"
        return
    fi

    mkdir -p "$HOME/.config/tmux"

    cat > "$tmux_conf" << 'TMUXEOF'
# Managed by devmux setup-host
set -g default-terminal "screen-256color"
set -g terminal-overrides ",xterm-256color:RGB"

set -g prefix C-a
unbind C-b
bind C-a send-prefix

set -g base-index 1
set -g pane-base-index 1
set -g detach-on-destroy off
set -g escape-time 0
set -g history-limit 1000000
set -g renumber-windows on
set -g set-clipboard on
set -g status-position top
set -g mouse on
setw -g mode-keys vi

bind \\ split-window -h -c "#{pane_current_path}"
bind - split-window -v -c "#{pane_current_path}"
bind c new-window -c "#{pane_current_path}"
bind h select-pane -L
bind j select-pane -D
bind k select-pane -U
bind l select-pane -R
bind r source-file ~/.config/tmux/tmux.conf \; display "Reloaded!"

bind-key -T copy-mode-vi v send-keys -X begin-selection
bind-key -T copy-mode-vi y send-keys -X copy-selection-and-cancel

bind -n M-H previous-window
bind -n M-L next-window

# yazi file manager - open in split pane (Ctrl+A, f)
bind f split-window -h -c "#{pane_current_path}" "yazi" \; swap-pane -U

# ── plugins (managed by TPM - install with Ctrl+A, Shift+I) ─────────
set -g @plugin 'tmux-plugins/tpm'
set -g @plugin 'tmux-plugins/tmux-sensible'
set -g @plugin 'tmux-plugins/tmux-yank'
set -g @plugin 'tmux-plugins/tmux-resurrect'
set -g @plugin 'tmux-plugins/tmux-continuum'
set -g @plugin 'omerxx/catppuccin-tmux'
set -g @plugin 'omerxx/tmux-sessionx'
set -g @plugin 'omerxx/tmux-floax'

# Floax: popup terminal overlay (Ctrl+A, p)
set -g @floax-width '80%'
set -g @floax-height '80%'
set -g @floax-border-color 'magenta'
set -g @floax-text-color 'blue'
set -g @floax-bind 'p'
set -g @floax-change-path 'true'

# SessionX: fuzzy session/directory switcher (Ctrl+A, o)
set -g @sessionx-bind 'o'
set -g @sessionx-x-path '~/.config'
set -g @sessionx-window-height '85%'
set -g @sessionx-window-width '75%'
set -g @sessionx-zoxide-mode 'on'
set -g @sessionx-filter-current 'false'
set -g @sessionx-auto-accept 'off'

# Continuum + Resurrect: save/restore sessions across reboots.
set -g @continuum-restore 'off'
set -g @resurrect-strategy-nvim 'session'

# Catppuccin theme: colored status bar with session name and directory
set -g @catppuccin_window_left_separator "█"
set -g @catppuccin_window_right_separator "█"
set -g @catppuccin_window_middle_separator " █"
set -g @catppuccin_window_number_position "right"
set -g @catppuccin_window_default_fill "number"
set -g @catppuccin_window_default_text "#W"
set -g @catppuccin_window_current_fill "number"
set -g @catppuccin_window_current_text "#W#{?window_zoomed_flag,(),}"
set -g @catppuccin_status_modules_right "directory"
set -g @catppuccin_status_modules_left "session"
set -g @catppuccin_status_left_separator "█"
set -g @catppuccin_status_right_separator "█"
set -g @catppuccin_status_fill "icon"
set -g @catppuccin_status_connect_separator "no"
set -g @catppuccin_directory_text "#{b:pane_current_path}"

run '~/.tmux/plugins/tpm/tpm'
TMUXEOF
    ok "Wrote $tmux_conf"

    # Clone TPM if missing
    if [[ ! -d "$HOME/.tmux/plugins/tpm" ]]; then
        info "Cloning TPM..."
        git clone https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm" 2>/dev/null || warn "Could not clone TPM — install manually"
    else
        ok "TPM already present"
    fi

    # Create resurrect directory
    mkdir -p "$HOME/.tmux/resurrect"

    # Try to install plugins if tmux server is running
    if tmux list-sessions &>/dev/null 2>&1; then
        info "tmux server running — installing plugins..."
        "$HOME/.tmux/plugins/tpm/bin/install_plugins" 2>/dev/null && ok "Plugins installed" || warn "Plugin install failed — press Ctrl+A, Shift+I inside tmux"
    else
        info "tmux not running — after starting tmux, press Ctrl+A, Shift+I to install plugins"
    fi
}

# ── Feature: Starship prompt ──────────────────────────────────────
install_starship() {
    step "Starship prompt"

    local starship_toml="$HOME/.config/starship.toml"

    if $DRY_RUN; then
        info "Would write $starship_toml"
        info "Would add starship init to $BASHRC"
        return
    fi

    mkdir -p "$HOME/.config"

    cat > "$starship_toml" << 'STAREOF'
# Managed by devmux setup-host
format = """$directory$git_branch
$character"""

right_format = ""
command_timeout = 1000
add_newline = false

[character]
success_symbol = '[➜](bold green)'
error_symbol = '[✗](bold red)'

[directory]
truncation_length = 3
truncation_symbol = "…/"
style = "bold cyan"

[git_branch]
format = '[$branch]($style) '
symbol = ""
style = "bold purple"

[git_status]
disabled = true
[cmd_duration]
disabled = true
[nodejs]
disabled = true
[python]
disabled = true
[docker_context]
disabled = true
[kubernetes]
disabled = true
[golang]
disabled = true
[package]
disabled = true
[aws]
disabled = true
[rust]
disabled = true
[java]
disabled = true
[ruby]
disabled = true
[lua]
disabled = true
[c]
disabled = true
[cmake]
disabled = true
[dart]
disabled = true
[elixir]
disabled = true
[elm]
disabled = true
[erlang]
disabled = true
[haskell]
disabled = true
[kotlin]
disabled = true
[perl]
disabled = true
[php]
disabled = true
[scala]
disabled = true
[swift]
disabled = true
[terraform]
disabled = true
[zig]
disabled = true
[nix_shell]
disabled = true
[conda]
disabled = true
[crystal]
disabled = true
[dotnet]
disabled = true
STAREOF
    ok "Wrote $starship_toml"

    write_managed_block "$BASHRC" "starship" \
'# Starship prompt
command -v starship >/dev/null 2>&1 && eval "$(starship init bash)"'
    ok "Added starship init to $BASHRC"
}

# ── Feature: Bash aliases ─────────────────────────────────────────
install_aliases() {
    step "Bash aliases"

    if $DRY_RUN; then
        info "Would add aliases to $BASHRC"
        return
    fi

    write_managed_block "$BASHRC" "aliases" '# devmux shell aliases

# Navigation
alias ..="cd .."
alias ...="cd ../.."
alias ....="cd ../../.."

# Git
alias gs="git status"
alias gd="git diff"
alias gds="git diff --staged"
alias ga="git add"
alias gaa="git add --all"
alias gc="git commit"
alias gcm="git commit -m"
alias gp="git push"
alias gpl="git pull"
alias gl="git log --oneline --graph --all"
alias gco="git checkout"
alias gsw="git switch"
alias gb="git branch"
alias gst="git stash"
alias gstp="git stash pop"

# Modern CLI (conditional on tool existence)
command -v eza  >/dev/null 2>&1 && alias ls="eza --icons --group-directories-first"
command -v eza  >/dev/null 2>&1 && alias la="eza --icons -la --group-directories-first"
command -v eza  >/dev/null 2>&1 && alias ll="eza --icons -l --group-directories-first"
command -v eza  >/dev/null 2>&1 && alias lt="eza --icons --tree --level=2"
command -v bat  >/dev/null 2>&1 && alias cat="bat"
command -v bat  >/dev/null 2>&1 && alias c="bat --style=plain"
command -v rg   >/dev/null 2>&1 && alias grep="rg"
command -v fd   >/dev/null 2>&1 && alias find="fd"
command -v nvim >/dev/null 2>&1 && alias vim="nvim"
command -v nvim >/dev/null 2>&1 && alias v="nvim"
command -v yazi >/dev/null 2>&1 && alias fm="yazi"

# Utilities
ports() { lsof -i -P -n 2>/dev/null | grep LISTEN; }
publicip() { curl -s https://ifconfig.me; }
localip() { hostname -I 2>/dev/null | awk "{print \$1}"; }'
    ok "Added aliases to $BASHRC"
}

# ── Feature: zoxide ───────────────────────────────────────────────
install_zoxide() {
    step "zoxide"

    if $DRY_RUN; then
        info "Would add zoxide init to $BASHRC"
        return
    fi

    write_managed_block "$BASHRC" "zoxide" \
'# zoxide smart directory jumping
command -v zoxide >/dev/null 2>&1 && eval "$(zoxide init bash)"'
    ok "Added zoxide init to $BASHRC"
}

# ── Main ──────────────────────────────────────────────────────────
echo "" >&2
info "devmux host provisioning"
info "========================"

if has_feature tools; then
    if maybe_confirm "Install CLI tools (starship, eza, bat, rg, fd, zoxide, fzf)?"; then
        install_tools
    fi
fi

if has_feature tmux; then
    if maybe_confirm "Configure tmux (catppuccin theme, vim nav, plugins)?"; then
        install_tmux
    fi
fi

if has_feature starship; then
    if maybe_confirm "Configure Starship prompt?"; then
        install_starship
    fi
fi

if has_feature aliases; then
    if maybe_confirm "Install bash aliases (git, modern CLI, utilities)?"; then
        install_aliases
    fi
fi

if has_feature zoxide; then
    if maybe_confirm "Configure zoxide?"; then
        install_zoxide
    fi
fi

echo "" >&2
ok "Done! Run 'source ~/.bashrc' or open a new shell to apply changes."
