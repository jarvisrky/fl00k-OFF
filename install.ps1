<#
.SYNOPSIS
    flookOFF installer. Run once after cloning the repo.

.DESCRIPTION
    1. Creates the flookOFF directory at the chosen install path.
    2. Copies all tool files into place.
    3. Appends (or replaces) the flookOFF function in your PowerShell profile
       so you can type "flookOFF" from any shell.

.EXAMPLE
    .\install.ps1
    .\install.ps1 -InstallPath "D:\Tools\flookOFF"

.NOTES
    Requires PowerShell 5.1+ on Windows.
    Run from the repo root directory.
#>
param(
    [string]$InstallPath = "C:\Users\$env:USERNAME\Documents\flookOFF"
)

$ErrorActionPreference = "Stop"
Set-ExecutionPolicy -Scope Process Bypass -Force

$BANNER = @"

  Installing flookOFF...
  Install path : $InstallPath
  Profile      : $PROFILE

"@
Write-Host $BANNER -ForegroundColor Cyan

# ---------------------------------------------------------------------------
# 1. Create directory structure
# ---------------------------------------------------------------------------
$dirs = @(
    $InstallPath,
    (Join-Path $InstallPath "lib"),
    (Join-Path $InstallPath "sessions"),
    (Join-Path $InstallPath "captures"),
    (Join-Path $InstallPath "exports"),
    (Join-Path $InstallPath "screenshots")
)
foreach ($d in $dirs) {
    New-Item -ItemType Directory -Force -Path $d | Out-Null
    Write-Host "  [dir]  $d" -ForegroundColor DarkGray
}

# ---------------------------------------------------------------------------
# 2. Copy tool files
# ---------------------------------------------------------------------------
$src = $PSScriptRoot

$filesToCopy = @(
    @{ Src = "flookOFF.ps1";         Dst = $InstallPath },
    @{ Src = "lib\network.ps1";      Dst = (Join-Path $InstallPath "lib") },
    @{ Src = "lib\export.ps1";       Dst = (Join-Path $InstallPath "lib") },
    @{ Src = "lib\scan_lldp.ps1";    Dst = (Join-Path $InstallPath "lib") }
)

foreach ($f in $filesToCopy) {
    $srcPath = Join-Path $src $f.Src
    if (-not (Test-Path $srcPath)) {
        Write-Host "  [MISSING]  $($f.Src) - skipped" -ForegroundColor Yellow
        continue
    }
    Copy-Item -Path $srcPath -Destination $f.Dst -Force
    Write-Host "  [copy]  $($f.Src)" -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# 3. Wire up the PowerShell profile
# ---------------------------------------------------------------------------
$profileDir = Split-Path $PROFILE -Parent
New-Item -ItemType Directory -Force -Path $profileDir | Out-Null

$escapedPath = $InstallPath -replace '\\','\\'

$funcBlock = @"

# ---- flookOFF (auto-added by install.ps1) ----
`$FlookOFFRoot = "$InstallPath"

function flookOFF {
    [CmdletBinding()]
    param(
        [string]`$TsharkPath     = "C:\Program Files\Wireshark\tshark.exe",
        [string]`$OutputDir      = "",
        [string]`$Adapter        = "auto",
        [string]`$WindowsAdapter = "",
        [int]`$Duration          = 90,
        [int]`$IpWaitSeconds     = 25,
        [ValidateSet("csv","xlsx")]
        [string]`$Format         = "csv",
        [switch]`$IncludeOwnLldp,
        [switch]`$KeepRaw,
        [switch]`$NoLiveExcel,
        [switch]`$NoMenu
    )
    & (Join-Path `$FlookOFFRoot "flookOFF.ps1") @PSBoundParameters
}

Set-Alias flook-OFF flookOFF
# ---- end flookOFF ----
"@

# Remove any previous flookOFF block from the profile before re-adding
$profileContent = ""
if (Test-Path $PROFILE) {
    $profileContent = Get-Content $PROFILE -Raw
    $profileContent = $profileContent -replace '(?s)# ---- flookOFF.*?# ---- end flookOFF ----\r?\n?', ''
}

$profileContent + $funcBlock | Set-Content $PROFILE -Encoding UTF8
Write-Host "  [profile]  flookOFF function written to $PROFILE" -ForegroundColor Green

# ---------------------------------------------------------------------------
# 4. Done
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "  Install complete." -ForegroundColor Cyan
Write-Host "  Reload your profile then type 'flookOFF' to start:" -ForegroundColor White
Write-Host ""
Write-Host "      . `$PROFILE" -ForegroundColor Yellow
Write-Host "      flookOFF" -ForegroundColor Yellow
Write-Host ""
Write-Host "  To uninstall, delete $InstallPath and remove the" -ForegroundColor DarkGray
Write-Host "  '# ---- flookOFF ----' block from your PowerShell profile." -ForegroundColor DarkGray
Write-Host ""
