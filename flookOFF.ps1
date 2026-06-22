<#
.SYNOPSIS
    flookOFF - Network Jack Scanner. Main launcher.

.DESCRIPTION
    Entry point for the flookOFF tool. Shows the banner, checks all
    dependencies, then presents a menu for starting a scan session,
    exporting previous sessions, or adjusting settings.

    Place this file (and the lib/ subfolder) in a permanent directory.
    The PowerShell profile adds a global "flookOFF" alias pointing here.

.EXAMPLE
    flookOFF
    flookOFF -TsharkPath "C:\Tools\tshark.exe"

.NOTES
    v6 - full venv-style rewrite. Launcher separated from scan engine.
    Scan engine is in lib\scan_lldp.ps1.
    Export helpers are in lib\export.ps1.
    Network helpers are in lib\network.ps1.
#>
param(
    [string]$TsharkPath     = "C:\Program Files\Wireshark\tshark.exe",
    [string]$OutputDir      = "",          # default: <script-dir>\exports
    [string]$Adapter        = "auto",
    [string]$WindowsAdapter = "",
    [int]$Duration          = 90,
    [int]$IpWaitSeconds     = 25,
    [ValidateSet("csv","json","xlsx")]
    [string]$Format         = "csv",
    [switch]$IncludeOwnLldp,
    [switch]$KeepRaw,
    [switch]$NoLiveExcel,
    [switch]$NoMenu          # Skip menu, jump straight into scanning
)

$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# Paths and optional local config
# ---------------------------------------------------------------------------
$ROOT = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$ConfigPath = Join-Path $ROOT "flookOFF.config.json"

if (Test-Path $ConfigPath) {
    try {
        $cfg = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json
        if (-not $PSBoundParameters.ContainsKey("TsharkPath")     -and $cfg.TsharkPath)     { $TsharkPath     = [string]$cfg.TsharkPath }
        if (-not $PSBoundParameters.ContainsKey("OutputDir")      -and $cfg.OutputDir)      { $OutputDir      = [string]$cfg.OutputDir }
        if (-not $PSBoundParameters.ContainsKey("Adapter")        -and $cfg.Adapter)        { $Adapter        = [string]$cfg.Adapter }
        if (-not $PSBoundParameters.ContainsKey("WindowsAdapter") -and $cfg.WindowsAdapter) { $WindowsAdapter = [string]$cfg.WindowsAdapter }
        if (-not $PSBoundParameters.ContainsKey("Duration")       -and $cfg.Duration)       { $Duration       = [int]$cfg.Duration }
        if (-not $PSBoundParameters.ContainsKey("IpWaitSeconds")  -and $cfg.IpWaitSeconds)  { $IpWaitSeconds  = [int]$cfg.IpWaitSeconds }
        if (-not $PSBoundParameters.ContainsKey("Format")         -and $cfg.Format)         { $Format         = [string]$cfg.Format }
        if (-not $PSBoundParameters.ContainsKey("IncludeOwnLldp") -and $null -ne $cfg.IncludeOwnLldp) { $IncludeOwnLldp = [bool]$cfg.IncludeOwnLldp }
        if (-not $PSBoundParameters.ContainsKey("KeepRaw")        -and $null -ne $cfg.KeepRaw)        { $KeepRaw        = [bool]$cfg.KeepRaw }
        if (-not $PSBoundParameters.ContainsKey("NoLiveExcel")    -and $null -ne $cfg.NoLiveExcel)    { $NoLiveExcel    = [bool]$cfg.NoLiveExcel }
    }
    catch {
        Write-Host "  [WARN]     Could not read flookOFF.config.json ($($_.Exception.Message)). Using defaults." -ForegroundColor Yellow
    }
}

if ($Format -notin @("csv","json","xlsx")) {
    throw "Invalid Format '$Format'. Use csv, json, or xlsx."
}

$LIB      = Join-Path $ROOT "lib"
$SESSIONS = Join-Path $ROOT "sessions"
$CAPTURES = Join-Path $ROOT "captures"
$EXPORTS  = if ($OutputDir) { $OutputDir } else { Join-Path $ROOT "exports" }

foreach ($d in @($SESSIONS, $CAPTURES, $EXPORTS)) {
    New-Item -ItemType Directory -Force -Path $d | Out-Null
}

