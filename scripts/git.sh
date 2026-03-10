#!/usr/bin/env bash
# Configure git global settings (skips keys that are already set)
set -euo pipefail

git_set() {
    local key="$1" val="$2"
    if git config --global --get "$key" &>/dev/null; then
        echo "  $key: already set to '$(git config --global --get "$key")'"
    else
        git config --global "$key" "$val"
        echo "  $key = $val"
    fi
}

echo "git: configuring..."
git_set user.email         "carl.paten@g2i.ai"
git_set user.name          "Carl Patenaude-Poulin"
git_set gpg.format         "ssh"
git_set user.signingkey    "$HOME/.ssh/id_ed25519.pub"
echo "git: done"
