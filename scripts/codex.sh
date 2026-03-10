#!/usr/bin/env bash
# Install @openai/codex globally via pnpm
set -euo pipefail

case "$OSTYPE" in
    darwin*) PNPM_HOME="$HOME/Library/pnpm" ;;
    *)       PNPM_HOME="$HOME/.local/share/pnpm" ;;
esac
export PNPM_HOME

pnpm="$PNPM_HOME/pnpm"
if [ ! -x "$pnpm" ]; then
    echo "codex: pnpm not found at $PNPM_HOME — run scripts/pnpm.sh first"
    exit 1
fi

if "$pnpm" list -g --depth 0 2>/dev/null | grep -qF "@openai/codex"; then
    echo "codex: already installed"
else
    echo "codex: installing @openai/codex..."
    "$pnpm" add -g "@openai/codex"
    echo "codex: done"
fi
