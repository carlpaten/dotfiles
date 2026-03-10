# Auto-start tmux for interactive terminal sessions.
# Disabled — tmux no longer auto-attaches on session start.
# To re-enable, uncomment the block below.

# case "$-" in
#     *i*) ;;
#       *) return ;;
# esac
#
# if command -v tmux >/dev/null 2>&1 \
#     && [ -z "${TMUX:-}" ] \
#     && [ -z "${INSIDE_EMACS:-}" ] \
#     && [ -z "${VSCODE_PID:-}" ] \
#     && [ -z "${AUTO_TMUX_DISABLE:-}" ] \
#     && [ -t 0 ] && [ -t 1 ]; then
#     tmux new-session -A -s main && exit
# fi
