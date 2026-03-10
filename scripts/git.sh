#!/usr/bin/env bash
# Configure git global settings.
set -euo pipefail

git_set() {
    local key="$1" val="$2"
    local current=""
    current="$(git config --global --get "$key" 2>/dev/null || true)"

    if [ "$current" = "$val" ]; then
        echo "  $key: already '$current'"
        return
    fi

    git config --global "$key" "$val"
    if [ -n "$current" ]; then
        echo "  $key: '$current' -> '$val'"
    else
        echo "  $key = $val"
    fi
}

signing_key="$HOME/.ssh/id_ed25519.pub"
if [ ! -f "$signing_key" ]; then
    echo "git: missing signing key at $signing_key" >&2
    echo "git: run scripts/ssh-keygen.sh first" >&2
    exit 1
fi

echo "git: configuring..."
git_set user.email         "carl.paten@g2i.ai"
git_set user.name          "Carl Patenaude-Poulin"
git_set gpg.format         "ssh"
git_set user.signingkey    "$signing_key"
git_set commit.gpgsign     "true"
git_set tag.gpgsign        "true"
echo "git: done"
