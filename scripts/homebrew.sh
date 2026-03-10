#!/usr/bin/env bash
# Install Homebrew — macOS (Apple Silicon or Intel) and Linux
set -euo pipefail

case "$OSTYPE" in
    darwin*) brew_prefix="/opt/homebrew" ;;
    linux*)  brew_prefix="/home/linuxbrew/.linuxbrew" ;;
    *)       echo "homebrew: unsupported OS '$OSTYPE', skipping"; exit 0 ;;
esac

if [ -x "$brew_prefix/bin/brew" ]; then
    echo "homebrew: already installed at $brew_prefix"
    exit 0
fi

echo "homebrew: installing..."
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
echo "homebrew: done"
