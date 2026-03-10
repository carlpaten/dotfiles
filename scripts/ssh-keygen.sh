#!/usr/bin/env bash
# Generate an ed25519 SSH key (interactive — will prompt for passphrase)
set -euo pipefail

key="$HOME/.ssh/id_ed25519"

if [ -f "$key" ]; then
    echo "ssh-keygen: $key already exists, skipping"
    exit 0
fi

comment="$(git config --global user.email 2>/dev/null || hostname)"
echo "ssh-keygen: generating ed25519 key (comment: $comment)..."
mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
ssh-keygen -t ed25519 -C "$comment" -f "$key"

# On macOS, store passphrase in the system Keychain and ensure the agent
# loads it automatically via ~/.ssh/config (UseKeychain + AddKeysToAgent)
case "$OSTYPE" in
    darwin*)
        ssh-add --apple-use-keychain "$key"
        echo "ssh-keygen: passphrase stored in macOS Keychain"
        ;;
esac

echo ""
echo "ssh-keygen: public key:"
cat "${key}.pub"
echo ""
echo "Add the above to GitHub → Settings → SSH keys"
