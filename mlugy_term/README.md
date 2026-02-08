# Your Terminal Stack - Quick Guide

---

## The Stack

```
┌──────────────────────────────────────┐
│  Aerospace   (tiling window manager) │
│  ┌────────────────────────────────┐  │
│  │  Ghostty   (terminal app)      │  │
│  │  ┌────────────────────────┐    │  │
│  │  │  tmux  (multiplexer)   │    │  │
│  │  │  ┌──────────────────┐  │    │  │
│  │  │  │ Nushell (shell)  │  │    │  │
│  │  │  │ Starship (prompt)│  │    │  │
│  │  │  └──────────────────┘  │    │  │
│  │  └────────────────────────┘    │  │
│  └────────────────────────────────┘  │
└──────────────────────────────────────┘
```

---

## Ghostty (the terminal app)

Ghostty is the window that runs everything. It replaced Terminal.app/iTerm2.

**Option+S** from any app → dropdown terminal appears. Press again to hide. Works system-wide - this alone is worth the switch.

Edit config: `nvim ~/.config/ghostty/config` - Ghostty auto-reloads on save.

Browse themes: `ghostty +list-themes` (300+ built-in).

---

## Nushell (your shell)

Nushell replaced zsh/bash. Its big idea is **structured data** - commands return tables with named columns instead of plain text.

### Nushell tables vs text (important!)

We aliased `ls`, `cat`, `grep`, and `find` to prettier replacements (eza, bat, rg, fd).

For **looking at files** - use the aliases:

```
ls                          # eza: pretty icons and colors
la                          # eza: includes hidden files
lt                          # eza: tree view
cat file.txt                # bat: syntax highlighting
```

For **filtering and querying** - use nushell's built-in commands:

```
glob **/*.json              # find files by pattern (returns table)
glob **/*.ts | where ($it | path stat).size > 1mb   # filter by size
ps | where name =~ node     # find processes
open data.csv | where amount > 100   # query CSV like SQL
open config.json | get db.host       # drill into JSON
sys host                    # system info as a table
http get https://api.github.com/users/octocat   # HTTP → table
```

### Nushell gotchas (coming from bash/zsh)

Nushell is a different language, not just a different shell. A few things work differently:

- **No `-p` flag on mkdir** - nushell's `mkdir` creates parents automatically. Just `mkdir ~/.config/tmux`.
- **No `2>/dev/null**` - nushell doesn't use bash-style redirects. Errors display differently.
- **No `&&` or `||**` - use `;`  to chain commands, or `try { } catch { }` for error handling.
- **No `$()` subshells** - use `()` directly: `let name = (hostname)`.
- **No `export**` - use `$env.MY_VAR = "value"`.
- `**open` is a nushell built-in** that reads files into structured data. To open files/URLs in macOS apps, use `xopen` (defined in config).

**If something doesn't work in nushell,** type `zsh` to drop into a classic shell, do your thing, type `exit` to return.

### 10 things to try

- `ps | where name =~ node` - find processes
- `open config.json | get db.host` - drill into JSON
- `open data.csv | where amount > 100` - query CSV like SQL
- `history | where command =~ docker` - search history
- `sys host` - system info as a table
- `http get https://ifconfig.me` - your public IP
- `echo "hello" | str upcase` - string manipulation
- `1..10 | each { |n| $n * $n }` - list comprehension
- `open file.csv | to json` - convert formats
- `glob **/*.rs | length` - count Rust files in project

---

## Starship (prompt)

The line before your cursor. Shows only your directory and git branch.

```
…/project main
➜
```

- `➜` green = last command succeeded
- `✗` red = last command failed
- `main` purple = git branch (only appears inside git repos)

---

## tmux (session manager)

tmux gives you persistent sessions with tabs (windows) and splits (panes). Everything survives terminal closes and reboots.

**IMPORTANT:** The prefix key is **Ctrl+A** (not Ctrl+B). This is a two-step action: hold Ctrl, press A, release both, **then** press the next key.

### The 8 shortcuts that matter


