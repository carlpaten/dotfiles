# Homebrew
case "$OSTYPE" in
    linux*)  _brew_prefix="/home/linuxbrew/.linuxbrew" ;;
    darwin*) _brew_prefix="/opt/homebrew" ;;
esac

if [ -n "$_brew_prefix" ] && [ -x "$_brew_prefix/bin/brew" ]; then
    eval "$("$_brew_prefix/bin/brew" shellenv)"
fi
unset _brew_prefix
