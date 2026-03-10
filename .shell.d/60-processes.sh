# Alert for long running commands (e.g. sleep 10; alert)
# With argument:  true; alert hey   → title from history, body: hey
# Without:        sleep 10; alert   → title from history, body: directory
alert() {
    local rc=$?
    local icon=$( [ $rc = 0 ] && echo terminal || echo error )
    local cmd
    cmd=$(history 1 | sed -e 's/^\s*[0-9]\+\s*//;s/[;&|]\+\s*alert\(.*\)\?$//')
    local body
    if [[ $# -gt 0 ]]; then
        body="$*"
    else
        body="$PWD"
    fi

    # Escape single quotes for PowerShell single-quoted strings.
    local cmd_ps body_ps
    cmd_ps="${cmd//\'/''}"
    body_ps="${body//\'/''}"

    # Get current tmux window index
    local tmux_win=""
    if [[ -n "$TMUX" ]]; then
        tmux_win=$(tmux display-message -p '#{window_index}')
    fi

    # Build the WSL command to switch tmux window
    local tmux_cmd=""
    if [[ -n "$tmux_win" ]]; then
        tmux_cmd="tmux select-window -t :$tmux_win"
    fi

    # Show notification and focus WT when clicked
    # The user clicks the toast to dismiss it, which brings WT to foreground
    # We then run the tmux switch command
    (
        # Wait briefly for user to click the notification
        sleep 1.5
        # Focus Windows Terminal and run tmux command
        if [[ -n "$tmux_cmd" ]]; then
            wt.exe wsl.exe bash -c "$tmux_cmd" 2>/dev/null
        else
            wt.exe wsl.exe 2>/dev/null
        fi
    ) &

    # Show the toast notification
    powershell.exe -c "
        [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
        \$template = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent([Windows.UI.Notifications.ToastTemplateType]::ToastText02)
        \$textNodes = \$template.GetElementsByTagName('text')
        \$textNodes[0].AppendChild(\$template.CreateTextNode('$cmd_ps')) | Out-Null
        \$textNodes[1].AppendChild(\$template.CreateTextNode('$body_ps')) | Out-Null
        \$toast = [Windows.UI.Notifications.ToastNotification]::new(\$template)
        [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('Windows Terminal').Show(\$toast)
    " &
}

# Show what process is using a port
case "$OSTYPE" in
    linux*)
        whoison() { ss -tlnp | grep ":$1 "; }
        killport() { ss -tlnp | grep ":$1 " | sed -n 's/.*pid=\([0-9]*\).*/\1/p' | xargs -r kill -9; }
        ;;
    darwin*)
        whoison() { lsof -nP -iTCP:"$1" | grep LISTEN; }
        killport() {
            local pids
            pids="$(lsof -ti TCP:"$1" -sTCP:LISTEN)"
            [ -n "$pids" ] && kill -9 $pids
        }
        ;;
esac
