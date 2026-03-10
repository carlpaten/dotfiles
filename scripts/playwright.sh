#!/usr/bin/env bash
# Install Playwright CLI globally and install local agent skills
set -euo pipefail

if ! command -v npm &>/dev/null; then
    echo "playwright: npm not found — run scripts/node.sh first"
    exit 1
fi

echo "playwright: installing @playwright/cli..."
npm install -g @playwright/cli@latest

echo "playwright: installing skills..."
playwright-cli install --skills

echo "playwright: done"
