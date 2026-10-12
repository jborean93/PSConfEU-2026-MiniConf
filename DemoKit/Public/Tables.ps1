Function Show-CertificateOptions {
    [CmdletBinding()]
    param ()

    # Artifact Signing prices are the published Basic/Premium tiers, check
    # https://azure.microsoft.com/pricing/details/artifact-signing/ before
    # the talk.
    $rows = @(
        [PSCustomObject]@{ Option = 'Self-signed'; TrustedBy = 'Only machines you import it into'; KeyLivesIn = 'Wherever you put it'; Cost = 'Free'; GoodFor = 'Labs, demos, learning' }
        [PSCustomObject]@{ Option = 'Internal PKI (AD CS)'; TrustedBy = 'Machines trusting your root'; KeyLivesIn = 'Your call (HSM recommended)'; Cost = 'Free, but you run and maintain the PKI'; GoodFor = 'Internal automation' }
        [PSCustomObject]@{ Option = 'Public CA'; TrustedBy = 'Everyone'; KeyLivesIn = 'HSM / token (CA/B Forum)'; Cost = 'Hundreds of dollars a year'; GoodFor = 'Public modules' }
        [PSCustomObject]@{ Option = 'Azure Artifact Signing'; TrustedBy = 'Windows'; KeyLivesIn = "Microsoft's HSM"; Cost = '$9.99/month (Basic), $99.99/month (Premium)'; GoodFor = 'CI pipelines, no key to lose' }
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
    $rows | Format-SpectreTable -Color $script:Colors.Trust -Title 'SignTool vs OpenAuthenticode for Artifact Signing'
}

Function Show-DemoFile {
    <#
    .SYNOPSIS
    Shows a file with syntax highlighting.

    .PARAMETER HideSignature
    Collapse the Authenticode signature block so only the code is shown.

    .PARAMETER SignatureLines
    With -HideSignature, still show this many lines of the base64 block
    before collapsing the rest.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, Position = 0)]
        [string]
        $Path,

        [Parameter()]
        [switch]
        $HideSignature,

        [Parameter()]
        [int]
        $SignatureLines = 0
    )

    $name = Split-Path -Path $Path -Leaf
    $text = Get-Content -LiteralPath $Path -Raw
    if ($HideSignature) {
        $start, $end = Get-CommentMarker -Path $Path
        $pattern = "(?s)$([regex]::Escape("$start`SIG # Begin signature block$end"))\r?\n(.*?)$([regex]::Escape("$start`SIG # End signature block$end"))"
        $text = [regex]::Replace($text, $pattern, {
                param ($m)
                $lines = @($m.Groups[1].Value -split '\r?\n' | Where-Object { $_ })
                $shown = @($lines | Select-Object -First $SignatureLines)
                $hidden = $lines.Count - $shown.Count
                @(
                    "$start`SIG # Begin signature block$end"
                    $shown
                    if ($hidden) { "$start... $hidden $(if ($shown) { 'more ' })lines of base64 ...$end" }
                    "$start`SIG # End signature block$end"
                ) -join "`n"
            })
    }

    if (Get-Command -Name bat -CommandType Application -ErrorAction SilentlyContinue) {
        $text | bat --style=numbers,header --paging=never --file-name $name
    }
    else {
        $text
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
