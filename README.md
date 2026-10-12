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

This writes `demo.config.psd1` with the prod host and user, the other settings
are defaults in `DemoKit/DemoKit.psm1` that the file can override. It creates
the demo certificates and a demo only SSH config in `state/ssh` with a
`win-prod` alias (`ssh -F state/ssh/config win-prod`, the demo shell does this
for you with `ssh win-prod`). On prod it sets up SSH key auth, pwsh as the
default shell and the PowerShell SSH subsystem, and trusts the demo root CA.
Files on prod are kept under `C:\PSConfEU-MiniConf`. `Set-ProdWdac Enforced`
creates and applies the WDAC policy live, `Set-ProdWdac Absent` removes it and
reboots prod.

The CI segment uses `.github/workflows/sign.yml`, triggered by publishing a
`vX.Y.Z` release from the browser during the talk. The repo must be public so
prod can download the release asset. To set up the signing identity add the
Artifact Signing details (needs `Az.Accounts` and `Az.Resources`) after
connecting to the tenant:

```powershell
Connect-AzAccount -Tenant '<tenant id>' -UseDeviceAuthentication

$initParams = @{
    ComputerName = '192.168.64.18'
    Credential = 'vagrant'
    ArtifactSigningAccount = '<account>'
    ArtifactSigningProfile = '<certificate profile>'
}
./tools/Initialize-Demo.ps1 @initParams
```

This creates an Entra app with a federated credential for the workflow's
`signing` environment and gives it the signer role on the certificate profile.
It prints the GitHub environment secrets and `gh` commands needed at the
end. See [Cleanup](#cleanup) to remove it again.

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

## Cleanup

Remove the WDAC policy (reboots prod) and the Entra app, service principal and
role assignment used by the release workflow:

```powershell
Connect-AzAccount -Tenant '<tenant id>' -UseDeviceAuthentication
./tools/Reset-Demo.ps1 -RemoveWdac -RemoveArtifactSigning
```

`-RemoveArtifactSigning` uses the IDs Initialize-Demo saved in
`state/azure.json`, CI signing stops working until `Initialize-Demo.ps1` is
run again with the Artifact Signing details. Everything else on prod lives in
`C:\PSConfEU-MiniConf` and can be deleted.
