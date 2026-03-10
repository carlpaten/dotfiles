#!/usr/bin/env bash
set -euo pipefail

DOTFILES="$(cd "$(dirname "$0")" && pwd)"

# ── Setup scripts ──────────────────────────────────────────────────────────────
"$DOTFILES/scripts/homebrew.sh"

# Bring brew into PATH for the rest of this session
case "$OSTYPE" in
    darwin*) eval "$(/opt/homebrew/bin/brew shellenv)" 2>/dev/null || true ;;
    linux*)  eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)" 2>/dev/null || true ;;
esac

"$DOTFILES/scripts/packages.sh"

# Bring fnm (just installed) into PATH so node.sh and pnpm.sh can use it
if command -v fnm &>/dev/null; then
    eval "$(fnm env)"
fi

"$DOTFILES/scripts/node.sh"
"$DOTFILES/scripts/pnpm.sh"
"$DOTFILES/scripts/codex.sh"
"$DOTFILES/scripts/claude.sh"
"$DOTFILES/scripts/ssh-keygen.sh"
"$DOTFILES/scripts/git.sh"
echo ""

# ── Symlinks ───────────────────────────────────────────────────────────────────
link() {
    local src="$DOTFILES/$1" dst="$HOME/$1"
    if [ -L "$dst" ]; then
        rm "$dst"
    elif [ -e "$dst" ]; then
        echo "backing up ~/$1 -> ~/$1.bak"
        mv "$dst" "$dst.bak"
    fi
    mkdir -p "$(dirname "$dst")"
    ln -s "$src" "$dst"
    echo "linked ~/$1 -> $src"
}

link .bashrc
link .zprofile
link .zshrc
link .shell.d
link .tmux.conf
link .scripts
link .local/bin/notify-send
link .local/bin/claude_usage
link .local/bin/git-prune-merged
link .local/bin/playwright-mcp-authenticated
link .local/bin/pi-playwright-signin-state-from-bitwarden
link .local/bin/start-outhouse-worktree
link .local/bin/start-noshun-worktree
link .cursor/mcp.json
link AGENTS.md

# AGENTS.md is the source of truth; symlink it as CLAUDE.md for Claude Code
agents_src="$DOTFILES/AGENTS.md"
agents_dst="$HOME/CLAUDE.md"
if [ -L "$agents_dst" ]; then
    rm "$agents_dst"
elif [ -e "$agents_dst" ]; then
    echo "backing up ~/CLAUDE.md -> ~/CLAUDE.md.bak"
    mv "$agents_dst" "$agents_dst.bak"
fi
ln -s "$agents_src" "$agents_dst"
echo "linked ~/CLAUDE.md -> $agents_src"

# SSH authorized keys
keys=("$DOTFILES"/ssh-keys/*.pub)
if [ ${#keys[@]} -gt 0 ]; then
    echo ""
    echo "available SSH keys:"
    for i in "${!keys[@]}"; do
        name="$(basename "${keys[$i]}" .pub)"
        comment="$(awk '{print $3}' "${keys[$i]}")"
        printf "  [%d] %s (%s)\n" "$((i+1))" "$name" "$comment"
    done
    echo ""
    read -rp "enable which keys? (e.g. 1 3 4, or 'all', or 'none') " selection

    mkdir -p ~/.ssh && chmod 700 ~/.ssh
    if [ "$selection" = "all" ]; then
        cat "${keys[@]}" > ~/.ssh/authorized_keys
    elif [ "$selection" != "none" ]; then
        > ~/.ssh/authorized_keys
        for i in $selection; do
            cat "${keys[$((i-1))]}" >> ~/.ssh/authorized_keys
        done
    fi

    if [ -f ~/.ssh/authorized_keys ]; then
        chmod 600 ~/.ssh/authorized_keys
        n=$(wc -l < ~/.ssh/authorized_keys)
        echo "wrote $n key(s) to ~/.ssh/authorized_keys"
    fi
fi

# Claude MCP servers and statusline
"$DOTFILES/install-mcps.sh"
"$DOTFILES/install-statusline.sh"
"$DOTFILES/install-skills.sh"

# Pre-commit hook
hook="$DOTFILES/.git/hooks/pre-commit"
ln -sf "$DOTFILES/hooks/pre-commit" "$hook"
chmod +x "$DOTFILES/hooks/pre-commit"
echo "installed pre-commit hook"

echo ""
echo "done — restart your shell or: source ~/.bashrc"
