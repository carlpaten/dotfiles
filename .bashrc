# ~/.bashrc: executed by bash(1) for interactive non-login shells.

[ -r "$HOME/.bash_env" ] && . "$HOME/.bash_env"

# If not running interactively, don't do anything
case $- in
    *i*) ;;
      *) return;;
esac

# Source bash-specific modules
for f in ~/.shell.d/*.bash; do
    [ -r "$f" ] && . "$f"
done
unset f

# opencode
export PATH=/home/carl/.opencode/bin:$PATH
