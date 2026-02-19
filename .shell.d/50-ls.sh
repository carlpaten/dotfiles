# ls color support
case "$OSTYPE" in
    linux*)  alias ls='ls --color=auto' ;;
    darwin*) alias ls='ls -G' ;;
esac

alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
