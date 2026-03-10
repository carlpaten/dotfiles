#!/usr/bin/env bash
# Auto-pull dev branch if safe to do so.
# Runs as a cron job every hour.

set -euo pipefail

REPO_DIR="/home/carl/macrosoft"
LOG_FILE="$HOME/.local/state/auto-pull-dev.log"

mkdir -p "$(dirname "$LOG_FILE")"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"; }

cd "$REPO_DIR"

# 1. Must be on dev branch
BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
if [[ "$BRANCH" != "dev" ]]; then
  log "SKIP: on branch '$BRANCH', not 'dev'"
  exit 0
fi

# 2. Fetch remote
git fetch origin dev --quiet 2>/dev/null
LOCAL=$(git rev-parse HEAD)
REMOTE=$(git rev-parse origin/dev)

if [[ "$LOCAL" == "$REMOTE" ]]; then
  log "SKIP: already up to date"
  exit 0
fi

# 3. Dry-run merge to check for conflicts
if ! git merge-tree --write-tree origin/dev HEAD >/dev/null 2>&1; then
  # Fallback for older git: try merge --no-commit --no-ff then abort
  if git merge --no-commit --no-ff origin/dev >/dev/null 2>&1; then
    git merge --abort 2>/dev/null || true
  else
    git merge --abort 2>/dev/null || true
    log "SKIP: merge would conflict"
    exit 0
  fi
fi

# 4. Pull with autostash
if git pull --autostash --ff origin dev --quiet 2>>"$LOG_FILE"; then
  NEW_HEAD=$(git rev-parse --short HEAD)
  log "PULLED: ${LOCAL:0:7} -> $NEW_HEAD"
else
  log "ERROR: git pull failed"
  exit 1
fi
