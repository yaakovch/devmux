# devmux

Interactive SSH + tmux launcher. Pick a host, project, and tool from a menu — land in the right tmux session instantly.

Built for developers who work across multiple machines (home PC, work PC) and connect from laptops, phones (Termux), or other devices over Tailscale/SSH.

## How it works

```
[Client]                          [Host (Windows+WSL or Linux)]
devmux                            devmux-remote
  ├─ pick host ──── SSH ────────→   ├─ cd ~/projects/<project>
  ├─ pick project (fetched live)    ├─ tmux new/attach session
  ├─ pick tool (codex/claude/…)     └─ run tool inside tmux
  └─ pick resume/new
```

- **Client** runs on any machine you SSH *from* (laptop, phone, another PC).
- **Host** is the machine you SSH *into* (your dev PCs running WSL or Linux).

## Quickstart

### 1. Install on a host (your dev PC)

Inside WSL or Linux on the target machine:

```bash
git clone <repo-url> ~/devmux
cd ~/devmux
bash install/install-host-wsl.sh
```

For Windows hosts, also see `install/install-host-windows.ps1` for OpenSSH/WSL setup notes.

### 2. Install on a client

On any machine you connect *from*:

```bash
git clone <repo-url> ~/devmux
cd ~/devmux
bash install/install-client.sh
```

Then edit `~/.config/devmux/devmux.conf` with your hosts:

```bash
HOSTS=("home" "work")
HOST_home_SSH="home-pc"           # SSH alias or Tailscale hostname
HOST_home_WSL_PREFIX=""           # empty if SSH lands in Linux/WSL
HOST_work_SSH="work-pc"
HOST_work_WSL_PREFIX="wsl -d Ubuntu --exec bash -lc"
```

### 3. Run

```bash
devmux
```

Or with flags to skip menus:

```bash
devmux --host work --project myapp --tool claude --mode resume
```

## Android (Termux)

### Setup

```bash
pkg install openssh fzf
git clone <repo-url> ~/devmux
cd ~/devmux
bash install/install-client.sh
```

Edit `~/.config/devmux/devmux.conf` as above.

### One-tap launch (Termux:Widget)

1. Install **Termux:Widget** from F-Droid.
2. The installer places a script at `~/.shortcuts/devmux`.
3. Add a Termux:Widget widget to your home screen.
4. Tap **devmux** — it opens the interactive menu.

`~/.shortcuts/` is the directory Termux:Widget scans for scripts. Each executable file there becomes a launchable shortcut.

### SSH key setup

```bash
# Generate a key (if you haven't)
ssh-keygen -t ed25519

# Copy to your hosts
ssh-copy-id home-pc
ssh-copy-id work-pc
```

## Configuration

Config lives at `~/.config/devmux/devmux.conf`. See `config/devmux.example.conf` for all options.

### Hosts

```bash
HOSTS=("home" "work" "cloud")

# SSH target — use an SSH alias from ~/.ssh/config or user@hostname
HOST_home_SSH="home-pc"
HOST_cloud_SSH="user@cloud.example.com"

# WSL prefix — set this if SSH lands on Windows, not inside WSL
HOST_work_WSL_PREFIX="wsl -d Ubuntu --exec bash -lc"
```

### Tools

```bash
TOOLS=("codex" "claude" "shell")
TOOL_codex_CMD="codex"
TOOL_claude_CMD="claude"
TOOL_shell_CMD=""          # empty = plain bash
```

Add any tool by defining `TOOL_<name>_CMD="<command>"`.

### SSH aliases (recommended)

In `~/.ssh/config` on your client:

```
Host home-pc
    HostName home-pc    # Tailscale MagicDNS name
    User sapir

Host work-pc
    HostName work-pc
    User sapir
```

## Session naming

Sessions follow the pattern `<tool>:<project>` for resume mode, and `<tool>:<project>:<timestamp>` for new mode. This avoids collisions and makes `tmux ls` output readable:

```
claude:myapp        ← resumed
codex:backend:1706123456  ← new session
```

## File structure

```
devmux/
├── scripts/
│   ├── devmux              # Client menu script
│   └── devmux-remote       # Runs on host, manages tmux
├── install/
│   ├── install-client.sh   # Client installer
│   ├── install-host-wsl.sh # Host installer (WSL/Linux)
│   └── install-host-windows.ps1  # Windows host setup notes
├── termux/
│   └── shortcuts/
│       └── devmux          # Termux:Widget shortcut
├── config/
│   └── devmux.example.conf # Example config
└── README.md
```

## Requirements

- **Client**: bash, ssh, optional fzf
- **Host**: bash, tmux, ssh server
- **Connectivity**: Tailscale (recommended) or any SSH-reachable network

## Troubleshooting

**"Config not found"** — Run `install/install-client.sh` or copy `config/devmux.example.conf` to `~/.config/devmux/devmux.conf`.

**"Could not connect"** — Check that `ssh <host-alias>` works manually. Verify Tailscale is up.

**"No projects found"** — Ensure `~/projects/` exists on the host and has subdirectories.

**"devmux-remote: command not found"** — Run `install/install-host-wsl.sh` on the host, or check that `~/.local/bin` is in PATH.
