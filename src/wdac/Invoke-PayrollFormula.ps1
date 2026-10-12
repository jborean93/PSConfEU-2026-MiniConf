# Signed by Reset-Demo.ps1 so it runs in FullLanguage under WDAC. It turns the
# caller's string into code without validating it.
[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [string]
    $Formula
)

"Language mode: $($ExecutionContext.SessionState.LanguageMode)"

$calculation = [ScriptBlock]::Create($Formula)
"Result: $(& $calculation)"
