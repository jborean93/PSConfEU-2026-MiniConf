#!/usr/bin/env pwsh
#Requires -Version 7.6

<#
.SYNOPSIS
Sets up the interactive shell used for the talk.

.DESCRIPTION
Run with 'pwsh -NoExit -File Start-Talk.ps1'.
Press the NextStepChord (F9 by default) to insert the next demo step into the
prompt and Enter to run it. PreviousStepChord (F8) re-inserts the previous
step. Use Get-DemoStep and Set-DemoStep to jump around.

.PARAMETER Stop
Start the queue at this segment number instead of the beginning.
#>

using namespace System.Security.Cryptography.X509Certificates

[CmdletBinding()]
param (
    [Parameter()]
    [ValidateRange(0, 7)]
    [int]
    $Stop = 0
)

Import-Module (Join-Path $PSScriptRoot 'DemoKit') -Force -Global

$config = Get-DemoConfig

# Variables used by the demo steps, kept short so the commands read well.
$global:ProdHost = $config.ProdHost
$global:ProdPath = $config.ProdPath
$global:GitHubRepo = $config.GitHubRepo
$global:tsa = $config.TimeStampServer
$global:signer = Get-DemoCertificate Signer
$global:signerRenewed = Get-DemoCertificate SignerRenewed
$global:trustStore = [X509Certificate2Collection]::new(
    (Get-DemoCertificate CA -PublicOnly))

Import-DemoSegment -Path (Join-Path $PSScriptRoot 'segments')
Register-DemoKeyHandler
if ($Stop) {
    Set-DemoStep -Segment ('{0:D2}-' -f $Stop)
}

Set-Location -LiteralPath (Get-DemoPath state, work)

Function global:prompt {
    $dev = "$($PSStyle.Foreground.BrightGreen)🐧 dev$($PSStyle.Reset)"
    $location = "$($PSStyle.Foreground.BrightBlack)$(Split-Path -Leaf $PWD)$($PSStyle.Reset)"
    "`n$dev $location ❯ "
}

Show-Stop $Stop
