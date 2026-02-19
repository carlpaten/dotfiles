# ~/.bashrc: executed by bash(1) for non-login shells.

# If not running interactively, don't do anything
case $- in
    *i*) ;;
      *) return;;
esac

# Source portable (.sh) and bash-specific (.bash) modules
for f in ~/.shell.d/*.sh ~/.shell.d/*.bash; do
    [ -r "$f" ] && . "$f"
done
unset f
