#!/usr/bin/env bash
set -euo pipefail

DOTFILES="$(cd "$(dirname "$0")" && pwd)"
MCP_FILE="$DOTFILES/mcps.json"

if ! command -v jq &>/dev/null; then
    echo "jq not found, skipping MCP auth"
    exit 0
fi

remote_names=()
while IFS= read -r name; do
    remote_names+=("$name")
done < <(jq -r '
    to_entries[]
    | select(.value.type == "http" and (.value.url | type == "string"))
    | .key
' "$MCP_FILE")

if [ ${#remote_names[@]} -eq 0 ]; then
    echo "no remote MCPs require auth"
    exit 0
fi

ensure_codex_mcp_auth() {
    local status_json
    local auth_status
    local name
    local pids=()
    local pid

    if ! command -v codex &>/dev/null; then
        echo "codex not found, skipping Codex MCP auth"
        return
    fi

    status_json="$(codex mcp list --json 2>/dev/null || echo '[]')"

    for name in "${remote_names[@]}"; do
        auth_status="$(printf '%s\n' "$status_json" | jq -r --arg name "$name" '
            map(select(.name == $name)) | .[0].auth_status // empty
        ')"

        if [ "$auth_status" = "not_logged_in" ]; then
            echo ""
            echo "starting Codex MCP auth: $name"
            codex mcp login "$name" &
            pids+=("$!")
        else
            echo "Codex MCP auth OK: $name"
        fi
    done

    for pid in "${pids[@]}"; do
        wait "$pid"
    done
}

ensure_claude_mcp_auth() {
    local name
    local pids=()
    local pid

    if ! command -v claude &>/dev/null; then
        echo "claude not found, skipping Claude MCP auth"
        return
    fi

    for name in "${remote_names[@]}"; do
        echo ""
        echo "starting Claude MCP auth: $name"
        (
            claude mcp get "$name" >/dev/null
            echo "Claude MCP auth OK: $name"
        ) &
        pids+=("$!")
    done

    for pid in "${pids[@]}"; do
        wait "$pid"
    done
}

ensure_codex_mcp_auth
ensure_claude_mcp_auth