# ---------------------------------------------------------------------------
# Banner
# ---------------------------------------------------------------------------
function Show-Banner {
    $c = "`e[1;36m"  # bold cyan  (same escape airgeddon uses)
    $r = "`e[0m"
    Write-Host "${c}+----------------------------------------------------------------------------+" 
    Write-Host "|                                                                            |"
    Write-Host "|                  __ _             _    _________________                  |"
    Write-Host "|                 / _| |           | |  |  _  |  ___|  ___|                 |"
    Write-Host "|                | |_| | ___   ___ | | _| | | | |_  | |_                   |"
    Write-Host "|                |  _| |/ _ \ / _ \| |/ / | | |  _| |  _|                  |"
    Write-Host "|                | | | | (_) | (_) |   <\ \_/ / |   | |                    |"
    Write-Host "|                |_| |_|\___/ \___/|_|\_\\___/\_|   \_|                    |"
    Write-Host "|                                                                            |"
    Write-Host "|           Network Jack Scanner  |  LLDP / CDP  |  Auto-populate           |"
    Write-Host "|                                                                            |"
    Write-Host "|                                        /|                                  |"
    Write-Host "|                                       / |                                  |"
    Write-Host "|                                      /  |                                  |"
    Write-Host "|                               .----------.                                 |"
    Write-Host "|                               |  _______  |                                |"
    Write-Host "|                               | |       | |                                |"
    Write-Host "|                               | |_______| |                                |"
    Write-Host "|                               |   () ()   |                                |"
    Write-Host "|                               |  ///////  |                                |"
    Write-Host "|                               |  ///////  |                                |"
    Write-Host "|                               |  ///////  |                                |"
    Write-Host "|                               '-----------'                                |"
    Write-Host "|                                                                            |"
    Write-Host "+--------------------------------------------------------------~Jarvy script~+${r}"
    Write-Host ""
}

# ---------------------------------------------------------------------------
# Dependency check
# ---------------------------------------------------------------------------
function Test-Dependencies {
    $ok = $true

    # TShark
    if (-not (Test-Path $TsharkPath)) {
        $cmd = Get-Command tshark.exe -ErrorAction SilentlyContinue
        if ($cmd) {
            $script:TsharkPath = $cmd.Source
            $TsharkPath = $cmd.Source
        } else {
            Write-Host "  [MISSING]  tshark.exe - Install Wireshark (with TShark) or set -TsharkPath" -ForegroundColor Red
            $ok = $false
        }
    }
    if ($ok) {
        try {
            $ver = & $TsharkPath --version 2>&1 | Select-Object -First 1
            Write-Host "  [OK]       TShark - $ver" -ForegroundColor Green
        }
        catch {
            Write-Host "  [MISSING]  Could not run TShark at '$TsharkPath' ($($_.Exception.Message))" -ForegroundColor Red
            $ok = $false
        }
    }

    # Npcap / WinPcap
    $npcap = Get-ItemProperty "HKLM:\SOFTWARE\Npcap" -ErrorAction SilentlyContinue
    $winpcap = Get-ItemProperty "HKLM:\SOFTWARE\WinPcap" -ErrorAction SilentlyContinue
    if ($npcap -or $winpcap) {
        $driver = if ($npcap) { "Npcap $($npcap.Version)" } else { "WinPcap" }
        Write-Host "  [OK]       Packet driver - $driver" -ForegroundColor Green
    } else {
        Write-Host "  [WARN]     Npcap/WinPcap not detected - TShark may still work if installed with Wireshark" -ForegroundColor Yellow
    }

    # Excel (optional - for live auto-populate)
    try {
        $xl = New-Object -ComObject Excel.Application -ErrorAction Stop
        $xl.Quit() | Out-Null
        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($xl) | Out-Null
        Write-Host "  [OK]       Microsoft Excel (live auto-populate available)" -ForegroundColor Green
    } catch {
        Write-Host "  [INFO]     Microsoft Excel not found - live workbook auto-populate will be skipped" -ForegroundColor DarkYellow
    }

    # Admin rights (needed for packet capture)
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if ($isAdmin) {
        Write-Host "  [OK]       Running as Administrator" -ForegroundColor Green
    } else {
        Write-Host "  [WARN]     Not running as Administrator - TShark capture may fail on some adapters" -ForegroundColor Yellow
    }

    Write-Host ""
    return $ok
}

