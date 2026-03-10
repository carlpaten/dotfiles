#!/usr/bin/env bash
# Install Claude Code CLI
set -euo pipefail

claude_bin="$HOME/.local/bin/claude"

if [ -x "$claude_bin" ]; then
    echo "claude: already installed ($("$claude_bin" --version 2>/dev/null || echo 'unknown version'))"
    exit 0
fi

echo "claude: installing..."
curl -fsSL https://claude.ai/install.sh | bash
echo "claude: done"
