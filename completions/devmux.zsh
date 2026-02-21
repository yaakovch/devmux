# devmux zsh completion
# Place this file in a directory in your $fpath (e.g., /usr/local/share/zsh/site-functions/)
# Or source it directly in your .zshrc

_devmux() {
    local curcontext="$curcontext" state line
    typeset -A opt_args

    _arguments -C \
        '(-h --help)'{-h,--help}'[Show help]' \
        '--host[Host to connect to]:host:_devmux_hosts' \
        '--project[Project to open]:project:_devmux_projects' \
        '--session[Session to attach or "new"]:session:(new)' \
        '--settings[Open settings menu]' \
        '--fast[Skip pre-flight check]' \
        '1: :_devmux_subcommands'
}

_devmux_hosts() {
    local -a hosts
    if [[ -f ~/.config/devmux/devmux.conf ]]; then
        # Extract hosts from config
        hosts=(${(f)"$(grep -o 'HOSTS=([^)]*)' ~/.config/devmux/devmux.conf 2>/dev/null | grep -o '"[^"]*"' | tr -d '"')"})
    fi
    _describe -t hosts 'hosts' hosts
}

_devmux_projects() {
    # Projects are dynamic based on host, so we can't complete them here
    # Just return empty
    return 1
}

_devmux_subcommands() {
    local -a subcmds
    subcmds=('settings:Open settings menu')
    _describe -t commands 'devmux subcommand' subcmds
}

compdef _devmux devmux
