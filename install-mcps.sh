#!/usr/bin/env bash
set -euo pipefail

DOTFILES="$(cd "$(dirname "$0")" && pwd)"
MCP_FILE="$DOTFILES/mcps.json"
CODEX_CONFIG_FILE="$HOME/.codex/config.toml"

if ! command -v jq &>/dev/null; then
    echo "jq not found, skipping MCP install"
    exit 0
fi

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

render_codex_mcp_sections() {
    local name
    local command_json
    local args_json
    local url_json

    while IFS= read -r name; do
        if jq -e --arg name "$name" '.[$name].type == "http" and (.[$name].url | type == "string")' "$MCP_FILE" >/dev/null; then
            url_json="$(jq -r --arg name "$name" '.[$name].url | @json' "$MCP_FILE")"
            printf '[mcp_servers.%s]\nurl = %s\n\n' "$name" "$url_json"
        elif jq -e --arg name "$name" '.[$name].command | type == "string"' "$MCP_FILE" >/dev/null; then
            command_json="$(jq -r --arg name "$name" '.[$name].command | @json' "$MCP_FILE")"
            args_json="$(jq -c --arg name "$name" '.[$name].args // []' "$MCP_FILE")"
            printf '[mcp_servers.%s]\ncommand = %s\nargs = %s\n\n' "$name" "$command_json" "$args_json"
        fi
    done < <(jq -r 'keys[]' "$MCP_FILE")
}

install_codex_mcp() {
    mkdir -p "$(dirname "$CODEX_CONFIG_FILE")"

    if [ -f "$CODEX_CONFIG_FILE" ]; then
        awk '
            BEGIN { in_mcp_section = 0 }
            /^\[mcp_servers\./ {
                in_mcp_section = 1
                next
            }
            /^\[/ {
                in_mcp_section = 0
            }
            !in_mcp_section { print }
        ' "$CODEX_CONFIG_FILE" > "$CODEX_CONFIG_FILE.tmp"
    else
        : > "$CODEX_CONFIG_FILE.tmp"
    fi

    if [ -s "$CODEX_CONFIG_FILE.tmp" ]; then
        printf '\n' >> "$CODEX_CONFIG_FILE.tmp"
    fi

    render_codex_mcp_sections >> "$CODEX_CONFIG_FILE.tmp"
    mv "$CODEX_CONFIG_FILE.tmp" "$CODEX_CONFIG_FILE"

    echo "merged mcps.json -> ~/.codex/config.toml"
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
        jq --argjson mcp "$opencode_mcp" '.mcp = $mcp' "$target" > "$target.tmp" \
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