| What you want        | Keys                                      |
| -------------------- | ----------------------------------------- |
| Split side by side   | Ctrl+A, `\`                               |
| Split top/bottom     | Ctrl+A, `-`                               |
| Move between panes   | Ctrl+A, h/j/k/l                           |
| Zoom pane fullscreen | Ctrl+A, z (again to unzoom)               |
| New window (tab)     | Ctrl+A, c                                 |
| Switch window        | Ctrl+A, 1-9 or Option+Shift+H/L           |
| Session switcher     | Ctrl+A, o (SessionX - the killer feature) |
| Popup terminal       | Ctrl+A, p (Floax)                         |


### SessionX (Ctrl+A, o)

The productivity killer feature: a fuzzy finder showing all your tmux sessions plus your frequently-visited directories. Type part of a project name → select → instantly in that project's session. Powered by zoxide's directory database.

---

## Aerospace (tiling window manager)

Aerospace automatically arranges your windows in a grid. No more dragging and resizing.

**First launch:** Open from /Applications or Spotlight. macOS will ask for accessibility permission - grant it. The icon appears in your menu bar.

**All shortcuts use the Option key** (labeled `⌥` on your Mac keyboard, same physical key as Alt):


| What you want              | Keys                      |
| -------------------------- | ------------------------- |
| Switch workspace           | Option+1 through Option+9 |
| Move window to workspace   | Option+Shift+1 through 9  |
| Toggle last two workspaces | Option+Tab                |
| Focus window               | Option+h/j/k/l            |
| Move window                | Option+Shift+h/j/k/l      |
| Toggle horizontal/vertical | Option+/                  |
| Fullscreen                 | Option+f                  |
| Float/unfloat              | Option+Shift+f            |


**Suggested workspace layout:**

- Option+1 → Terminal (Ghostty + tmux)
- Option+2 → Browser
- Option+3 → Chat (Slack, etc.)
- Option+4 → IDE / notes

**Tip:** Some apps shouldn't tile (Settings, Finder popups). The config already floats these. To float any window temporarily: Option+Shift+f.

---

## Cursor movement

These work everywhere in nushell (and most terminal apps):


| What you want             | Keys                       |
| ------------------------- | -------------------------- |
| Jump one word left/right  | Option+Left / Option+Right |
| Jump to start of line     | Ctrl+A                     |
| Jump to end of line       | Ctrl+E                     |
| Delete word behind cursor | Option+Backspace           |
| Delete to end of line     | Ctrl+K                     |
| Delete entire line        | Ctrl+U                     |
| Fuzzy search history      | Ctrl+R                     |
| Clear screen              | Ctrl+L                     |


**Note:** Option+Arrow requires `macos-option-as-alt = true` in Ghostty (already set by the script).

---

## zoxide (smart cd)

Type `z` + partial directory name instead of `cd` + full path.

- `z proj` → jumps to your most-visited directory matching "proj"
- `z for com` → matches directory with both "for" and "com" in the path
- `zi` → interactive picker showing all matches
- `z -` → go back to previous directory

zoxide learns from `z` usage - the more you visit a directory, the higher it ranks. Give it a day or two of use and it becomes magic. It also powers SessionX's directory suggestions in tmux.

---

## eza, bat, ripgrep, fd (modern replacements)

These are aliased automatically - just use the familiar commands:


| You type       | What actually runs | Why it's better                 |
| -------------- | ------------------ | ------------------------------- |
| `ls`           | eza                | Icons, colors, git status       |
| `la`           | eza -la            | Includes hidden files           |
| `lt`           | eza --tree         | Tree view (2 levels)            |
| `cat file`     | bat                | Syntax highlighting             |
| `c file`       | bat --style=plain  | Quick view, no line numbers     |
| `grep pattern` | ripgrep            | 10x faster, respects .gitignore |
| `find .json`   | fd                 | Simpler, faster                 |


---

## Claude Code in tmux

`**cc-split**` - Splits your current tmux pane and opens Claude Code alongside your work. Must be inside tmux first.

`**cc-project ~/path**` - Creates a new tmux session named after the directory with Claude in one pane, shell in the other.

---

## Config file locations


| Tool           | Path                                              |
| -------------- | ------------------------------------------------- |
| Ghostty        | `~/.config/ghostty/config`                        |
| Nushell config | `~/Library/Application Support/nushell/config.nu` |
| Nushell env    | `~/Library/Application Support/nushell/env.nu`    |
| Starship       | `~/.config/starship.toml`                         |
| tmux           | `~/.config/tmux/tmux.conf`                        |
| Aerospace      | `~/.config/aerospace/aerospace.toml`              |