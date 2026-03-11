#!/usr/bin/env bash
# Install Playwright CLI globally and install local agent skills
set -euo pipefail

echo "playwright: installing @playwright/cli..."
pnpm install -g @playwright/cli@latest

echo "playwright: done"
