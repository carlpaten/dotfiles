# SSH agent configuration — use a fixed socket so all tmux panes share one agent
export SSH_AUTH_SOCK="$HOME/.ssh/agent.sock"

if ! ssh-add -l &>/dev/null; then
    rm -f "$SSH_AUTH_SOCK"
    eval "$(ssh-agent -a "$SSH_AUTH_SOCK")" > /dev/null
    ssh-add ~/.ssh/id_ed25519 2>/dev/null
fi
