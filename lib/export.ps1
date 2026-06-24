<#
    lib/export.ps1
    Export helpers for flookOFF.
    Handles per-jack individual exports and full-session exports.
    Formats: csv, json, xlsx.
    Dot-sourced by flookOFF.ps1.
#>

# Column order for tabular exports.
$script:EXPORT_FIELDS = @(
    "Building","Room","JackPort","Jack",
    "Switch","switchport","VLAN(s)",
    "LinkSpeed","Adapter","IPv4","PrefixLength","SubnetID","Gateway","DHCPServer",
    "Protocol","MgmtIP","SourceMAC",
    "EvidenceCount","CandidateCount",
    "ScanTime","VerifiedBy"
)

function Get-ExportFormatChoice {
    <#
    Prompt the user to pick an export format.
    Returns "csv", "json", "xlsx", or "" (skip).
    #>
    param([string]$Prompt = "  Export format")
    Write-Host ""
    Write-Host "  Export formats:" -ForegroundColor Cyan
    Write-Host "    [1]  CSV  - opens directly in Excel, no dependencies"
    Write-Host "    [2]  JSON - full data including all raw fields"
    Write-Host "    [3]  XLSX - formatted Excel workbook (bold header, frozen row)"
    Write-Host "    [s]  Skip export"
    Write-Host ""
    $choice = Read-Host $Prompt
    switch ($choice.Trim().ToLower()) {
        "1"     { return "csv"  }
        "csv"   { return "csv"  }
        "2"     { return "json" }
        "json"  { return "json" }
        "3"     { return "xlsx" }
        "xlsx"  { return "xlsx" }
        default { return ""     }
    }
}

function Export-RowsToCsv {
    param([object[]]$Rows, [string]$Path, [switch]$Quiet)
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
    $Rows | Select-Object -Property $script:EXPORT_FIELDS |
        Export-Csv -Path $Path -NoTypeInformation -Encoding UTF8
    if (-not $Quiet) { Write-Host "  CSV  -> $Path" -ForegroundColor Green }
}

function Export-RowsToJson {
    param([object[]]$Rows, [string]$Path)
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
    $Rows | ConvertTo-Json -Depth 5 | Set-Content -Path $Path -Encoding UTF8
    Write-Host "  JSON -> $Path" -ForegroundColor Green
}

function Export-RowsToXlsx {
    param([object[]]$Rows, [string]$Path)

    # Build a temp CSV, then open it in Excel and save as XLSX
    $tmpCsv = [System.IO.Path]::ChangeExtension($Path, ".tmp.csv")
    Export-RowsToCsv -Rows $Rows -Path $tmpCsv -Quiet

    $excel = $null
    try {
        $excel = New-Object -ComObject Excel.Application
        $excel.Visible = $false
        $excel.DisplayAlerts = $false

        $wb = $excel.Workbooks.Open($tmpCsv)
        $ws = $wb.Worksheets.Item(1)

        # Formatting
        $ws.Rows.Item(1).Font.Bold = $true
        $ws.Rows.Item(1).AutoFilter() | Out-Null
        $excel.ActiveWindow.SplitRow = 1
        $excel.ActiveWindow.FreezePanes = $true
        $ws.UsedRange.Columns.AutoFit() | Out-Null

        if (Test-Path $Path) { Remove-Item $Path -Force -ErrorAction SilentlyContinue }
        $wb.SaveAs($Path, 51)   # 51 = xlOpenXMLWorkbook
        $wb.Close($false)

        Write-Host "  XLSX -> $Path" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "  Could not build XLSX ($($_.Exception.Message)). CSV is still available." -ForegroundColor Yellow
        return $false
    }
    finally {
        if ($excel) {
            $excel.Quit() | Out-Null
            [System.Runtime.InteropServices.Marshal]::ReleaseComObject($excel) | Out-Null
            [GC]::Collect()
            [GC]::WaitForPendingFinalizers()
        }
        if (Test-Path $tmpCsv) { Remove-Item $tmpCsv -Force -ErrorAction SilentlyContinue }
    }
}

function Export-SingleRow {
    <#
    Export one jack's scan result to an individual file.
    Called interactively after each jack scan.
    #>
    param(
        [object]$Row,
        [string]$ExportsDir
    )

    $fmt = Get-ExportFormatChoice -Prompt "  Format for this jack's export (or s to skip)"
    if (-not $fmt) { return }

    $stamp   = (Get-Date).ToString("yyyyMMdd-HHmmss")
    $safeTag = ($Row.Jack -replace '[^a-zA-Z0-9._-]','_')
    $base    = "$stamp-$safeTag"
    $outPath = Join-Path $ExportsDir "$base.$fmt"

    switch ($fmt) {
        "csv"  { Export-RowsToCsv  -Rows @($Row) -Path $outPath }
        "json" { Export-RowsToJson -Rows @($Row) -Path $outPath }
        "xlsx" { Export-RowsToXlsx -Rows @($Row) -Path $outPath }
    }
}

