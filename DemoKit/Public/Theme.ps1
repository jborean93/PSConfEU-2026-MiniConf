Function Set-DemoTheme {
    <#
    .SYNOPSIS
    Sets the colours used by the demo visuals.

    .DESCRIPTION
    Each Authenticode question has its own colour used throughout the talk:
    What, Who, When, and Trust. Green/red are reserved for pass/fail.

    .PARAMETER LightMode
    Use colours that are readable on a light terminal background.
    #>
    [CmdletBinding()]
    param (
        [Parameter()]
        [switch]
        $LightMode
    )

    $script:Colors = if ($LightMode) {
        @{
            What = 'DodgerBlue3'
            Who = 'DarkMagenta'
            When = 'DarkGoldenrod'
            Trust = 'DarkCyan'
            Pass = 'Green4'
            Fail = 'Red3'
            Warn = 'DarkOrange3'
            Dim = 'Grey42'
            # Text on the highlighted journey stop.
            OnTrust = 'White'
            # Prompt colours, as $PSStyle values.
            PromptHost = $PSStyle.Foreground.Green
            PromptLocation = $PSStyle.Foreground.FromRgb(100, 100, 100)
            # bat syntax highlighting theme for Show-DemoFile.
            BatTheme = 'GitHub'
        }
    }
    else {
        @{
            What = 'DeepSkyBlue1'
            Who = 'Orchid'
            When = 'Gold1'
            Trust = 'Aqua'
            Pass = 'Green'
            Fail = 'Red'
            Warn = 'Yellow'
            Dim = 'Grey50'
            OnTrust = 'Black'
            PromptHost = $PSStyle.Foreground.BrightGreen
            PromptLocation = $PSStyle.Foreground.BrightBlack
            BatTheme = 'Monokai Extended'
        }
    }
}

Function Get-DemoTheme {
    [CmdletBinding()]
    param ()

    $script:Colors
}
