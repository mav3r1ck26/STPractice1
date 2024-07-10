#!/usr/bin/env bash
set -e

# @describe Runs the shell command.
# @option --command! The command to execute.

main() {
    if [ -t 1 ]; then
        read -r -p "Are you sure you want to continue? [Y/n] " ans
        if [[ "$ans" == "N" || "$ans" == "n" ]]; then
            echo "Aborted!"
            exit 1
        fi
    fi
    eval "$argc_command" >> "$LLM_OUTPUT"
}

eval "$(argc --argc-eval "$0" "$@")"
