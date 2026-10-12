$script:Stops = @(
    @{ Label = 'Start'; Title = 'Sign of the Times'; Subtitle = 'PowerShell and Authenticode' }
    @{ Label = 'Anatomy'; Title = 'Anatomy'; Subtitle = 'What does a signature actually contain?' }
    @{ Label = 'Certificates'; Title = 'Certificates'; Subtitle = 'Who are you, and who says so?' }
    @{ Label = 'Signing'; Title = 'Signing'; Subtitle = 'Signing scripts and modules' }
    @{ Label = 'Trust'; Title = 'Can I Trust It?'; Subtitle = "Valid isn't the same as trusted" }
    @{ Label = 'Enforce'; Title = 'Enforce It'; Subtitle = 'WDAC / App Control for Business' }
    @{ Label = 'Ship'; Title = 'Ship It'; Subtitle = 'Signing in CI with Artifact Signing' }
    @{ Label = 'Time'; Title = 'Sign of the Times'; Subtitle = 'When does a signature die?' }
)

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

    $parts = for ($i = 1; $i -lt $script:Stops.Count; $i++) {
        $label = $script:Stops[$i].Label
        if ($i -eq $Stop) {
            "[black on $($script:Colors.Trust) bold] $label [/]"
        }
        elseif ($i -lt $Stop) {
            "[$($script:Colors.Dim)]$label[/]"
        }
        else {
            $label
        }
    }

    Write-SpectreHost ("  " + ($parts -join " [$($script:Colors.Dim)]›[/] "))
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

    Clear-Host
    Write-SpectreFigletText -Text $info.Title -Color $script:Colors.Trust | Out-Host
    Write-SpectreHost "  [italic]$(Get-SpectreEscapedText $info.Subtitle)[/]"
    Write-SpectreHost ''
    if ($Stop -gt 0) {
        Show-JourneyMap -Stop $Stop
        Write-SpectreHost ''
    }
}
