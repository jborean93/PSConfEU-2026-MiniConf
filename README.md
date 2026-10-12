# Sign of the Times - PowerShell and Authenticode

Demos for my PSConfEU 2026 MiniConf talk. Everything runs in a terminal: a
`pwsh` shell on Linux with a Windows host over SSH acting as prod.

## Requirements

* Local: PowerShell 7.6+, `PwshSpectreConsole`, `OpenAuthenticode`
* Prod: Windows with the OpenSSH server installed and an admin account,
  PowerShell 7 is installed with winget if missing

## Setup

```powershell
./tools/Initialize-Demo.ps1 -ComputerName 192.168.64.18 -Credential vagrant
```

This writes the local config, creates the demo certificates and a demo only SSH
config in `state/ssh` with a `win-prod` alias (`ssh -F state/ssh/config
win-prod`, the demo shell does this for you with `ssh win-prod`). On prod it
sets up SSH key auth, pwsh as the default shell and the PowerShell SSH
subsystem, and trusts the demo root CA. Files on prod are kept under
`C:\PSConfEU-MiniConf`. `Set-ProdWdac Enforced` creates and applies the WDAC
policy live, `Set-ProdWdac Absent` removes it and reboots prod.

The CI segment uses `.github/workflows/sign.yml`, triggered by publishing a
`vX.Y.Z` release from the browser during the talk. It needs a GitHub `signing`
environment with the `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AAS_ACCOUNT`,
`AAS_PROFILE` and `AAS_ENDPOINT` variables for Artifact Signing over OIDC. The
repo must be public so prod can download the release asset.

## Running

```bash
./tools/Reset-Demo.ps1 -RemoveWdac   # before every run
pwsh -NoExit -File ./Start-Talk.ps1  # optionally add -Stop <segment>
```

`F9` inserts the next step into the prompt, `F8` the previous one, and `Enter`
runs it. `Get-DemoStep` lists the steps and `Set-DemoStep -Segment 05-` jumps
ahead.

The steps live in `segments/`, one `#region` per step with `# NOTE:` lines as
speaker notes.
