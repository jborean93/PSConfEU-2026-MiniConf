using namespace Microsoft.PowerShell
using namespace System.Collections.Generic

$script:DemoSteps = [List[PSObject]]::new()
$script:DemoIndex = 0

Function Import-DemoSegment {
    <#
    .SYNOPSIS
    Loads the demo steps from the segment files.

    .DESCRIPTION
    Each '#region <title>' ... '#endregion' block in a segment file is a step.
    Lines starting with '# NOTE:' are speaker notes for reading the file, they
    are not inserted into the prompt.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, Position = 0)]
        [string[]]
        $Path
    )

    $script:DemoSteps.Clear()
    $script:DemoIndex = 0

    $pattern = '(?ms)^#region (?<title>[^\r\n]+)\r?\n(?<code>.*?)^#endregion'
    foreach ($file in Get-ChildItem -Path $Path -Filter '*.ps1' | Sort-Object Name) {
        $content = Get-Content -LiteralPath $file.FullName -Raw
        foreach ($match in [regex]::Matches($content, $pattern)) {
            $code = $match.Groups['code'].Value -split '\r?\n' |
                Where-Object { $_ -notmatch '^\s*# NOTE:' }

            $script:DemoSteps.Add([PSCustomObject]@{
                    Index = $script:DemoSteps.Count
                    Segment = $file.BaseName
                    Title = $match.Groups['title'].Value.Trim()
                    Code = ($code -join "`n").Trim()
                })
        }
    }

    Write-SpectreHost "[$($script:Colors.Dim)]Loaded $($script:DemoSteps.Count) demo steps[/]"
}

Function Get-DemoStep {
    <#
    .SYNOPSIS
    Lists the loaded demo steps, the next step to be inserted is marked.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Position = 0)]
        [string]
        $Segment
    )

    $script:DemoSteps |
        Where-Object { -not $Segment -or $_.Segment -like "*$Segment*" } |
        Select-Object @{ N = 'Next'; E = { if ($_.Index -eq $script:DemoIndex) { '▶' } } }, Index, Segment, Title
}

Function Set-DemoStep {
    <#
    .SYNOPSIS
    Moves the queue so the next insert is the step specified, useful when
    rehearsing or recovering from a broken demo.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Index')]
    param (
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'Index')]
        [int]
        $Index,

        [Parameter(Mandatory, ParameterSetName = 'Segment')]
        [string]
        $Segment
    )

    if ($PSCmdlet.ParameterSetName -eq 'Segment') {
        $step = $script:DemoSteps | Where-Object Segment -like "*$Segment*" | Select-Object -First 1
        if (-not $step) {
            throw "No segment matching '$Segment'"
        }
        $Index = $step.Index
    }

    $script:DemoIndex = [Math]::Clamp($Index, 0, $script:DemoSteps.Count)
}

Function Write-DemoStep {
    [CmdletBinding()]
    param (
        [Parameter()]
        [switch]
        $Previous
    )

    if ($Previous) {
        # The step in the buffer is DemoIndex - 1, go back one before that.
        $script:DemoIndex = [Math]::Max(0, $script:DemoIndex - 2)
    }

    if ($script:DemoIndex -ge $script:DemoSteps.Count) {
        [PSConsoleReadLine]::Ding()
        return
    }

    $step = $script:DemoSteps[$script:DemoIndex]
    $script:DemoIndex++

    [PSConsoleReadLine]::RevertLine()
    [PSConsoleReadLine]::Insert("# $($step.Title)`n$($step.Code)")
}

Function Register-DemoKeyHandler {
    <#
    .SYNOPSIS
    Binds the PSReadLine chords that insert the next/previous demo step into
    the prompt. Nothing runs until Enter is pressed.
    #>
    [CmdletBinding()]
    param (
        [Parameter()]
        [string]
        $NextChord = $script:Config.NextStepChord,

        [Parameter()]
        [string]
        $PreviousChord = $script:Config.PreviousStepChord
    )

    Set-PSReadLineKeyHandler -Chord $NextChord -BriefDescription DemoNextStep -Description 'Insert the next demo step' -ScriptBlock {
        Write-DemoStep
    }
    Set-PSReadLineKeyHandler -Chord $PreviousChord -BriefDescription DemoPreviousStep -Description 'Insert the previous demo step' -ScriptBlock {
        Write-DemoStep -Previous
    }
}
