# Alert for long running commands (e.g. sleep 10; alert)
# With argument:  true; alert hey   → title from history, body: hey
# Without:        sleep 10; alert   → title from history, body: directory
alert() {
    local rc=$?
    local icon=$( [ $rc = 0 ] && echo terminal || echo error )
    local cmd
    cmd=$(history 1 | sed -e 's/^\s*[0-9]\+\s*//;s/[;&|]\+\s*alert\(.*\)\?$//')
    if [[ $# -gt 0 ]]; then
        notify-send --urgency=low -i "$icon" "${cmd:-Command completed}" "$*"
    else
        notify-send --urgency=low -i "$icon" "${cmd:-Command completed}" "$PWD"
    fi
}

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
