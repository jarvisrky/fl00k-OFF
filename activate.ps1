<#
    Session-only flookOFF activation.
    Dot-source it from the repo root:
        . .\activate.ps1
#>

$ErrorActionPreference = "Stop"
$scriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$mainScript = Join-Path $scriptRoot "flookOFF.ps1"

if (-not (Test-Path $mainScript)) {
    throw "Could not find flookOFF.ps1 next to activate.ps1. Keep the repo folder structure intact."
}

$env:FLOOKOFF_HOME = $scriptRoot

function global:flookOFF {
    & (Join-Path $env:FLOOKOFF_HOME "flookOFF.ps1") @args
}

Set-Alias -Name flook-OFF -Value flookOFF -Scope Global

if (-not $global:__FLOOKOFF_OLD_PROMPT) {
    $global:__FLOOKOFF_OLD_PROMPT = (Get-Command prompt).ScriptBlock
}

function global:prompt {
    "(flookOFF) " + (& $global:__FLOOKOFF_OLD_PROMPT)
}

function global:deactivate-flookOFF {
    if ($global:__FLOOKOFF_OLD_PROMPT) {
        Set-Item -Path function:global:prompt -Value $global:__FLOOKOFF_OLD_PROMPT
        Remove-Variable -Name __FLOOKOFF_OLD_PROMPT -Scope Global -ErrorAction SilentlyContinue
    }
    Remove-Item function:global:flookOFF -ErrorAction SilentlyContinue
    Remove-Item alias:\flook-OFF -ErrorAction SilentlyContinue
    Remove-Item env:\FLOOKOFF_HOME -ErrorAction SilentlyContinue
    Write-Host "flookOFF deactivated." -ForegroundColor Cyan
}

Write-Host "flookOFF activated. Run 'flookOFF' or 'deactivate-flookOFF'." -ForegroundColor Cyan
