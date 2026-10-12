# Segment 6 - Ship It: CI with Artifact Signing (~6 min)
#
# The release is published live from the browser, the build/sign/release jobs
# finish while the workflow file is on screen.

#region Stop: Ship It
# NOTE: Browser: publish a new release with a vX.Y.Z tag now, show the run starting.
# NOTE: Point out the repo has no secrets, only the signing environment variables.
Show-Stop 6
#endregion

#region What it used to take
# NOTE: Factual, not a dig at SignTool.
Show-SigningComparison
#endregion

#region The workflow
# NOTE: Three jobs, least privilege: build (no secrets) -> sign (OIDC only, never
# NOTE: runs repo code) -> release (contents: write, packs and uploads the nupkg).
# NOTE: GitHub proves who the workflow is, Entra trusts that, the key never leaves the HSM.
Show-DemoFile (Get-DemoPath .github, workflows, sign.yml)
#endregion

#region Download the release on prod
# NOTE: Browser: show the finished run and the nupkg asset on the release first.
$version = Read-Host 'Release version (without the v)'
$url = "https://github.com/$GitHubRepo/releases/download/v$version/PaydayTools.$version.nupkg"
Invoke-Prod {
    param ($Url)

    Invoke-WebRequest -Uri $Url -OutFile ".\ci\$(Split-Path -Path $Url -Leaf)"
    Get-ChildItem .\ci
} $url
#endregion

#region Install it like any other module
Invoke-Prod {
    Register-PSResourceRepository -Name DemoRelease -Uri (Resolve-Path .\ci).Path -Trusted
    Install-PSResource -Name PaydayTools -Repository DemoRelease
    Get-InstalledPSResource -Name PaydayTools | Select-Object Name, Version, Repository
}
#endregion

#region Prod trusts it out of the box
# NOTE: Signed on Linux, Windows trusts the Microsoft issued chain.
Invoke-Prod {
    $module = Get-Module -Name PaydayTools -ListAvailable | Select-Object -First 1
    Get-ChildItem -Path $module.ModuleBase -Include *.ps1, *.psm1, *.psd1, *.ps1xml -Recurse |
        Get-AuthenticodeSignature
}
#endregion

#region Anatomy of a CI signature
# NOTE: Same tree as before. Microsoft issued chain, Microsoft TSA.
$null = New-Item ./ci -ItemType Directory -Force
Invoke-WebRequest -Uri $url -OutFile ./ci/PaydayTools.nupkg
[IO.Compression.ZipFile]::ExtractToDirectory("$PWD/ci/PaydayTools.nupkg", "$PWD/ci/PaydayTools", $true)
Show-AuthenticodeAnatomy ./ci/PaydayTools/PaydayTools.psm1 -Expand Who, When
#endregion

#region A certificate that lives for 3 days
# NOTE: New cert every day: thumbprint pinning can't work, timestamping is mandatory.
# NOTE: Durable identity EKU (1.3.6.1.4.1.311.97.*) stays the same, WDAC can target it.
Show-Certificate (Get-OpenAuthenticodeSignature ./ci/PaydayTools/PaydayTools.psm1 -SkipCertificateCheck).Certificate
#endregion
