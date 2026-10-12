# Segment 2 - Certificates (~2 min)

#region Stop: Certificates
Show-Stop 2
#endregion

#region The signing certificate
# NOTE: Key usage DigitalSignature + EKU Code Signing 1.3.6.1.5.5.7.3.3.
# NOTE: Made with .NET CertificateRequest on Linux. On Windows:
# NOTE: New-SelfSignedCertificate -Type CodeSigningCert -Subject ...
Show-Certificate $signer
#endregion

#region Issued by a CA that prod trusts
# NOTE: tools/Initialize-Demo.ps1 put the CA into LocalMachine\Root on prod.
Show-Certificate (Get-DemoCertificate CA -PublicOnly)
Invoke-Prod { Get-ChildItem Cert:\LocalMachine\Root | Where-Object Subject -like '*PSConfEU*' }
#endregion

#region Where do certificates come from?
# NOTE: Since 2023 the CA/B Forum requires public code signing keys in an HSM,
# NOTE: no more PFX in a pipeline secret. That's why Artifact Signing matters.
Show-CertificateOptions
#endregion
