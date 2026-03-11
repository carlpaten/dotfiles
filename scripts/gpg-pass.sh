#!/usr/bin/env bash
# Configure GPG for interactive pinentry use and initialize pass.
set -euo pipefail

case "$OSTYPE" in
    darwin*)
        pinentry_program="/opt/homebrew/bin/pinentry-mac"
        ;;
    linux*)
        pinentry_program="/home/linuxbrew/.linuxbrew/bin/pinentry"
        ;;
    *)
        echo "gpg/pass: unsupported OS '$OSTYPE', skipping"
        exit 0
        ;;
esac

require_cmd() {
    local cmd="$1"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "gpg/pass: missing required command '$cmd'" >&2
        exit 1
    fi
}

primary_fingerprint() {
    gpg --list-secret-keys --with-colons --keyid-format=long 2>/dev/null | awk -F: '
        $1 == "sec" { in_sec = 1; next }
        in_sec && $1 == "fpr" { print $10; exit }
    '
}

fingerprint_for_email() {
    local email="$1"
    gpg --list-secret-keys --with-colons --keyid-format=long 2>/dev/null | awk -F: -v email="$email" '
        $1 == "sec" { current = ""; next }
        $1 == "fpr" && current == "" { current = $10; next }
        $1 == "uid" && current != "" && index($10, email) { print current; exit }
    '
}

has_encryption_subkey() {
    local fingerprint="$1"
    gpg --list-secret-keys --with-colons "$fingerprint" 2>/dev/null | awk -F: '
        $1 == "ssb" && index($12, "e") { found = 1 }
        END { exit found ? 0 : 1 }
    '
}

require_cmd gpg
require_cmd gpgconf
require_cmd pass

if [ ! -x "$pinentry_program" ]; then
    echo "gpg/pass: missing pinentry program at $pinentry_program" >&2
    echo "gpg/pass: run scripts/packages.sh first" >&2
    exit 1
fi

mkdir -p "$HOME/.gnupg"
chmod 700 "$HOME/.gnupg"

cat > "$HOME/.gnupg/gpg-agent.conf" <<EOF
pinentry-program $pinentry_program
default-cache-ttl 600
max-cache-ttl 7200
EOF
chmod 600 "$HOME/.gnupg/gpg-agent.conf"

gpgconf --kill gpg-agent >/dev/null 2>&1 || true
gpgconf --launch gpg-agent
echo "gpg/pass: configured gpg-agent"

email="$(git config --global user.email 2>/dev/null || true)"
fingerprint=""
if [ -n "$email" ]; then
    fingerprint="$(fingerprint_for_email "$email" || true)"
fi

if [ -z "$fingerprint" ]; then
    fingerprint="$(primary_fingerprint || true)"
fi

if [ -z "$fingerprint" ]; then
    name="$(git config --global user.name 2>/dev/null || true)"

    if [ -n "$name" ] && [ -n "$email" ]; then
        uid="$name <$email>"
    elif [ -n "$email" ]; then
        uid="$email"
    else
        uid="$(whoami)@$(hostname)"
    fi

    echo "gpg/pass: generating a new GPG key for $uid"
    gpg --quick-generate-key "$uid" ed25519 cert,sign 1y
    fingerprint="$(primary_fingerprint || true)"
    if [ -z "$fingerprint" ]; then
        echo "gpg/pass: failed to determine the new key fingerprint" >&2
        exit 1
    fi
else
    echo "gpg/pass: using existing key $fingerprint"
fi

if has_encryption_subkey "$fingerprint"; then
    echo "gpg/pass: encryption subkey already present"
else
    echo "gpg/pass: adding encryption subkey"
    gpg --quick-add-key "$fingerprint" cv25519 encrypt 1y
fi

store_dir="${PASSWORD_STORE_DIR:-$HOME/.password-store}"
mkdir -p "$store_dir"
chmod 700 "$store_dir"

echo "gpg/pass: initializing pass for $fingerprint"
pass init "$fingerprint"
echo "gpg/pass: store ready at $store_dir"
