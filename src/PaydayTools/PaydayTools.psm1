Function Get-Payslip {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]
        $Employee,

        [Parameter()]
        [decimal]
        $Amount = 1000
    )

    [PSCustomObject]@{
        PSTypeName = 'PaydayTools.Payslip'
        Employee = $Employee
        Amount = $Amount
        PaidOn = [DateTime]::Today
    }
}
