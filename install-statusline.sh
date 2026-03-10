#!/usr/bin/env bash
set -euo pipefail

DOTFILES="$(cd "$(dirname "$0")" && pwd)"

# Symlink the statusline script
src="$DOTFILES/.claude/usage-statusline.py"
dst="$HOME/.claude/usage-statusline.py"
if [ -L "$dst" ]; then
    rm "$dst"
elif [ -e "$dst" ]; then
    echo "backing up ~/.claude/usage-statusline.py -> ~/.claude/usage-statusline.py.bak"
    mv "$dst" "$dst.bak"
fi
mkdir -p "$(dirname "$dst")"
ln -s "$src" "$dst"
echo "linked ~/.claude/usage-statusline.py -> $src"

# Merge statusLine config into ~/.claude/settings.json
if ! command -v jq &>/dev/null; then
    echo "jq not found, skipping statusLine config merge"
    exit 0
fi

target="$HOME/.claude/settings.json"
if [ -f "$target" ]; then
    jq --slurpfile sl "$DOTFILES/claude-statusline.json" '.statusLine = $sl[0]' "$target" > "$target.tmp" \
        && mv "$target.tmp" "$target"
else
    mkdir -p "$(dirname "$target")"
    jq -n --slurpfile sl "$DOTFILES/claude-statusline.json" '{statusLine: $sl[0]}' > "$target"
fi
echo "merged claude-statusline.json -> ~/.claude/settings.json"
