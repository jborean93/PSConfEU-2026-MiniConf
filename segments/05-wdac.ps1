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

#region Before: language mode and execution policy
# NOTE: Reset execution policy so we only see what WDAC does.
<#
Put the execution policy back to RemoteSigned so it doesn't get in the way and
check the current state of the prod session. Without WDAC everything runs in
FullLanguage.
#>
Invoke-Prod {
    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force

    "Language mode: $($ExecutionContext.SessionState.LanguageMode)"
    "Execution policy: $(Get-ExecutionPolicy)"
}
#endregion

#region Before: an unsigned script
<#
Unsigned.ps1 prints the language mode it runs in and compiles a .NET class
with Add-Type, something only FullLanguage allows. Without WDAC it just works.
#>
Show-DemoFile ./wdac/Unsigned.ps1
Invoke-Prod { .\wdac\Unsigned.ps1 }
#endregion

#region Enforce the policy
# NOTE: Applies live with CiTool, no reboot.
<#
Build a WDAC policy from Microsoft's DefaultWindows_Enforced example, add
signer rules for the demo root CA and pwsh's own signing certificates, and
apply it with CiTool. Script enforcement is on so PowerShell has to honour it.
#>
Set-ProdWdac Enforced
#endregion

#region After: the session itself
# NOTE: Interactive sessions aren't trusted code, so ConstrainedLanguage.
<#
A new session on prod. Interactive input isn't signed code, so PowerShell now
runs it in ConstrainedLanguage. That's also why plain strings are output here,
even [PSCustomObject]@{} isn't allowed in ConstrainedLanguage.
#>
Invoke-Prod {
    "Language mode: $($ExecutionContext.SessionState.LanguageMode)"
    "Execution policy: $(Get-ExecutionPolicy)"
}
#endregion

#region After: unsigned script
<#
The same unsigned script as before. The policy doesn't trust it so it runs in
ConstrainedLanguage and Add-Type is blocked.
#>
Show-DemoFile ./wdac/Unsigned.ps1
Invoke-Prod { .\wdac\Unsigned.ps1 }
#endregion

#region After: unsigned but CLM friendly
<#
WDAC doesn't stop unsigned scripts from running, it limits what they can do.
This unsigned script only uses what ConstrainedLanguage allows so it still
works.
#>
Show-DemoFile ./wdac/ClmSafe.ps1
Invoke-Prod { .\wdac\ClmSafe.ps1 }
#endregion

#region After: signed script
<#
The same code as Unsigned.ps1 but signed by the demo signer, which chains to
the demo root CA the policy trusts. It runs in FullLanguage and Add-Type works.
#>
Show-DemoFile ./wdac/Signed.ps1 -HideSignature
Invoke-Prod { .\wdac\Signed.ps1 }
#endregion

#region Signed with the renewed certificate
# NOTE: The pinning problem from the last segment is gone, the rule is about the CA.
<#
The policy's signer rule is for the demo root CA, not a specific leaf
certificate. Any certificate issued by that CA is trusted, so signing with
the renewed certificate just works without touching the policy. Compare that
with TrustedPublisher, which matched one exact thumbprint.
#>
Copy-Item ./wdac/Unsigned.ps1 ./wdac/Renewed.ps1
Set-OpenAuthenticodeSignature -Path ./wdac/Renewed.ps1 -Certificate $signerRenewed -TimeStampServer $tsa
Copy-ToProd ./wdac/Renewed.ps1 wdac/
Invoke-Prod { .\wdac\Renewed.ps1 }
#endregion

#region Signed script, unsigned helper
# NOTE: Poll: does the signed script lend its trust to what it dot-sources?
<#
A signed script that dot-sources an unsigned helper. The helper would run in
ConstrainedLanguage while the caller is in FullLanguage, PowerShell refuses to
mix the two in the same scope.
#>
Show-DemoFile ./wdac/PaydayWithHelper.ps1 -HideSignature
Show-DemoFile ./wdac/Helper.ps1
Invoke-Prod { .\wdac\PaydayWithHelper.ps1 }
#endregion

#region What got logged
# NOTE: Verify the log name and event ids during rehearsal.
<#
Script enforcement decisions are logged in the AppLocker MSI and Script event
log, useful when working out why something was blocked.
#>
Invoke-Prod {
    Get-WinEvent -LogName 'Microsoft-Windows-AppLocker/MSI and Script' -MaxEvents 5 |
        Select-Object TimeCreated, Id, Message
}
#endregion

#region Signed code, untrusted input
# NOTE: Verify during rehearsal that the created ScriptBlock runs in FullLanguage.
# NOTE: The takeaway: signing gives code full trust, so signed code must treat its
# NOTE: input as untrusted. No Invoke-Expression / [ScriptBlock]::Create on input.
<#
A signed script runs in FullLanguage, and so does any code it builds from a
string. This one turns its -Formula parameter into a ScriptBlock and runs it.
Used as intended it does maths, but the caller is our ConstrainedLanguage
session and it can pass any code it likes. The Add-Type that was blocked
earlier now runs, because it runs as part of trusted code.
#>
Show-DemoFile ./wdac/Invoke-PayrollFormula.ps1 -HideSignature
Invoke-Prod {
    .\wdac\Invoke-PayrollFormula.ps1 -Formula '1000 * 1.1'
    .\wdac\Invoke-PayrollFormula.ps1 -Formula 'Add-Type -TypeDefinition "public static class Pwned { public static int Run() { return 42; } }"; [Pwned]::Run()'
}
#endregion
