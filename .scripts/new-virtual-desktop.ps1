[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [string]$Name,

    [Parameter(Mandatory = $false)]
    [switch]$SwitchToDesktop
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Compatible with both Windows PowerShell 5.1 and PowerShell 7+.
$runningOnWindows = $false
if ($PSVersionTable.PSEdition -eq "Desktop") {
    $runningOnWindows = $true
}
else {
    $isWindowsVar = Get-Variable -Name IsWindows -ErrorAction SilentlyContinue
    if ($null -ne $isWindowsVar) {
        $runningOnWindows = [bool]$isWindowsVar.Value
    }
}

if (-not $runningOnWindows) {
    throw "This script must be run on Windows."
}

if (-not (Get-Module -ListAvailable -Name VirtualDesktop)) {
    Write-Host "Installing PowerShell module 'VirtualDesktop'..." -ForegroundColor Yellow
    Install-Module -Name VirtualDesktop -Scope CurrentUser -Repository PSGallery -Force -AllowClobber
}

Import-Module VirtualDesktop -DisableNameChecking -ErrorAction Stop

$desktop = New-Desktop
$desktop | Set-DesktopName -Name $Name | Out-Null

if ($SwitchToDesktop) {
    $desktop | Switch-Desktop
}

$index = $desktop | Get-DesktopIndex
Write-Output "Created virtual desktop #$index named '$Name'."
