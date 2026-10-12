Function Show-CertificateOptions {
    [CmdletBinding()]
    param ()

    $rows = @(
        [PSCustomObject]@{ Option = 'Self-signed'; TrustedBy = 'Only machines you import it into'; KeyLivesIn = 'Wherever you put it'; GoodFor = 'Labs, demos, learning' }
        [PSCustomObject]@{ Option = 'Internal PKI (AD CS)'; TrustedBy = 'Machines trusting your root'; KeyLivesIn = 'Your call (HSM recommended)'; GoodFor = 'Internal automation' }
        [PSCustomObject]@{ Option = 'Public CA'; TrustedBy = 'Everyone'; KeyLivesIn = 'HSM / token (CA/B Forum)'; GoodFor = 'Public modules' }
        [PSCustomObject]@{ Option = 'Azure Artifact Signing'; TrustedBy = 'Everyone'; KeyLivesIn = "Microsoft's HSM"; GoodFor = 'CI pipelines, no key to lose' }
    )
    $rows | Format-SpectreTable -Color $script:Colors.Who -Title 'Where does a code signing certificate come from?'
}

Function Show-SigningComparison {
    [CmdletBinding()]
    param ()

    $rows = @(
        [PSCustomObject]@{ Step = 'Runner'; SignTool = 'Windows only'; OpenAuthenticode = 'Any OS' }
        [PSCustomObject]@{ Step = 'Tooling'; SignTool = 'Windows SDK for signtool.exe'; OpenAuthenticode = 'Install-PSResource OpenAuthenticode' }
        [PSCustomObject]@{ Step = 'Artifact Signing'; SignTool = 'Download dlib + .NET dependencies'; OpenAuthenticode = 'Built in' }
        [PSCustomObject]@{ Step = 'Config'; SignTool = 'metadata.json + /dlib /dmdf args'; OpenAuthenticode = 'Get-OpenAuthenticodeAzTrustedSigner' }
        [PSCustomObject]@{ Step = 'Auth'; SignTool = 'Azure CLI / env vars'; OpenAuthenticode = 'Azure CLI / env vars' }
    )
    $rows | Format-SpectreTable -Color $script:Colors.Trust -Title 'Signing with Artifact Signing in CI'
}

Function Show-DemoFile {
    <#
    .SYNOPSIS
    Shows a file with syntax highlighting.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, Position = 0)]
        [string]
        $Path
    )

    if (Get-Command -Name bat -ErrorAction SilentlyContinue) {
        bat --style=numbers,header --paging=never $Path
    }
    elseif (Get-Command -Name Show-TextMate -ErrorAction SilentlyContinue) {
        Show-TextMate -Path $Path
    }
    else {
        Get-Content -LiteralPath $Path
    }
}

Function Show-Closing {
    [CmdletBinding()]
    param ()

    $c = $script:Colors
    $lines = @(
        "[$($c.What) bold]WHAT[/]   the hash proves the content hasn't changed"
        "[$($c.Who) bold]WHO[/]    the certificate chain proves who signed it"
        "[$($c.When) bold]WHEN[/]   the timestamp keeps it valid after the cert expires"
        "[$($c.Trust) bold]TRUST[/]  your machine decides if that is enough"
        ''
        "[bold]Demos[/]             github.com/$($script:Config.GitHubRepo)"
        '[bold]OpenAuthenticode[/]  github.com/jborean93/PowerShell-OpenAuthenticode'
        '[bold]GitHub[/]            jborean93'
        '[bold]BlueSky[/]           jborean.bsky.social'
    )
    Format-SpectrePanel -Data ($lines -join "`n") -Header ' Thanks! Questions? ' -Color $c.Trust -Expand
}
