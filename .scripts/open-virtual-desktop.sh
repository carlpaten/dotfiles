#!/usr/bin/env bash
set -euo pipefail

if ! command -v powershell.exe >/dev/null 2>&1; then
    echo "powershell.exe not found in PATH." >&2
    exit 1
fi

if ! command -v wslpath >/dev/null 2>&1; then
    echo "wslpath not found in PATH." >&2
    exit 1
fi

ps_script="$HOME/.scripts/new-virtual-desktop.ps1"
if [[ ! -f "$ps_script" ]]; then
    echo "Missing script: $ps_script" >&2
    exit 1
fi

win_ps_script="$(wslpath -w "$ps_script")"

# Default name when none is provided.
if [[ $# -eq 0 ]]; then
    set -- -Name "Desktop $(date +%H:%M:%S)"
fi

has_switch=false
for arg in "$@"; do
    if [[ "$arg" == "-SwitchToDesktop" ]]; then
        has_switch=true
        break
    fi
done

if [[ "$has_switch" == "true" ]]; then
    exec powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$win_ps_script" "$@"
else
    exec powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$win_ps_script" "$@" -SwitchToDesktop
fi
