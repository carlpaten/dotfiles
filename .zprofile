# Keep login shells aligned with the same brew/fnm ordering used elsewhere.
# Non-interactive login shells do not read ~/.zshrc, so load the minimal
# environment setup needed for tool resolution here.
for f in ~/.shell.d/50-brew.sh ~/.shell.d/50-fnm.sh; do
    [ -r "$f" ] && . "$f"
done
unset f
