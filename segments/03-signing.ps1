# Segment 3 - Signing scripts and modules (~3 min)

#region Stop: Signing
Show-Stop 3
#endregion

#region Sign every file in a module
# NOTE: On Windows: Set-AuthenticodeSignature -HashAlgorithm SHA256 -TimestampServer ...
<#
A module is more than the .psm1. The manifest (.psd1) and format/type files
(.ps1xml) are loaded too, so every one of them needs a signature, not just the
.ps1 and .psm1 files.
#>
Get-ChildItem ./PaydayTools
Set-OpenAuthenticodeSignature -Path ./PaydayTools/* -Certificate $signer -TimeStampServer $tsa
#endregion

#region XML files get an XML comment block
<#
The signature is always stored as a comment in the file's own syntax. For XML
files like .ps1xml that means XML comments instead of '#' lines.
#>
Show-DemoFile ./PaydayTools/PaydayTools.Format.ps1xml
#endregion

#region Verify on Linux
<#
OpenAuthenticode can verify the signatures too. Linux doesn't know about our
demo root CA so pass it in as a custom trust store.
#>
$ca = Get-PfxCertificate -FilePath ../certs/CA.cer
$trustStore = [System.Security.Cryptography.X509Certificates.X509Certificate2Collection]::new($ca)
Get-OpenAuthenticodeSignature -Path ./PaydayTools/* -TrustStore $trustStore |
    Select-Object Path, HashAlgorithm, @{ N = 'Signer'; E = { $_.Certificate.Subject } }
#endregion

#region Verify on prod
<#
Copy the signed module to prod and let Windows verify every file.
#>
Copy-ToProd ./PaydayTools modules/
Invoke-Prod { Get-ChildItem .\modules\PaydayTools | Get-AuthenticodeSignature }
#endregion

#region Valid, but is it trusted?
# NOTE: Poll first. This is the hand off to the Trust segment.
<#
Every file is Valid, so can the module be used? Import it in a Windows
PowerShell process running with the AllSigned execution policy, as if it was
enforced by group policy, where every file must be signed by a trusted
publisher.
#>
ssh win-prod powershell.exe -NoProfile -NonInteractive -ExecutionPolicy AllSigned -Command Import-Module $ProdPath/modules/PaydayTools
#endregion