# ---------------------------------------------------------------------------
# Menu helpers
# ---------------------------------------------------------------------------
function Show-Menu {
    Write-Host "  flookOFF Main Menu" -ForegroundColor Cyan
    Write-Host "  ------------------" -ForegroundColor DarkGray
    Write-Host "  [1]  Start scanning session" -ForegroundColor White
    Write-Host "  [2]  Export / re-export last session" -ForegroundColor White
    Write-Host "  [3]  Browse saved sessions" -ForegroundColor White
    Write-Host "  [4]  Show options & current settings" -ForegroundColor White
    Write-Host "  [5]  Help" -ForegroundColor White
    Write-Host "  [q]  Quit" -ForegroundColor White
    Write-Host ""
}

function Show-Settings {
    Write-Host ""
    Write-Host "  Current Settings" -ForegroundColor Cyan
    Write-Host ("  {0,-22} {1}" -f "TSharkPath",     $TsharkPath)
    Write-Host ("  {0,-22} {1}" -f "Adapter",        $Adapter)
    Write-Host ("  {0,-22} {1}" -f "WindowsAdapter", $(if ($WindowsAdapter) { $WindowsAdapter } else { "(auto)" }))
    Write-Host ("  {0,-22} {1}" -f "Duration",       "$Duration sec")
    Write-Host ("  {0,-22} {1}" -f "IpWaitSeconds",  "$IpWaitSeconds sec")
    Write-Host ("  {0,-22} {1}" -f "Format",         $Format)
    Write-Host ("  {0,-22} {1}" -f "IncludeOwnLldp", $IncludeOwnLldp)
    Write-Host ("  {0,-22} {1}" -f "KeepRaw",        $KeepRaw)
    Write-Host ("  {0,-22} {1}" -f "NoLiveExcel",    $NoLiveExcel)
    Write-Host ("  {0,-22} {1}" -f "OutputDir",      $EXPORTS)
    Write-Host ("  {0,-22} {1}" -f "SessionsDir",    $SESSIONS)
    Write-Host ("  {0,-22} {1}" -f "CapturesDir",    $CAPTURES)
    Write-Host ""
    Write-Host "  Pass any of these as parameters to flookOFF to override." -ForegroundColor DarkGray
    Write-Host "  e.g.  flookOFF -Duration 60 -Format xlsx" -ForegroundColor DarkGray
    Write-Host ""
}

function Show-Help {
    Write-Host ""
    Write-Host "  flookOFF - Network Jack Scanner" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  WORKFLOW" -ForegroundColor White
    Write-Host "    1.  Open your tracking spreadsheet in Excel (optional but recommended)."
    Write-Host "    2.  Run flookOFF."
    Write-Host "    3.  Enter Building and Verified By name once at session start."
    Write-Host "    4.  Plug into a jack. Enter Room number and Jack port number."
    Write-Host "    5.  flookOFF captures LLDP/CDP for -Duration seconds, prints the"
    Write-Host "        switch and interface, and writes the row to the session JSON"
    Write-Host "        and to your open Excel sheet simultaneously."
    Write-Host "    6.  After each jack you can export that scan individually to CSV / JSON / XLSX."
    Write-Host "    7.  Type q or quit at any prompt to end the session and export the full set."
    Write-Host ""
    Write-Host "  EXPORT FORMATS  (per-jack or full session)" -ForegroundColor White
    Write-Host "    csv     Comma-separated. Opens directly in Excel."
    Write-Host "    json    Machine-readable. Includes all raw fields."
    Write-Host "    xlsx    Formatted Excel workbook (bold header, frozen row, autofit)."
    Write-Host ""
    Write-Host "  COLUMNS IN OUTPUT" -ForegroundColor White
    Write-Host "    Building, Room, JackPort, Jack, Switch, switchport, VLAN(s),"
    Write-Host "    LinkSpeed, Adapter, IPv4, PrefixLength, SubnetID, Gateway,"
    Write-Host "    DHCPServer, Protocol, MgmtIP, SourceMAC, EvidenceCount,"
    Write-Host "    CandidateCount, ScanTime, VerifiedBy"
    Write-Host ""
    Write-Host "  LIVE EXCEL AUTO-POPULATE" -ForegroundColor White
    Write-Host "    If a workbook is open in Excel with a sheet containing these headers:"
    Write-Host "    Building, Room Number, Jack, Switch, switchport, VLAN(s), verified by"
    Write-Host "    ...flookOFF will fill in matching columns after each scan automatically."
    Write-Host "    The 'any damage/repair?' and 'update description?' columns are left"
    Write-Host "    blank intentionally - those need eyes on the physical jack."
    Write-Host ""
}

