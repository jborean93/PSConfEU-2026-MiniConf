#!/usr/bin/env pwsh
#Requires -Version 7.6

<#
.SYNOPSIS
Puts the local working copies and prod back into a known state. Run before
every rehearsal and before going live.

.DESCRIPTION
Local:
    Recreates state/work with fresh unsigned copies of the source files and
    pre-signs the WDAC demo scripts.

Prod:
    Wipes the demo folder (except certs and policy), resets the CurrentUser execution
    policy to RemoteSigned and removes any demo certificates from the
    TrustedPublisher and Disallowed stores.

WDAC is not touched unless -RemoveWdac is set, which reboots prod if the
policy was enforced.

.PARAMETER RemoveWdac
Also remove the WDAC policy from prod.
#>
[CmdletBinding()]
param (
    [Parameter()]
    [switch]
    $RemoveWdac
)

$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot '..' 'DemoKit') -Force

$config = Get-DemoConfig
$signer = Get-DemoCertificate Signer

# Local state
$work = Get-DemoPath state, work
if (Test-Path -LiteralPath $work) {
    Remove-Item -LiteralPath $work -Recurse -Force
}
$null = New-Item -Path $work -ItemType Directory
Remove-Item -LiteralPath (Get-DemoPath state, countdown.json) -ErrorAction SilentlyContinue

Copy-Item -LiteralPath (Get-DemoPath src, Invoke-Payday.ps1) -Destination $work
Copy-Item -LiteralPath (Get-DemoPath src, PaydayTools) -Destination $work -Recurse

$wdacWork = Join-Path $work wdac
$null = New-Item -Path $wdacWork -ItemType Directory
$wdacSrc = Get-DemoPath src, wdac
Copy-Item -LiteralPath (Join-Path $wdacSrc Payday.ps1) -Destination (Join-Path $wdacWork Unsigned.ps1)
Copy-Item -LiteralPath (Join-Path $wdacSrc Payday.ps1) -Destination (Join-Path $wdacWork Signed.ps1)
Copy-Item -LiteralPath (Join-Path $wdacSrc PaydayWithHelper.ps1) -Destination $wdacWork
Copy-Item -LiteralPath (Join-Path $wdacSrc Helper.ps1) -Destination $wdacWork

$toSign = @(
    Join-Path $wdacWork Signed.ps1
    Join-Path $wdacWork PaydayWithHelper.ps1
)
Set-OpenAuthenticodeSignature -LiteralPath $toSign -Certificate $signer -TimeStampServer $config.TimeStampServer

# Prod state
if ($RemoveWdac) {
    Set-ProdWdac Absent
}

Invoke-Prod -ErrorAction Stop {
    param ($ProdPath)

    Get-ChildItem -LiteralPath $ProdPath |
        Where-Object Name -NotIn 'certs', 'policy' |
        Remove-Item -Recurse -Force
    'wib', 'trust', 'wdac', 'countdown', 'ci', 'modules' | ForEach-Object {
        $null = New-Item -Path "$ProdPath/$_" -ItemType Directory
    }

    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force

    # Undo the release install from the CI segment.
    Uninstall-PSResource -Name PaydayTools -ErrorAction SilentlyContinue
    Unregister-PSResourceRepository -Name DemoRelease -ErrorAction SilentlyContinue

    $demoIssuer = 'CN=PSConfEU Demo Root CA'
    $stores = @(
        'Cert:\CurrentUser\TrustedPublisher'
        'Cert:\LocalMachine\TrustedPublisher'
        'Cert:\CurrentUser\Disallowed'
        'Cert:\LocalMachine\Disallowed'
    )
    Get-ChildItem -Path $stores -ErrorAction SilentlyContinue |
        Where-Object Issuer -eq $demoIssuer |
        Remove-Item
} $config.ProdPath

Copy-ToProd -Path (Join-Path $wdacWork '*') -Destination 'wdac/'

$state = Invoke-Prod {
    [PSCustomObject]@{
        LanguageMode = "$($ExecutionContext.SessionState.LanguageMode)"
        ExecutionPolicy = "$(Get-ExecutionPolicy)"
    }
}
Write-Host "Prod language mode: $($state.LanguageMode), execution policy: $($state.ExecutionPolicy)"
if ($state.LanguageMode -ne 'FullLanguage') {
    Write-Warning 'WDAC still looks enforced on prod, run with -RemoveWdac or Set-ProdWdac Absent'
}
