Function Show-TrustTrace {
    <#
    .SYNOPSIS
    Walks through how PowerShell decides whether to run a signed script on
    prod.

    .DESCRIPTION
    The facts are gathered on prod and the decision is rendered locally. This
    is a visual approximation of the checks PowerShell does, not its literal
    implementation.

    .PARAMETER Path
    The path to the script on prod, relative to the prod demo folder.

    .PARAMETER ExecutionPolicy
    Evaluate the decision for this execution policy instead of the prod
    session's policy, e.g. when the script is run with
    'pwsh -ExecutionPolicy AllSigned'.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, Position = 0)]
        [string]
        $Path,

        [Parameter()]
        [ValidateSet('AllSigned', 'RemoteSigned', 'Unrestricted', 'Bypass', 'Restricted')]
        [string]
        $ExecutionPolicy,

        [Parameter()]
        [int]
        $DelayMilliseconds = 600
    )

    $c = $script:Colors
    $e = { Get-SpectreEscapedText "$args" }

    # Keep this CLM friendly, no method calls on non-core types and no
    # [PSCustomObject] casts, return a hashtable instead.
    $facts = Invoke-Prod {
        param ($ProdPath, $Path)

        $Path = Join-Path $ProdPath $Path

        $sig = Get-AuthenticodeSignature -LiteralPath $Path
        $thumbprint = $sig.SignerCertificate.Thumbprint
        $zone = Get-Content -LiteralPath $Path -Stream Zone.Identifier -ErrorAction SilentlyContinue |
            Where-Object { $_ -like 'ZoneId=*' }

        $disallowed = Get-ChildItem Cert:\CurrentUser\Disallowed, Cert:\LocalMachine\Disallowed -ErrorAction SilentlyContinue |
            Where-Object Thumbprint -eq $thumbprint
        $trusted = Get-ChildItem Cert:\CurrentUser\TrustedPublisher, Cert:\LocalMachine\TrustedPublisher -ErrorAction SilentlyContinue |
            Where-Object Thumbprint -eq $thumbprint

        @{
            ExecutionPolicy = "$(Get-ExecutionPolicy)"
            Zone = "$zone"
            Status = "$($sig.Status)"
            StatusMessage = $sig.StatusMessage
            Subject = $sig.SignerCertificate.Subject
            Thumbprint = $thumbprint
            Disallowed = [bool]$disallowed
            TrustedPublisher = [bool]$trusted
        }
    } $script:Config.ProdPath $Path

    if ($ExecutionPolicy) {
        $facts.ExecutionPolicy = $ExecutionPolicy
    }

    $zoneId = if ($facts.Zone -match 'ZoneId=(\d)') { [int]$Matches[1] } else { 0 }
    $isRemote = $zoneId -ge 3
    $needsSignature = $facts.ExecutionPolicy -eq 'AllSigned' -or ($facts.ExecutionPolicy -eq 'RemoteSigned' -and $isRemote)

    $policyDetail = $facts.ExecutionPolicy
    if ($facts.ExecutionPolicy -eq 'RemoteSigned') {
        $policyDetail += if ($isRemote) { ", Mark of the Web ZoneId=$zoneId" } else { ', no Mark of the Web' }
    }

    $steps = @(
        @{ Tag = 'POLICY'; Color = $c.Dim; Question = 'Does the execution policy require a signature?'; Ok = $needsSignature; Detail = $policyDetail }
        @{ Tag = 'WHAT'; Color = $c.What; Question = 'Does the content hash match?'; Ok = $facts.Status -notin 'HashMismatch', 'NotSigned'; Detail = $facts.Status }
        @{ Tag = 'WHO'; Color = $c.Who; Question = 'Does the chain build to a trusted root?'; Ok = $facts.Status -eq 'Valid'; Detail = $facts.Subject }
        @{ Tag = 'TRUST'; Color = $c.Trust; Question = 'Is the publisher absent from Disallowed?'; Ok = -not $facts.Disallowed; Detail = $facts.Thumbprint }
        @{ Tag = 'TRUST'; Color = $c.Trust; Question = 'Is the publisher in TrustedPublisher?'; Ok = $facts.TrustedPublisher; Detail = $facts.Thumbprint }
    )

    Write-SpectreRule -Title "[$($c.Trust)]Can I trust it?[/] [$($c.Dim)]$(& $e $Path)[/]" -Color $c.Trust | Out-Host

    for ($i = 0; $i -lt $steps.Count; $i++) {
        $step = $steps[$i]
        Start-Sleep -Milliseconds $DelayMilliseconds

        $mark = if ($step.Ok) { "[$($c.Pass)]yes[/]" } else { "[$($c.Fail)]no [/]" }
        $tag = "[$($step.Color) bold]$($step.Tag.PadRight(6))[/]"
        Write-SpectreHost "$tag $($step.Question.PadRight(48)) $mark [$($c.Dim)]$(& $e $step.Detail)[/]"

        if ($i -eq 0 -and -not $step.Ok) {
            Write-SpectreHost "[$($c.Pass) bold]→ Runs, the signature is never even checked[/]"
            return
        }
        if ($i -in 1, 2, 3 -and -not $step.Ok) {
            Write-SpectreHost "[$($c.Fail) bold]→ Blocked[/] [$($c.Dim)]$(& $e $facts.StatusMessage)[/]"
            return
        }
        if ($i -eq 4 -and -not $step.Ok) {
            Write-SpectreHost "[$($c.Warn) bold]→ Interactive: prompts[/] [$($c.Warn)][[V]] Never run  [[D]] Do not run  [[R]] Run once  [[A]] Always run[/]"
            Write-SpectreHost "[$($c.Fail) bold]→ Non-interactive:[/] [$($c.Fail)]fails, nobody can answer the prompt (AuthorizationManager check failed)[/]"
            return
        }
    }

    Write-SpectreHost "[$($c.Pass) bold]→ Runs silently[/]"
}
