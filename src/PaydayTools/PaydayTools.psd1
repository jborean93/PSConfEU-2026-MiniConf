@{
    RootModule = 'PaydayTools.psm1'
    ModuleVersion = '0.0.0'  # Set from the release tag at build time
    GUID = '5c0a4f9e-3d1b-4f7e-9a51-2b8f0f6d7c41'
    Author = 'Jordan Borean'
    Description = 'Demo module used to show module signing.'
    PowerShellVersion = '7.4'
    FormatsToProcess = @('PaydayTools.Format.ps1xml')
    FunctionsToExport = @('Get-Payslip')
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
}
