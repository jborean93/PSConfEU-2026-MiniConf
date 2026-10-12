# Segment 1 - Anatomy: What / Who / When (~5 min)

#region Stop: Anatomy
# NOTE: "You'll never parse this by hand, this is so the errors make sense later."
Show-Stop 1
#endregion

#region What is this blob?
<#
The signature lives at the end of the script itself, a comment block of base64
between the 'SIG # Begin' and 'SIG # End' markers.
#>
Show-DemoFile ./Invoke-Payday.ps1 -HideSignature -SignatureLines 3
#endregion

#region It is just base64 CMS (PKCS #7)
# NOTE: tools/authenticode.oids only gives OpenSSL names for the Microsoft OIDs.
<#
Strip the comment markers, base64 decode it and save it as a .p7s file. OpenSSL
dumps the ASN.1: a ContentInfo whose type is pkcs7-signedData, a standard CMS
SignedData structure (RFC 5652, the successor of PKCS #7) like S/MIME signed
email. Inside it the signed content's type is SpcIndirectDataContent
(1.3.6.1.4.1.311.2.1.4), Microsoft's Authenticode structure, with the content
itself as an opaque OCTET STRING.
#>
$raw = Get-Content ./Invoke-Payday.ps1 -Raw
$b64 = [regex]::Match($raw, '(?s)# SIG # Begin signature block\r\n(.*)# SIG # End').Groups[1].Value -replace '# |\r\n'
[IO.File]::WriteAllBytes("$PWD/signature.p7s", [Convert]::FromBase64String($b64))
openssl asn1parse -inform DER -in signature.p7s -i -oid (Get-DemoPath tools, authenticode.oids) |
    Select-Object -First 12
#endregion

#region Inside the content: SpcIndirectDataContent
# NOCLEAR
# NOTE: Doesn't clear the screen so both dumps are visible together.
<#
The OCTET STRING at offset 57 is the signed content. Extract the bytes from
the HEX DUMP above to content.der and parse them as ASN.1 too. It's another
structure, the SpcIndirectDataContent: an SpcSipInfo identifying the
PowerShell SIP by GUID (stored little endian,
{603bcc1f-4b59-4e08-b724-d2c6297ef351}) and the SHA256 digest of the script.
This is the WHAT of the signature.
#>
openssl asn1parse -inform DER -in signature.p7s -strparse 57 -noout -out content.der
openssl asn1parse -inform DER -in content.der -i -oid (Get-DemoPath tools, authenticode.oids)
#endregion

#region Three questions
# NOTE: Blue = What, magenta = Who, gold = When. Same colours for the rest of the talk.
<#
Every Authenticode signature answers three questions: what was signed, who
signed it, and when it was signed.
#>
Show-AuthenticodeAnatomy ./Invoke-Payday.ps1
#endregion

#region WHAT was signed?
<#
The SpcIndirectDataContent records which Subject Interface Package (SIP)
produced the digest, here the PowerShell SIP, and the digest of the file
itself. The SIP decides which bytes of a file are hashed.
#>
Show-AuthenticodeAnatomy ./Invoke-Payday.ps1 -Expand What
#endregion

#region Compute the hash ourselves
# NOTE: Remember the BOM detail for "Will it break?".
<#
The PowerShell SIP hashes the script text, as UTF-16LE, up to the signature
block. The UTF-8 BOM is part of that text but Get-Content strips it, so add it
back as the U+FEFF character before hashing.
#>
$text = Get-Content ./Invoke-Payday.ps1 -Raw
$body = $text.Substring(0, $text.IndexOf("`r`n# SIG # Begin signature block"))
$bytes = [Text.Encoding]::Unicode.GetBytes([char]0xFEFF + $body)
[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))
#endregion

#region Same number
# NOCLEAR
<#
Compare the digest stored in the signature with the one computed from the
current file content.
#>
Compare-ScriptDigest ./Invoke-Payday.ps1
#endregion

#region Change one character
<#
Change the amount in a copy of the script and compare again, the computed
digest no longer matches the one in the signature: HashMismatch.
#>
Copy-Item ./Invoke-Payday.ps1 ./Tampered.ps1
$text = (Get-Content ./Tampered.ps1 -Raw).Replace('= 1000', '= 9000')
Set-Content ./Tampered.ps1 -Value $text -NoNewline -Encoding utf8BOM
Compare-ScriptDigest ./Tampered.ps1
#endregion

#region WHO signed it?
# NOTE: The root is NOT in the signature, the machine must already trust it.
# NOTE: That's what UnknownError means most of the time.
<#
The signer's certificate and any intermediates are embedded, the root CA is
not, the machine verifying the signature must already trust it. The signer
signs a set of attributes, one of them is messageDigest which is a hash of the
whole WHAT block, not of the file, so it won't match the file digest.
#>
Show-AuthenticodeAnatomy ./Invoke-Payday.ps1 -Expand Who
#endregion

#region WHEN was it signed?
# NOTE: Tease only: "We'll come back to this, keep an eye on that countdown."
<#
The timestamp is added after signing by a timestamp authority (TSA). The TSA
signs a hash of the signer's signature value together with the current time,
proving that exact signature existed at that moment.
#>
Show-AuthenticodeAnatomy ./Invoke-Payday.ps1 -Expand When
#endregion
