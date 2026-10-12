# Segment 6 - Ship It: CI with Artifact Signing (~6 min)
#
# The release is published live from the browser, the build/sign/release jobs
# finish while the workflow file is on screen.

#region Stop: Ship It
# NOTE: Browser: publish a new release with a vX.Y.Z tag now, show the run starting.
# NOTE: The signing environment only has the IDs as secrets, no keys or passwords.
Show-Stop 6
#endregion

#region SignTool vs OpenAuthenticode
# NOTE: Factual, not a dig at SignTool.
<#
Signing with Artifact Signing used to mean a Windows runner, the Windows SDK,
an extra client library, and a metadata file. OpenAuthenticode talks to the
service directly from any OS.
#>
Show-SigningComparison
#endregion

#region The workflow
# NOTE: GitHub proves who the workflow is, Entra trusts that, the key never leaves the HSM.
<#
Three jobs, each with only the permissions it needs. build runs the repo's
code with no secrets. sign never runs repo code, it logs in to Azure with the
GitHub OIDC token and signs the build output. release packs the signed module
into a nupkg and attaches it to the GitHub release.
#>
Show-DemoFile (Get-DemoPath .github, workflows, sign.yml)
#endregion

#region Download the release on prod
# NOTE: Browser: show the finished run and the nupkg asset on the release first.
<#
Download the nupkg attached to the release we just published straight onto
prod from GitHub.
#>
$version = Read-Host 'Release version (without the v)'
$url = "https://github.com/$GitHubRepo/releases/download/v$version/PaydayTools.$version.nupkg"
Invoke-Prod {
    param ($Url)

    Invoke-WebRequest -Uri $Url -OutFile ".\ci\$(Split-Path -Path $Url -Leaf)"
    Get-ChildItem .\ci
} $url
#endregion

#region Install it like any other module
<#
Register the download folder as a local repository and install the module
from it, the same way a module from the PowerShell Gallery is installed.
#>
Invoke-Prod {
    Register-PSResourceRepository -Name DemoRelease -Uri (Resolve-Path .\ci).Path -Trusted
    Install-PSResource -Name PaydayTools -Repository DemoRelease
    Get-InstalledPSResource -Name PaydayTools | Select-Object Name, Version, Repository
}
#endregion

#region Prod trusts it out of the box
# NOTE: Signed on Linux, Windows trusts the Microsoft issued chain.
<#
Check every PowerShell file in the installed module. They were signed on a
Linux runner but chain to a Microsoft root Windows already trusts.
#>
Invoke-Prod {
    $module = Get-Module -Name PaydayTools -ListAvailable | Select-Object -First 1
    Get-ChildItem -Path $module.ModuleBase -Include *.ps1, *.psm1, *.psd1, *.ps1xml -Recurse |
        Get-AuthenticodeSignature
}
#endregion

#region Anatomy of a CI signature
# NOTE: Same tree as before. Microsoft issued chain, Microsoft TSA.
<#
Download the same nupkg locally, it's just a zip, and look at the signature
with the same view as before. WHO is now a Microsoft issued chain and WHEN is
Microsoft's timestamp authority.
#>
$null = New-Item ./ci -ItemType Directory -Force
Invoke-WebRequest -Uri $url -OutFile ./ci/PaydayTools.nupkg
[IO.Compression.ZipFile]::ExtractToDirectory("$PWD/ci/PaydayTools.nupkg", "$PWD/ci/PaydayTools", $true)
Show-AuthenticodeAnatomy ./ci/PaydayTools/PaydayTools.psm1 -Expand Who, When
#endregion

#region A certificate that lives for 3 days
# NOTE: Timestamping is mandatory here, without it every signature dies in 3 days.
# NOTE: Source: learn.microsoft.com/azure/artifact-signing/concept-certificate-management
# NOTE: The Artifact Signing CAs are leaving the CCADB but stay on the Windows trust list,
# NOTE: so these signatures are for Windows consumers.
<#
Artifact Signing issues a new certificate every day that is only valid for
72 hours, so the thumbprint keeps changing and TrustedPublisher pinning can't
keep up. The Identity EKU (1.3.6.1.4.1.311.97.*) is unique to the certificate
profile and is the same on every certificate it issues. Microsoft documents
using it in a WDAC policy to pin trust to the profile instead of a
thumbprint. Recreating the profile gives it a new EKU.
#>
Show-Certificate (Get-OpenAuthenticodeSignature ./ci/PaydayTools/PaydayTools.psm1 -SkipCertificateCheck).Certificate
#endregion
