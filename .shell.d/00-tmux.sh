# Auto-start tmux for interactive sessions
if command -v tmux &>/dev/null && [ -z "$TMUX" ] && [ -z "$INSIDE_EMACS" ] && [ -z "$VSCODE_PID" ]; then
    exec tmux new-session -A -s main
fi
