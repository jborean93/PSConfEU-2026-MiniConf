#!/usr/bin/env pwsh
#Requires -Version 7.6

<#
.SYNOPSIS
One time setup for the demo environment.

.DESCRIPTION
Writes the local, git ignored, files the demos need and prepares prod:

    demo.config.psd1  Prod host and other machine specific values
    state/certs       Demo root CA, Signer and SignerRenewed certs
    state/ssh         Demo only ed25519 key, SSH config with the 'win-prod'
                      alias, pinned known_hosts and the askpass helper

On prod it first sets up SSH: the demo only ed25519 key is added to the
authorized keys (prompting for the password once if key auth isn't working
yet), PowerShell 7 is installed with winget if missing, pwsh becomes the
OpenSSH default shell and the powershell SSH subsystem is added for
PSRemoting. Then the demo root CA is imported into
Cert:\LocalMachine\Root and the public certs are copied to the 'certs' folder.
The WDAC policy is created when Set-ProdWdac Enforced is run.

Everything the setup and demos write on prod is kept under
C:\PSConfEU-MiniConf, delete it to clean up.

.PARAMETER ComputerName
The Windows host used as prod.

.PARAMETER Credential
The admin account on prod. The password is only used for the first SSH
connection, before the demo key is authorized.

.PARAMETER GitHubRepo
The GitHub repo running the release workflow.

.PARAMETER TimeStampServer
RFC 3161 timestamp server used for local signing.

.PARAMETER Force
Recreate the demo certificates and WDAC policy even if they already exist.

.PARAMETER SkipProd
Don't configure the prod host.
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [string]
    $ComputerName,

    [Parameter(Mandatory)]
    [PSCredential]
    [System.Management.Automation.Credential()]
    $Credential,

    [Parameter()]
    [string]
    $GitHubRepo = 'jborean93/PSConfEU-2026-MiniConf',

    [Parameter()]
    [string]
    $TimeStampServer = 'http://timestamp.digicert.com',

    [Parameter()]
    [switch]
    $Force,

    [Parameter()]
    [switch]
    $SkipProd
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Path $PSScriptRoot -Parent
$UserName = $Credential.UserName

# Local config, read by DemoKit on import.
Write-Host 'Writing demo.config.psd1'
@"
@{
    ProdComputerName = '$ComputerName'
    ProdUserName = '$UserName'
    TimeStampServer = '$TimeStampServer'
    GitHubRepo = '$GitHubRepo'
}
"@ | Set-Content -LiteralPath (Join-Path $root 'demo.config.psd1')

Import-Module (Join-Path $root 'DemoKit') -Force

# Demo PKI
$caPath = Get-DemoPath state, certs, CA.pfx
if ($Force -or -not (Test-Path -LiteralPath $caPath)) {
    Write-Host 'Creating demo certificates'

    $caParams = @{
        Subject = 'CN=PSConfEU Demo Root CA'
        NotBefore = [DateTimeOffset]::UtcNow.AddDays(-1)
        NotAfter = [DateTimeOffset]::UtcNow.AddYears(2)
        CertificateAuthority = $true
    }
    $ca = New-DemoCertificate @caParams
    Save-DemoCertificate -Certificate $ca -Name CA

    $subject = 'CN=Jordan Borean (Demo), O=PSConfEU Demo'
    $signer = New-DemoCertificate -Subject $subject -Issuer $ca
    Save-DemoCertificate -Certificate $signer -Name Signer

    $renewed = New-DemoCertificate -Subject $subject -Issuer $ca
    Save-DemoCertificate -Certificate $renewed -Name SignerRenewed
}
else {
    Write-Host 'Demo certificates already exist, use -Force to recreate'
}

if ($SkipProd) {
    return
}

# Prod SSH setup, runs in Windows PowerShell through whatever the current
# default shell is so it works on a fresh OpenSSH install.
$publicKey = (Get-Content -LiteralPath "$(Get-DemoSshKey).pub" -Raw).Trim()

