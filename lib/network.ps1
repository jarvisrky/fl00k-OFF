<#
    lib/network.ps1
    Network adapter detection and local IP info helpers.
    Dot-sourced by flookOFF.ps1 and scan_lldp.ps1.
#>

function Resolve-CaptureAdapter {
    param([string]$RequestedAdapter)

    if (-not [string]::IsNullOrWhiteSpace($RequestedAdapter) -and $RequestedAdapter -ne "auto") {
        return $RequestedAdapter
    }

    $wired = @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object {
        $_.Status -eq "Up" -and $_.HardwareInterface -eq $true -and
        ($_.Name -like "*Ethernet*" -or $_.InterfaceDescription -like "*Ethernet*" -or $_.NdisPhysicalMedium -eq 14) -and
        $_.InterfaceDescription -notlike "*Virtual*" -and
        $_.InterfaceDescription -notlike "*VPN*" -and
        $_.InterfaceDescription -notlike "*Bluetooth*"
    })

    if ($wired.Count -eq 1) {
        Write-Host "  Auto-detected wired adapter: $($wired[0].Name) ($($wired[0].InterfaceDescription))" -ForegroundColor Green
        return $wired[0].Name
    }

    if ($wired.Count -gt 1) {
        Write-Host ""
        Write-Host "  Multiple wired adapters are up - pick one:" -ForegroundColor Yellow
        for ($i = 0; $i -lt $wired.Count; $i++) {
            Write-Host ("    [{0}] {1,-22} {2}" -f ($i+1), $wired[$i].Name, $wired[$i].InterfaceDescription) -ForegroundColor Gray
        }
        $choice = Read-Host "  Adapter number (or type the adapter name)"
        if ($choice -match '^\d+$' -and [int]$choice -ge 1 -and [int]$choice -le $wired.Count) {
            return $wired[[int]$choice - 1].Name
        }
        return $choice
    }

    # No wired adapter up yet - show everything
    $all = @(Get-NetAdapter -ErrorAction SilentlyContinue |
             Sort-Object @{Expression={if ($_.Status -eq "Up"){0}else{1}}})
    Write-Host ""
    Write-Host "  No wired Ethernet adapter detected as connected. Available:" -ForegroundColor Yellow
    for ($i = 0; $i -lt $all.Count; $i++) {
        Write-Host ("    [{0}] {1,-22} {2,-8} {3}" -f ($i+1), $all[$i].Name, $all[$i].Status, $all[$i].InterfaceDescription) -ForegroundColor Gray
    }
    Write-Host ""
    $choice = Read-Host "  Plug in your cable, press Enter, then enter an adapter number (or name)"
    if ([string]::IsNullOrWhiteSpace($choice)) {
        $retry = @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object {
            $_.Status -eq "Up" -and $_.HardwareInterface -eq $true -and
            ($_.Name -like "*Ethernet*" -or $_.InterfaceDescription -like "*Ethernet*" -or $_.NdisPhysicalMedium -eq 14)
        })
        if ($retry.Count -eq 1) {
            Write-Host "  Auto-detected: $($retry[0].Name) ($($retry[0].InterfaceDescription))" -ForegroundColor Green
            return $retry[0].Name
        }
        $choice = Read-Host "  Adapter number (or name)"
    }
    if ($choice -match '^\d+$' -and [int]$choice -ge 1 -and [int]$choice -le $all.Count) {
        return $all[[int]$choice - 1].Name
    }
    return $choice
}

function Convert-MacToColonLower {
    param([string]$Mac)
    if ([string]::IsNullOrWhiteSpace($Mac)) { return "" }
    $clean = ($Mac -replace '[-:\.]','').ToLower()
    if ($clean.Length -ne 12) { return $Mac.ToLower() }
    return (($clean -split '(.{2})' | Where-Object { $_ }) -join ':')
}

function Get-SubnetId {
    param([string]$IpAddress, [int]$PrefixLength)
    if ([string]::IsNullOrWhiteSpace($IpAddress) -or $PrefixLength -lt 0 -or $PrefixLength -gt 32) { return "" }
    $ipBytes = [System.Net.IPAddress]::Parse($IpAddress).GetAddressBytes()
    [Array]::Reverse($ipBytes)
    $ipInt = [BitConverter]::ToUInt32($ipBytes,0)
    if ($PrefixLength -eq 0) { $maskInt = [uint32]0 }
    else { $maskInt = ([uint32]::MaxValue -shl (32 - $PrefixLength)) }
    $networkInt = $ipInt -band $maskInt
    $networkBytes = [BitConverter]::GetBytes([uint32]$networkInt)
    [Array]::Reverse($networkBytes)
    return ([System.Net.IPAddress]::new($networkBytes)).ToString() + "/" + $PrefixLength
}

