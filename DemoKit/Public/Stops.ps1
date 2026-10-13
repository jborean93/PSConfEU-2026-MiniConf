$script:Stops = @(
    @{
        Label = 'Intro'
        Title = 'Sign of the Times'
        Subtitle = 'PowerShell and Authenticode'
        Summary = ''
        Image = 'sponsors.png'
    }
    @{
        Label = 'Anatomy'
        Title = 'Anatomy'
        Subtitle = 'What does a signature actually contain?'
        Summary = 'A signature is a CMS (PKCS #7) blob appended to the script as a comment. We decode it and answer three questions: what was signed, who signed it, and when.'
    }
    @{
        Label = 'Certificates'
        Title = 'Certificates'
        Subtitle = 'Who are you, and who says so?'
        Summary = 'Signing needs a certificate with the Code Signing EKU, issued by a CA the machine trusts. Where the certificate comes from decides who will trust it.'
    }
    @{
        Label = 'Signing'
        Title = 'Signing'
        Subtitle = 'Signing scripts and modules'
        Summary = 'Every PowerShell file in a module can carry a signature, not just .ps1 files. We sign a module on Linux with OpenAuthenticode and check that Windows agrees.'
    }
    @{
        Label = 'Trust'
        Title = 'Can I Trust It?'
        Subtitle = "Valid isn't the same as trusted"
        Summary = 'A valid signature only proves what and who. The execution policy, the TrustedPublisher store, and the Disallowed store decide whether a signed script is allowed to run.'
    }
    @{
        Label = 'Enforce'
        Title = 'Enforce It'
        Subtitle = 'WDAC / App Control for Business'
        Summary = 'Execution policy is a safety net, not a security boundary. With WDAC enforced, untrusted scripts drop to ConstrainedLanguage and only code from trusted signers gets full access.'
    }
    @{
        Label = 'Ship'
        Title = 'Ship It'
        Subtitle = 'Signing in CI with Artifact Signing'
        Summary = 'A release workflow that signs with Azure Artifact Signing through OIDC. No client secrets or private keys in the pipeline, then we install the release on prod and verify it.'
    }
    @{
        Label = 'Time'
        Title = 'Sign of the Times'
        Subtitle = 'When does a signature die?'
        Summary = 'The countdown certificate from the start of the talk has expired. Does the timestamp keep its signature valid?'
    }
)

Function Get-JourneyMapMarkup {
    <#
    .SYNOPSIS
    Gets the Spectre markup for the breadcrumb of the talk with the current
    stop highlighted.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, Position = 0)]
        [ValidateRange(0, 7)]
        [int]
        $Stop
    )

    $parts = for ($i = 0; $i -lt $script:Stops.Count; $i++) {
        $label = $script:Stops[$i].Label
        if ($i -eq $Stop) {
            "[$($script:Colors.OnTrust) on $($script:Colors.Trust) bold] $label [/]"
        }
        elseif ($i -lt $Stop) {
            "[$($script:Colors.Dim)]$label[/]"
        }
        else {
            $label
        }
    }

    "  " + ($parts -join " [$($script:Colors.Dim)]›[/] ")
}

Function Show-JourneyMap {
    <#
    .SYNOPSIS
    Renders the breadcrumb of the talk with the current stop highlighted.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, Position = 0)]
        [ValidateRange(0, 7)]
        [int]
        $Stop
    )

    Write-SpectreHost (Get-JourneyMapMarkup -Stop $Stop)
}

Function Show-Stop {
    <#
    .SYNOPSIS
    The "slide" for each segment, a title and where we are in the journey.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, Position = 0)]
        [ValidateRange(0, 7)]
        [int]
        $Stop
    )

    $info = $script:Stops[$Stop]

    Clear-DemoImage
    Clear-Host
    Write-SpectreFigletText -Text $info.Title -Color $script:Colors.Trust | Out-Host
    Write-SpectreHost "  [italic]$(Get-SpectreEscapedText $info.Subtitle)[/]"
    Write-SpectreHost ''
    Show-JourneyMap -Stop $Stop
    Write-SpectreHost ''
    if ($info.Summary) {
        Format-SpectrePanel -Data (Get-SpectreEscapedText $info.Summary) -Color $script:Colors.Dim -Expand | Out-Host
    }
    if ($info.Image) {
        $imagePath = Join-Path $PSScriptRoot '..' 'assets' $info.Image
        Show-DemoImage -Path $imagePath -ReservedRows ([Console]::CursorTop + 1)
    }
}
