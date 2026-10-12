# Segment 3 - Signing scripts and modules (~3 min)

#region Stop: Signing
Show-Stop 3
#endregion

#region Sign every file in a module
# NOTE: .ps1, .psm1, .psd1 and .ps1xml all get signed. Don't forget the psd1.
# NOTE: On Windows: Set-AuthenticodeSignature -HashAlgorithm SHA256 -TimestampServer ...
Get-ChildItem ./PaydayTools
Set-OpenAuthenticodeSignature -Path ./PaydayTools/* -Certificate $signer -TimeStampServer $tsa
#endregion

#region XML files get an XML comment block
Get-Content ./PaydayTools/PaydayTools.Format.ps1xml -Tail 3
#endregion

#region Verify on Linux
Get-OpenAuthenticodeSignature -Path ./PaydayTools/* -TrustStore $trustStore |
    Select-Object Path, HashAlgorithm, @{ N = 'Signer'; E = { $_.Certificate.Subject } }
#endregion

#region Verify on prod
Copy-ToProd ./PaydayTools modules/
Invoke-Prod { Get-ChildItem .\modules\PaydayTools | Get-AuthenticodeSignature }
#endregion

#region Optional: catalog files
# NOTE: Optional, only if there is time. A catalog covers every file in the module,
# NOTE: even ones that can't hold a signature. Sign the .cat on Windows to finish.
Invoke-Prod {
    $catParams = @{
        Path = '.\modules\PaydayTools'
        CatalogFilePath = '.\modules\PaydayTools.cat'
    }
    $null = New-FileCatalog @catParams -CatalogVersion 2.0
    Add-Content .\modules\PaydayTools\PaydayTools.psm1 -Value '# sneaky'
    Test-FileCatalog @catParams
}
#endregion
