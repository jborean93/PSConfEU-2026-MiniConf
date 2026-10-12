# Segment 7 - Sign of the Times (~2 min)

#region Stop: Sign of the Times
# NOTE: "The CI cert dies in 3 days. My countdown cert died a few minutes ago."
Show-Stop 7
#endregion

#region The countdown certificate
<#
The certificate created at the very start of the talk. Make sure it has
expired, waiting if the talk ran faster than 25 minutes, then look at it.
#>
Wait-CountdownExpiry
Show-Certificate (Get-PfxCertificate -FilePath ../certs/Countdown.cer)
#endregion

#region Moment of truth
# NOTE: Poll first: which one survives?
<#
Both scripts were signed with that certificate while it was still valid, one
with a timestamp and one without. Ask Windows about both now, as a list so the
full status message is shown.
#>
Invoke-Prod {
    Get-ChildItem .\countdown\*.ps1 |
        Get-AuthenticodeSignature |
        Select-Object Path, Status, StatusMessage
} | Format-List
#endregion

#region Why: the timestamp
# NOTE: Trivia: the Lifetime Signing EKU (1.3.6.1.4.1.311.10.3.13) opts out of this.
<#
The timestamp authority vouched that the signature existed while the
certificate was still valid, so the signature stays valid after the
certificate expires. Without a timestamp, it dies with the certificate.
Compare the certificate's validity under WHO and the timestamp under WHEN with
the current time.
#>
"Current time: $([DateTime]::UtcNow.ToString('yyyy-MM-dd HH:mm:ss')) UTC"
Show-AuthenticodeAnatomy ./countdown/WithTimestamp.ps1 -Expand Who, When
Show-AuthenticodeAnatomy ./countdown/NoTimestamp.ps1 -Expand Who, When
#endregion

#region Thanks
Show-Closing
#endregion
