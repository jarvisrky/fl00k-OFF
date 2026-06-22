<# Removes the flookOFF profile block. Does not delete your repo folder or exports. #>
[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$profilePath = $PROFILE.CurrentUserAllHosts
$start = "# >>> flookOFF >>>"
$end   = "# <<< flookOFF <<<"

if (Test-Path $profilePath) {
    $current = Get-Content -Path $profilePath -Raw
    $pattern = "(?s)$([regex]::Escape($start)).*?$([regex]::Escape($end))\r?\n?"
    $updated = [regex]::Replace($current, $pattern, "")
    $updated.TrimEnd() + "`r`n" | Set-Content -Path $profilePath -Encoding UTF8
    Write-Host "Removed flookOFF from profile: $profilePath" -ForegroundColor Green
} else {
    Write-Host "No PowerShell profile found at: $profilePath" -ForegroundColor Yellow
}

Remove-Item env:\FLOOKOFF_HOME -ErrorAction SilentlyContinue
Remove-Item alias:\flook-OFF -ErrorAction SilentlyContinue
Remove-Item function:flookOFF -ErrorAction SilentlyContinue
