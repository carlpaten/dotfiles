#!/usr/bin/env bash
set -euo pipefail

DOTFILES="$(cd "$(dirname "$0")" && pwd)"

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
link .zshrc
link .shell.d
link .tmux.conf
link .local/bin/notify-send

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

echo ""
echo "done — restart your shell or: source ~/.bashrc"
