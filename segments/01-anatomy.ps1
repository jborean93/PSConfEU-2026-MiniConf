# Segment 1 - Anatomy: What / Who / When (~5 min)

#region Stop: Anatomy
# NOTE: "You'll never parse this by hand, this is so the errors make sense later."
Show-Stop 1
#endregion

#region What is this blob?
Get-Content ./Invoke-Payday.ps1 | Select-Object -First 16
#endregion

#region It is just base64 PKCS #7
# NOTE: Standard CMS SignedData, the same container as signed email.
$raw = Get-Content ./Invoke-Payday.ps1 -Raw
$b64 = [regex]::Match($raw, '(?s)# SIG # Begin signature block\r\n(.*)# SIG # End').Groups[1].Value -replace '# |\r\n'
$cms = [System.Security.Cryptography.Pkcs.SignedCms]::new()
$cms.Decode([Convert]::FromBase64String($b64))
$cms.ContentInfo.ContentType
#endregion

#region Three questions
# NOTE: Blue = What, magenta = Who, gold = When. Same colours for the rest of the talk.
Show-AuthenticodeAnatomy ./Invoke-Payday.ps1
#endregion

#region WHAT was signed?
# NOTE: The SIP GUID tells Windows to hand the file to PowerShell's SIP.
Show-AuthenticodeAnatomy ./Invoke-Payday.ps1 -Expand What
#endregion

#region Compute the hash ourselves
# NOTE: Script text as UTF-16LE up to the signature block. The BOM is part of it,
# NOTE: Get-Content strips it so add it back. Remember this for "Will it break?".
$text = Get-Content ./Invoke-Payday.ps1 -Raw
$body = $text.Substring(0, $text.IndexOf("`r`n# SIG # Begin signature block"))
$bytes = [Text.Encoding]::Unicode.GetBytes([char]0xFEFF + $body)
[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))
#endregion

#region Same number
Compare-ScriptDigest ./Invoke-Payday.ps1
#endregion

#region Change one character
Copy-Item ./Invoke-Payday.ps1 ./Tampered.ps1
$text = (Get-Content ./Tampered.ps1 -Raw).Replace('= 1000', '= 9000')
Set-Content ./Tampered.ps1 -Value $text -NoNewline -Encoding utf8BOM
Compare-ScriptDigest ./Tampered.ps1
#endregion

#region WHO signed it?
# NOTE: The root is NOT in the signature, the machine must already trust it.
# NOTE: That's what UnknownError means most of the time.
Show-AuthenticodeAnatomy ./Invoke-Payday.ps1 -Expand Who
#endregion

#region WHEN was it signed?
# NOTE: Tease only: "We'll come back to this, keep an eye on that countdown."
Show-AuthenticodeAnatomy ./Invoke-Payday.ps1 -Expand When
#endregion