function Show-Sessions {
    $files = Get-ChildItem -Path $SESSIONS -Filter "*.json" -ErrorAction SilentlyContinue |
             Sort-Object LastWriteTime -Descending
    if (-not $files) {
        Write-Host "  No saved sessions found in $SESSIONS" -ForegroundColor Yellow
        Write-Host ""
        return
    }
    Write-Host ""
    Write-Host "  Saved Sessions:" -ForegroundColor Cyan
    $i = 1
    foreach ($f in $files) {
        try {
            $data = Get-Content $f.FullName -Raw | ConvertFrom-Json
            $rows = if ($data -is [array]) { $data.Count } else { 1 }
            Write-Host ("  [{0}]  {1}  ({2} rows)  {3}" -f $i, $f.BaseName, $rows, $f.LastWriteTime.ToString("yyyy-MM-dd HH:mm"))
        } catch {
            Write-Host ("  [{0}]  {1}  (unreadable)" -f $i, $f.BaseName) -ForegroundColor Yellow
        }
        $i++
    }
    Write-Host ""

    $choice = Read-Host "  Enter number to export, or Enter to go back"
    if ([string]::IsNullOrWhiteSpace($choice)) { return }
    if ($choice -match '^\d+$' -and [int]$choice -ge 1 -and [int]$choice -le $files.Count) {
        $selected = $files[[int]$choice - 1]
        $rows = Get-Content $selected.FullName -Raw | ConvertFrom-Json
        if ($rows -isnot [array]) { $rows = @($rows) }
        Invoke-SessionExport -Rows $rows -BaseName $selected.BaseName -ExportsDir $EXPORTS
    }
}

# ---------------------------------------------------------------------------
# Load library scripts
# ---------------------------------------------------------------------------
$requiredLibs = @(
    (Join-Path $LIB "network.ps1"),
    (Join-Path $LIB "export.ps1"),
    (Join-Path $LIB "scan_lldp.ps1")
)
foreach ($libFile in $requiredLibs) {
    if (-not (Test-Path $libFile)) {
        throw "Missing required library file: $libFile. Keep the repo folder structure intact."
    }
    . $libFile
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
Show-Banner

Write-Host "  Checking dependencies..." -ForegroundColor Cyan
$depsOk = Test-Dependencies
if (-not $depsOk) {
    Write-Host "  One or more required dependencies are missing. Install them and re-run." -ForegroundColor Red
    exit 1
}

if ($NoMenu) {
    Start-ScanSession -TsharkPath $TsharkPath -Adapter $Adapter -WindowsAdapter $WindowsAdapter `
        -Duration $Duration -IpWaitSeconds $IpWaitSeconds -Format $Format `
        -IncludeOwnLldp:$IncludeOwnLldp -KeepRaw:$KeepRaw -NoLiveExcel:$NoLiveExcel `
        -SessionsDir $SESSIONS -CapturesDir $CAPTURES -ExportsDir $EXPORTS
    exit 0
}

while ($true) {
    Show-Menu
    $choice = Read-Host "  Select"
    Write-Host ""
    switch ($choice.Trim().ToLower()) {
        "1" {
            Start-ScanSession -TsharkPath $TsharkPath -Adapter $Adapter -WindowsAdapter $WindowsAdapter `
                -Duration $Duration -IpWaitSeconds $IpWaitSeconds -Format $Format `
                -IncludeOwnLldp:$IncludeOwnLldp -KeepRaw:$KeepRaw -NoLiveExcel:$NoLiveExcel `
                -SessionsDir $SESSIONS -CapturesDir $CAPTURES -ExportsDir $EXPORTS
        }
        "2" {
            $latest = Get-ChildItem -Path $SESSIONS -Filter "*.json" -ErrorAction SilentlyContinue |
                      Sort-Object LastWriteTime -Descending | Select-Object -First 1
            if ($latest) {
                $rows = Get-Content $latest.FullName -Raw | ConvertFrom-Json
                if ($rows -isnot [array]) { $rows = @($rows) }
                Invoke-SessionExport -Rows $rows -BaseName $latest.BaseName -ExportsDir $EXPORTS
            } else {
                Write-Host "  No sessions found yet." -ForegroundColor Yellow
                Write-Host ""
            }
        }
        "3" { Show-Sessions }
        "4" { Show-Settings }
        "5" { Show-Help }
        { $_ -in @("q","quit","exit","-q") } {
            Write-Host "  Goodbye." -ForegroundColor Cyan
            Write-Host ""
            exit 0
        }
        default {
            Write-Host "  Invalid choice. Enter 1-5 or q." -ForegroundColor Yellow
            Write-Host ""
        }
    }
}
