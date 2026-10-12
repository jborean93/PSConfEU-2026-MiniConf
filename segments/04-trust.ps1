# Segment 4 - Can I Trust It? (~5 min)
#
# The ssh -t steps give a real console on prod so the trust prompt works.
# Prod must not have an unsigned profile for the SSH user, AllSigned would
# block it.

#region Stop: Can I Trust It?
# NOTE: What/Who/When are facts. Trust is a decision your machine makes.
Show-Stop 4
#endregion

#region AllSigned and a valid signature
Copy-ToProd ./Invoke-Payday.ps1 trust/
Invoke-Prod {
    Set-ExecutionPolicy -ExecutionPolicy AllSigned -Scope CurrentUser -Force
    Get-AuthenticodeSignature .\trust\Invoke-Payday.ps1
}
#endregion

#region So it just runs?
# NOTE: Prompt appears. Answer [D] Do not run for now.
ssh -t win-prod pwsh -NoProfile -File $ProdPath/trust/Invoke-Payday.ps1
#endregion

#region Why did it ask?
# NOTE: Valid != trusted. Hash and chain are fine, publisher isn't trusted yet.
Show-TrustTrace trust/Invoke-Payday.ps1
#endregion

#region Always run
# NOTE: Answer [A] Always run this time.
ssh -t win-prod pwsh -NoProfile -File $ProdPath/trust/Invoke-Payday.ps1
#endregion

#region What did [A] actually remember?
# NOTE: Not "Jordan", this exact certificate. [V] Never run goes to Disallowed.
Invoke-Prod { Get-ChildItem Cert:\CurrentUser\TrustedPublisher | Select-Object Subject, Thumbprint }
Show-TrustTrace trust/Invoke-Payday.ps1
#endregion

#region A year later, the cert is renewed
# NOTE: Same subject, same CA, new key.
[PSCustomObject]@{ Old = $signer.Thumbprint; New = $signerRenewed.Thumbprint }
Set-OpenAuthenticodeSignature -Path ./Invoke-Payday.ps1 -Certificate $signerRenewed -TimeStampServer $tsa
Copy-ToProd ./Invoke-Payday.ps1 trust/
#endregion

#region Will it prompt again?
# NOTE: Poll first. Answer [D] if running it for real.
Show-TrustTrace trust/Invoke-Payday.ps1
#endregion

#region Nobody there to answer
# NOTE: No -t, -NonInteractive: this is your scheduled task. "It worked when I tested it."
ssh win-prod pwsh -NoProfile -NonInteractive -File $ProdPath/trust/Invoke-Payday.ps1
#endregion

#region Fix it before you switch
# NOTE: In real life: GPO/Intune to LocalMachine\TrustedPublisher, rolled out BEFORE
# NOTE: you start signing with the new cert. Then bridge: WDAC writes rules, not pins.
Invoke-Prod {
    Import-Certificate -FilePath .\certs\SignerRenewed.cer -CertStoreLocation Cert:\LocalMachine\TrustedPublisher |
        Select-Object Subject, Thumbprint
}
ssh win-prod pwsh -NoProfile -NonInteractive -File $ProdPath/trust/Invoke-Payday.ps1
#endregion
