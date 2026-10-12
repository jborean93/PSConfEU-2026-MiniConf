# Segment 2 - Certificates (~2 min)

#region Stop: Certificates
Show-Stop 2
#endregion

#region The signing certificate
# NOTE: Made with .NET CertificateRequest on Linux. On Windows:
# NOTE: New-SelfSignedCertificate -Type CodeSigningCert -Subject ...
<#
A code signing certificate needs the Digital Signature key usage and the Code
Signing enhanced key usage (EKU) 1.3.6.1.5.5.7.3.3. It is a normal leaf
certificate, not a CA.
#>
Show-Certificate $signer
#endregion

#region Issued by a CA that prod trusts
# NOTE: tools/Initialize-Demo.ps1 put the CA into LocalMachine\Root on prod.
<#
The signer was issued by the demo root CA. Windows only accepts the signature
because that root is in prod's Trusted Root Certification Authorities store.
#>
$ca = Get-PfxCertificate -FilePath ../certs/CA.cer
Show-Certificate $ca
Invoke-Prod { Get-ChildItem Cert:\LocalMachine\Root | Where-Object Subject -Like '*PSConfEU*' }
#endregion

#region Where do certificates come from?
# NOTE: Since 2023 the CA/B Forum requires public code signing keys in an HSM,
# NOTE: no more PFX in a pipeline secret. That's why Artifact Signing matters.
<#
Where the certificate comes from decides which machines will trust the
signature and where the private key has to live.
#>
Show-CertificateOptions
#endregion
