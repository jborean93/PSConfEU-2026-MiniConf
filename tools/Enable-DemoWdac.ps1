<#
.SYNOPSIS
Creates and enforces the demo WDAC policy on prod.

.DESCRIPTION
Copied to the prod 'policy' folder and run in pwsh by Set-ProdWdac Enforced.
Based on how the ansible.windows collection enables App Control in its
integration tests.

The policy starts from DefaultWindows_Enforced and adds user mode signer rules
for the demo root CA and for the certificates that signed pwsh itself,
otherwise pwsh would be blocked. The CA rule is on the root, not the leaf, so
the policy keeps working when the signing certificate is renewed. That's the
contrast to the TrustedPublisher thumbprint pinning in the Trust segment.

It is applied without a reboot through CiTool.exe or the
PS_UpdateAndCompareCIPolicy CIM method. Details are written to enforced.json
next to this script so Set-ProdWdac Absent knows what to remove.

.PARAMETER CertificatePath
Path to the demo root CA certificate.

.PARAMETER PolicyName
The policy friendly name.
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [string]
    $CertificatePath,

    [Parameter()]
    [string]
    $PolicyName = 'PSConfEU_Demo'
)

$ErrorActionPreference = 'Stop'

$policyPath = Join-Path $PSScriptRoot policy.xml
$markerPath = Join-Path $PSScriptRoot enforced.json
# ConvertFrom-CIPolicy fails writing to other locations.
$policyBinPath = "$env:windir\System32\CodeIntegrity\SiPolicy.p7b"

if (Test-Path -LiteralPath $policyBinPath) {
    throw "A WDAC policy already exists at '$policyBinPath', not overwriting it"
}

Copy-Item -LiteralPath "$env:windir\schemas\CodeIntegrity\ExamplePolicies\DefaultWindows_Enforced.xml" -Destination $policyPath -Force

$signScript = {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]
        $PolicyName,

        [Parameter(Mandatory)]
        [string]
        $PolicyPath,

        [Parameter(Mandatory)]
        [string]
        $PolicyBinPath,

        [Parameter(Mandatory)]
        [string[]]
        $CertPath
    )

    $ErrorActionPreference = 'Stop'

    Set-CIPolicyIdInfo -FilePath $PolicyPath -PolicyName $PolicyName -PolicyId (New-Guid)
    Set-CIPolicyVersion -FilePath $PolicyPath -Version '1.0.0.0'

    $CertPath | ForEach-Object -Process {
        Add-SignerRule -FilePath $PolicyPath -CertificatePath $_ -User
    }
    Set-RuleOption -FilePath $PolicyPath -Option 0          # Enabled:UMCI
    Set-RuleOption -FilePath $PolicyPath -Option 3 -Delete  # Enabled:Audit Mode
    Set-RuleOption -FilePath $PolicyPath -Option 11 -Delete # Disabled:Script Enforcement
    Set-RuleOption -FilePath $PolicyPath -Option 19         # Enabled:Dynamic Code Security

    $null = ConvertFrom-CIPolicy -XmlFilePath $PolicyPath -BinaryFilePath $PolicyBinPath
}

# Trust the certs that signed pwsh.exe and its DLLs, DefaultWindows only
# trusts Windows signed code.
$psSigningCerts = Get-ChildItem -LiteralPath $PSHOME |
    Where-Object Extension -In @('.dll', '.exe') |
    Get-AuthenticodeSignature |
    Select-Object -ExpandProperty SignerCertificate -Unique |
    ForEach-Object -Process {
        $certOut = Join-Path -Path $PSScriptRoot -ChildPath "pwsh-$($_.Thumbprint).cer"
        [System.IO.File]::WriteAllBytes($certOut, $_.Export('Cert'))
        $certOut
    }

# The ConfigCI cmdlets only work in Windows PowerShell.
$jobArgs = @(
    $PolicyName
    $policyPath
    $policyBinPath
    , @((Resolve-Path -LiteralPath $CertificatePath).Path; $psSigningCerts)
)
Start-Job -ScriptBlock $signScript -ArgumentList $jobArgs -PSVersion 5.1 |
    Receive-Job -Wait -AutoRemoveJob

$ciTool = Get-Command -Name CiTool.exe -ErrorAction SilentlyContinue
$policyId = $null
if ($ciTool) {
    $setInfo = & $ciTool --update-policy $policyBinPath *>&1
    if ($LASTEXITCODE) {
        throw "CiTool.exe --update-policy failed ${LASTEXITCODE}: $setInfo"
    }

    $policyId = & $ciTool --list-policies --json |
        ConvertFrom-Json |
        Select-Object -ExpandProperty Policies |
        Where-Object FriendlyName -EQ $PolicyName |
        Select-Object -ExpandProperty PolicyID
}
else {
    $cimParams = @{
        Namespace = 'root\Microsoft\Windows\CI'
        ClassName = 'PS_UpdateAndCompareCIPolicy'
        MethodName = 'Update'
        Arguments = @{ FilePath = $policyBinPath }
    }
    $rc = Invoke-CimMethod @cimParams
    if ($rc.ReturnValue) {
        throw "PS_UpdateAndCompareCIPolicy Update failed $($rc.ReturnValue)"
    }
}

$result = [PSCustomObject]@{
    PolicyName = $PolicyName
    PolicyId = $policyId
    Path = $policyBinPath
}
$result | ConvertTo-Json | Set-Content -LiteralPath $markerPath
$result
