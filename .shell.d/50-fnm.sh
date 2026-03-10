# fnm (Fast Node Manager)
FNM_PATH="$HOME/.local/share/fnm"
if [ -d "$FNM_PATH" ]; then
    export PATH="$FNM_PATH:$PATH"
    unset FNM_MULTISHELL_PATH
    eval "$(fnm env)"
fi
