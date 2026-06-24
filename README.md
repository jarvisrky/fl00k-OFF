# flookOFF

```
+----------------------------------------------------------------------------+
|                                                                            |
|                  __ _             _    _________________                   |
|                 / _| |           | |  |  _  |  ___|  ___|                 |
|                | |_| | ___   ___ | | _| | | | |_  | |_                   |
|                |  _| |/ _ \ / _ \| |/ / | | |  _| |  _|                  |
|                | | | | (_) | (_) |   <\ \_/ / |   | |                    |
|                |_| |_|\___/ \___/|_|\_\\___/\_|   \_|                    |
|                                                                            |
|           Network Jack Scanner  |  LLDP / CDP  |  Auto-populate           |
|                                                                            |
+--------------------------------------------------------------~Jarvy script~+
```

A PowerShell tool for walking campus network jacks one at a time, capturing
LLDP and CDP advertisements with TShark, and automatically populating a
tracking spreadsheet with switch name, interface, VLAN, IP, and more —
without leaving the terminal.

---

## What it does

1. Detects your wired Ethernet adapter automatically (or shows a picker).
2. Prompts once for **Building** and **Verified By** for the session.
3. For each jack: prompts for **Room** and **Jack port**, then listens for
   LLDP/CDP for a configurable duration.
4. Prints the switch name and interface the jack is wired to — clearly, in green.
5. Captures link speed, DHCP-assigned IP, subnet, gateway, and DHCP server.
6. Appends the row live to your open Excel tracking sheet (if one is open)
   and saves everything to a session JSON file so nothing is ever lost.
7. Lets you export each jack individually (CSV / JSON / XLSX) right after the
   scan, or export the full session at the end.

---

## Requirements

