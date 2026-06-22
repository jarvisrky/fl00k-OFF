# Code review notes

## Biggest issues found

1. **Repo structure mismatch**
   - `flookOFF.ps1` dot-sources `lib\network.ps1`, `lib\export.ps1`, and `lib\scan_lldp.ps1`.
   - The uploaded files were flat, so a fresh clone/copy would fail unless the `lib/` folder is created.
   - Fixed by moving helper scripts into `lib/`.

2. **`-Format json` was supported in export menus but blocked by the launcher**
   - Export code supports CSV, JSON, and XLSX.
   - Main launcher only allowed `csv` and `xlsx`.
   - Fixed by changing `ValidateSet` to `csv`, `json`, `xlsx`.

3. **Main script changed execution policy during runtime**
   - `Set-ExecutionPolicy -Scope Process Bypass -Force` works, but it is better handled by the install/cmd launcher instead of the main code.
   - Fixed by removing it from `flookOFF.ps1` and using bypass only in wrappers/install instructions.

4. **Profile wrapper could go stale**
   - The old profile copied every parameter into a function.
   - If the main script parameters change, the profile function must also be edited.
   - Fixed by using `@args` in the install-generated profile block.

5. **Runtime output should not go to GitHub**
   - Captures, sessions, and exports can include sensitive network data.
   - Added `.gitignore` for `captures/`, `sessions/`, `exports/`, `*.pcap`, and `*.pcapng`.

6. **No venv-style terminal activation existed**
   - Added `activate.ps1`, which sets `FLOOKOFF_HOME`, defines `flookOFF`, adds the `flook-OFF` alias, and marks the prompt with `(flookOFF)`.

## Good parts already present

- Good split between launcher, network helpers, scan engine, and export helpers.
- Session JSON is saved after each jack, which protects against losing data mid-audit.
- LLDP/CDP field detection is dynamic, so it should handle some Wireshark/TShark field-name differences.
- Excel live update is optional and does not block CSV/JSON/XLSX export.
- DHCP server, subnet, gateway, link speed, and adapter are captured in the output row.

## Suggested next improvements

- Add a `-NoPrompt` mode later if you want fully non-interactive scans.
- Add a TShark adapter mapping helper if Windows adapter names ever fail with `tshark -i`.
- Add Pester tests once the functions settle.
- Consider removing or auto-pruning old `.pcapng` captures if storage grows too quickly.
