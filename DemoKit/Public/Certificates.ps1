using namespace System.Security.Cryptography
using namespace System.Security.Cryptography.X509Certificates

$script:KnownEku = @{
    '1.3.6.1.5.5.7.3.3' = 'Code Signing'
    '1.3.6.1.5.5.7.3.8' = 'Time Stamping'
    '1.3.6.1.4.1.311.10.3.13' = 'Lifetime Signing'
    '1.3.6.1.4.1.311.97.1.0' = 'Artifact Signing marker'
}

Function Format-Eku {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [X509Certificate2]
        $Certificate
    )

    $ekuExt = $Certificate.Extensions | Where-Object { $_ -is [X509EnhancedKeyUsageExtension] }
    foreach ($oid in $ekuExt.EnhancedKeyUsages) {
        $name = if ($script:KnownEku.ContainsKey($oid.Value)) {
            $script:KnownEku[$oid.Value]
        }
        elseif ($oid.Value -like '1.3.6.1.4.1.311.97.*') {
            'Artifact Signing durable identity'
        }
        elseif ($oid.FriendlyName) {
            $oid.FriendlyName
        }
        else {
            'Unknown'
        }

        [PSCustomObject]@{
            Oid = $oid.Value
            Name = $name
        }
    }
}

Function Format-Duration {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [TimeSpan]
        $TimeSpan
    )

    if ($TimeSpan.TotalDays -ge 365) {
        '{0:N1} years' -f ($TimeSpan.TotalDays / 365)
    }
    elseif ($TimeSpan.TotalDays -ge 1) {
        '{0:N1} days' -f $TimeSpan.TotalDays
    }
    elseif ($TimeSpan.TotalHours -ge 1) {
        '{0:N1} hours' -f $TimeSpan.TotalHours
    }
    else {
        '{0:N0} minutes' -f $TimeSpan.TotalMinutes
    }
}

Function New-DemoCertificate {
    <#
    .SYNOPSIS
    Creates a CA or code signing certificate in memory with .NET, works the
    same on Linux and Windows.
    #>
    [OutputType([System.Security.Cryptography.X509Certificates.X509Certificate2])]
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]
        $Subject,

        [Parameter()]
        [X509Certificate2]
        $Issuer,

        [Parameter()]
        [DateTimeOffset]
        $NotBefore = [DateTimeOffset]::UtcNow.AddMinutes(-5),

        [Parameter()]
        [DateTimeOffset]
        $NotAfter = [DateTimeOffset]::UtcNow.AddYears(1),

        [Parameter()]
        [switch]
        $CertificateAuthority
    )

    $key = [RSA]::Create(3072)
    $request = [CertificateRequest]::new($Subject, $key, [HashAlgorithmName]::SHA256, [RSASignaturePadding]::Pkcs1)
    $request.CertificateExtensions.Add(
        [X509BasicConstraintsExtension]::new([bool]$CertificateAuthority, $false, 0, $true))
    $request.CertificateExtensions.Add(
        [X509SubjectKeyIdentifierExtension]::new($request.PublicKey, $false))

    if ($CertificateAuthority) {
        $request.CertificateExtensions.Add(
            [X509KeyUsageExtension]::new('KeyCertSign, CrlSign', $true))
    }
    else {
        $request.CertificateExtensions.Add(
            [X509KeyUsageExtension]::new('DigitalSignature', $true))

        $ekus = [OidCollection]::new()
        $null = $ekus.Add([Oid]::new('1.3.6.1.5.5.7.3.3', 'Code Signing'))
        $request.CertificateExtensions.Add(
            [X509EnhancedKeyUsageExtension]::new($ekus, $false))
    }

    if (-not $Issuer) {
        return $request.CreateSelfSigned($NotBefore, $NotAfter)
    }

    $request.CertificateExtensions.Add(
        [X509AuthorityKeyIdentifierExtension]::CreateFromCertificate($Issuer, $true, $false))

    $serial = [byte[]]::new(16)
    [RandomNumberGenerator]::Fill($serial)
    $serial[0] = $serial[0] -band 0x7F

    $cert = $request.Create($Issuer, $NotBefore, $NotAfter, $serial)
    [RSACertificateExtensions]::CopyWithPrivateKey($cert, $key)
}