function Get-LocalAdapterInfo {
    param(
        [string]$TsharkAdapterName,
        [string]$WinAdapterName,
        [int]$WaitSeconds = 20
    )

    $adapterObj = $null

    if (-not [string]::IsNullOrWhiteSpace($WinAdapterName)) {
        $adapterObj = Get-NetAdapter -Name $WinAdapterName -ErrorAction SilentlyContinue
    }
    if (-not $adapterObj -and $TsharkAdapterName -notmatch '^\d+$') {
        $adapterObj = Get-NetAdapter -Name $TsharkAdapterName -ErrorAction SilentlyContinue
    }
    if (-not $adapterObj -and $TsharkAdapterName -notmatch '^\d+$') {
        $adapterObj = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object {
            $_.Status -eq "Up" -and (
                $_.Name -like "*$TsharkAdapterName*" -or
                $_.InterfaceDescription -like "*$TsharkAdapterName*"
            )
        } | Select-Object -First 1
    }
    if (-not $adapterObj) {
        $adapterObj = Get-NetAdapter -ErrorAction SilentlyContinue |
            Where-Object { $_.Status -eq "Up" -and $_.HardwareInterface -eq $true } |
            Sort-Object @{Expression={if ($_.Name -like "*Ethernet*" -or $_.NdisPhysicalMedium -eq 14){0}else{1}}} |
            Select-Object -First 1
    }
    if (-not $adapterObj) {
        $adapterObj = Get-NetAdapter -ErrorAction SilentlyContinue |
            Where-Object { $_.Status -eq "Up" } | Select-Object -First 1
    }

    $ipv4 = ""; $prefix = ""; $gateway = ""; $subnet = ""; $ipSource = ""; $dhcpServer = ""

    if ($adapterObj) {
        $deadline = (Get-Date).AddSeconds($WaitSeconds)
        do {
            $ipObj = Get-NetIPAddress -AddressFamily IPv4 -InterfaceIndex $adapterObj.ifIndex -ErrorAction SilentlyContinue |
                Where-Object { $_.IPAddress -ne "127.0.0.1" -and $_.IPAddress -notlike "169.254.*" -and $_.AddressState -ne "Deprecated" } |
                Sort-Object @{Expression={if ($_.AddressState -eq "Preferred"){0}else{1}}},PrefixOrigin |
                Select-Object -First 1
            if ($ipObj) {
                $ipv4   = $ipObj.IPAddress
                $prefix = [string]$ipObj.PrefixLength
                $subnet = Get-SubnetId -IpAddress $ipv4 -PrefixLength ([int]$ipObj.PrefixLength)
                $ipSource = "Get-NetIPAddress"
                break
            }
            Start-Sleep -Seconds 2
        } while ((Get-Date) -lt $deadline)

        if (-not $ipv4) {
            $ipConfig = Get-NetIPConfiguration -InterfaceIndex $adapterObj.ifIndex -ErrorAction SilentlyContinue
            if ($ipConfig -and $ipConfig.IPv4Address) {
                $ipv4Obj = $ipConfig.IPv4Address |
                    Where-Object { $_.IPAddress -notlike '169.254.*' -and $_.IPAddress -ne '127.0.0.1' } |
                    Select-Object -First 1
                if ($ipv4Obj) {
                    $ipv4   = $ipv4Obj.IPAddress
                    $prefix = [string]$ipv4Obj.PrefixLength
                    $subnet = Get-SubnetId -IpAddress $ipv4 -PrefixLength ([int]$ipv4Obj.PrefixLength)
                    $ipSource = "Get-NetIPConfiguration"
                }
            }
        }

        $route = Get-NetRoute -InterfaceIndex $adapterObj.ifIndex -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue |
            Sort-Object RouteMetric | Select-Object -First 1
        if ($route) { $gateway = $route.NextHop }

        $cimCfg = Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration -ErrorAction SilentlyContinue |
            Where-Object { $_.InterfaceIndex -eq $adapterObj.ifIndex } | Select-Object -First 1
        if ($cimCfg -and $cimCfg.DHCPEnabled -and $cimCfg.DHCPServer) {
            $dhcpServer = $cimCfg.DHCPServer
        }
    }

    [PSCustomObject]@{
        AdapterName = if ($adapterObj) { $adapterObj.Name } else { $TsharkAdapterName }
        LinkSpeed   = if ($adapterObj) { $adapterObj.LinkSpeed } else { "" }
        MacAddress  = if ($adapterObj) { Convert-MacToColonLower $adapterObj.MacAddress } else { "" }
        IPv4        = $ipv4
        Prefix      = $prefix
        SubnetID    = $subnet
        Gateway     = $gateway
        DHCPServer  = $dhcpServer
        IPSource    = $ipSource
    }
}
