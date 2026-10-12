# Segment 4 - Can I Trust It? (~5 min)
#
# The script is run on prod with 'ssh win-prod powershell.exe -ExecutionPolicy
# AllSigned -NonInteractive', like a scheduled task under a group policy
# enforced AllSigned, so an untrusted publisher fails instead of prompting.
# AllSigned is only applied to that process, the prod session used for the
# other steps stays RemoteSigned. Both share the same certificate stores.
#
# Why Windows PowerShell: pwsh 7's own module files are signed by Microsoft
# Corporation and aren't exempt from AllSigned, loading something like
# Microsoft.PowerShell.Security (Import-Certificate, Cert:) wants Microsoft
# as a trusted publisher too. Windows PowerShell's built in modules are OS
# signed so it doesn't hit this. Good Q&A material.
#
# Every step that depends on which certificate signed the script signs it and
# copies it itself so the steps can be re-run in any order.

#region Stop: Can I Trust It?
# NOTE: What/Who/When are facts. Trust is a decision your machine makes.
Show-Stop 4
#endregion

#region A valid signature
<#
Sign the script with the original signer and copy it to prod. Windows says the
signature is valid.
#>
Set-OpenAuthenticodeSignature -Path ./Invoke-Payday.ps1 -Certificate $signer -TimeStampServer $tsa
Copy-ToProd ./Invoke-Payday.ps1 trust/
Invoke-Prod { Get-AuthenticodeSignature .\trust\Invoke-Payday.ps1 }
#endregion

#region So it just runs under AllSigned?
# NOTE: Poll first. Interactive pwsh would show the [V]/[D]/[R]/[A] prompt instead.
<#
This is the script we're running. Run it on prod with Windows PowerShell under
the AllSigned execution policy without an interactive session, like a
scheduled task or CI agent would.
#>
Show-DemoFile ./Invoke-Payday.ps1 -HideSignature
ssh win-prod powershell.exe -NoProfile -NonInteractive -ExecutionPolicy AllSigned -File $ProdPath/trust/Invoke-Payday.ps1
#endregion

#region Why didn't it run?
# NOTE: Valid != trusted. Hash and chain are fine, publisher isn't trusted yet.
# NOTE: "AuthorizationManager check failed" is PowerShell's way of saying it
# NOTE: wanted to prompt but couldn't.
<#
Walk through the checks PowerShell makes before running a script under
AllSigned. The signature is valid but the publisher isn't trusted: an
interactive session would prompt, a non-interactive one can only fail.
#>
Show-TrustTrace trust/Invoke-Payday.ps1 -ExecutionPolicy AllSigned
#endregion

#region Trust the publisher
# NOTE: This is exactly what [A] Always run does. [V] Never run adds it to Disallowed.
<#
Answering [A] Always run at the prompt adds the signing certificate to the
CurrentUser TrustedPublisher store. Do the same thing explicitly and run the
script again.
#>
Invoke-Prod {
    Import-Certificate -FilePath .\certs\Signer.cer -CertStoreLocation Cert:\CurrentUser\TrustedPublisher |
        Select-Object Subject, Thumbprint
}
ssh win-prod powershell.exe -NoProfile -NonInteractive -ExecutionPolicy AllSigned -File $ProdPath/trust/Invoke-Payday.ps1
#endregion

#region A year later, the cert is renewed
# NOTE: Same subject, same CA, new key.
<#
The signing certificate is renewed: same subject, same issuing CA, but a new
key and so a new thumbprint. Sign the script with the renewed certificate and
copy it to prod again.
#>
$signerRenewed = Get-PfxCertificate -FilePath ../certs/SignerRenewed.pfx -NoPromptForPassword
[PSCustomObject]@{ Original = $signer.Thumbprint; Renewed = $signerRenewed.Thumbprint }
Set-OpenAuthenticodeSignature -Path ./Invoke-Payday.ps1 -Certificate $signerRenewed -TimeStampServer $tsa
Copy-ToProd ./Invoke-Payday.ps1 trust/
#endregion

#region Does it still run?
# NOTE: Poll first. "It worked when I tested it."
<#
TrustedPublisher matches the exact certificate by thumbprint, not the subject
name. Check the trust decision and run it again.
#>
Show-TrustTrace trust/Invoke-Payday.ps1 -ExecutionPolicy AllSigned
ssh win-prod powershell.exe -NoProfile -NonInteractive -ExecutionPolicy AllSigned -File $ProdPath/trust/Invoke-Payday.ps1
#endregion

#region Fix it before you switch
# NOTE: In real life: GPO/Intune to LocalMachine\TrustedPublisher, rolled out BEFORE
# NOTE: you start signing with the new cert. Then bridge: WDAC writes rules, not pins.
<#
Trust the renewed certificate machine wide in LocalMachine\TrustedPublisher,
the CurrentUser view of the store includes it. In real life this is deployed
by GPO or Intune before anything is signed with the new certificate.
#>
Invoke-Prod {
    Import-Certificate -FilePath .\certs\SignerRenewed.cer -CertStoreLocation Cert:\LocalMachine\TrustedPublisher |
        Select-Object Subject, Thumbprint
}
ssh win-prod powershell.exe -NoProfile -NonInteractive -ExecutionPolicy AllSigned -File $ProdPath/trust/Invoke-Payday.ps1
#endregion
