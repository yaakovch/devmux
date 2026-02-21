# devmux bash completion
# Source this file in your .bashrc: source /path/to/devmux/completions/devmux.bash

_devmux_completions() {
    local cur prev opts
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"

    # Options
    opts="--host --project --session --settings --fast -h --help"

    case "${prev}" in
        --host)
            # Complete with hosts from config
            if [[ -f ~/.config/devmux/devmux.conf ]]; then
                # Source config to get HOSTS array
                local hosts=""
                while IFS= read -r line; do
                    if [[ "$line" =~ HOSTS=\(([[:space:]]*\"([^\"]+)\"[[:space:]]*)*\) ]]; then
                        hosts=$(echo "$line" | grep -o '"[^"]*"' | tr -d '"')
                    fi
                done < ~/.config/devmux/devmux.conf
                COMPREPLY=( $(compgen -W "${hosts}" -- "${cur}") )
            fi
            return 0
            ;;
        --session)
            COMPREPLY=( $(compgen -W "new" -- "${cur}") )
            return 0
            ;;
    esac

    # Default: complete with options and subcommands
    COMPREPLY=( $(compgen -W "${opts} settings" -- "${cur}") )
}

complete -F _devmux_completions devmux
