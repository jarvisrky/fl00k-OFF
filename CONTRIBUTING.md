# Contributing

1. Keep runtime output out of Git: do not commit `captures/`, `sessions/`, or `exports/`.
2. Run PowerShell linting before opening a pull request:

```powershell
Install-Module PSScriptAnalyzer -Scope CurrentUser
Invoke-ScriptAnalyzer -Path . -Recurse
```

3. Test with a short capture first:

```powershell
. .\activate.ps1
flookOFF -Duration 15 -NoLiveExcel
```