| Requirement | Notes |
|---|---|
| Windows 10 / 11 | PowerShell 5.1+ |
| [Wireshark](https://www.wireshark.org/download.html) | Install with TShark and Npcap |
| Administrator privileges | Required for packet capture on most adapters |
| Microsoft Excel | Optional — only needed for live workbook auto-populate and XLSX export |

---

## Installation

```powershell
# Clone the repo
git clone https://github.com/yourusername/flookOFF.git
cd flookOFF

# Run the installer (creates dirs, copies files, adds flookOFF to your profile)
.\install.ps1

# Reload your profile
. $PROFILE

# Launch
flookOFF
```

By default, files are installed to `C:\Users\<you>\Documents\flookOFF`.
To change the location:

```powershell
.\install.ps1 -InstallPath "D:\Tools\flookOFF"
```

---

## Usage

```
flookOFF [options]
```

| Option | Default | Description |
|---|---|---|
| `-Adapter` | `auto` | TShark capture interface. `auto` detects a connected wired adapter |
| `-WindowsAdapter` | auto | Windows adapter name for IP info, if different from `-Adapter` |
| `-Duration` | `90` | Seconds to listen per jack (LLDP/CDP re-advertise every ~30s) |
| `-IpWaitSeconds` | `25` | Seconds to wait for DHCP before recording the IP |
| `-Format` | `csv` | Default export format (`csv` or `xlsx`) |
| `-IncludeOwnLldp` | off | Include your laptop's own outgoing LLDP frame as a candidate |
| `-KeepRaw` | off | Keep the per-jack TShark TSV field dumps in `captures/` |
| `-NoLiveExcel` | off | Skip auto-filling an open tracking workbook |
| `-NoMenu` | off | Skip the menu and jump straight into scanning |
| `-TsharkPath` | `C:\Program Files\Wireshark\tshark.exe` | Override the TShark path |

### Examples

```powershell
# Standard scan, 60-second capture window, auto-detect adapter
flookOFF -Duration 60

# Build a formatted Excel file at the end of the session
flookOFF -Format xlsx

# Skip the menu and start scanning immediately
flookOFF -NoMenu

# Keep raw TShark field dumps for troubleshooting
flookOFF -KeepRaw

# Backwards-compatible alias still works
flook-OFF
```

---

## Workflow

### 1. Open your tracking spreadsheet in Excel (optional but recommended)

Your sheet needs these column headers somewhere in the first five rows:

```
Building | Room Number | Jack | Switch | switchport | VLAN(s) | verified by
```

Column order doesn't matter — flookOFF matches by header text.
The **any damage/repair?** and **(need to) update description?** columns are
intentionally left blank; those need eyes on the physical jack.

### 2. Run `flookOFF` in an Administrator PowerShell window

The dependency checker runs at startup and warns you about anything missing.

### 3. Enter Building and Verified By once for the session

```
Building name (same for every jack this session): Ozanam Hall
Verified by: david
```

### 4. For each jack: plug in the cable, enter Room and Jack port

```
Room number: 201
Jack port: C45

>> Capturing LLDP/CDP for 90 seconds on Ethernet...

==> Switch     : sw-ozanam-1.campus.edu
==> Interface  : ge-0/0/0
==> VLAN(s)    : PVID:911; VLAN:911 (data)
==> IP / Subnet: 10.11.201.45 / 10.11.200.0/22
==> DHCP Server: 10.11.200.5
==> Link Speed : 1 Gbps
```

### 5. Export the jack individually if you want

```
Export this jack individually? [y/N]: y
  [1] CSV
  [2] JSON
  [3] XLSX
  [s] Skip
```

### 6. Type `q` at any prompt to finish the session

You'll be offered a full-session export (and can pick multiple formats).

---

## Output columns

| Column | Source |
|---|---|
| Building | Session prompt |
| Room | Per-jack prompt |
| JackPort | Per-jack prompt |
| Jack | Combined `Room <n> Jack <p>` |
| Switch | LLDP system name / CDP device ID |
| switchport | LLDP port ID / CDP port ID |
| VLAN(s) | PVID, VLAN Name, MED policy, CDP native/voice |
| LinkSpeed | `Get-NetAdapter` |
| Adapter | Windows adapter name |
| IPv4 | `Get-NetIPAddress` / `Get-NetIPConfiguration` |
| PrefixLength | From IP assignment |
| SubnetID | Calculated from IP + prefix |
| Gateway | `Get-NetRoute` default route |
| DHCPServer | `Win32_NetworkAdapterConfiguration` |
| Protocol | `LLDP` or `CDP` |
| MgmtIP | LLDP management address TLV |
| SourceMAC | Sender MAC from the captured frame |
| EvidenceCount | Number of packets that agreed on this answer |
| CandidateCount | Total distinct LLDP/CDP senders seen |
| ScanTime | ISO 8601 timestamp |
| VerifiedBy | Session prompt |

---

## File structure

```
flookOFF/
├── flookOFF.ps1          # Main launcher: banner, menu, dependency check
├── install.ps1           # One-command installer
├── Microsoft_PowerShell_profile.ps1  # Profile snippet (install.ps1 handles this)
├── LICENSE
├── README.md
├── CHANGELOG.md
├── .gitignore
├── lib/
│   ├── network.ps1       # Adapter detection, IP helpers
│   ├── export.ps1        # CSV / JSON / XLSX export, live Excel auto-populate
│   └── scan_lldp.ps1     # TShark capture + LLDP/CDP parse engine
├── captures/             # Raw .pcapng files (git-ignored)
├── sessions/             # Session JSON files (git-ignored)
├── exports/              # Exported CSV / JSON / XLSX files (git-ignored)
├── example-output/
│   ├── sample_portmap.csv
│   └── sample_session.json
└── .github/
    └── ISSUE_TEMPLATE.md
```

`lldp_to_csv_plus.py` is an optional offline fallback for re-parsing a saved
`.pcapng` on a machine without TShark. The live capture path does not use it.

---

## Troubleshooting

**TShark can't capture packets**
Run PowerShell as Administrator. On some systems, Npcap must be installed in
"WinPcap compatibility mode" — reinstall Npcap with that option ticked.

**No LLDP/CDP found for a jack**
- Some switches are configured to suppress LLDP on access ports. Check the
  switch config.
- Try increasing `-Duration` to 120 seconds. LLDP re-advertises every 30s
  by default, but some vendors use longer intervals.
- Run with `-KeepRaw` and open the `.tsv` in `captures/` to see exactly what
  TShark received.

**Live Excel write fails**
Make sure your spreadsheet is already open and the correct sheet is the active
(visible) one before starting the scan. The script attaches to Excel via COM
automation — it must already be running.

**IP shows as blank or 169.254.x.x**
The DHCP lease hadn't arrived within `-IpWaitSeconds`. Increase the value:
`flookOFF -IpWaitSeconds 40`. The CSV row is still written; you can fill in
the IP manually later.

**"Could not resolve enough TShark fields"**
Your TShark version may be too old or the executable path is wrong. Update
Wireshark, or pass `-TsharkPath` to point to the correct binary.

---

## License

MIT — see [LICENSE](LICENSE).
