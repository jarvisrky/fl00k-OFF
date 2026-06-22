<#
    Adds flookOFF to your PowerShell profile as a persistent command.
    Run from the repo root:
        powershell.exe -ExecutionPolicy Bypass -File .\install.ps1
#>
[CmdletBinding()]
param(
    [string]$InstallPath = ""
)

$ErrorActionPreference = "Stop"
$sourceRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }

if (-not $InstallPath) {
    $InstallPath = Join-Path ([Environment]::GetFolderPath("MyDocuments")) "flookOFF"
}

$sourceFull = [System.IO.Path]::GetFullPath($sourceRoot)
$targetFull = [System.IO.Path]::GetFullPath($InstallPath)

if ($sourceFull.TrimEnd('\') -ne $targetFull.TrimEnd('\')) {
    New-Item -ItemType Directory -Force -Path $targetFull | Out-Null
    $exclude = @(".git", "captures", "sessions", "exports")
    Get-ChildItem -Path $sourceFull -Force | Where-Object { $_.Name -notin $exclude } | ForEach-Object {
        $dest = Join-Path $targetFull $_.Name
        if ($_.PSIsContainer) {
            Copy-Item -Path $_.FullName -Destination $dest -Recurse -Force
        } else {
            Copy-Item -Path $_.FullName -Destination $dest -Force
        }
    }
}

$profilePath = $PROFILE.CurrentUserAllHosts
$profileDir = Split-Path -Parent $profilePath
New-Item -ItemType Directory -Force -Path $profileDir | Out-Null
if (-not (Test-Path $profilePath)) { New-Item -ItemType File -Force -Path $profilePath | Out-Null }

$start = "# >>> flookOFF >>>"
$end   = "# <<< flookOFF <<<"
$block = @"
$start
`$env:FLOOKOFF_HOME = "$targetFull"
function flookOFF {
    & (Join-Path `$env:FLOOKOFF_HOME "flookOFF.ps1") @args
}
Set-Alias flook-OFF flookOFF
$end
"@

$current = Get-Content -Path $profilePath -Raw
$escapedStart = [regex]::Escape($start)
$escapedEnd = [regex]::Escape($end)
$pattern = "(?s)$escapedStart.*?$escapedEnd\r?\n?"
if ($current -match $pattern) {
    $current = [regex]::Replace($current, $pattern, "")
}
($current.TrimEnd() + "`r`n`r`n" + $block + "`r`n") | Set-Content -Path $profilePath -Encoding UTF8

Write-Host "flookOFF installed." -ForegroundColor Green
Write-Host "Install path : $targetFull"
Write-Host "Profile      : $profilePath"
Write-Host "Open a new PowerShell window and run: flookOFF" -ForegroundColor Cyan
