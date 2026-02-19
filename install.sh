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

echo "done — restart your shell or: source ~/.bashrc"
