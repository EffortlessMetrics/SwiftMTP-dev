# Bash completion for swiftmtp
# Source this file: source completions/swiftmtp.bash

_swiftmtp() {
    local cur prev commands global_opts
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"

    commands="probe usb-dump device-lab diag storages ls pull push bench
              mirror quirks info health collect submit add-device wizard
              delete move cp copy edit events learn-promote bdd snapshot
              thumb version storybook profile"

    global_opts="--real-only --mock --mock-profile --json --jsonl
                 --trace-usb --trace-usb-details --strict --safe
                 --vid --pid --bus --address --help"

    # Complete global options that take a value
    case "$prev" in
        --mock-profile)
            COMPREPLY=( $(compgen -W "pixel7 galaxy iphone canon default" -- "$cur") )
            return 0
            ;;
        --vid|--pid)
            return 0
            ;;
        --bus|--address)
            return 0
            ;;
    esac

    # If current word starts with -, complete options
    if [[ "$cur" == -* ]]; then
        COMPREPLY=( $(compgen -W "$global_opts" -- "$cur") )
        return 0
    fi

    # Check if a subcommand has already been given
    local subcmd=""
    for word in "${COMP_WORDS[@]:1}"; do
        case "$word" in
            -*) continue ;;
            *)
                if [[ " $commands " == *" $word "* ]]; then
                    subcmd="$word"
                    break
                fi
                ;;
        esac
    done

    # If no subcommand yet, complete subcommands
    if [[ -z "$subcmd" ]]; then
        COMPREPLY=( $(compgen -W "$commands" -- "$cur") )
        return 0
    fi

    # Subcommand-specific completions
    case "$subcmd" in
        pull|push|ls|delete|move|cp|copy|edit|thumb|info)
            # File path arguments — use default file completion
            COMPREPLY=( $(compgen -f -- "$cur") )
            return 0
            ;;
        mirror)
            COMPREPLY=( $(compgen -W "--dry-run --delete --format --conflict" -f -- "$cur") )
            return 0
            ;;
    esac

    # Default: offer global options
    COMPREPLY=( $(compgen -W "$global_opts" -- "$cur") )
    return 0
}

complete -F _swiftmtp swiftmtp