Function Save-DemoCertificate {
    <#
    .SYNOPSIS
    Saves the cert as <Name>.pfx (with key) and <Name>.cer (public only).
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [X509Certificate2]
        $Certificate,

        [Parameter(Mandatory)]
        [string]
        $Name
    )

    $null = New-Item -Path $script:CertPath -ItemType Directory -Force
    $base = Join-Path $script:CertPath $Name
    [IO.File]::WriteAllBytes("$base.pfx", $Certificate.Export([X509ContentType]::Pfx))
    [IO.File]::WriteAllBytes("$base.cer", $Certificate.Export([X509ContentType]::Cert))
}

Function Get-DemoCertificate {
    <#
    .SYNOPSIS
    Loads a demo certificate saved by Save-DemoCertificate.
    #>
    [OutputType([System.Security.Cryptography.X509Certificates.X509Certificate2])]
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, Position = 0)]
        [ValidateSet('CA', 'Signer', 'SignerRenewed', 'Countdown')]
        [string]
        $Name,

        [Parameter()]
        [switch]
        $PublicOnly
    )

    $base = Join-Path $script:CertPath $Name
    if (-not (Test-Path -LiteralPath "$base.pfx")) {
        throw "Certificate '$Name' not found, run tools/Initialize-Demo.ps1 first"
    }

    if ($PublicOnly) {
        [X509CertificateLoader]::LoadCertificateFromFile("$base.cer")
    }
    else {
        [X509CertificateLoader]::LoadPkcs12FromFile("$base.pfx", $null)
    }
}

Function Show-Certificate {
    <#
    .SYNOPSIS
    Renders the parts of a certificate that matter for code signing.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [X509Certificate2]
        $Certificate,

        [Parameter()]
        [string]
        $Header
    )

    process {
        $who = $script:Colors.Who
        $dim = $script:Colors.Dim
        $e = { Get-SpectreEscapedText "$args" }

        $lifetime = Format-Duration ($Certificate.NotAfter - $Certificate.NotBefore)
        $expired = $Certificate.NotAfter -lt [DateTime]::Now
        $validFrom = $Certificate.NotBefore.ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss')
        $validTo = $Certificate.NotAfter.ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss')
        $validity = "$validFrom → $validTo UTC [$dim]($lifetime)[/]"
        if ($expired) {
            $validity += " [$($script:Colors.Fail)]EXPIRED[/]"
        }

        $basic = $Certificate.Extensions | Where-Object { $_ -is [X509BasicConstraintsExtension] }
        $keyUsage = $Certificate.Extensions | Where-Object { $_ -is [X509KeyUsageExtension] }
        $ekus = @(Format-Eku -Certificate $Certificate | ForEach-Object {
                $color = if ($_.Oid -eq '1.3.6.1.5.5.7.3.3' -or $_.Name -like 'Artifact*') { $who } else { 'default' }
                "[$color]$(& $e $_.Name)[/] [$dim]$($_.Oid)[/]"
            })

        $lines = @(
            "[bold]Subject[/]     $(& $e $Certificate.Subject)"
            "[bold]Issuer[/]      $(& $e $Certificate.Issuer)"
            "[bold]Valid[/]       $validity"
            "[bold]Is CA[/]       $([bool]$basic.CertificateAuthority)"
            "[bold]Key Usage[/]   $(if ($keyUsage) { $keyUsage.KeyUsages } else { '-' })"
            "[bold]EKU[/]         $(if ($ekus) { $ekus -join "`n            " } else { '-' })"
            "[bold]Thumbprint[/]  [$who]$($Certificate.Thumbprint)[/]"
        )

        # Artifact Signing certs carry an EKU unique to the certificate
        # profile, it stays the same when the cert (and thumbprint) changes
        # every day.
        $identity = Format-Eku -Certificate $Certificate |
            Where-Object Name -EQ 'Artifact Signing durable identity' |
            Select-Object -First 1
        if ($identity) {
            $lines += "[bold]Identity[/]    [$who bold]$($identity.Oid)[/]"
            $lines += "            [$dim]unique to the certificate profile, the same on every certificate it issues[/]"
        }

        $panelHeader = if ($Header) { $Header } else { $Certificate.GetNameInfo('SimpleName', $false) }
        Format-SpectrePanel -Data ($lines -join "`n") -Header (& $e $panelHeader) -Color $who -Expand
    }
}

