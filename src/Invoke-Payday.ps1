# Pays everyone. What could possibly go wrong?
[CmdletBinding()]
param (
    [Parameter()]
    [decimal]
    $Amount = 1000
)

foreach ($employee in 'Alice', 'Bob', 'Carol') {
    "Paying $employee `$$Amount"
}
