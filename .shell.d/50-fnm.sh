# fnm (Fast Node Manager)
FNM_PATH="$HOME/.local/share/fnm"
if [ -d "$FNM_PATH" ]; then
    export PATH="$FNM_PATH:$PATH"
    _fnm_runtime_dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
    unset FNM_MULTISHELL_PATH
    eval "$(XDG_RUNTIME_DIR="$_fnm_runtime_dir" fnm env)"
    unset _fnm_runtime_dir
fi
