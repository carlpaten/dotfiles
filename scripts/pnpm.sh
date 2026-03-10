#!/usr/bin/env bash
# Install pnpm and global Node packages
set -euo pipefail

case "$OSTYPE" in
    darwin*) PNPM_HOME="$HOME/Library/pnpm" ;;
    *)       PNPM_HOME="$HOME/.local/share/pnpm" ;;
esac
export PNPM_HOME

if [ -x "$PNPM_HOME/pnpm" ]; then
    echo "pnpm: already installed at $PNPM_HOME"
else
    echo "pnpm: installing..."
    curl -fsSL https://get.pnpm.io/install.sh | sh -
    echo "pnpm: installed"
fi
