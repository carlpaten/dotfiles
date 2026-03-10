[CmdletBinding()]
param(
    [int]$TerminalDisplay = 1,
    [int]$CursorDisplay = 2,
    [string]$TerminalProcessName = "WindowsTerminal",
    [string]$CursorProcessName = "Cursor",
    [string]$CursorTitleLike = "",
    [int]$WaitSeconds = 20
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Windows.Forms
Add-Type @"
using System;
using System.Runtime.InteropServices;

public static class WinApi {
    [DllImport("user32.dll")]
    public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool SetWindowPos(
        IntPtr hWnd,
        IntPtr hWndInsertAfter,
        int X,
        int Y,
        int cx,
        int cy,
        uint uFlags
    );
}
"@

$SW_RESTORE = 9
$SW_MAXIMIZE = 3
$SWP_NOZORDER = 0x0004
$SWP_NOACTIVATE = 0x0010

function Get-SortedScreens {
    return [System.Windows.Forms.Screen]::AllScreens |
        Sort-Object @{ Expression = { $_.Bounds.X } }, @{ Expression = { $_.Bounds.Y } }
}

function Resolve-Screen {
    param(
        [System.Windows.Forms.Screen[]]$Screens,
        [int]$DisplayNumber
    )

    if ($Screens.Count -eq 0) {
        throw "No displays detected."
    }

    $index = $DisplayNumber - 1
    if ($index -lt 0 -or $index -ge $Screens.Count) {
        return $Screens[0]
    }

    return $Screens[$index]
}

function Get-WindowHandle {
    param(
        [string]$ProcessName,
        [string]$TitleLike = "",
        [int]$TimeoutSeconds = 20
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $procs = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue |
            Sort-Object StartTime -Descending

        foreach ($proc in $procs) {
            $handle = [IntPtr]::Zero
            $title = ""
            try {
                $handle = [IntPtr]$proc.MainWindowHandle
                $title = [string]$proc.MainWindowTitle
            }
            catch {
                continue
            }

            if ($handle -eq [IntPtr]::Zero) {
                continue
            }

            if ([string]::IsNullOrWhiteSpace($TitleLike) -or $title -like "*$TitleLike*") {
                return $handle
            }
        }

        Start-Sleep -Milliseconds 200
    } while ((Get-Date) -lt $deadline)

    return [IntPtr]::Zero
}

function Move-MaximizeWindow {
    param(
        [IntPtr]$Handle,
        [System.Windows.Forms.Screen]$Screen
    )

    if ($Handle -eq [IntPtr]::Zero) {
        return
    }

    $bounds = $Screen.WorkingArea
    [void][WinApi]::ShowWindowAsync($Handle, $SW_RESTORE)
    Start-Sleep -Milliseconds 100
    [void][WinApi]::SetWindowPos(
        $Handle,
        [IntPtr]::Zero,
        $bounds.X,
        $bounds.Y,
        $bounds.Width,
        $bounds.Height,
        [uint32]($SWP_NOZORDER -bor $SWP_NOACTIVATE)
    )
    Start-Sleep -Milliseconds 80
    [void][WinApi]::ShowWindowAsync($Handle, $SW_MAXIMIZE)
}

$screens = Get-SortedScreens
$terminalScreen = Resolve-Screen -Screens $screens -DisplayNumber $TerminalDisplay
$cursorScreen = Resolve-Screen -Screens $screens -DisplayNumber $CursorDisplay

$terminalHandle = Get-WindowHandle -ProcessName $TerminalProcessName -TimeoutSeconds $WaitSeconds
$cursorHandle = Get-WindowHandle -ProcessName $CursorProcessName -TitleLike $CursorTitleLike -TimeoutSeconds $WaitSeconds
if ($cursorHandle -eq [IntPtr]::Zero -and -not [string]::IsNullOrWhiteSpace($CursorTitleLike)) {
    $cursorHandle = Get-WindowHandle -ProcessName $CursorProcessName -TimeoutSeconds 4
}

Move-MaximizeWindow -Handle $terminalHandle -Screen $terminalScreen
Move-MaximizeWindow -Handle $cursorHandle -Screen $cursorScreen
