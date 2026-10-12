using namespace System.Formats.Asn1
using namespace System.Security.Cryptography
using namespace System.Security.Cryptography.Pkcs

$script:KnownSip = @{
    '603bcc1f-4b59-4e08-b724-d2c6297ef351' = 'PowerShell SIP (pwrshsip.dll)'
}

Function Get-CommentMarker {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]
        $Path
    )

    switch -Regex ([IO.Path]::GetExtension($Path)) {
        '^\.(ps1xml|psc1|cdxml)$' { @('<!-- ', ' -->') }
        '^\.mof$' { @('/* ', ' */') }
        default { @('# ', '') }
    }
}

Function Get-ScriptText {
    <#
    .SYNOPSIS
    Decodes the script like the PowerShell SIP does, keeping any BOM as the
    U+FEFF char as it is part of the hashed data.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]
        $Path
    )

    $bytes = [IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $Path).ProviderPath)
    $encoding = if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
        [Text.UnicodeEncoding]::new($false, $true)
    }
    elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF) {
        [Text.UnicodeEncoding]::new($true, $true)
    }
    else {
        [Text.UTF8Encoding]::new($false)
    }

    $encoding.GetString($bytes)
}

Function Get-SignatureBlock {
    <#
    .SYNOPSIS
    Extracts the base64 signature block from a script and decodes it as the
    PKCS #7 SignedData (SignedCms) it really is.
    #>
    [OutputType([System.Security.Cryptography.Pkcs.SignedCms])]
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, Position = 0)]
        [string]
        $Path
    )

    $start, $end = Get-CommentMarker -Path $Path
    $text = Get-ScriptText -Path $Path

    $begin = "$start`SIG # Begin signature block$end"
    $finish = "$start`SIG # End signature block$end"
    $beginIdx = $text.IndexOf($begin)
    $finishIdx = $text.IndexOf($finish)
    if ($beginIdx -eq -1 -or $finishIdx -eq -1) {
        throw "No signature block found in '$Path'"
    }

    $b64 = $text.Substring($beginIdx + $begin.Length, $finishIdx - $beginIdx - $begin.Length) -split '\r?\n' |
        Where-Object { $_ } |
        ForEach-Object { $_.Substring($start.Length, $_.Length - $start.Length - $end.Length) }

    $cms = [SignedCms]::new()
    $cms.Decode([Convert]::FromBase64String($b64 -join ''))
    $cms
}

Function Get-ScriptDigest {
    <#
    .SYNOPSIS
    Computes the Authenticode digest of a script the same way the PowerShell
    SIP does: hash the UTF-16LE script text before the signature block.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, Position = 0)]
        [string]
        $Path,

        [Parameter()]
        [HashAlgorithmName]
        $HashAlgorithm = 'SHA256'
    )

    $start, $end = Get-CommentMarker -Path $Path
    $text = Get-ScriptText -Path $Path
    $idx = $text.IndexOf("`r`n$start`SIG # Begin signature block$end")
    $body = if ($idx -eq -1) { $text } else { $text.Substring(0, $idx) }

    $data = [Text.Encoding]::Unicode.GetBytes($body)
    [Convert]::ToHexString([CryptographicOperations]::HashData($HashAlgorithm, $data))
}

Function Get-SignatureDigest {
    <#
    .SYNOPSIS
    Parses the SpcIndirectDataContent to get the SIP and digest stored in the
    signature.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [SignedCms]
        $SignedCms
    )

    $reader = [AsnReader]::new($SignedCms.ContentInfo.Content, [AsnEncodingRules]::DER)
    $indirectData = $reader.ReadSequence()

    $data = $indirectData.ReadSequence()
    $dataType = $data.ReadObjectIdentifier()
    $sipGuid = $null
    if ($dataType -eq '1.3.6.1.4.1.311.2.1.30' -and $data.HasData) {
        # SpcSipInfo
        $sipInfo = $data.ReadSequence()
        $null = $sipInfo.ReadInteger()
        $sipGuid = [Guid]::new($sipInfo.ReadOctetString())
    }

    $digestInfo = $indirectData.ReadSequence()
    $algorithm = $digestInfo.ReadSequence().ReadObjectIdentifier()
    $digest = $digestInfo.ReadOctetString()

    [PSCustomObject]@{
        DataType = $dataType
        SipGuid = $sipGuid
        HashAlgorithm = [HashAlgorithmName]::FromOid($algorithm)
        Digest = [Convert]::ToHexString($digest)
    }
}

