# Pays everyone. What could possibly go wrong?
[CmdletBinding()]
param (
    [Parameter()]
    [decimal]
    $Amount = 1000
)

foreach ($employee in 'Jordan', 'Gael', 'Geoffroy') {
    "Paying $employee `$$Amount"
}
