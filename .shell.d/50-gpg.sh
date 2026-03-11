# shellcheck shell=sh
# Ensure gpg-agent pinentry can talk to the active terminal.
if [ -t 0 ]; then
    gpg_tty="$(tty)"
    export GPG_TTY="$gpg_tty"
    unset gpg_tty
fi
