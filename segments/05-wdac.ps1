# Segment 5 - Enforce It: WDAC / App Control (~4 min)
#
# The policy (tools/Enable-DemoWdac.ps1) trusts Windows, pwsh and anything
# chaining to the demo root CA. It applies live, removing it reboots prod.
# The policy stays enforced for the rest of the talk, Reset-Demo.ps1
# -RemoveWdac takes it off again.

#region Stop: Enforce It
# NOTE: Execution policy is a seatbelt, not a lock. WDAC is the lock.
Show-Stop 5
#endregion

#region Before: back to RemoteSigned
# NOTE: Reset execution policy so we only see what WDAC does.
Invoke-Prod {
    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
    $ExecutionContext.SessionState.LanguageMode
}
#endregion

#region Before: an unsigned script
Invoke-Prod { .\wdac\Unsigned.ps1 }
#endregion

#region Enforce the policy
# NOTE: Applies live with CiTool, no reboot. The rule is on the demo ROOT CA, not
# NOTE: a thumbprint. Built from DefaultWindows, so pwsh's own signers are trusted too.
Set-ProdWdac Enforced
#endregion

#region After: the session itself
# NOTE: Interactive sessions aren't trusted code, so ConstrainedLanguage.
Invoke-Prod { $ExecutionContext.SessionState.LanguageMode }
#endregion

#region After: unsigned script
Invoke-Prod { .\wdac\Unsigned.ps1 }
#endregion

#region After: signed script
Invoke-Prod { .\wdac\Signed.ps1 }
#endregion

#region Signed with the renewed certificate
# NOTE: The pinning problem from the last segment is gone, the rule is about the CA.
Copy-Item ./wdac/Unsigned.ps1 ./wdac/Renewed.ps1
Set-OpenAuthenticodeSignature -Path ./wdac/Renewed.ps1 -Certificate $signerRenewed -TimeStampServer $tsa
Copy-ToProd ./wdac/Renewed.ps1 wdac/
Invoke-Prod { .\wdac\Renewed.ps1 }
#endregion

#region Signed script, unsigned helper
# NOTE: Poll: does the signed script lend its trust to what it dot-sources?
Invoke-Prod { .\wdac\PaydayWithHelper.ps1 }
#endregion

#region What got logged
# NOTE: Verify the log name and event ids during rehearsal.
Invoke-Prod {
    Get-WinEvent -LogName 'Microsoft-Windows-AppLocker/MSI and Script' -MaxEvents 5 |
        Select-Object TimeCreated, Id, Message
}
#endregion
