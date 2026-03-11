# shellcheck shell=bash

bw_unlock() {
    local entry session

    if ! command -v bw >/dev/null 2>&1; then
        echo "bw_unlock: missing 'bw' command" >&2
        return 1
    fi

    if ! command -v pass >/dev/null 2>&1; then
        echo "bw_unlock: missing 'pass' command" >&2
        return 1
    fi

    entry="${BW_PASS_ENTRY:-bitwarden/carlpaten@protonmail.com/password}"
    if ! BW_MASTER_PW="$(pass show "$entry" | sed -n '1p')"; then
        echo "bw_unlock: failed to read pass entry '$entry'" >&2
        unset BW_MASTER_PW
        return 1
    fi

    export BW_MASTER_PW
    if [ -z "$BW_MASTER_PW" ]; then
        echo "bw_unlock: pass entry '$entry' is empty" >&2
        unset BW_MASTER_PW
        return 1
    fi

    if ! session="$(bw unlock --passwordenv BW_MASTER_PW --raw)"; then
        echo "bw_unlock: unlock failed" >&2
        unset BW_MASTER_PW
        return 1
    fi

    export BW_SESSION="$session"

    if ! bw sync --session "$BW_SESSION"; then
        echo "bw_unlock: sync failed" >&2
        unset BW_MASTER_PW
        return 1
    fi

    unset BW_MASTER_PW
}
