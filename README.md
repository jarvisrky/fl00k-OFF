# flookOFF

`flookOFF` is a PowerShell terminal tool for auditing Ethernet wall jacks. It captures LLDP/CDP with TShark, identifies the upstream switch and switchport, collects local IPv4/DHCP/subnet info, and exports the result to CSV, JSON, or XLSX.

It is structured like a small terminal app rather than a pile of scripts: one launcher, a `lib/` folder, a config file, install/activate scripts, and runtime output folders ignored by Git.

## Requirements

- Windows PowerShell 5.1 or PowerShell 7+
- Wireshark/TShark installed
- Npcap recommended for packet capture
- Administrator terminal recommended for live capture
- Microsoft Excel optional, only needed for live workbook auto-populate and formatted `.xlsx` export

## Quick start

From the repo folder:

```powershell
. .\activate.ps1
flookOFF
```

Or run without activation:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\flookOFF.ps1
```

## Install as a terminal command

Run this once from the repo folder:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\install.ps1
```

Close and reopen PowerShell, then run:

```powershell
flookOFF
```

The installer adds a small managed block to your PowerShell profile. It does not move Wireshark, Npcap, or any system drivers.

## Config

Defaults live in `flookOFF.config.json`. CLI parameters override the config.

Example:

```powershell
flookOFF -Duration 60 -Format json -NoLiveExcel
```

Useful parameters:

| Parameter | Purpose |
|---|---|
| `-TsharkPath` | Full path to `tshark.exe` if not found automatically. |
| `-Adapter` | Capture adapter name or `auto`. |
| `-WindowsAdapter` | Windows adapter name used for DHCP/IP lookup when different from TShark adapter. |
| `-Duration` | LLDP/CDP capture duration in seconds. |
| `-IpWaitSeconds` | How long to wait for IPv4/DHCP data after plugging in. |
| `-Format` | Default full-session export: `csv`, `json`, or `xlsx`. |
| `-KeepRaw` | Keep intermediate TSV files. PCAP captures are retained by default. |
| `-NoLiveExcel` | Skip open-workbook auto-populate. |

## GitHub-safe folders

These folders are created at runtime and ignored by `.gitignore`:

- `captures/` for `.pcapng` and field TSV files
- `sessions/` for session JSON
- `exports/` for CSV/JSON/XLSX outputs

Do not commit production captures unless you have approval. LLDP/CDP can expose switch names, ports, VLANs, and management IPs.

## Excel live tracker headers

If an Excel workbook is already open and the active sheet has at least several of these headers in the first five rows, flookOFF will append the scanned data:

- `Building`
- `Room Number`
- `Jack`
- `Switch`
- `switchport`
- `VLAN(s)`
- `verified by`

## Repo layout

```text
flookOFF/
├─ flookOFF.ps1              # Main launcher/menu
├─ flookOFF.cmd              # Double-click/cmd wrapper
├─ activate.ps1              # Session-only terminal activation, venv-style
├─ install.ps1               # Adds flookOFF command to PowerShell profile
├─ uninstall.ps1             # Removes the profile block
├─ flookOFF.config.json      # Defaults
├─ lib/
│  ├─ network.ps1            # Adapter/IP/DHCP helpers
│  ├─ scan_lldp.ps1          # LLDP/CDP capture and parsing
│  └─ export.ps1             # CSV/JSON/XLSX and Excel helpers
├─ docs/
├─ examples/
└─ .github/workflows/
```

## Notes

This tool captures local Layer 2 discovery frames. Use it only on networks where you are authorized to perform jack audits.
