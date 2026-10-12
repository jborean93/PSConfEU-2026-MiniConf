# Segment 0 - Cold open (~2 min)
#
# Each '#region <title>' block is one demo step inserted into the prompt by
# F9. '# NOTE:' lines are speaker notes, they aren't inserted into the prompt.

#region Start the clock
# NOTE: Do this before the intro.
# NOTE: "I just created a certificate that dies in 25 minutes. Remember that."
<#
Create a code signing certificate that is only valid for the next 25 minutes
and sign two copies of the script with it, one with a timestamp and one
without. We'll check both scripts again at the end of the talk, after the
certificate has expired.
#>
New-CountdownSignature
#endregion

#region The signing certificate and timestamp server
<#
The certificate and its private key come from a PFX file created when setting
up the demo. It was issued by a demo root CA that prod already trusts. The
timestamp server is DigiCert's public RFC 3161 service.
#>
$signer = Get-PfxCertificate -FilePath ../certs/Signer.pfx -NoPromptForPassword
$tsa = 'http://timestamp.digicert.com'
$signer | Select-Object Subject, Issuer, NotAfter, HasPrivateKey
#endregion

#region Sign a script on Linux
# NOTE: Plain OpenAuthenticode on Linux. Prod is a Windows box over SSH.
<#
This is the script we're signing, it pays everyone a default of $1000. Sign it
on Linux with OpenAuthenticode, it appends the signature as a comment block at
the end of the file. Then copy the file as is to the Windows host we're
calling prod.
#>
Show-DemoFile ./Invoke-Payday.ps1
Set-OpenAuthenticodeSignature -Path ./Invoke-Payday.ps1 -Certificate $signer -TimeStampServer $tsa
Copy-ToProd ./Invoke-Payday.ps1
#endregion

#region Windows says it is valid
<#
Ask Windows itself, using the built in Get-AuthenticodeSignature, whether the
signature created on Linux is valid.
#>
Invoke-Prod { Get-AuthenticodeSignature .\Invoke-Payday.ps1 }
#endregion

#region Give myself a raise
# NOTE: Chat poll before pressing Enter: still valid?
# NOTE: Wait ~15 seconds for the stream delay before revealing.
<#
Change the default amount from 1000 to 9000 in the copy on prod without
touching the signature block. Show the changed script with the start of the
untouched signature block, then ask Windows again.
#>
Invoke-Prod {
    $text = (Get-Content .\Invoke-Payday.ps1 -Raw).Replace('= 1000', '= 9000')
    Set-Content .\Invoke-Payday.ps1 -Value $text -NoNewline -Encoding utf8BOM

    Get-Content .\Invoke-Payday.ps1 | Select-Object -First 16
    Get-AuthenticodeSignature .\Invoke-Payday.ps1
}
#endregion
