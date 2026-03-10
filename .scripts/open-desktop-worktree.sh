#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage:
  open-desktop-worktree.sh [--background] [--browser "<browser>"] [--harness "<command>"] [--dev-cmd "<pnpm-script>"] [--reference-url "<url>"] <main-worktree-path> <linear-issue-key>

Example:
  open-desktop-worktree.sh ~/macrosoft FOX-1234
  open-desktop-worktree.sh --dev-cmd dev:outhouse ~/macrosoft FOX-1234
  open-desktop-worktree.sh --reference-url https://app.example.com --dev-cmd dev:outhouse ~/macrosoft FOX-1234
  open-desktop-worktree.sh --browser firefox --harness codex ~/macrosoft FOX-1234
  open-desktop-worktree.sh --background ~/macrosoft FOX-1234
EOF
}

die() {
    echo "$1" >&2
    exit 1
}

require_command() {
    local cmd="$1"
    local message="${2:-$cmd not found in PATH.}"
    command -v "$cmd" >/dev/null 2>&1 || die "$message"
}

parse_args() {
    DEV_CMD="dev"
    BROWSER="firefox"
    HARNESS_CMD="codex"
    REFERENCE_URL=""
    BACKGROUND_MODE="false"
    local positional=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --background)
                BACKGROUND_MODE="true"
                shift
                ;;
            --browser)
                [[ $# -ge 2 ]] || die "Missing value for --browser"
                BROWSER="$2"
                shift 2
                ;;
            --harness)
                [[ $# -ge 2 ]] || die "Missing value for --harness"
                HARNESS_CMD="$2"
                shift 2
                ;;
            --dev-cmd)
                [[ $# -ge 2 ]] || die "Missing value for --dev-cmd"
                DEV_CMD="$2"
                shift 2
                ;;
            --reference-url|--reference-app-url)
                [[ $# -ge 2 ]] || die "Missing value for --reference-url"
                REFERENCE_URL="$2"
                shift 2
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            --)
                shift
                while [[ $# -gt 0 ]]; do
                    positional+=("$1")
                    shift
                done
                ;;
            -*)
                usage >&2
                die "Unknown option: $1"
                ;;
            *)
                positional+=("$1")
                shift
                ;;
        esac
    done

    [[ ${#positional[@]} -eq 2 ]] || {
        usage >&2
        die "Expected <main-worktree-path> and <linear-issue-key>."
    }

    MAIN_WORKTREE_INPUT="${positional[0]}"
    ISSUE_KEY="${positional[1]}"
}

find_free_port() {
    local port="${1:-3002}"
    while [[ $port -le 65535 ]]; do
        if command -v ss >/dev/null 2>&1; then
            if ! ss -Htan "( sport = :$port )" 2>/dev/null | grep -q . \
                && ! ss -Huan "( sport = :$port )" 2>/dev/null | grep -q .; then
                printf '%s\n' "$port"
                return 0
            fi
        elif command -v netstat >/dev/null 2>&1; then
            if ! netstat -tan 2>/dev/null | awk '{print $4}' | grep -Eq "[:.]$port$" \
                && ! netstat -uan 2>/dev/null | awk '{print $4}' | grep -Eq "[:.]$port$"; then
                printf '%s\n' "$port"
                return 0
            fi
        else
            printf '%s\n' "$port"
            return 0
        fi
        port=$((port + 1))
    done
    return 1
}

resolve_repo_root() {
    local path="$1"
    git -C "$path" rev-parse --show-toplevel 2>/dev/null || true
}

slugify() {
    local value="$1"
    printf '%s' "$value" \
        | tr '[:upper:]' '[:lower:]' \
        | sed -E 's/[^a-z0-9._-]+/-/g; s/^-+//; s/-+$//; s/-{2,}/-/g'
}

next_available_branch() {
    local repo_root="$1"
    local base="$2"
    local branch="$base"
    local counter=2
    while git -C "$repo_root" show-ref --verify --quiet "refs/heads/$branch"; do
        branch="${base}-${counter}"
        counter=$((counter + 1))
    done
    printf '%s\n' "$branch"
}

refresh_origin_dev() {
    local repo_root="$1"
    git -C "$repo_root" fetch --quiet origin dev || die "Failed to fetch latest origin/dev from $repo_root"
    git -C "$repo_root" rev-parse --verify --quiet refs/remotes/origin/dev >/dev/null \
        || die "origin/dev not found after fetch in $repo_root"
}

ensure_worktree() {
    local repo_root="$1"
    local worktree_path="$2"
    local branch_to_create="$3"
    local start_point="$4"

    if [[ -e "$worktree_path" ]]; then
        if git -C "$worktree_path" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
            local existing_branch
            existing_branch="$(git -C "$worktree_path" rev-parse --abbrev-ref HEAD)"
            printf 'reused|%s\n' "$existing_branch"
            return 0
        fi
        die "Target path exists and is not a git worktree: $worktree_path"
    fi

    git -C "$repo_root" worktree add -b "$branch_to_create" "$worktree_path" "$start_point"
    printf 'created|%s\n' "$branch_to_create"
}

build_desktop_name() {
    local issue_key="$1"
    local desktop_name="$issue_key"

    if command -v claude >/dev/null 2>&1; then
        local prompt output keywords
        prompt="$(cat <<EOF
Use the Linear MCP server to fetch issue $issue_key.
From the issue title, extract 2 to 4 concise keywords suitable for a virtual desktop label.
Output rules:
- output exactly one line
- no issue key
If the issue cannot be fetched, output exactly: NOT_FOUND
EOF
)"
        output="$(claude -p --model haiku --allowed-tools "mcp__linear__get_issue" --output-format text -- "$prompt" 2>/dev/null || true)"
        keywords="$(printf '%s\n' "$output" | tr -d '\r' | sed -n '1{s/^[[:space:]]*//;s/[[:space:]]*$//;p;q}')"
        keywords="${keywords#\"}"
        keywords="${keywords%\"}"
        if [[ -n "$keywords" && "$keywords" != "NOT_FOUND" ]]; then
            desktop_name="$issue_key $keywords"
        fi
    fi

    printf '%s\n' "$desktop_name"
}

create_virtual_desktop() {
    local desktop_name="$1"
    local switch_to_desktop="$2"
    local desktop_script="$HOME/.scripts/new-virtual-desktop.ps1"
    [[ -f "$desktop_script" ]] || die "Desktop creation script missing: $desktop_script"

    local win_script
    win_script="$(wslpath -w "$desktop_script")"

    if [[ "$switch_to_desktop" == "true" ]]; then
        powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$win_script" -Name "$desktop_name" -SwitchToDesktop >/dev/null
    else
        powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$win_script" -Name "$desktop_name" >/dev/null
    fi

    local desktop_count
    desktop_count="$(powershell.exe -NoProfile -Command '$ErrorActionPreference="Stop"; Import-Module VirtualDesktop -DisableNameChecking; [int](Get-DesktopCount)' | tr -d '\r')"
    [[ "$desktop_count" =~ ^[0-9]+$ ]] || die "Failed to read desktop count after creating desktop."
    (( desktop_count > 0 )) || die "Desktop count is invalid after creating desktop."
    printf '%s\n' "$((desktop_count - 1))"
}

set_virtual_desktop_name() {
    local desktop_index="$1"
    local desktop_name="$2"
    local desktop_index_ps desktop_name_ps
    desktop_index_ps="$(escape_powershell_single_quoted "$desktop_index")"
    desktop_name_ps="$(escape_powershell_single_quoted "$desktop_name")"

    powershell.exe -NoProfile -Command "
\$ErrorActionPreference='Stop'
Import-Module VirtualDesktop -DisableNameChecking
\$desktop = Get-Desktop -Index ([int]'$desktop_index_ps')
\$desktop | Set-DesktopName -Name '$desktop_name_ps' | Out-Null
" >/dev/null 2>&1
}

rename_desktop_from_issue_async() {
    local desktop_index="$1"
    local issue_key="$2"

    (
        local target_name
        target_name="$(build_desktop_name "$issue_key")"
        if [[ -z "$target_name" || "$target_name" == "$issue_key" ]]; then
            exit 0
        fi
        if ! set_virtual_desktop_name "$desktop_index" "$target_name"; then
            echo "Warning: failed to rename desktop index $desktop_index to '$target_name'." >&2
        fi
    ) &
}

wait_for_desktop_switch() {
    local desktop_name="$1"
    local timeout_seconds="${2:-8}"
    local deadline=$((SECONDS + timeout_seconds))
    local desktop_name_ps
    desktop_name_ps="${desktop_name//\'/''}"

    while (( SECONDS < deadline )); do
        if powershell.exe -NoProfile -Command "\$ErrorActionPreference='SilentlyContinue'; Import-Module VirtualDesktop -DisableNameChecking; \$name = (Get-CurrentDesktop | Get-DesktopName); if (\$name -eq '$desktop_name_ps') { exit 0 } else { exit 1 }" >/dev/null 2>&1; then
            return 0
        fi
        sleep 0.1
    done

    return 1
}

launch_cursor_window() {
    local distro_name="$1"
    local worktree_path="$2"
    local folder_uri="vscode-remote://wsl+${distro_name}${worktree_path}"
    cursor --new-window --folder-uri "$folder_uri" >/dev/null 2>&1 &
}

write_tmux_bootstrap() {
    local tmux_session="$1"
    local worktree_path="$2"
    local dev_cmd="$3"
    local dev_port="$4"
    local harness_cmd="$5"

    local script_path
    script_path="$(mktemp "${TMPDIR:-/tmp}/open-desktop-worktree-tmux.XXXXXX.sh")"

    local session_q workdir_q dev_cmd_q dev_port_q harness_cmd_q
    session_q="$(printf '%q' "$tmux_session")"
    workdir_q="$(printf '%q' "$worktree_path")"
    dev_cmd_q="$(printf '%q' "$dev_cmd")"
    dev_port_q="$(printf '%q' "$dev_port")"
    harness_cmd_q="$(printf '%q' "$harness_cmd")"

    cat > "$script_path" <<EOF
#!/usr/bin/env bash
set -euo pipefail

session_name=$session_q
workdir=$workdir_q
dev_cmd=$dev_cmd_q
dev_port=$dev_port_q
harness_cmd=$harness_cmd_q
cd "\$workdir"

ensure_two_panes() {
    local top_pane bottom_pane pane_count top_cmd
    pane_count="\$(tmux list-panes -t "\$session_name" -F '#{pane_id}' | wc -l | tr -d ' ')"
    top_pane="\$(tmux list-panes -t "\$session_name" -F '#{pane_id}' | head -n1)"
    [[ -n "\$top_pane" ]] || { echo "Failed to determine tmux top pane." >&2; exit 1; }

    if [[ "\${pane_count:-0}" -lt 2 ]]; then
        top_cmd="\$(tmux display-message -p -t "\$top_pane" '#{pane_current_command}' || true)"
        if [[ "\$top_cmd" == "bash" || "\$top_cmd" == "zsh" || "\$top_cmd" == "sh" || "\$top_cmd" == "fish" ]]; then
            tmux send-keys -t "\$top_pane" "cd \\"\$workdir\\" && \$harness_cmd" C-m
        fi

        bottom_pane="\$(tmux split-window -v -P -F '#{pane_id}' -t "\$top_pane" -c "\$workdir")"
        tmux send-keys -t "\$bottom_pane" "cd \\"\$workdir\\" && pnpm install && (printf 'a\\\\n\\\\n' | pnpm approve-builds || true) && PORT=\\"\$dev_port\\" pnpm \\"\$dev_cmd\\" -- --port \\"\$dev_port\\"" C-m
    fi

    if [[ "\$(tmux display-message -p -t "\$top_pane" '#{window_zoomed_flag}')" == "1" ]]; then
        tmux resize-pane -Z -t "\$top_pane"
    fi
    tmux select-layout -t "\$session_name" even-vertical >/dev/null 2>&1 || true
    tmux select-pane -t "\$top_pane"
}

if tmux has-session -t "\$session_name" 2>/dev/null; then
    ensure_two_panes
    exec tmux attach -t "\$session_name"
fi

tmux new-session -d -s "\$session_name" -c "\$workdir"
top_pane="\$(tmux list-panes -t "\$session_name" -F '#{pane_id}' | head -n1)"
[[ -n "\$top_pane" ]] || { echo "Failed to determine tmux top pane." >&2; exit 1; }
tmux send-keys -t "\$top_pane" "cd \\"\$workdir\\" && \$harness_cmd" C-m
bottom_pane="\$(tmux split-window -v -P -F '#{pane_id}' -t "\$top_pane" -c "\$workdir")"
tmux send-keys -t "\$bottom_pane" "cd \\"\$workdir\\" && pnpm install && (printf 'a\\\\n\\\\n' | pnpm approve-builds || true) && PORT=\\"\$dev_port\\" pnpm \\"\$dev_cmd\\" -- --port \\"\$dev_port\\"" C-m
tmux select-layout -t "\$session_name" even-vertical >/dev/null 2>&1 || true
tmux select-pane -t "\$top_pane"
exec tmux attach -t "\$session_name"
EOF

    chmod +x "$script_path"
    printf '%s\n' "$script_path"
}

launch_terminal_tmux() {
    local worktree_path="$1"
    local tmux_bootstrap_script="$2"
    local terminal_title="$3"
    wt.exe --title "$terminal_title" wsl.exe --cd "$worktree_path" bash "$tmux_bootstrap_script" >/dev/null 2>&1 &
}

get_windows_utc_timestamp() {
    powershell.exe -NoProfile -Command '(Get-Date).ToUniversalTime().ToString("o")' | tr -d '\r'
}

normalize_process_name() {
    local raw="$1"
    raw="${raw##*\\}"
    raw="${raw##*/}"
    raw="${raw%% *}"
    raw="${raw%.exe}"
    printf '%s\n' "$raw"
}

escape_powershell_single_quoted() {
    local value="$1"
    printf '%s' "${value//\'/\'\'}"
}

move_launched_windows_to_desktop() {
    local desktop_index="$1"
    local launched_after_utc="$2"
    local cursor_title_like="$3"
    local terminal_title_like="$4"
    local browser_process_name="${5:-}"
    local desktop_index_ps launched_after_ps cursor_title_ps terminal_title_ps browser_process_ps
    desktop_index_ps="$(escape_powershell_single_quoted "$desktop_index")"
    launched_after_ps="$(escape_powershell_single_quoted "$launched_after_utc")"
    cursor_title_ps="$(escape_powershell_single_quoted "$cursor_title_like")"
    terminal_title_ps="$(escape_powershell_single_quoted "$terminal_title_like")"
    browser_process_ps="$(escape_powershell_single_quoted "$browser_process_name")"

    powershell.exe -NoProfile -Command "
\$ErrorActionPreference = 'Stop'
Import-Module VirtualDesktop -DisableNameChecking
\$target = Get-Desktop -Index ([int]'$desktop_index_ps')
\$started = [DateTime]::Parse('$launched_after_ps', [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind)
\$cursorTitle = '$cursor_title_ps'
\$terminalTitle = '$terminal_title_ps'
\$browserProcess = '$browser_process_ps'

function Move-NewWindow {
    param(
        [string]\$ProcessName,
        [string]\$TitleLike,
        [datetime]\$StartedAfter,
        [int]\$TimeoutSeconds = 30
    )

    \$deadline = (Get-Date).AddSeconds(\$TimeoutSeconds)
    do {
        \$procs = Get-Process -Name \$ProcessName -ErrorAction SilentlyContinue | Sort-Object StartTime -Descending
        foreach (\$proc in \$procs) {
            try {
                \$startedAt = \$proc.StartTime.ToUniversalTime()
            }
            catch {
                continue
            }

            if (\$startedAt -lt \$StartedAfter) { continue }
            if ([IntPtr]\$proc.MainWindowHandle -eq [IntPtr]::Zero) { continue }

            \$title = [string]\$proc.MainWindowTitle
            if (-not [string]::IsNullOrWhiteSpace(\$TitleLike) -and \$title -notlike \"*\$TitleLike*\") {
                continue
            }

            Move-Window -Desktop \$target -Hwnd \$proc.MainWindowHandle | Out-Null
            return \$true
        }
        Start-Sleep -Milliseconds 200
    } while ((Get-Date) -lt \$deadline)

    return \$false
}

function Move-WindowByTitle {
    param(
        [string]\$Title,
        [int]\$TimeoutSeconds = 30
    )

    if ([string]::IsNullOrWhiteSpace(\$Title)) { return \$false }

    \$deadline = (Get-Date).AddSeconds(\$TimeoutSeconds)
    do {
        \$handles = @(Find-WindowHandle -Title \$Title 2>\$null)
        if (\$handles.Count -gt 0) {
            foreach (\$h in \$handles) {
                if ([IntPtr]\$h -ne [IntPtr]::Zero) {
                    Move-Window -Desktop \$target -Hwnd \$h | Out-Null
                    return \$true
                }
            }
        }
        Start-Sleep -Milliseconds 200
    } while ((Get-Date) -lt \$deadline)

    return \$false
}

\$movedTerminal = Move-WindowByTitle -Title \$terminalTitle -TimeoutSeconds 30
if (-not \$movedTerminal) {
    [void](Move-NewWindow -ProcessName 'WindowsTerminal' -TitleLike '' -StartedAfter \$started -TimeoutSeconds 10)
}
\$movedCursor = Move-NewWindow -ProcessName 'Cursor' -TitleLike \$cursorTitle -StartedAfter \$started -TimeoutSeconds 30
if (-not \$movedCursor) {
    [void](Move-NewWindow -ProcessName 'Cursor' -TitleLike '' -StartedAfter \$started -TimeoutSeconds 10)
}

if (-not [string]::IsNullOrWhiteSpace(\$browserProcess)) {
    [void](Move-NewWindow -ProcessName \$browserProcess -TitleLike '' -StartedAfter \$started -TimeoutSeconds 30)
}
" >/dev/null 2>&1 || echo "Warning: failed to move one or more windows to background desktop index $desktop_index." >&2
}

resolve_windows_command_path() {
    local command_name="$1"
    local windows_name="$command_name"
    local windows_name_ps
    local resolved_path
    if [[ "$windows_name" != *.exe ]]; then
        windows_name="${windows_name}.exe"
    fi
    windows_name_ps="$(escape_powershell_single_quoted "$windows_name")"
    resolved_path="$(powershell.exe -NoProfile -Command "\$c = Get-Command '$windows_name_ps' -ErrorAction SilentlyContinue; if (\$c) { \$c.Source }" | tr -d '\r')"
    if [[ -n "$resolved_path" ]]; then
        printf '%s\n' "$resolved_path"
    else
        printf '%s\n' "$windows_name"
    fi
}

open_browser_tabs() {
    local browser_name="$1"
    local issue_key="$2"
    local dev_port="$3"
    local reference_url="${4:-}"
    local browser_path local_url issue_url browser_process_name
    local browser_path_ps local_url_ps issue_url_ps browser_process_ps reference_url_ps
    local launch_ok

    browser_path="$(resolve_windows_command_path "$browser_name")"

    local_url="http://localhost:${dev_port}"
    issue_url="https://linear.app/issue/${issue_key}"
    browser_process_name="$(normalize_process_name "$browser_name")"
    browser_path_ps="$(escape_powershell_single_quoted "$browser_path")"
    local_url_ps="$(escape_powershell_single_quoted "$local_url")"
    issue_url_ps="$(escape_powershell_single_quoted "$issue_url")"
    reference_url_ps="$(escape_powershell_single_quoted "$reference_url")"
    browser_process_ps="$(escape_powershell_single_quoted "$browser_process_name")"
    launch_ok="$(powershell.exe -NoProfile -Command "try { \$browserPath = '$browser_path_ps'; \$localUrl = '$local_url_ps'; \$issueUrl = '$issue_url_ps'; \$referenceUrl = '$reference_url_ps'; \$browserProcess = '$browser_process_ps'; if (\$browserProcess -eq 'firefox') { \$args = @('-new-window',\$localUrl,'-new-tab',\$issueUrl); if (-not [string]::IsNullOrWhiteSpace(\$referenceUrl)) { \$args += @('-new-tab',\$referenceUrl) } } elseif (\$browserProcess -eq 'chrome' -or \$browserProcess -eq 'msedge' -or \$browserProcess -eq 'brave') { \$args = @('--new-window',\$localUrl,\$issueUrl); if (-not [string]::IsNullOrWhiteSpace(\$referenceUrl)) { \$args += @(\$referenceUrl) } } else { \$args = @('--new-window',\$localUrl,\$issueUrl); if (-not [string]::IsNullOrWhiteSpace(\$referenceUrl)) { \$args += @(\$referenceUrl) } }; Start-Process -FilePath \$browserPath -ArgumentList \$args -ErrorAction Stop | Out-Null; 'ok' } catch { '' }" | tr -d '\r')"
    if [[ "$launch_ok" != "ok" ]]; then
        echo "Warning: failed to open browser '$browser_name'." >&2
        printf '\n'
        return 0
    fi
    printf '%s\n' "$browser_process_name"
}

arrange_windows() {
    local worktree_name="$1"
    local arrange_script="$HOME/.scripts/arrange-dev-windows.ps1"
    [[ -f "$arrange_script" ]] || return 0

    local terminal_display cursor_display arrange_windows_win
    terminal_display="${TERMINAL_DISPLAY:-1}"
    cursor_display="${CURSOR_DISPLAY:-2}"
    arrange_windows_win="$(wslpath -w "$arrange_script")"

    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$arrange_windows_win" \
        -TerminalDisplay "$terminal_display" \
        -CursorDisplay "$cursor_display" \
        -CursorTitleLike "$worktree_name" \
        -WaitSeconds 20 >/dev/null 2>&1 &
}

print_summary() {
    local worktree_path="$1"
    local branch_name="$2"
    local reused_worktree="$3"
    local desktop_name="$4"
    local desktop_index="$5"
    local background_mode="$6"
    local tmux_session="$7"
    local dev_cmd="$8"
    local dev_port="$9"
    local harness_cmd="${10}"
    local browser_name="${11}"
    local reference_url="${12}"

    echo "Created worktree: $worktree_path"
    echo "Created branch: $branch_name"
    if [[ "$reused_worktree" == "true" ]]; then
        echo "Reused existing worktree directory."
    fi
    echo "Opened desktop: $desktop_name"
    echo "Desktop index: $desktop_index"
    echo "Background mode: $background_mode"
    echo "Opened tmux session: $tmux_session"
    echo "Top pane harness command: $harness_cmd"
    echo "Bottom pane dev command: $dev_cmd"
    echo "Assigned dev port: $dev_port"
    echo "Browser command: $browser_name"
    if [[ -n "$reference_url" ]]; then
        echo "Reference app URL: $reference_url"
    fi
}

main() {
    parse_args "$@"

    require_command git "git not found in PATH."
    require_command cursor "Cursor CLI not found (expected 'cursor' in PATH)."
    require_command tmux "tmux not found in PATH."
    require_command wt.exe "wt.exe not found in PATH."
    require_command pnpm "pnpm not found in PATH."
    require_command powershell.exe "powershell.exe not found in PATH."
    require_command wslpath "wslpath not found in PATH."
    local harness_exe harness_name
    harness_exe="${HARNESS_CMD%% *}"
    [[ -n "$harness_exe" ]] || die "Harness command cannot be empty."
    require_command "$harness_exe" "Harness command not found in PATH: $harness_exe"
    harness_name="$(normalize_process_name "$harness_exe")"

    local main_repo_root
    main_repo_root="$(resolve_repo_root "$MAIN_WORKTREE_INPUT")"
    [[ -n "$main_repo_root" ]] || die "Path is not inside a git worktree: $MAIN_WORKTREE_INPUT"
    [[ -n "${WSL_DISTRO_NAME:-}" ]] || die "WSL_DISTRO_NAME is not set; cannot build WSL remote URI for Cursor."

    local repo_name parent_dir issue_slug
    repo_name="$(basename "$main_repo_root")"
    parent_dir="$(dirname "$main_repo_root")"
    issue_slug="$(slugify "$ISSUE_KEY")"
    [[ -n "$issue_slug" ]] || die "Issue key produced an empty slug: $ISSUE_KEY"

    local dev_port
    dev_port="$(find_free_port 3002 || true)"
    [[ -n "$dev_port" ]] || die "Unable to determine a free development port."

    local worktree_name worktree_path
    worktree_name="${repo_name}-${issue_slug}"
    worktree_path="${parent_dir}/${worktree_name}"

    refresh_origin_dev "$main_repo_root"
    local start_point
    start_point="origin/dev"

    local branch_base branch_to_create
    branch_base="feature/${repo_name}-${issue_slug}"
    branch_to_create="$(next_available_branch "$main_repo_root" "$branch_base")"

    local worktree_result reused_worktree branch_name
    worktree_result="$(ensure_worktree "$main_repo_root" "$worktree_path" "$branch_to_create" "$start_point")"
    reused_worktree="false"
    if [[ "${worktree_result%%|*}" == "reused" ]]; then
        reused_worktree="true"
    fi
    branch_name="${worktree_result#*|}"

    local desktop_name desktop_index switch_to_desktop launch_marker_utc
    desktop_name="$ISSUE_KEY"
    switch_to_desktop="true"
    if [[ "$BACKGROUND_MODE" == "true" ]]; then
        switch_to_desktop="false"
    fi
    desktop_index="$(create_virtual_desktop "$desktop_name" "$switch_to_desktop")"
    rename_desktop_from_issue_async "$desktop_index" "$ISSUE_KEY"
    if [[ "$switch_to_desktop" == "true" ]] && ! wait_for_desktop_switch "$desktop_name" 8; then
        echo "Warning: timed out waiting for desktop switch to '$desktop_name'." >&2
    fi

    local terminal_title
    terminal_title="WT ${worktree_name} ${dev_port}"

    launch_marker_utc="$(get_windows_utc_timestamp)"
    launch_cursor_window "$WSL_DISTRO_NAME" "$worktree_path"

    local harness_prompt_text harness_run_cmd
    harness_prompt_text="You are working on Linear issue $ISSUE_KEY. The outhouse dev server for this worktree is running on port $dev_port (http://localhost:$dev_port). To run E2E tests against it: CI=1 PORT=$dev_port npx playwright test <spec-file> --reporter=list --retries=0. CI=1 skips webServer startup, PORT sets baseURL."
    harness_run_cmd="$HARNESS_CMD"
    if [[ "$harness_name" == "codex" ]]; then
        harness_run_cmd="$HARNESS_CMD -c developer_instructions=\"$harness_prompt_text\""
    elif [[ "$harness_name" == "claude" ]]; then
        harness_run_cmd="$HARNESS_CMD --append-system-prompt=\"$harness_prompt_text\""
    fi

    local tmux_session tmux_bootstrap_script
    tmux_session="desk-${repo_name}-${issue_slug}"
    tmux_bootstrap_script="$(write_tmux_bootstrap "$tmux_session" "$worktree_path" "$DEV_CMD" "$dev_port" "$harness_run_cmd")"
    launch_terminal_tmux "$worktree_path" "$tmux_bootstrap_script" "$terminal_title"

    local browser_process_name
    browser_process_name="$(open_browser_tabs "$BROWSER" "$ISSUE_KEY" "$dev_port" "$REFERENCE_URL")"
    if [[ "$BACKGROUND_MODE" == "true" ]]; then
        move_launched_windows_to_desktop "$desktop_index" "$launch_marker_utc" "$worktree_name" "$terminal_title" "$browser_process_name"
    else
        arrange_windows "$worktree_name"
    fi

    print_summary "$worktree_path" "$branch_name" "$reused_worktree" "$desktop_name" "$desktop_index" "$BACKGROUND_MODE" "$tmux_session" "$DEV_CMD" "$dev_port" "$harness_run_cmd" "$BROWSER" "$REFERENCE_URL"
}

main "$@"
