Function Clear-DemoImage {
    <#
    .SYNOPSIS
    Removes any image drawn with Show-DemoImage from the terminal.
    #>
    [CmdletBinding()]
    param ()

    # q=2 stops the terminal replying, the reply would end up in the prompt.
    [Console]::Out.Write("`e_Ga=d,d=A,q=2;`e\")
    [Console]::Out.Flush()
}

Function Show-DemoImage {
    <#
    .SYNOPSIS
    Draws a PNG in the terminal with the kitty graphics protocol.

    .DESCRIPTION
    Works in terminals that support the kitty graphics protocol, like Ghostty
    and kitty. The image is scaled to fit the terminal width, or the rows left
    under the cursor, keeping its aspect ratio.

    .PARAMETER Path
    The PNG file to draw.

    .PARAMETER ReservedRows
    Rows already used on the screen that the image shouldn't push off the top.

    .PARAMETER ClearScreen
    Clear the screen first so the image can use the whole terminal.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, Position = 0)]
        [string]
        $Path,

        [Parameter()]
        [int]
        $ReservedRows = 0,

        [Parameter()]
        [switch]
        $ClearScreen
    )

    if ($ClearScreen) {
        Clear-DemoImage
        Clear-Host
    }

    $bytes = [System.IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $Path).ProviderPath)
    # The PNG IHDR chunk has the width and height as big endian ints.
    $width = [BitConverter]::ToInt32($bytes[19..16], 0)
    $height = [BitConverter]::ToInt32($bytes[23..20], 0)

    # Cells are roughly twice as tall as they are wide. Only the columns are
    # sent, the terminal works out the rows from the aspect ratio.
    $maxCols = [Console]::WindowWidth - 4
    $maxRows = [Console]::WindowHeight - $ReservedRows - 2
    $cols = [Math]::Min($maxCols, [int]($maxRows * 2 * $width / $height))
    if ($cols -lt 10) {
        return
    }

    $data = [Convert]::ToBase64String($bytes)
    $chunkSize = 4096
    $sb = [System.Text.StringBuilder]::new()
    $null = $sb.Append(' ' * [int](([Console]::WindowWidth - $cols) / 2))
    for ($i = 0; $i -lt $data.Length; $i += $chunkSize) {
        $chunk = $data.Substring($i, [Math]::Min($chunkSize, $data.Length - $i))
        $more = [int](($i + $chunkSize) -lt $data.Length)
        $control = if ($i -eq 0) { "a=T,f=100,q=2,c=$cols,m=$more" } else { "m=$more" }
        $null = $sb.Append("`e_G$control;$chunk`e\")
    }
    $null = $sb.AppendLine()

    [Console]::Out.Write($sb.ToString())
    [Console]::Out.Flush()
}