Function Get-SignatureTimestamp {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [SignerInfo]
        $SignerInfo
    )

    foreach ($attr in $SignerInfo.UnsignedAttributes) {
        if ($attr.Oid.Value -eq '1.3.6.1.4.1.311.3.3.1') {
            # RFC 3161 timestamp token stored by Microsoft as an unsigned attribute.
            $token = $null
            $consumed = 0
            $raw = [ReadOnlyMemory[byte]]::new($attr.Values[0].RawData)
            if ([Rfc3161TimestampToken]::TryDecode($raw, [ref]$token, [ref]$consumed)) {
                $tsaCms = $token.AsSignedCms()
                return [PSCustomObject]@{
                    Type = 'RFC 3161'
                    Time = $token.TokenInfo.Timestamp
                    Certificate = $tsaCms.SignerInfos[0].Certificate
                    MessageHash = [Convert]::ToHexString($token.TokenInfo.GetMessageHash().ToArray())
                    MessageHashAlgorithm = [HashAlgorithmName]::FromOid($token.TokenInfo.HashAlgorithmId.Value)
                }
            }
        }
    }

    foreach ($counter in $SignerInfo.CounterSignerInfos) {
        # Legacy Authenticode countersignature
        $signingTime = $counter.SignedAttributes |
            Where-Object { $_.Oid.Value -eq '1.2.840.113549.1.9.5' } |
            ForEach-Object { [Pkcs9SigningTime]::new($_.Values[0].RawData).SigningTime }

        return [PSCustomObject]@{
            Type = 'Legacy countersignature'
            Time = [DateTimeOffset]$signingTime
            Certificate = $counter.Certificate
            MessageHash = $null
            MessageHashAlgorithm = $null
        }
    }
}

Function New-TreeNode {
    param ([object]$Value, [object[]]$Children = @())

    @{ Value = $Value; Children = @($Children | Where-Object { $null -ne $_ }) }
}

Function Format-Check {
    param ([bool]$Ok)

    if ($Ok) { "[$($script:Colors.Pass)]verified[/]" } else { "[$($script:Colors.Fail)]does not match[/]" }
}

