#!/bin/bash
# ╔══════════════════════════════════════════════════════════════════╗
# ║  setup-terminal.sh v8                                            ║
# ║  One-shot setup for a modern macOS terminal stack                ║
# ║  Run with: bash setup-terminal.sh                                ║
# ║                                                                  ║
# ║  Stack: Ghostty → Nushell → Starship → tmux + catppuccin         ║
# ║         → Aerospace (tiling window manager)                      ║
# ║                                                                  ║
# ║  What it does:                                                   ║
# ║  1. Installs all packages via Homebrew                           ║
# ║  2. Configures Ghostty (terminal) with catppuccin theme          ║
# ║  3. Sets up Nushell (shell) with aliases, functions, zoxide      ║
# ║  4. Configures Starship (prompt) - minimal: directory + branch   ║
# ║  5. Sets up tmux with plugins, catppuccin status bar             ║
# ║  6. Configures Aerospace (tiling window manager)                 ║
# ║                                                                  ║
# ║  Safe to re-run - overwrites configs, re-installs plugins.       ║
# ╚══════════════════════════════════════════════════════════════════╝

set -euo pipefail
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'; BOLD='\033[1m'
info()  { echo -e "${BLUE}▸${NC} $*"; }
ok()    { echo -e "${GREEN}✓${NC} $*"; }
warn()  { echo -e "${YELLOW}⚠${NC} $*"; }
step()  { echo -e "\n${BOLD}━━━ $* ━━━${NC}\n"; }
[[ "$(uname)" != "Darwin" ]] && { echo "macOS only."; exit 1; }

NU_CFG="$HOME/Library/Application Support/nushell"


#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
step "1/6 Prerequisites"
# Checks that Homebrew is installed. All packages should be installed
# separately via: brew install nushell starship fzf zoxide ripgrep fd
# bat eza git gh neovim jq tree coreutils tmux
# And casks: brew install --cask ghostty font-hack-nerd-font
# nikitabobko/tap/aerospace
#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

if ! command -v brew &>/dev/null; then
    echo "Homebrew is required. Install it first:"
    echo '  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
    exit 1
fi
ok "Homebrew found"


#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
step "2/6 Ghostty"
# The terminal emulator - the outermost layer of the stack.
# Launches nushell directly (not zsh). Uses Catppuccin Mocha theme,
# Hack Nerd Font for icons, translucent background with blur.
# Key setting: macos-option-as-alt = true (enables Option+Arrow word jump).
# Option+S toggles a system-wide dropdown terminal from any app.
#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

mkdir -p ~/.config/ghostty
NU_BIN=$(which nu 2>/dev/null || echo "/opt/homebrew/bin/nu")

cat > ~/.config/ghostty/config << EOF
command = ${NU_BIN}
shell-integration = none
theme = Catppuccin Mocha
font-family = Hack Nerd Font
font-family = Menlo
font-size = 15
background-opacity = 0.85
background-blur-radius = 20
window-padding-x = 8
window-padding-y = 4
window-decoration = true
mouse-hide-while-typing = true
confirm-close-surface = false
macos-option-as-alt = true
keybind = global:opt+s=toggle_quick_terminal
copy-on-select = clipboard
EOF
ok "Ghostty"


#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
step "3/6 Nushell"
# The shell - replaces zsh/bash. Everything is structured data (tables).
# env.nu: PATH setup, editor defaults.
# config.nu: shell settings, keybindings, all aliases, utility functions.
#
# Key decisions:
# - ls/cat/grep/find are aliased to eza/bat/rg/fd (pretty text output).
#   For nushell table operations, use built-in commands: glob, ps, open, sys.
# - No hooks (caused crashes on some nushell versions). Zoxide learns
#   directories via the z function instead of automatic cd tracking.
# - "alias open" removed - conflicts with nushell built-in. Use xopen.
# - Starship integration loaded from integrations/ subfolder.
#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

mkdir -p "$NU_CFG/integrations"

# env.nu - loaded first on every nushell start. Sets PATH and editor.
cat > "$NU_CFG/env.nu" << 'EOF'
$env.PATH = ($env.PATH | split row (char esep)
    | prepend "/opt/homebrew/bin"
    | prepend "/opt/homebrew/sbin"
    | prepend $"($env.HOME)/.local/bin"
    | uniq)
$env.EDITOR = "nvim"
$env.VISUAL = "nvim"
$env.STARSHIP_SHELL = "nu"
EOF

# config.nu - loaded after env.nu. All shell behavior lives here.
cat > "$NU_CFG/config.nu" << 'CONFIGEOF'
$env.config = {
    show_banner: false
    edit_mode: emacs
    ls: { use_ls_colors: true, clickable_links: true }
    table: { mode: rounded, index_mode: auto,
             trim: { methodology: wrapping, wrapping_try_keep_words: true } }
    history: { max_size: 1000000, sync_on_enter: true, file_format: "sqlite" }
    completions: { case_sensitive: false, quick: true, partial: true, algorithm: "fuzzy" }
}

# ── keybindings ───────────────────────────────────────────────────────
# Option+Left/Right = jump by word (requires macos-option-as-alt in Ghostty)
# Ctrl+A/E = start/end of line, Alt+Backspace = delete word
$env.config.keybindings = [
    { name: word_left,     modifier: alt,     keycode: left,      mode: [emacs vi_insert], event: { edit: MoveWordLeft } }
    { name: word_right,    modifier: alt,     keycode: right,     mode: [emacs vi_insert], event: { edit: MoveWordRight } }
    { name: del_word_back, modifier: alt,     keycode: backspace, mode: [emacs vi_insert], event: { edit: BackspaceWord } }
    { name: del_word_fwd,  modifier: alt,     keycode: char_d,    mode: [emacs vi_insert], event: { edit: DeleteWord } }
    { name: line_start,    modifier: control, keycode: char_a,    mode: [emacs vi_insert], event: { edit: MoveToLineStart } }
    { name: line_end,      modifier: control, keycode: char_e,    mode: [emacs vi_insert], event: { edit: MoveToLineEnd } }
]

# ── aliases ───────────────────────────────────────────────────────────
# Navigation
alias .. = cd ..
alias ... = cd ../..
alias .... = cd ../../..

# File listing - eza gives pretty text output with icons and colors.
# These are NOT nushell tables. For table operations use: glob, ps, open, sys.
alias ls = eza --icons --group-directories-first
alias la = eza --icons -la --group-directories-first
alias ll = eza --icons -l --group-directories-first
alias lt = eza --icons --tree --level=2
alias lta = eza --icons --tree --level=2 -a

# Git - short aliases for the commands you use 50 times a day
alias gs = git status
alias gd = git diff
alias gds = git diff --staged
alias ga = git add
alias gaa = git add --all
alias gc = git commit
alias gcm = git commit -m
alias gp = git push
alias gpl = git pull
alias gl = git log --oneline --graph --all
alias gco = git checkout
alias gsw = git switch
alias gb = git branch
alias gst = git stash
alias gstp = git stash pop

# Modern CLI tool replacements (transparent - just use the familiar name)
alias vim = nvim
alias v = nvim
alias c = bat --style=plain
alias cat = bat
alias grep = rg
alias find = fd

# ── utility functions ─────────────────────────────────────────────────
def flushdns [] { sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder; print "DNS flushed" }
def ports [] { ^lsof -i -P -n | lines | find LISTEN }
def ip [] { http get https://ifconfig.me }
def localip [] { ^ipconfig getifaddr en0 }
def json-pretty [] { pbpaste | from json | to json --indent 2 }

# macOS "open" command - can't alias over nushell's built-in open, so it's xopen
def xopen [...args: string] { ^open ...$args }

# ── Claude Code helpers (require tmux) ────────────────────────────────
# cc-split: opens Claude in a pane next to your current shell
def cc-split [] {
    if "TMUX" not-in $env { print "Start tmux first"; return }
    ^tmux split-window -h -p 55 -c "#{pane_current_path}"
    ^tmux send-keys -t '{left}' "claude" Enter
}

# cc-project: creates a full tmux session with Claude + shell for a project
def cc-project [dir: string = "."] {
    let full = ($dir | path expand)
    let name = ($full | path basename)
    ^tmux new-session -d -s $name -c $full
    ^tmux send-keys -t $name "claude" Enter
    ^tmux split-window -h -t $name -c $full
    ^tmux select-pane -t $"($name):0.1"
    ^tmux attach -t $name
}

# ── zoxide - smart directory jumping ─────────────────────────────────
# Custom z/zi functions because zoxide's auto-generated nushell init
# is broken on nushell 0.103+. Use z instead of cd for smart jumping.
def --env z [...rest: string] {
    if ($rest | is-empty) { cd ~; return }
    let arg = $rest.0
    if $arg == "-" { cd -; return }
    let expanded = ($arg | path expand)
    if ($expanded | path type) == "dir" { cd $expanded } else {
        cd (^zoxide query -- ...$rest | str trim)
    }
}
def --env zi [...rest: string] { cd (^zoxide query --interactive -- ...$rest | str trim) }

# ── starship prompt ──────────────────────────────────────────────────
# Loads the starship init script if it exists. Generated by setup script.
let starship_file = ($nu.default-config-dir | path join "integrations/starship.nu")
if ($starship_file | path exists) { source integrations/starship.nu }
CONFIGEOF

# Generate starship integration for nushell and clean up stale zoxide file
command -v starship &>/dev/null && starship init nu > "$NU_CFG/integrations/starship.nu" 2>/dev/null
rm -f "$NU_CFG/integrations/zoxide.nu"
ok "Nushell"


#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
step "4/6 Starship"
# The prompt - the text before your cursor. Shows only two things:
# 1. Current directory (truncated to 3 levels, e.g. …/project/src)
# 2. Git branch name (only inside git repos, in purple)
# All other modules (nodejs, python, docker, aws, etc.) are disabled
# to keep the prompt fast and clean. Uses single-quoted heredoc so
# starship $variables pass through without bash expanding them.
#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

cat > ~/.config/starship.toml << 'STAREOF'
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
ok "Starship"


#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
step "5/6 tmux"
# Terminal multiplexer - persistent sessions with splits and tabs.
# Survives terminal closes and reboots (via tmux-resurrect/continuum).
#
# Prefix key is Ctrl+A (not default Ctrl+B).
# Splits: Ctrl+A,\ (vertical) and Ctrl+A,- (horizontal).
# Pane navigation: Ctrl+A,h/j/k/l (vim-style).
#
# How this works:
# 1. Nukes ALL old tmux state (plugins, sessions, config) for clean start.
# 2. Writes minimal tmux.conf with keybindings (single-quoted heredoc
#    so backslash bindings pass through correctly).
# 3. Injects nushell path via sed (avoids heredoc escaping nightmares).
# 4. Appends plugin config (catppuccin theme, SessionX, Floax, etc.).
# 5. Starts a detached tmux session so TPM can install plugins
#    (TPM requires a running tmux server to function).
#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

NU_PATH=$(which nu 2>/dev/null || echo "/opt/homebrew/bin/nu")

# ── clean slate: remove ALL old tmux state ────────────────────────────
tmux kill-server 2>/dev/null || true
rm -rf "$HOME/.tmux"
rm -f "$HOME/.tmux.conf"
rm -rf "$HOME/.config/tmux"
mkdir -p "$HOME/.config/tmux"

# ── write tmux.conf (single-quoted heredoc - no bash expansion) ───────
cat > ~/.config/tmux/tmux.conf << 'TMUXEOF'
set -g default-shell __NU_PATH__
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
TMUXEOF

# ── inject nushell path (sed avoids all heredoc escaping issues) ──────
sed -i '' "s|__NU_PATH__|${NU_PATH}|" ~/.config/tmux/tmux.conf

# ── append plugin config ─────────────────────────────────────────────
git clone https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm" 2>/dev/null || true

cat >> ~/.config/tmux/tmux.conf << 'PLUGCONF'

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
# Restore is OFF by default - enable after you have real sessions saved.
# To enable: set @continuum-restore 'on' in tmux.conf
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
PLUGCONF

# ── install plugins via detached tmux session ─────────────────────────
# TPM needs a running tmux server to install plugins. We start one
# in the background, run the installer, then clean up.
info "Installing tmux plugins (this takes ~30s)..."
tmux new-session -d -s _plugin_install 2>/dev/null || true
sleep 2
"$HOME/.tmux/plugins/tpm/bin/install_plugins" 2>/dev/null && ok "Plugins installed" || warn "Plugin install failed - run Ctrl+A, Shift+I inside tmux"
tmux kill-session -t _plugin_install 2>/dev/null || true

# Create resurrect directory so continuum doesn't error on first launch
mkdir -p "$HOME/.tmux/resurrect"
touch "$HOME/.tmux/resurrect/last"

ok "tmux"


#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
step "6/6 Aerospace"
# Tiling window manager - automatically arranges windows in a grid.
# All shortcuts use the Option key (⌥). Option+1-9 switches workspaces,
# Option+h/j/k/l moves focus between windows (vim-style).
# Finder and System Settings are set to float (not tile).
# First launch: open from Spotlight, grant accessibility permission.
#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

mkdir -p ~/.config/aerospace
cat > ~/.config/aerospace/aerospace.toml << 'EOF'
start-at-login = true
enable-normalization-flatten-containers = true
enable-normalization-opposite-orientation-for-nested-containers = true

[gaps]
inner.horizontal = 8
inner.vertical = 8
outer.left = 8
outer.right = 8
outer.bottom = 8
outer.top = 8

[mode.main.binding]
alt-h = 'focus left'
alt-j = 'focus down'
alt-k = 'focus up'
alt-l = 'focus right'
alt-shift-h = 'move left'
alt-shift-j = 'move down'
alt-shift-k = 'move up'
alt-shift-l = 'move right'
alt-slash = 'layout tiles horizontal vertical'
alt-comma = 'layout accordion horizontal vertical'
alt-f = 'fullscreen'
alt-shift-f = 'layout floating tiling'
alt-shift-semicolon = 'mode service'
alt-1 = 'workspace 1'
alt-2 = 'workspace 2'
alt-3 = 'workspace 3'
alt-4 = 'workspace 4'
alt-5 = 'workspace 5'
alt-6 = 'workspace 6'
alt-7 = 'workspace 7'
alt-8 = 'workspace 8'
alt-9 = 'workspace 9'
alt-shift-1 = 'move-node-to-workspace 1'
alt-shift-2 = 'move-node-to-workspace 2'
alt-shift-3 = 'move-node-to-workspace 3'
alt-shift-4 = 'move-node-to-workspace 4'
alt-shift-5 = 'move-node-to-workspace 5'
alt-shift-6 = 'move-node-to-workspace 6'
alt-shift-7 = 'move-node-to-workspace 7'
alt-shift-8 = 'move-node-to-workspace 8'
alt-shift-9 = 'move-node-to-workspace 9'
alt-tab = 'workspace-back-and-forth'

[mode.service.binding]
esc = 'mode main'
r = 'mode resize'

[mode.resize.binding]
h = 'resize width -50'
j = 'resize height +50'
k = 'resize height -50'
l = 'resize width +50'
esc = 'mode main'

[[on-window-detected]]
if.app-id = 'com.apple.systempreferences'
run = 'layout floating'

[[on-window-detected]]
if.app-id = 'com.apple.finder'
run = 'layout floating'
EOF
ok "Aerospace"


#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Fallback .zshrc - so zsh still works if you open Terminal.app or
# drop into zsh from nushell. Backs up existing .zshrc first.
#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

[[ -f "$HOME/.zshrc" ]] && cp "$HOME/.zshrc" "$HOME/.zshrc.bak.$(date +%s)" 2>/dev/null
cat > "$HOME/.zshrc" << 'EOF'
[[ -f /opt/homebrew/bin/brew ]] && eval "$(/opt/homebrew/bin/brew shellenv)"
eval "$(starship init zsh)" 2>/dev/null
eval "$(zoxide init zsh)" 2>/dev/null
alias vim="nvim"; alias ls="eza --icons"
EOF


echo ""
echo -e "${GREEN}${BOLD}  ✓ All done!${NC}"
echo ""
echo "  Next steps:"
echo "    1. Cmd+Q Ghostty → reopen"
echo "    2. Type: tmux"
echo "    3. If theme looks plain: Ctrl+A, Shift+I (wait 30s), then Ctrl+A, r"
echo ""