$sshSetup = {
    $ErrorActionPreference = 'Stop'

    # The demos change machine wide settings (LocalMachine cert stores, WDAC),
    # check before touching anything.
    $principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "'$env:USERNAME' is not an administrator on prod, the demos need an admin account"
    }

    # Admins use the shared administrators_authorized_keys file, see the
    # 'Match Group administrators' block in the default sshd_config.
    $keyFile = Join-Path $env:ProgramData 'ssh\administrators_authorized_keys'
    $existing = if (Test-Path -LiteralPath $keyFile) { @(Get-Content -LiteralPath $keyFile) } else { @() }
    if ($existing -notcontains $publicKey) {
        Add-Content -LiteralPath $keyFile -Value $publicKey -Encoding Ascii
        "Added public key to $keyFile"
    }

    # sshd ignores the file unless only Administrators and SYSTEM can access it.
    $null = icacls.exe $keyFile /inheritance:r /grant '*S-1-5-32-544:F' /grant '*S-1-5-18:F'

    $pwshCmd = Get-Command -Name pwsh.exe -CommandType Application -All -ErrorAction Ignore |
        Select-Object -First 1
    if (-not $pwshCmd) {
        if (-not (Get-Command -Name winget.exe -ErrorAction Ignore)) {
            throw "PowerShell 7 not found and winget isn't available to install it"
        }

        'Installing PowerShell 7 with winget'
        $wingetArgs = @(
            'install'
            '--id', 'Microsoft.PowerShell'
            '--exact'
            '--source', 'winget'
            '--scope', 'user'
            '--silent'
            '--accept-package-agreements'
            '--accept-source-agreements'
            '--disable-interactivity'
        )
        winget.exe @wingetArgs
        if ($LASTEXITCODE) {
            throw "winget failed to install PowerShell 7, exit code $LASTEXITCODE"
        }

        # The MSIX app execution alias dir is already on the user's PATH.
        $pwshCmd = Get-Command -Name pwsh.exe -CommandType Application -All -ErrorAction Ignore |
            Select-Object -First 1
        if (-not $pwshCmd) {
            throw 'PowerShell 7 was installed but pwsh.exe could not be found'
        }
    }

    # An MSIX install can only be started through its app execution alias,
    # the package dir under Program Files\WindowsApps isn't accessible to the
    # user. Never point sshd at the package dir.
    $pwshPath = $pwshCmd.Definition
    if ($pwshPath -like "$env:ProgramFiles\WindowsApps\*") {
        $pwshPath = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\pwsh.exe'
        if (-not (Test-Path -LiteralPath $pwshPath)) {
            throw "pwsh resolved to the MSIX package dir '$($pwshCmd.Definition)' but the app execution alias '$pwshPath' doesn't exist"
        }
    }

    $null = New-ItemProperty -Path HKLM:\SOFTWARE\OpenSSH -Name DefaultShell -Value $pwshPath -PropertyType String -Force

    # sshd_config can't handle spaces in the Subsystem path, use the 8.3 short
    # name instead.
    $subsystemPath = $pwshPath
    if ($subsystemPath.Contains(' ')) {
        $subsystemPath = (New-Object -ComObject Scripting.FileSystemObject).GetFile($subsystemPath).ShortPath
        if ($subsystemPath.Contains(' ')) {
            throw "No 8.3 name for '$pwshPath', 8.3 names may be disabled on the volume"
        }
    }
    $subsystem = "Subsystem powershell $($subsystemPath -replace '\\', '/') -sshs -nologo"

    # The line must come before the first Match block. Since OpenSSH 9.5 a
    # Subsystem inside a matching Match block replaces the global ones, which
    # drops sftp (and so scp) for that user. Any existing powershell entry is
    # removed and re-added in the right place, fixing older runs that appended
    # it to the end.
    $sshdConfig = Join-Path $env:ProgramData 'ssh\sshd_config'
    $current = @(Get-Content -LiteralPath $sshdConfig)
    $lines = [System.Collections.Generic.List[string]]@(
        $current | Where-Object { $_ -notmatch '^\s*Subsystem\s+powershell\s' }
    )
    $matchIdx = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\s*Match\s') {
            $matchIdx = $i
            break
        }
    }
    if ($matchIdx -eq -1) {
        $lines.Add($subsystem)
    }
    else {
        $lines.Insert($matchIdx, $subsystem)
    }

    if (($current -join "`n") -ne ($lines -join "`n")) {
        Set-Content -LiteralPath $sshdConfig -Value $lines -Encoding Ascii

        # Restarting sshd doesn't close existing connections like this one.
        Restart-Service -Name sshd
        'Configured the powershell SSH subsystem and restarted sshd'
    }
}

