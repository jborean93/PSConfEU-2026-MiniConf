# Segment 0 - Cold open (~2 min)
#
# Each '#region <title>' block is one demo step inserted into the prompt by
# F9. '# NOTE:' lines are speaker notes, they aren't inserted into the prompt.

#region Start the clock
# NOTE: Do this before the intro. The prompt starts counting down.
# NOTE: "I just created a certificate that dies in 25 minutes. Remember that."
New-CountdownSignature
#endregion

#region Sign a script on Linux
# NOTE: Plain OpenAuthenticode on Linux. Prod is a Windows box over SSH.
Set-OpenAuthenticodeSignature -Path ./Invoke-Payday.ps1 -Certificate $signer -TimeStampServer $tsa
Copy-ToProd ./Invoke-Payday.ps1
#endregion

#region Windows says it is valid
Invoke-Prod { Get-AuthenticodeSignature .\Invoke-Payday.ps1 }
#endregion

#region Give myself a raise
# NOTE: Chat poll before pressing Enter: still valid? 💥 or ✅
# NOTE: Wait ~15 seconds for the stream delay before revealing.
Invoke-Prod {
    $text = (Get-Content .\Invoke-Payday.ps1 -Raw).Replace('= 1000', '= 9000')
    Set-Content .\Invoke-Payday.ps1 -Value $text -NoNewline -Encoding utf8BOM
    Get-AuthenticodeSignature .\Invoke-Payday.ps1
}
#endregion
