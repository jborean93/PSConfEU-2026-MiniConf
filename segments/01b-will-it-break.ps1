# Segment 1b - Will it break? (pick 3-4 live, keep the rest for Q&A)
#
# Every case starts from a pristine signed copy on prod and asks the native
# Get-AuthenticodeSignature for the verdict. Verify every answer during
# rehearsal, they are the reveals. Skip ahead with: Set-DemoStep -Segment 02-

#region Will it break? Setup
Copy-ToProd ./Invoke-Payday.ps1 wib/
Invoke-Prod { Get-AuthenticodeSignature .\wib\Invoke-Payday.ps1 }
#endregion

#region Will it break? Edit a comment
# NOTE: Poll 💥 or ✅
Invoke-Prod {
    $text = (Get-Content .\wib\Invoke-Payday.ps1 -Raw).Replace('What could possibly go wrong?', 'Nothing!')
    Set-Content .\wib\Comment.ps1 -Value $text -NoNewline -Encoding utf8BOM
    Get-AuthenticodeSignature .\wib\Comment.ps1
}
#endregion

#region Will it break? Rename the file
# NOTE: Poll 💥 or ✅
Invoke-Prod {
    Copy-Item .\wib\Invoke-Payday.ps1 .\wib\Invoke-PayRise.ps1
    Get-AuthenticodeSignature .\wib\Invoke-PayRise.ps1
}
#endregion

#region Will it break? git autocrlf (LF to CRLF)
# NOTE: Poll 💥 or ✅. The classic "works on my machine, broken after clone".
# NOTE: Fix is .gitattributes, this repo marks src/** as -text.
Invoke-Prod {
    $text = (Get-Content .\wib\Invoke-Payday.ps1 -Raw) -replace '(?<!\r)\n', "`r`n"
    Set-Content .\wib\Crlf.ps1 -Value $text -NoNewline -Encoding utf8BOM
    Get-AuthenticodeSignature .\wib\Crlf.ps1
}
#endregion

#region Will it break? Remove the BOM
# NOTE: Poll 💥 or ✅. The BOM char is part of the hashed text.
Invoke-Prod {
    Get-Content .\wib\Invoke-Payday.ps1 -Raw | Set-Content .\wib\NoBom.ps1 -NoNewline -Encoding utf8NoBOM
    Get-AuthenticodeSignature .\wib\NoBom.ps1
}
#endregion

#region Will it break? Re-save as UTF-16
# NOTE: Poll 💥 or ✅. Every byte changes but the decoded text (BOM included) is
# NOTE: identical, the SIP hashes text not bytes. Verify this one on the day!
Invoke-Prod {
    Get-Content .\wib\Invoke-Payday.ps1 -Raw | Set-Content .\wib\Utf16.ps1 -NoNewline -Encoding Unicode
    Get-AuthenticodeSignature .\wib\Utf16.ps1
}
#endregion

#region Will it break? Mark of the Web
# NOTE: Poll 💥 or ✅. "Downloaded" is just an alternate data stream. Matters for
# NOTE: RemoteSigned in the Trust segment.
Invoke-Prod {
    Copy-Item .\wib\Invoke-Payday.ps1 .\wib\Downloaded.ps1
    Set-Content .\wib\Downloaded.ps1 -Stream Zone.Identifier -Value "[ZoneTransfer]`r`nZoneId=3"
    Get-AuthenticodeSignature .\wib\Downloaded.ps1
}
#endregion

#region Will it break? Change the modified date
# NOTE: Poll 💥 or ✅
Invoke-Prod {
    Copy-Item .\wib\Invoke-Payday.ps1 .\wib\Old.ps1
    (Get-Item .\wib\Old.ps1).LastWriteTime = '1999-12-31'
    Get-AuthenticodeSignature .\wib\Old.ps1
}
#endregion

#region Will it break? Whitespace after the signature block
# NOTE: Poll 💥 or ✅. Only newlines are tolerated after the end marker.
Invoke-Prod {
    Copy-Item .\wib\Invoke-Payday.ps1 .\wib\Trailing.ps1
    Add-Content .\wib\Trailing.ps1 -Value '   '
    Get-AuthenticodeSignature .\wib\Trailing.ps1
}
#endregion
