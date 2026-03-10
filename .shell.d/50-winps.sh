if command -v powershell.exe >/dev/null 2>&1 && command -v wslpath >/dev/null 2>&1; then
    # Run inline PowerShell from WSL.
    winps() {
        powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$*"
    }

    # Run a PowerShell script file from WSL with auto path conversion.
    winpss() {
        local script="${1:?usage: winpss <script.ps1> [args...]}"
        shift

        if [[ "$script" == "~/"* ]]; then
            script="$HOME/${script#~/}"
        fi

        local win_script
        win_script="$(wslpath -w "$(realpath -m "$script")")"
        powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$win_script" "$@"
    }
fi
