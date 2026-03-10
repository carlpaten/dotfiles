#!/usr/bin/env bash
set -euo pipefail

DOTFILES="$(cd "$(dirname "$0")" && pwd)"
MCP_FILE="$DOTFILES/mcps.json"
CODEX_CONFIG_FILE="$HOME/.codex/config.toml"

if ! command -v jq &>/dev/null; then
    echo "jq not found, skipping MCP install"
    exit 0
fi

patch_codex_playwright_timeout() {
    local config_file="$CODEX_CONFIG_FILE"
    local timeout="90.0"

    if [ ! -f "$config_file" ]; then
        return 0
    fi

    awk -v target="[mcp_servers.playwright]" -v timeout="$timeout" '
        BEGIN { in_target = 0; saw_timeout = 0 }
        {
            if ($0 ~ /^\[.*\]/) {
                if (in_target && !saw_timeout) {
                    printf "startup_timeout_sec = %s\n", timeout
                }
                in_target = ($0 == target)
                saw_timeout = 0
                print
                next
            }

            if (in_target && $0 ~ /^startup_timeout_sec[[:space:]]*=/) {
                printf "startup_timeout_sec = %s\n", timeout
                saw_timeout = 1
                next
            }

            print
        }
        END {
            if (in_target && !saw_timeout) {
                printf "startup_timeout_sec = %s\n", timeout
            }
        }
    ' "$config_file" > "$config_file.tmp" && mv "$config_file.tmp" "$config_file"
}

merge_claude_mcp() {
    local target="$HOME/.claude.json"

    if [ -f "$target" ]; then
        jq --slurpfile mcps "$MCP_FILE" '.mcpServers = $mcps[0]' "$target" > "$target.tmp" \
            && mv "$target.tmp" "$target"
    else
        jq -n --slurpfile mcps "$MCP_FILE" '{mcpServers: $mcps[0]}' > "$target"
    fi

    echo "merged mcps.json -> ~/.claude.json"
}

install_codex_mcp() {
    if ! command -v codex &>/dev/null; then
        echo "codex not found, skipping Codex MCP install"
        return
    fi

    mapfile -t names < <(jq -r 'keys[]' "$MCP_FILE")

    for name in "${names[@]}"; do
        if jq -e --arg name "$name" '.[$name].type == "http" and (.[$name].url | type == "string")' "$MCP_FILE" >/dev/null; then
            url="$(jq -r --arg name "$name" '.[$name].url' "$MCP_FILE")"
            codex mcp add "$name" --url "$url" >/dev/null
            echo "configured Codex MCP: $name (remote)"
        elif jq -e --arg name "$name" '.[$name].command | type == "string"' "$MCP_FILE" >/dev/null; then
            command="$(jq -r --arg name "$name" '.[$name].command' "$MCP_FILE")"
            mapfile -t args < <(jq -r --arg name "$name" '.[$name].args[]? // empty' "$MCP_FILE")
            codex mcp add "$name" -- "$command" "${args[@]}" >/dev/null
            echo "configured Codex MCP: $name (local)"
        fi
    done

    patch_codex_playwright_timeout
    echo "configured Codex MCP timeout: playwright (90.0 seconds)"
}

merge_opencode_mcp() {
    local target="$HOME/.config/opencode/opencode.json"
    local target_dir
    local opencode_mcp

    target_dir="$(dirname "$target")"
    mkdir -p "$target_dir"

    opencode_mcp="$(jq -c '
        to_entries
        | map(
            if (.value.type? == "http" and (.value.url? | type == "string")) then
                {key: .key, value: {type: "remote", url: .value.url}}
            elif (.value.command? | type == "string") then
                {key: .key, value: {type: "local", command: ([.value.command] + (.value.args // []))}}
            elif (.value.url? | type == "string") then
                {key: .key, value: {type: "remote", url: .value.url}}
            else
                empty
            end
        )
        | from_entries
    ' "$MCP_FILE")"

    if [ -f "$target" ] && jq empty "$target" >/dev/null 2>&1; then
        jq --argjson mcp "$opencode_mcp" '.mcp = ((.mcp // {}) + $mcp)' "$target" > "$target.tmp" \
            && mv "$target.tmp" "$target"
    else
        if [ -f "$target" ]; then
            cp "$target" "$target.bak"
            echo "backed up invalid opencode config to ~/.config/opencode/opencode.json.bak"
        fi
        jq -n --argjson mcp "$opencode_mcp" '{mcp: $mcp}' > "$target"
    fi

    echo "merged mcps.json -> ~/.config/opencode/opencode.json"
}

merge_claude_mcp
install_codex_mcp
merge_opencode_mcp
