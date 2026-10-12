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

When -ArtifactSigningAccount is set it also sets up the CI signing identity in
Azure: a temporary Entra app and service principal for the demo, a federated
credential trusting the GitHub OIDC token of the release workflow's 'signing'
environment, and the certificate profile signer role on the Artifact Signing
certificate profile. The details are saved in state/azure.json so
Reset-Demo.ps1 -RemoveArtifactSigning can delete it again. The GitHub
environment settings needed by the workflow are printed at the end.

The Azure session isn't created by this script, connect first with
Connect-AzAccount (e.g. -UseDeviceAuthentication) to the tenant holding the
Artifact Signing account. All subscriptions available to that session are
searched for the account.

.PARAMETER ComputerName
The Windows host used as prod.

.PARAMETER Credential
The admin account on prod. The password is only used for the first SSH
connection, before the demo key is authorized.

.PARAMETER GitHubRepo
The GitHub repo running the release workflow.

.PARAMETER TimeStampServer
RFC 3161 timestamp server used for local signing.

.PARAMETER ArtifactSigningAccount
The Artifact Signing account name, the subscription, resource group, and
tenant are found automatically.

.PARAMETER ArtifactSigningProfile
The certificate profile in the account that the workflow signs with.

.PARAMETER Force
Recreate the demo certificates even if they already exist.

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
    [string]
    $ArtifactSigningAccount,

    [Parameter()]
    [string]
    $ArtifactSigningProfile,

    [Parameter()]
    [switch]
    $Force,

    [Parameter()]
    [switch]
    $SkipProd
)

$ErrorActionPreference = 'Stop'

if ([bool]$ArtifactSigningAccount -ne [bool]$ArtifactSigningProfile) {
    throw '-ArtifactSigningAccount and -ArtifactSigningProfile must be set together'
}

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

