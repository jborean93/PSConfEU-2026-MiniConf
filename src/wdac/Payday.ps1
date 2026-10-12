# Signed and unsigned copies of this are created by Reset-Demo.ps1.
"Language mode: $($ExecutionContext.SessionState.LanguageMode)"

# Add-Type is blocked in ConstrainedLanguage mode.
Add-Type -TypeDefinition 'public static class Payroll { public static string Run() { return "Payroll ran with full .NET access"; } }'
[Payroll]::Run()
