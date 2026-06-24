<#
    lib/scan_lldp.ps1
    TShark-based LLDP/CDP capture and parse engine.
    Exposes Start-ScanSession, called by flookOFF.ps1.
    Dot-sourced by flookOFF.ps1 (which has already sourced network.ps1 and export.ps1).
#>

# ---------------------------------------------------------------------------
# LLDP/CDP field helpers
# ---------------------------------------------------------------------------
function fl_FirstNonEmpty {
    param([string[]]$Values)
    foreach ($v in $Values) { if (-not [string]::IsNullOrWhiteSpace($v)) { return $v.Trim() } }
    return ""
}

function fl_SplitFieldValues {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return @() }
    return ($Value -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

function fl_BuildVlanList {
    param($Row)
    $items = New-Object System.Collections.Generic.List[string]
    foreach ($v in (fl_SplitFieldValues $Row.lldp_pvid))       { if ($v) { $items.Add("PVID:$v") } }
    $vlanIds   = fl_SplitFieldValues $Row.lldp_vlan_id
    $vlanNames = fl_SplitFieldValues $Row.lldp_vlan_name
    for ($i = 0; $i -lt $vlanIds.Count; $i++) {
        $id   = $vlanIds[$i]
        $name = if ($i -lt $vlanNames.Count) { $vlanNames[$i] } else { "" }
        if ($id -and $name) { $items.Add("VLAN:$id ($name)") }
        elseif ($id)        { $items.Add("VLAN:$id") }
    }
    foreach ($v in (fl_SplitFieldValues $Row.cdp_native_vlan)) { if ($v) { $items.Add("CDP-native:$v") } }
    foreach ($v in (fl_SplitFieldValues $Row.cdp_voice_vlan))  { if ($v) { $items.Add("CDP-voice:$v") } }
    foreach ($v in (fl_SplitFieldValues $Row.med_vlan_id))     { if ($v) { $items.Add("MED-policy:$v") } }
    return (($items | Select-Object -Unique) -join '; ')
}

function fl_GetSupportedFields {
    param([string]$Tshark)
    $set = @{}
    try {
        $lines = & $Tshark -G fields 2>$null
        foreach ($line in $lines) {
            if ($line.StartsWith("F`t")) {
                $parts = $line -split "`t"
                if ($parts.Count -ge 3) { $set[$parts[2]] = $true }
            }
        }
    } catch {}
    return $set
}

function fl_ResolveField {
    param($Supported, [string[]]$Names)
    foreach ($n in $Names) { if ($Supported.ContainsKey($n)) { return $n } }
    return $null
}

function fl_BuildFieldMap {
    param([string]$Tshark)
    $supported = fl_GetSupportedFields -Tshark $Tshark
    $wanted = @(
        @{ Alias="frame_time_epoch"; Names=@("frame.time_epoch") },
        @{ Alias="eth_src";          Names=@("eth.src") },
        @{ Alias="lldp_system_name"; Names=@("lldp.tlv.system.name","lldp.system.name") },
        @{ Alias="lldp_chassis_id";  Names=@("lldp.chassis.id") },
        @{ Alias="lldp_port_id";     Names=@("lldp.port.id") },
        @{ Alias="lldp_port_desc";   Names=@("lldp.port.desc") },
        @{ Alias="lldp_mgmt_ip";     Names=@("lldp.mgn.addr.ip4","lldp.mgmt.addr.ip4") },
        @{ Alias="lldp_pvid";        Names=@("lldp.ieee.802_1.port_vlan.id") },
        @{ Alias="lldp_vlan_id";     Names=@("lldp.ieee.802_1.vlan.id") },
        @{ Alias="lldp_vlan_name";   Names=@("lldp.ieee.802_1.vlan.name") },
        @{ Alias="med_vlan_id";      Names=@("lldp.tia.network_policy.vlan_id") },
        @{ Alias="cdp_deviceid";     Names=@("cdp.deviceid") },
        @{ Alias="cdp_system_name";  Names=@("cdp.system_name") },
        @{ Alias="cdp_portid";       Names=@("cdp.portid") },
        @{ Alias="cdp_native_vlan";  Names=@("cdp.native_vlan") },
        @{ Alias="cdp_voice_vlan";   Names=@("cdp.voice_vlan") }
    )
    $map = New-Object System.Collections.Generic.List[object]
    foreach ($w in $wanted) {
        $field = fl_ResolveField -Supported $supported -Names $w.Names
        if ($field) { $map.Add([PSCustomObject]@{ Alias=$w.Alias; Field=$field }) }
    }
    return $map
}

function fl_GetBestNeighbor {
    param([string]$TsvPath, [string[]]$Headers, [string]$LocalMac, [bool]$IncludeOwn)
    if (-not (Test-Path $TsvPath)) { return $null }
    $rows       = Import-Csv -Path $TsvPath -Delimiter "`t" -Header $Headers
    $candidates = New-Object System.Collections.Generic.List[object]

    foreach ($row in $rows) {
        $src = Convert-MacToColonLower $row.eth_src
        if (-not $IncludeOwn -and $LocalMac -and $src -eq $LocalMac) { continue }

        $switch   = fl_FirstNonEmpty @($row.lldp_system_name,$row.cdp_deviceid,$row.cdp_system_name,$row.lldp_chassis_id)
        $port     = fl_FirstNonEmpty @($row.lldp_port_id,$row.cdp_portid,$row.lldp_port_desc)
        $portDesc = fl_FirstNonEmpty @($row.lldp_port_desc)
        $mgmt     = fl_FirstNonEmpty @($row.lldp_mgmt_ip)
        $vlans    = fl_BuildVlanList $row
        $protocol = if ($row.lldp_system_name -or $row.lldp_port_id -or $row.lldp_chassis_id) { "LLDP" }
                    elseif ($row.cdp_deviceid -or $row.cdp_portid) { "CDP" }
                    else { "" }

        if (-not $switch -and -not $port -and -not $vlans) { continue }

        $score = 0
        if ($switch) { $score += 4 }
        if ($port)   { $score += 4 }
        if ($vlans)  { $score += 3 }
        if ($mgmt)   { $score += 2 }
        if ($portDesc -and $portDesc -ne $port)                              { $score += 1 }
        if ($protocol -eq "LLDP")                                            { $score += 1 }
        if ($port -match '^[0-9a-fA-F]{2}(:[0-9a-fA-F]{2}){5}$')           { $score -= 2 }
        if ($switch -and $switch -notmatch '^[0-9a-fA-F:.-]+$')             { $score += 1 }

        $candidates.Add([PSCustomObject]@{
            Time          = $row.frame_time_epoch
            SourceMAC     = $src
            Protocol      = $protocol
            Switch        = $switch
            Switchport    = $port
            PortDesc      = $portDesc
            VLANs         = $vlans
            MgmtIP        = $mgmt
            Score         = $score
            Key           = "$switch|$port|$vlans"
        })
    }

    if ($candidates.Count -eq 0) { return $null }

    $bestGroup = $candidates |
        Group-Object Key |
        Sort-Object @{Expression={$_.Count};Descending=$true},
                    @{Expression={($_.Group | Measure-Object Score -Maximum).Maximum};Descending=$true} |
        Select-Object -First 1

    $best = $bestGroup.Group |
        Sort-Object @{Expression={$_.Score};Descending=$true},
                    @{Expression={[double]($_.Time -as [double])};Descending=$true} |
        Select-Object -First 1

    $best | Add-Member -NotePropertyName EvidenceCount  -NotePropertyValue $bestGroup.Count    -Force
    $best | Add-Member -NotePropertyName CandidateCount -NotePropertyValue $candidates.Count   -Force
    return $best
}

# ---------------------------------------------------------------------------
# Main scan session entry point
# ---------------------------------------------------------------------------
function Start-ScanSession {
    param(
        [string]$TsharkPath,
        [string]$Adapter,
        [string]$WindowsAdapter,
        [int]$Duration,
        [int]$IpWaitSeconds,
        [string]$Format,
        [bool]$IncludeOwnLldp,
        [bool]$KeepRaw,
        [bool]$NoLiveExcel,
        [string]$SessionsDir,
        [string]$CapturesDir,
        [string]$ExportsDir
    )

    # Resolve adapter
    $Adapter = Resolve-CaptureAdapter -RequestedAdapter $Adapter

    # Build TShark field map
    $fieldMap = fl_BuildFieldMap -Tshark $TsharkPath
    if ($fieldMap.Count -lt 4) {
        Write-Host "  Could not resolve enough TShark fields. Update Wireshark/TShark and retry." -ForegroundColor Red
        return
    }
    $headers = @($fieldMap | ForEach-Object { $_.Alias })

    # Session-level prompts
    Write-Host ""
    $Building   = Read-Host "  Building name (same for every jack this session)"
    $VerifiedBy = Read-Host "  Verified by"

    # Live Excel
    $liveSheet = $null
    if (-not $NoLiveExcel) {
        $liveSheet = Connect-LiveWorkbook
        if ($liveSheet) {
            Write-Host "  Live workbook found: '$($liveSheet.Workbook.Name)' / '$($liveSheet.Worksheet.Name)'" -ForegroundColor Green
        } else {
            Write-Host "  No matching open Excel sheet found - CSV/JSON/XLSX only." -ForegroundColor DarkYellow
        }
    }

    # Session state
    $sessionStamp = (Get-Date).ToString("yyyyMMdd-HHmmss")
    $sessionName  = "$sessionStamp-$($Building -replace '[^a-zA-Z0-9]','_')"
    $sessionJson  = Join-Path $SessionsDir "$sessionName.json"
    $sessionRows  = New-Object System.Collections.Generic.List[object]

    Write-Host ""
    Write-Host "  Adapter : $Adapter  |  Duration : $Duration s  |  IP wait : $IpWaitSeconds s" -ForegroundColor Cyan
    Write-Host "  Session : $sessionName" -ForegroundColor Cyan
    Write-Host "  Type q, quit, -q, or exit at any prompt to end the session." -ForegroundColor Yellow
    Write-Host ""

    # ---------------------------------------------------------------------------
    # Jack loop
    # ---------------------------------------------------------------------------
    while ($true) {
        $room = Read-Host "  Room number"
        if ($room -match '^(-q|q|quit|exit)$') { break }
        if ([string]::IsNullOrWhiteSpace($room)) { Write-Host "  (skipped)" -ForegroundColor DarkGray; continue }

        $jackPort = Read-Host "  Jack port"
        if ($jackPort -match '^(-q|q|quit|exit)$') { break }
        if ([string]::IsNullOrWhiteSpace($jackPort)) { Write-Host "  (skipped)" -ForegroundColor DarkGray; continue }

        $jack     = "Room $room Jack $jackPort"
        $safeJack = ($jack -replace '[^a-zA-Z0-9._-]','_')
        $stamp    = (Get-Date).ToString("yyyyMMdd-HHmmss")
        $pcap     = Join-Path $CapturesDir "$stamp-$safeJack.pcapng"
        $tsv      = Join-Path $CapturesDir "$stamp-$safeJack-fields.tsv"

        Write-Host ""
        Write-Host "  >> Capturing LLDP/CDP for $Duration seconds on $Adapter ..." -ForegroundColor Green

        & $TsharkPath -i $Adapter -a "duration:$Duration" `
            -f "ether proto 0x88cc or ether dst 01:00:0c:cc:cc:cc" `
            -w $pcap 2>$null | Out-Null

        $fieldArgs = @("-r",$pcap,"-Y","lldp or cdp","-T","fields")
        foreach ($m in $fieldMap) { $fieldArgs += @("-e",$m.Field) }
        $fieldArgs += @("-E","header=n","-E","separator=/t","-E","occurrence=a","-E","aggregator=;","-E","quote=n")
        $fieldOutput = & $TsharkPath @fieldArgs 2>&1
        $fieldExit = $LASTEXITCODE
        $fieldOutput | Set-Content -Path $tsv -Encoding UTF8
        if ($fieldExit -ne 0) {
            Write-Host "  [WARN]     TShark field extraction returned exit code $fieldExit. Results may be incomplete." -ForegroundColor Yellow
        }

        $local = Get-LocalAdapterInfo -TsharkAdapterName $Adapter -WinAdapterName $WindowsAdapter -WaitSeconds $IpWaitSeconds
        $best  = fl_GetBestNeighbor  -TsvPath $tsv -Headers $headers -LocalMac $local.MacAddress -IncludeOwn ([bool]$IncludeOwnLldp)

        if ($best) {
            $row = [PSCustomObject]@{
                Building       = $Building
                Room           = $room
                JackPort       = $jackPort
                Jack           = $jack
                Switch         = $best.Switch
                switchport     = $best.Switchport
                'VLAN(s)'      = $best.VLANs
                LinkSpeed      = $local.LinkSpeed
                Adapter        = $local.AdapterName
                IPv4           = $local.IPv4
                PrefixLength   = $local.Prefix
                SubnetID       = $local.SubnetID
                Gateway        = $local.Gateway
                DHCPServer     = $local.DHCPServer
                Protocol       = $best.Protocol
                MgmtIP         = $best.MgmtIP
                SourceMAC      = $best.SourceMAC
                EvidenceCount  = $best.EvidenceCount
                CandidateCount = $best.CandidateCount
                CaptureFile    = $pcap
                ScanTime       = (Get-Date).ToString("s")
                IPSource       = $local.IPSource
                VerifiedBy     = $VerifiedBy
            }
        } else {
            Write-Host "  No usable LLDP/CDP neighbor found. Raw capture saved." -ForegroundColor Red
            $row = [PSCustomObject]@{
                Building       = $Building
                Room           = $room
                JackPort       = $jackPort
                Jack           = $jack
                Switch         = ""
                switchport     = ""
                'VLAN(s)'      = ""
                LinkSpeed      = $local.LinkSpeed
                Adapter        = $local.AdapterName
                IPv4           = $local.IPv4
                PrefixLength   = $local.Prefix
                SubnetID       = $local.SubnetID
                Gateway        = $local.Gateway
                DHCPServer     = $local.DHCPServer
                Protocol       = ""
                MgmtIP         = ""
                SourceMAC      = ""
                EvidenceCount  = "0"
                CandidateCount = "0"
                CaptureFile    = $pcap
                ScanTime       = (Get-Date).ToString("s")
                IPSource       = $local.IPSource
                VerifiedBy     = $VerifiedBy
            }
        }

        $sessionRows.Add($row)

        # Persist session JSON after every jack so nothing is lost mid-session
        $sessionRows | ConvertTo-Json -Depth 5 | Set-Content -Path $sessionJson -Encoding UTF8

        # Live Excel write
        if ($liveSheet) {
            $liveOk = Write-LiveTrackerRow -Live $liveSheet -Building $Building -Room $room `
                -JackLabel $jackPort -Switch $row.Switch -Switchport $row.switchport `
                -Vlans $row.'VLAN(s)' -VerifiedBy $VerifiedBy
            if ($liveOk) { Write-Host "  Tracker sheet updated." -ForegroundColor Green }
        }

        # Switch/interface callout
        Write-Host ""
        if ($best -and $row.switchport) {
            Write-Host ("  ==> Switch     : {0}" -f $row.Switch)     -ForegroundColor Green
            Write-Host ("  ==> Interface  : {0}" -f $row.switchport) -ForegroundColor Green
            Write-Host ("  ==> VLAN(s)    : {0}" -f $row.'VLAN(s)') -ForegroundColor Green
        } else {
            Write-Host "  ==> No switch interface identified for this jack." -ForegroundColor Red
        }
        Write-Host ("  ==> IP / Subnet: {0} / {1}"   -f $row.IPv4, $row.SubnetID)
        Write-Host ("  ==> DHCP Server: {0}"          -f $row.DHCPServer)
        Write-Host ("  ==> Link Speed : {0}"          -f $row.LinkSpeed)
        Write-Host ""

        # Per-jack individual export option
        $exportNow = Read-Host "  Export this jack individually? [y/N]"
        if ($exportNow.Trim().ToLower() -eq "y") {
            Export-SingleRow -Row $row -ExportsDir $ExportsDir
        }

        if (-not $KeepRaw -and $best -and (Test-Path $tsv)) {
            Remove-Item $tsv -Force -ErrorAction SilentlyContinue
        }

        Write-Host ""
    }

    # ---------------------------------------------------------------------------
    # Session end - export full set
    # ---------------------------------------------------------------------------
    Write-Host ""
    Write-Host "  Session complete. $($sessionRows.Count) jack(s) scanned." -ForegroundColor Cyan
    Write-Host "  Session JSON saved to: $sessionJson" -ForegroundColor Cyan
    Write-Host ""

    if ($sessionRows.Count -gt 0) {
        Invoke-SessionExport -Rows $sessionRows.ToArray() -BaseName $sessionName -ExportsDir $ExportsDir -DefaultFormat $Format
    }
}
