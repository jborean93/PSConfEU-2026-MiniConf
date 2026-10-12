# Segment 7 - Sign of the Times (~2 min)

#region Stop: Sign of the Times
# NOTE: "The CI cert dies in 3 days. My countdown cert died a few minutes ago."
Show-Stop 7
#endregion

#region The countdown certificate
Show-Certificate (Get-DemoCertificate Countdown -PublicOnly)
#endregion

#region Moment of truth
# NOTE: Poll first: which one survives?
Invoke-Prod { Get-ChildItem .\countdown\*.ps1 | Get-AuthenticodeSignature }
#endregion

#region Why: the timestamp
# NOTE: The TSA vouched that the signature existed while the cert was valid.
# NOTE: Trivia: the Lifetime Signing EKU (1.3.6.1.4.1.311.10.3.13) opts out of this.
Show-AuthenticodeAnatomy ./countdown/WithTimestamp.ps1 -Expand When
Show-AuthenticodeAnatomy ./countdown/NoTimestamp.ps1 -Expand When
#endregion

#region Thanks
Show-Closing
#endregion