Function New-CountdownSignature {
    <#
    .SYNOPSIS
    Creates a short lived certificate and signs two copies of the script, one
    with a timestamp and one without, then copies them to prod.
    #>
    [CmdletBinding()]
    param (
        [Parameter()]
        [int]
        $Minutes = $script:Config.CountdownMinutes,

        [Parameter()]
        [string]
        $Path = (Join-Path $script:RepoRoot 'src' 'Invoke-Payday.ps1')
    )

    $ca = Get-DemoCertificate CA
    $cert = New-DemoCertificate -Subject 'CN=Countdown Signer (Demo)' -Issuer $ca -NotAfter ([DateTimeOffset]::UtcNow.AddMinutes($Minutes))
    Save-DemoCertificate -Certificate $cert -Name Countdown

    $workDir = Join-Path $script:StatePath 'work' 'countdown'
    $null = New-Item -Path $workDir -ItemType Directory -Force
    $withTs = Join-Path $workDir 'WithTimestamp.ps1'
    $noTs = Join-Path $workDir 'NoTimestamp.ps1'
    Copy-Item -LiteralPath $Path -Destination $withTs -Force
    Copy-Item -LiteralPath $Path -Destination $noTs -Force

    Set-OpenAuthenticodeSignature -LiteralPath $withTs -Certificate $cert -TimeStampServer $script:Config.TimeStampServer
    Set-OpenAuthenticodeSignature -LiteralPath $noTs -Certificate $cert

    Copy-ToProd -Path $withTs, $noTs -Destination 'countdown/'

    @{
        NotAfter = $cert.NotAfter.ToUniversalTime().ToString('o')
        Thumbprint = $cert.Thumbprint
    } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $script:StatePath 'countdown.json')

    Show-Certificate -Certificate $cert -Header 'Countdown certificate'
}

Function Wait-CountdownExpiry {
    <#
    .SYNOPSIS
    Makes sure the countdown certificate has expired, waiting with a spinner
    if the talk ran faster than CountdownMinutes.
    #>
    [CmdletBinding()]
    param ()

    $path = Join-Path $script:StatePath 'countdown.json'
    if (-not (Test-Path -LiteralPath $path)) {
        throw 'No countdown certificate found, New-CountdownSignature was not run'
    }

    # ConvertFrom-Json already turns the ISO string into a DateTime.
    $notAfter = [DateTimeOffset](Get-Content -LiteralPath $path -Raw | ConvertFrom-Json).NotAfter
    $remaining = $notAfter - [DateTimeOffset]::UtcNow
    if ($remaining -gt [TimeSpan]::Zero) {
        $statusParams = @{
            Title = "Waiting $([int]$remaining.TotalSeconds + 1) seconds for the countdown certificate to expire"
            Spinner = 'Dots'
            Color = $script:Colors.When
            ScriptBlock = {
                while ([DateTimeOffset]::UtcNow -le $notAfter) {
                    Start-Sleep -Milliseconds 500
                }
            }.GetNewClosure()
        }
        Invoke-SpectreCommandWithStatus @statusParams
    }

    Write-SpectreHost "[$($script:Colors.When)]The countdown certificate expired at $($notAfter.ToLocalTime().ToString('HH:mm:ss'))[/]"
}