# Pin the host key and write the 'win-prod' alias in state/ssh/config.
Initialize-DemoSshConfig
$sshHost = (Get-DemoConfig).ProdHost

Write-Host "Setting up SSH on '$UserName@$ComputerName'"
# Sent over stdin to avoid the cmd.exe command line limit. Wrapping it in
# '& { ... }' runs it as a single statement and the trailing newline is needed
# for PowerShell to run it. Errors don't set the exit code with -Command - so
# exit explicitly.
$setupScript = @"
& {
    try {
        `$publicKey = '$($publicKey -replace "'", "''")'
        $sshSetup
    }
    catch {
        [Console]::Error.WriteLine("ERROR: `$_")
        exit 1
    }
}

"@

# SSH_ASKPASS supplies the password, it only lives in this process'
# environment for this one call.
$env:SSH_ASKPASS = Get-DemoSshPath AskPass
$env:SSH_ASKPASS_REQUIRE = 'force'
$env:PSCONFEU_SSH_PASSWORD = $Credential.GetNetworkCredential().Password
# Only try password auth so the result clearly says whether the credential
# works, and fail on the first wrong password instead of retrying.
$passwordAuth = @(
    '-o', 'PreferredAuthentications=password'
    '-o', 'PubkeyAuthentication=no'
    '-o', 'NumberOfPasswordPrompts=1'
)
try {
    $setupScript | ssh @passwordAuth $sshHost powershell.exe -NoProfile -NonInteractive -Command -
    $rc = $LASTEXITCODE
}
finally {
    Remove-Item -Path Env:SSH_ASKPASS, Env:SSH_ASKPASS_REQUIRE, Env:PSCONFEU_SSH_PASSWORD -ErrorAction SilentlyContinue
}
if ($rc) {
    throw "SSH setup on prod failed with exit code $rc"
}

# Key auth should work now, wait for sshd if it was restarted.
$sshReady = $false
for ($i = 0; $i -lt 15 -and -not $sshReady; $i++) {
    Start-Sleep -Seconds 2
    try {
        $null = Get-ProdSession
        $sshReady = $true
    }
    catch {
        Reset-ProdSession
    }
}
if (-not $sshReady) {
    throw 'Could not open a PSSession to prod over SSH with key auth'
}

# Prod
Write-Host "Configuring prod host '$UserName@$ComputerName'"
$prodPath = (Get-DemoConfig).ProdPath

Invoke-Prod -ErrorAction Stop {
    param ($ProdPath)

    $null = New-Item -Path "$ProdPath/certs", "$ProdPath/policy" -ItemType Directory -Force

    # An enforced policy trusts the current CA, replacing it would lock us out.
    if (Test-Path -LiteralPath "$ProdPath/policy/enforced.json") {
        throw 'The demo WDAC policy is enforced, run tools/Reset-Demo.ps1 -RemoveWdac first'
    }
} $prodPath
Copy-ToProd -Path (Get-DemoPath state, certs, '*.cer') -Destination 'certs/'

Invoke-Prod -ErrorAction Stop {
    param ($ProdPath)

    $caSubject = 'CN=PSConfEU Demo Root CA'

    # Remove any old demo roots from a previous -Force run.
    Get-ChildItem Cert:\LocalMachine\Root |
        Where-Object Subject -eq $caSubject |
        Remove-Item

    Import-Certificate -FilePath "$ProdPath/certs/CA.cer" -CertStoreLocation Cert:\LocalMachine\Root |
        Select-Object Subject, Thumbprint, NotAfter
} $prodPath
