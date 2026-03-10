#!/usr/bin/env bash
# Install Node.js via fnm and set a default version
set -euo pipefail

NODE_VERSION="22"

# Find fnm — may not be in PATH if this is a fresh shell post-brew install
case "$OSTYPE" in
    darwin*) brew_bin="/opt/homebrew/bin" ;;
    linux*)  brew_bin="/home/linuxbrew/.linuxbrew/bin" ;;
    *)       brew_bin="" ;;
esac

fnm=""
if command -v fnm &>/dev/null; then
    fnm="fnm"
elif [ -n "$brew_bin" ] && [ -x "$brew_bin/fnm" ]; then
    fnm="$brew_bin/fnm"
fi

if [ -z "$fnm" ]; then
    echo "node: fnm not found — run scripts/packages.sh first"
    exit 1
fi

# Activate fnm environment in this shell
eval "$("$fnm" env)"

if "$fnm" list | grep -q "v${NODE_VERSION}\."; then
    echo "node: Node v${NODE_VERSION}.x already installed"
else
    echo "node: installing Node v${NODE_VERSION}..."
    "$fnm" install "$NODE_VERSION"
fi

echo "node: setting Node v${NODE_VERSION}.x as default..."
"$fnm" default "$NODE_VERSION"

echo "node: done ($(node --version 2>/dev/null || echo 'node not in PATH — restart shell'))"
