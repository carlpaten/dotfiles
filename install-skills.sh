#!/usr/bin/env bash
set -euo pipefail

DOTFILES="$(cd "$(dirname "$0")" && pwd)"
SOURCE_SKILLS_DIR="$DOTFILES/.agents/skills"
SHARED_SKILLS_DIR="$HOME/.agents/skills"

link_dir() {
    local src="$1"
    local dst="$2"
    local label="$3"

    if [ -L "$dst" ]; then
        if [ "$(readlink "$dst")" = "$src" ]; then
            echo "linked $label -> $src"
            return
        fi
        rm "$dst"
    elif [ -e "$dst" ]; then
        echo "backing up $label -> $label.bak"
        mv "$dst" "$dst.bak"
    fi

    mkdir -p "$(dirname "$dst")"
    ln -s "$src" "$dst"
    echo "linked $label -> $src"
}

merge_opencode_skills() {
    local target="$HOME/.config/opencode/opencode.json"
    local target_dir
    local skills_path="$HOME/.agents/skills"

    if ! command -v jq &>/dev/null; then
        echo "jq not found, skipping OpenCode skills config"
        return
    fi

    target_dir="$(dirname "$target")"
    mkdir -p "$target_dir"

    if [ -f "$target" ] && jq empty "$target" >/dev/null 2>&1; then
        jq --arg path "$skills_path" '
            .skills = ((.skills // {}) | if type == "object" then . else {} end)
            | .skills.paths = (
                ((.skills.paths // []) | if type == "array" then . else [] end) + [$path]
                | unique
            )
        ' "$target" > "$target.tmp" && mv "$target.tmp" "$target"
    else
        if [ -f "$target" ]; then
            cp "$target" "$target.bak"
            echo "backed up invalid OpenCode config to ~/.config/opencode/opencode.json.bak"
        fi
        jq -n --arg path "$skills_path" '{skills: {paths: [$path]}}' > "$target"
    fi

    echo "merged shared skills path -> ~/.config/opencode/opencode.json"
}

sync_skills() {
    local src_root="$1"
    local dst_root="$2"
    local label_root="$3"
    local src_path
    local name
    local copied=0

    mkdir -p "$dst_root"

    shopt -s nullglob
    for src_path in "$src_root"/*; do
        name="$(basename "$src_path")"

        if [ -d "$src_path" ] && [ ! -f "$src_path/SKILL.md" ]; then
            continue
        fi

        if [ -f "$src_path" ] && [[ "$name" != *.md ]]; then
            continue
        fi

        link_dir "$src_path" "$dst_root/$name" "$label_root/$name"
        copied=$((copied + 1))
    done
    shopt -u nullglob

    if [ "$copied" -eq 0 ]; then
        echo "no skills found in $src_root"
    fi
}

if [ ! -d "$SOURCE_SKILLS_DIR" ]; then
    echo "skills source directory not found at $SOURCE_SKILLS_DIR, skipping skill install"
    exit 0
fi

sync_skills "$SOURCE_SKILLS_DIR" "$SHARED_SKILLS_DIR" "~/.agents/skills"
sync_skills "$SHARED_SKILLS_DIR" "$HOME/.claude/skills" "~/.claude/skills"
sync_skills "$SHARED_SKILLS_DIR" "$HOME/.codex/skills" "~/.codex/skills"
sync_skills "$SHARED_SKILLS_DIR" "$HOME/.pi/agent/skills" "~/.pi/agent/skills"
merge_opencode_skills
