# Signed by Reset-Demo.ps1 but dot-sources the unsigned Helper.ps1.
"Language mode: $($ExecutionContext.SessionState.LanguageMode)"

. $PSScriptRoot\Helper.ps1
Get-PayrollTotal
