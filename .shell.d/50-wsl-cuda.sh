# Prefer WSL CUDA shim so GPU-aware apps in WSL resolve the correct libcuda.
if [ -d /usr/lib/wsl/lib ]; then
    case ":${LD_LIBRARY_PATH:-}:" in
        *:/usr/lib/wsl/lib:*) ;;
        *) export LD_LIBRARY_PATH="/usr/lib/wsl/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}" ;;
    esac
fi