# Artifact Signing identity for the release workflow
$githubEnvironment = $null
if ($ArtifactSigningAccount) {
    foreach ($module in 'Az.Accounts', 'Az.Resources') {
        if (-not (Get-Module -Name $module -ListAvailable)) {
            throw "The $module module is needed for the Artifact Signing setup: Install-PSResource -Name Az.Accounts, Az.Resources"
        }
    }

    if (-not (Get-AzContext)) {
        throw 'No Azure session, run Connect-AzAccount (e.g. -UseDeviceAuthentication) first'
    }

    # Find the account in whichever subscription it lives in. Listing by type
    # and filtering locally avoids -ExpandProperties, which needs Get-AzResource
    # to work out an API version for the provider and fails quietly when it
    # can't.
    $resourceType = 'Microsoft.CodeSigning/codeSigningAccounts'
    $account = $null
    $searched = [System.Collections.Generic.List[string]]::new()
    foreach ($subscription in Get-AzSubscription) {
        $searched.Add("$($subscription.Name) ($($subscription.Id))")
        $null = Set-AzContext -Subscription $subscription.Id -Tenant $subscription.TenantId
        $account = Get-AzResource -ResourceType $resourceType |
            Where-Object Name -EQ $ArtifactSigningAccount |
            Select-Object -First 1
        if ($account) {
            $tenantId = $subscription.TenantId
            break
        }
    }
    if (-not $account) {
        throw "Artifact Signing account '$ArtifactSigningAccount' not found, searched: $($searched -join ', ')"
    }

    # Read the account and profile through ARM with an API version the
    # provider advertises, preferring the newest stable one over previews.
    $apiVersions = (Get-AzResourceProvider -ProviderNamespace Microsoft.CodeSigning).ResourceTypes |
        Where-Object ResourceTypeName -EQ 'codeSigningAccounts' |
        ForEach-Object ApiVersions |
        Sort-Object -Descending
    $apiVersion = $apiVersions | Where-Object { $_ -notlike '*-preview' } | Select-Object -First 1
    if (-not $apiVersion) {
        $apiVersion = $apiVersions | Select-Object -First 1
    }
    $getArm = {
        param ($ResourceId)
        $response = Invoke-AzRestMethod -Method GET -Path "$($ResourceId)?api-version=$apiVersion"
        if ($response.StatusCode -ne 200) {
            throw "GET $ResourceId failed with $($response.StatusCode): $($response.Content)"
        }
        $response.Content | ConvertFrom-Json
    }

    $endpoint = (& $getArm $account.ResourceId).properties.accountUri
    $profileId = "$($account.ResourceId)/certificateProfiles/$ArtifactSigningProfile"
    $null = & $getArm $profileId

    # The job runs in the 'signing' environment so the OIDC subject is the
    # environment, not the tag. Uses GitHub's immutable format with the owner
    # and repo IDs.
    $repo = Invoke-RestMethod -Uri "https://api.github.com/repos/$GitHubRepo"
    $subject = "repo:$($repo.owner.login)@$($repo.owner.id)/$($repo.name)@$($repo.id):environment:signing"

    $role = 'Artifact Signing Certificate Profile Signer', 'Trusted Signing Certificate Profile Signer' |
        ForEach-Object { Get-AzRoleDefinition -Name $_ -ErrorAction SilentlyContinue } |
        Select-Object -First 1
    if (-not $role) {
        throw 'Could not find the Artifact Signing Certificate Profile Signer role definition'
    }

    # Reuse the app from a previous run if it still exists.
    $azureStatePath = Get-DemoPath state, azure.json
    $app = $null
    if (Test-Path -LiteralPath $azureStatePath) {
        $azureState = Get-Content -LiteralPath $azureStatePath -Raw | ConvertFrom-Json
        $app = Get-AzADApplication -ObjectId $azureState.AppObjectId -ErrorAction SilentlyContinue
    }
    if (-not $app) {
        Write-Host 'Creating the Entra app and service principal'
        $app = New-AzADApplication -DisplayName 'PSConfEU-MiniConf-Signing'
    }
    $sp = Get-AzADServicePrincipal -ApplicationId $app.AppId -ErrorAction SilentlyContinue
    if (-not $sp) {
        $sp = New-AzADServicePrincipal -ApplicationId $app.AppId
    }

    $existingCred = Get-AzADAppFederatedCredential -ApplicationObjectId $app.Id |
        Where-Object Subject -EQ $subject
    if (-not $existingCred) {
        Write-Host "Adding federated credential for '$subject'"
        $credParams = @{
            ApplicationObjectId = $app.Id
            Name = 'github-release-signing'
            Issuer = 'https://token.actions.githubusercontent.com'
            Subject = $subject
            Audience = 'api://AzureADTokenExchange'
        }
        $null = New-AzADAppFederatedCredential @credParams
    }

    $assignmentParams = @{
        ObjectId = $sp.Id
        RoleDefinitionId = $role.Id
        Scope = $profileId
    }
    if (-not (Get-AzRoleAssignment @assignmentParams -ErrorAction SilentlyContinue)) {
        Write-Host "Assigning '$($role.Name)' on the certificate profile"
        # ObjectType skips the directory lookup that can fail while the new
        # service principal is still replicating.
        $null = New-AzRoleAssignment @assignmentParams -ObjectType ServicePrincipal
    }

    [PSCustomObject]@{
        TenantId = $tenantId
        AppObjectId = $app.Id
        AppId = $app.AppId
        ServicePrincipalId = $sp.Id
        RoleDefinitionId = $role.Id
        Scope = $profileId
    } | ConvertTo-Json | Set-Content -LiteralPath $azureStatePath

    $githubEnvironment = [ordered]@{
        AZURE_CLIENT_ID = $app.AppId
        AZURE_TENANT_ID = $tenantId
        AAS_ACCOUNT = $ArtifactSigningAccount
        AAS_PROFILE = $ArtifactSigningProfile
        AAS_ENDPOINT = $endpoint
    }
}

# Printed at the very end so it isn't lost in the prod setup output.
$showGitHubSetup = {
    if (-not $githubEnvironment) {
        return
    }

    Write-Host ''
    Write-Host "GitHub setup for '$GitHubRepo'"
    Write-Host 'These go in the "signing" environment as secrets, the workflow reads'
    Write-Host 'secrets.* so the values are masked in the logs.'
    Write-Host ''
    $githubEnvironment.GetEnumerator() | ForEach-Object {
        Write-Host ('    {0,-16} {1}' -f $_.Key, $_.Value)
    }
    Write-Host ''
    Write-Host 'Create the environment, limited to v* release tags, and set them with gh:'
    Write-Host ''
    Write-Host "    gh api -X PUT repos/$GitHubRepo/environments/signing --input - <<< '{`"deployment_branch_policy`": {`"protected_branches`": false, `"custom_branch_policies`": true}}'"
    Write-Host "    gh api -X POST repos/$GitHubRepo/environments/signing/deployment-branch-policies -f name='v*' -f type=tag"
    $githubEnvironment.GetEnumerator() | ForEach-Object {
        Write-Host "    gh secret set $($_.Key) --env signing --repo $GitHubRepo --body '$($_.Value)'"
    }
}

if ($SkipProd) {
    & $showGitHubSetup
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

& $showGitHubSetup
