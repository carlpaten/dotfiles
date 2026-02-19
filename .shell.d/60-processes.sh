# Alert alias for long running commands (e.g. sleep 10; alert)
alias alert='notify-send --urgency=low -i "$([ $? = 0 ] && echo terminal || echo error)" "$(history|tail -n1|sed -e '\''s/^\s*[0-9]\+\s*//;s/[;&|]\s*alert$//'\'')"'

# Show what process is using a port
case "$OSTYPE" in
    linux*)
        whoison() { ss -tlnp | grep ":$1 "; }
        killport() { ss -tlnp | grep ":$1 " | sed -n 's/.*pid=\([0-9]*\).*/\1/p' | xargs -r kill -9; }
        ;;
    darwin*)
        whoison() { lsof -nP -iTCP:"$1" | grep LISTEN; }
        killport() { lsof -ti TCP:"$1" -sTCP:LISTEN | xargs kill -9; }
        ;;
esac
