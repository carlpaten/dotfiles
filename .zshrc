# Source portable (.sh) and zsh-specific (.zsh) modules
for f in ~/.shell.d/*.sh(N) ~/.shell.d/*.zsh(N); do
    [ -r "$f" ] && . "$f"
done
unset f
