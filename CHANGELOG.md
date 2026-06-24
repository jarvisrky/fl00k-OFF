# Changelog

All notable changes to flookOFF are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [1.0.0] - 2025-06-21

Initial public release. Merged and cleaned up from three prior internal
iterations of `scan_lldp.ps1`.

### Added
- Airgeddon-style ASCII banner and startup sequence
- Interactive main menu (scan, export, browse sessions, settings, help)
- Ethernet adapter auto-detection; falls back to interactive picker if
  ambiguous or no cable is plugged in yet
- One-time Building and Verified By prompts per session
- Room number + Jack port prompts per jack (replaces single "Jack label")
- TShark-based LLDP and CDP capture (no third-party Python libs required
  for the live capture path)
- Prominent switch name + interface callout after every scan
- Live Excel auto-populate: attaches to an already-open workbook and
  fills in Building, Room Number, Jack, Switch, switchport, VLAN(s),
  verified by; leaves damage/repair and update-description blank for
  manual review
- Per-jack individual export prompt after each scan (CSV, JSON, or XLSX)
- Full session export at quit time, with option to export in multiple
  formats in one go
- Session JSON written after every jack so no data is lost mid-session
- Browse and re-export any saved session from the main menu
- Dependency checker at startup (TShark, Npcap/WinPcap, Excel, admin rights)
- Modular venv-style layout: `lib/network.ps1`, `lib/export.ps1`,
  `lib/scan_lldp.ps1` dot-sourced by the main launcher
- `install.ps1` one-command setup: creates dirs, copies files, writes the
  `flookOFF` function into your PowerShell profile
- `lldp_to_csv_plus.py` kept as an optional offline fallback for
  re-parsing saved `.pcapng` files on machines without TShark
- DHCPServer column (sourced from Win32_NetworkAdapterConfiguration)
- `-NoLiveExcel`, `-KeepRaw`, `-IncludeOwnLldp`, `-NoMenu` flags
- `flook-OFF` alias preserved for backwards compatibility

### Fixed
- CSV header bug: previous versions exported an empty PSCustomObject row
  as a phantom data row above the real header
- TShark path now falls back to a PATH lookup if the default install path
  does not exist

---

## Pre-release internal versions

| Version | Notes |
|---------|-------|
| v3 (internal) | Added per-jack TSV field dumps, adapter config fallback |
| v2 (internal) | LLDP-MED / TIA TLV parsing, scoring-based best-neighbor selection |
| v1 (internal) | Initial TShark + pcapng proof of concept |