Function Show-AuthenticodeAnatomy {
    <#
    .SYNOPSIS
    Shows the signature as three questions: What, Who, and When.

    .PARAMETER Expand
    Which question(s) to open up, the others are shown as a one line summary.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, Position = 0)]
        [string]
        $Path,

        [Parameter()]
        [ValidateSet('What', 'Who', 'When', 'All')]
        [string[]]
        $Expand = @()
    )

    $c = $script:Colors
    $e = { Get-SpectreEscapedText "$args" }
    if ($Expand -contains 'All') {
        $Expand = 'What', 'Who', 'When'
    }

    $cms = Get-SignatureBlock -Path $Path
    $signer = $cms.SignerInfos[0]
    $digest = Get-SignatureDigest -SignedCms $cms
    $timestamp = Get-SignatureTimestamp -SignerInfo $signer

    # WHAT
    $whatSummary = "[$($c.What) bold]WHAT[/] was signed?     [$($c.What)]$($digest.HashAlgorithm.Name) $($digest.Digest)[/]"
    $whatChildren = if ($Expand -contains 'What') {
        $sipName = if ($digest.SipGuid -and $script:KnownSip.ContainsKey("$($digest.SipGuid)")) {
            $script:KnownSip["$($digest.SipGuid)"]
        }
        else {
            'Unknown SIP'
        }

        @(
            New-TreeNode "Content type: SpcIndirectDataContent [$($c.Dim)]$($cms.ContentInfo.ContentType.Value)[/]"
            New-TreeNode "Subject interface package: $sipName [$($c.Dim)]{$($digest.SipGuid)}[/]"
            New-TreeNode "File digest: [$($c.What)]$($digest.HashAlgorithm.Name) $($digest.Digest)[/]"
        )
    }

    # WHO
    $whoSummary = "[$($c.Who) bold]WHO[/] signed it?       [$($c.Who)]$(& $e $signer.Certificate.Subject)[/]"
    $whoChildren = if ($Expand -contains 'Who') {
        $embedded = @($cms.Certificates)
        $certNodes = foreach ($cert in $embedded) {
            $lifetime = Format-Duration ($cert.NotAfter - $cert.NotBefore)
            $ekus = @(Format-Eku -Certificate $cert | ForEach-Object { "$(& $e $_.Name) [$($c.Dim)]$($_.Oid)[/]" }) -join ', '
            New-TreeNode "[$($c.Who)]$(& $e $cert.Subject)[/]" @(
                New-TreeNode "Issued by: $(& $e $cert.Issuer)"
                New-TreeNode "Valid: $($cert.NotBefore.ToString('yyyy-MM-dd HH:mm')) to $($cert.NotAfter.ToString('yyyy-MM-dd HH:mm')) [$($c.Dim)]($lifetime)[/]"
                if ($ekus) { New-TreeNode "EKU: $ekus" }
                New-TreeNode "Thumbprint: [$($c.Dim)]$($cert.Thumbprint)[/]"
            )
        }

        $top = $embedded | Where-Object {
            $issuer = $_.Issuer
            -not ($embedded | Where-Object Subject -eq $issuer)
        } | Select-Object -First 1
        $rootNote = if ($top -and $top.Subject -ne $top.Issuer) {
            New-TreeNode "[$($c.Fail)]Root not embedded:[/] $(& $e $top.Issuer) [$($c.Dim)]- this machine must already trust it[/]"
        }

        # messageDigest covers the whole WHAT block (SIP info plus the file
        # digest), so it is expected to differ from the file digest.
        $hashAlgo = [HashAlgorithmName]::FromOid($signer.DigestAlgorithm.Value)
        $messageDigest = $signer.SignedAttributes |
            Where-Object { $_.Oid.Value -eq '1.2.840.113549.1.9.4' } |
            ForEach-Object {
                $md = [Pkcs9MessageDigest]::new()
                $md.CopyFrom($_.Values[0])
                [Convert]::ToHexString($md.MessageDigest)
            }
        $whatHash = [Convert]::ToHexString([CryptographicOperations]::HashData($hashAlgo, $cms.ContentInfo.Content))

        @(
            New-TreeNode "Embedded certificates ($($embedded.Count))" $certNodes
            $rootNote
            New-TreeNode 'SignerInfo' @(
                New-TreeNode "Signed attribute messageDigest: [$($c.Dim)]$messageDigest[/]" @(
                    New-TreeNode "= $($hashAlgo.Name) of the whole [$($c.What)]WHAT[/] block, not the file, so it differs from the file digest: $(Format-Check ($messageDigest -eq $whatHash))"
                )
                New-TreeNode "Signature: $($signer.SignatureAlgorithm.FriendlyName) over $($hashAlgo.Name) of the signed attributes [$($c.Dim)]($($signer.GetSignature().Length) bytes)[/]"
            )
        ) | Where-Object { $_ }
    }

    # WHEN
    $whenSummary = if ($timestamp) {
        "[$($c.When) bold]WHEN[/] was it signed?   [$($c.When)]$($timestamp.Time.UtcDateTime.ToString('yyyy-MM-dd HH:mm:ss')) UTC[/]"
    }
    else {
        "[$($c.When) bold]WHEN[/] was it signed?   [$($c.Fail)]no timestamp[/]"
    }
    $whenChildren = if ($Expand -contains 'When') {
        if ($timestamp) {
            $tsaNodes = @(
                New-TreeNode "Type: $($timestamp.Type) [$($c.Dim)](unsigned attribute, added after signing)[/]"
                New-TreeNode "Authority: [$($c.When)]$(& $e $timestamp.Certificate.Subject)[/]"
            )
            if ($timestamp.MessageHash) {
                # The TSA signs a hash of the signature value from WHO, it
                # vouches that this exact signature existed at that time.
                $signatureHash = [Convert]::ToHexString(
                    [CryptographicOperations]::HashData($timestamp.MessageHashAlgorithm, $signer.GetSignature()))
                $tsaNodes += New-TreeNode "Timestamped hash: [$($c.Dim)]$($timestamp.MessageHash)[/]" @(
                    New-TreeNode "= $($timestamp.MessageHashAlgorithm.Name) of the [$($c.Who)]WHO[/] signature value, the TSA vouches that this exact signature existed at that time: $(Format-Check ($timestamp.MessageHash -eq $signatureHash))"
                )
            }
            $tsaNodes
        }
        else {
            New-TreeNode "[$($c.Fail)]The signature is only valid while the signing certificate is[/]"
        }
    }

    $tree = New-TreeNode "[bold]SignedData (CMS / PKCS #7)[/] [$($c.Dim)]$(& $e (Split-Path -Leaf $Path))[/]" @(
        New-TreeNode $whatSummary $whatChildren
        New-TreeNode $whoSummary $whoChildren
        New-TreeNode $whenSummary $whenChildren
    )

    Format-SpectreTree -Data $tree -Guide BoldLine
}

Function Compare-ScriptDigest {
    <#
    .SYNOPSIS
    Compares the digest stored in the signature with one computed from the
    current file content.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, Position = 0)]
        [string]
        $Path
    )

    $c = $script:Colors
    $stored = Get-SignatureDigest -SignedCms (Get-SignatureBlock -Path $Path)
    $computed = Get-ScriptDigest -Path $Path -HashAlgorithm $stored.HashAlgorithm

    $match = $stored.Digest -eq $computed
    $resultColor = if ($match) { $c.Pass } else { $c.Fail }
    $result = if ($match) { 'Match' } else { 'HashMismatch' }

    $rows = @(
        [PSCustomObject]@{ Source = 'Stored in signature'; Digest = "[$($c.What)]$($stored.Digest)[/]" }
        [PSCustomObject]@{ Source = 'Computed from file'; Digest = "[$resultColor]$computed[/]" }
    )
    $rows | Format-SpectreTable -AllowMarkup -Color $c.What -Title "[$resultColor]$result[/]"
}
