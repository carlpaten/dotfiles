#!/usr/bin/env bash
# Install Homebrew formulae and casks
set -euo pipefail

case "$OSTYPE" in
    darwin*) brew_prefix="/opt/homebrew" ;;
    linux*)  brew_prefix="/home/linuxbrew/.linuxbrew" ;;
    *)       echo "packages: unsupported OS '$OSTYPE', skipping"; exit 0 ;;
esac

brew="$brew_prefix/bin/brew"
if [ ! -x "$brew" ]; then
    echo "packages: brew not found at $brew — run scripts/homebrew.sh first"
    exit 1
fi

formulae=(
    bitwarden-cli
    fnm
    tmux
    shellcheck
    gh
    gnupg
    pass
)

case "$OSTYPE" in
    darwin*) formulae+=(pinentry-mac) ;;
    linux*)  formulae+=(pinentry) ;;
esac

casks=(
    spotify
    cursor
    google-chrome
    rectangle
    slack
)

install_formula() {
    if "$brew" list --formula "$1" &>/dev/null; then
        echo "  $1: already installed"
    else
        echo "  installing $1..."
        "$brew" install "$1"
    fi
}

install_cask() {
    if "$brew" list --cask "$1" &>/dev/null; then
        echo "  $1: already installed"
    else
        echo "  installing $1..."
        "$brew" install --cask "$1"
    fi
}

echo "packages: checking formulae..."
for pkg in "${formulae[@]}"; do
    install_formula "$pkg"
done

# Casks are macOS-only
case "$OSTYPE" in darwin*)
    echo "packages: checking casks..."
    for pkg in "${casks[@]}"; do
        install_cask "$pkg"
    done
    ;; esac

echo "packages: done"
