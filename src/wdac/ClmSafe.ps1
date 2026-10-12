# Left unsigned on purpose, only uses what ConstrainedLanguage allows.
"Language mode: $($ExecutionContext.SessionState.LanguageMode)"

$employees = 'Jordan', 'Gael', 'Geoffroy'
foreach ($employee in $employees) {
    "Paying $employee `$1000"
}

"Total: `$$($employees.Count * 1000) on $(Get-Date -Format 'yyyy-MM-dd')"
