export EDITOR=vim
export VISUAL=vim

export PATH="$HOME/.local/bin:$PATH"

# make less more friendly for non-text input files
case "$OSTYPE" in
    linux*) [ -x /usr/bin/lesspipe ] && eval "$(SHELL=/bin/sh lesspipe)" ;;
esac

# set variable identifying the chroot you work in (used in the prompt below)
if [ -z "${debian_chroot:-}" ] && [ -r /etc/debian_chroot ]; then
    debian_chroot=$(cat /etc/debian_chroot)
fi
