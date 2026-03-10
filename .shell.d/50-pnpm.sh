# pnpm
case "$OSTYPE" in
    darwin*) export PNPM_HOME="$HOME/Library/pnpm" ;;
    *)       export PNPM_HOME="$HOME/.local/share/pnpm" ;;
esac
case ":$PATH:" in
    *":$PNPM_HOME:"*) ;;
    *) export PATH="$PNPM_HOME:$PATH" ;;
esac