function Invoke-SessionExport {
    <#
    Export all rows from a completed (or running) session.
    Called from the menu and at session end.
    Can be called multiple times for the same session (different formats).
    #>
    param(
        [object[]]$Rows,
        [string]$BaseName,
        [string]$ExportsDir,
        [ValidateSet("","csv","json","xlsx")]
        [string]$DefaultFormat = ""
    )

    if (-not $Rows -or $Rows.Count -eq 0) {
        Write-Host "  No rows to export." -ForegroundColor Yellow
        Write-Host ""
        return
    }

    function Export-SessionFormat {
        param([string]$Fmt)
        $stamp   = (Get-Date).ToString("yyyyMMdd-HHmmss")
        $outPath = Join-Path $ExportsDir "$BaseName-$stamp.$Fmt"
        switch ($Fmt) {
            "csv"  { Export-RowsToCsv  -Rows $Rows -Path $outPath }
            "json" { Export-RowsToJson -Rows $Rows -Path $outPath }
            "xlsx" { Export-RowsToXlsx -Rows $Rows -Path $outPath }
        }
    }

    Write-Host ""
    Write-Host "  Session has $($Rows.Count) row(s)." -ForegroundColor Cyan

    if ($DefaultFormat) {
        Export-SessionFormat -Fmt $DefaultFormat
        $again = Read-Host "  Export in another format too? [y/N]"
        if ($again.Trim().ToLower() -ne "y") { Write-Host ""; return }
    }

    $keepAsking = $true
    while ($keepAsking) {
        $fmt = Get-ExportFormatChoice -Prompt "  Format (or s to finish)"
        if (-not $fmt) { $keepAsking = $false; break }

        Export-SessionFormat -Fmt $fmt

        $again = Read-Host "  Export in another format too? [y/N]"
        if ($again.Trim().ToLower() -ne "y") { $keepAsking = $false }
    }
    Write-Host ""
}

# ---------------------------------------------------------------------------
# Live Excel auto-populate (moved here from scan_lldp.ps1)
# ---------------------------------------------------------------------------
function Connect-LiveWorkbook {
    <#
    Attaches to an already-running Excel instance (never launches a new one)
    and checks whether the currently active sheet has the tracker headers.
    Returns $null if Excel isn't running or the sheet doesn't match.
    #>
    $neededHeaders = @("building","room number","jack","switch","switchport","vlan(s)")
    $excelApp = $null
    try   { $excelApp = [System.Runtime.InteropServices.Marshal]::GetActiveObject("Excel.Application") }
    catch { return $null }
    if (-not $excelApp) { return $null }

    $ws = $null
    try   { $ws = $excelApp.ActiveSheet }
    catch { return $null }
    if (-not $ws) { return $null }

    $headerRow = $null
    $colMap    = @{}
    for ($r = 1; $r -le 5; $r++) {
        $map = @{}
        $usedCols = 30
        try { if ($ws.UsedRange.Columns.Count -gt 0) { $usedCols = $ws.UsedRange.Columns.Count } } catch {}
        for ($c = 1; $c -le $usedCols; $c++) {
            $val = $ws.Cells.Item($r,$c).Text
            if (-not [string]::IsNullOrWhiteSpace($val)) { $map[$val.Trim().ToLower()] = $c }
        }
        $hits = 0
        foreach ($h in $neededHeaders) { if ($map.ContainsKey($h)) { $hits++ } }
        if ($hits -ge 4) { $headerRow = $r; $colMap = $map; break }
    }
    if (-not $headerRow) { return $null }

    [PSCustomObject]@{
        Workbook  = $excelApp.ActiveWorkbook
        Worksheet = $ws
        HeaderRow = $headerRow
        Columns   = $colMap
    }
}

function Write-LiveTrackerRow {
    param(
        $Live,
        [string]$Building,
        [string]$Room,
        [string]$JackLabel,
        [string]$Switch,
        [string]$Switchport,
        [string]$Vlans,
        [string]$VerifiedBy
    )
    if (-not $Live) { return $false }
    try {
        $ws      = $Live.Worksheet
        $roomCol = $Live.Columns["room number"]
        if (-not $roomCol) { return $false }

        $row = $Live.HeaderRow + 1
        while (-not [string]::IsNullOrWhiteSpace($ws.Cells.Item($row,$roomCol).Text)) { $row++ }

        $fields = @{
            "building"    = $Building
            "room number" = $Room
            "jack"        = $JackLabel
            "switch"      = $Switch
            "switchport"  = $Switchport
            "vlan(s)"     = $Vlans
            "verified by" = $VerifiedBy
        }
        foreach ($key in $fields.Keys) {
            if ($Live.Columns.ContainsKey($key)) {
                $ws.Cells.Item($row,$Live.Columns[$key]).Value2 = $fields[$key]
            }
        }
        # "any damage/repair?" and "(need to) update description?" intentionally left blank.
        return $true
    }
    catch {
        Write-Host "  Could not write to the open workbook ($($_.Exception.Message))." -ForegroundColor Yellow
        return $false
    }
}
