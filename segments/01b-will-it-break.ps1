# Segment 1b - Will it break? (pick 3-4 live, keep the rest for Q&A)
#
# Every case starts from a pristine signed copy on prod and asks the native
# Get-AuthenticodeSignature for the verdict. Verify every answer during
# rehearsal, they are the reveals. Skip ahead with: Set-DemoStep -Segment 02-

#region Will it break? Setup
<#
Copy the signed script to prod again, every case below starts from this
pristine copy and only changes one thing.
#>
Copy-ToProd ./Invoke-Payday.ps1 wib/
Invoke-Prod { Get-AuthenticodeSignature .\wib\Invoke-Payday.ps1 }
#endregion

#region Will it break? Edit a comment
# NOTE: Poll first.
<#
Only change the comment on the first line of the script, the code itself stays
exactly the same. Comments are part of the script text that gets hashed.
#>
Invoke-Prod {
    $originalComment = '# Pays everyone. What could possibly go wrong?'
    $editedComment = '# Pays everyone. Nothing can go wrong!'

    $text = (Get-Content .\wib\Invoke-Payday.ps1 -Raw).Replace($originalComment, $editedComment)
    Set-Content .\wib\Comment.ps1 -Value $text -NoNewline -Encoding utf8BOM
    Get-AuthenticodeSignature .\wib\Comment.ps1
}
#endregion

#region Will it break? Rename the file
# NOTE: Poll first.
<#
Copy the script to a different file name, the content is untouched. The file
name isn't part of what gets signed.
#>
Invoke-Prod {
    Copy-Item .\wib\Invoke-Payday.ps1 .\wib\Invoke-PayRise.ps1
    Get-AuthenticodeSignature .\wib\Invoke-PayRise.ps1
}
#endregion

#region Will it break? git autocrlf (LF to CRLF)
# NOTE: Poll first. The classic "works on my machine, broken after clone".
# NOTE: Fix is .gitattributes, this repo marks src/** as -text.
<#
The script was written on Linux with LF line endings. Git on Windows with
core.autocrlf converts them to CRLF on checkout, simulate that by converting
every line ending to CRLF.
#>
Invoke-Prod {
    $text = (Get-Content .\wib\Invoke-Payday.ps1 -Raw) -replace '\r?\n', "`r`n"
    Set-Content .\wib\Crlf.ps1 -Value $text -NoNewline -Encoding utf8BOM
    Get-AuthenticodeSignature .\wib\Crlf.ps1
}
#endregion

#region Will it break? Remove the BOM
# NOTE: Poll first. The BOM char is part of the hashed text.
<#
Save the same text as UTF-8 without a byte order mark. Nothing visible changes
in an editor, only the 3 BOM bytes at the start of the file are gone.
#>
Invoke-Prod {
    Get-Content .\wib\Invoke-Payday.ps1 -Raw | Set-Content .\wib\NoBom.ps1 -NoNewline -Encoding utf8NoBOM
    Get-AuthenticodeSignature .\wib\NoBom.ps1
}
#endregion

#region Will it break? Re-save as UTF-16
# NOTE: Poll first. Every byte changes but the decoded text (BOM included) is
# NOTE: identical, the SIP hashes text not bytes. Verify this one on the day!
<#
Save the same text as UTF-16LE with a BOM. Every byte in the file is different
but the text, including the BOM character, is the same.
#>
Invoke-Prod {
    Get-Content .\wib\Invoke-Payday.ps1 -Raw | Set-Content .\wib\Utf16.ps1 -NoNewline -Encoding Unicode
    Get-AuthenticodeSignature .\wib\Utf16.ps1
}
#endregion

#region Will it break? Mark of the Web
# NOTE: Poll first. Matters for RemoteSigned in the Trust segment.
<#
Mark the file as downloaded from the internet. Mark of the Web is just an
alternate data stream called Zone.Identifier next to the file content.
#>
Invoke-Prod {
    Copy-Item .\wib\Invoke-Payday.ps1 .\wib\Downloaded.ps1
    Set-Content .\wib\Downloaded.ps1 -Stream Zone.Identifier -Value "[ZoneTransfer]`r`nZoneId=3"
    Get-AuthenticodeSignature .\wib\Downloaded.ps1
}
#endregion

#region Will it break? Change the modified date
# NOTE: Poll first.
<#
Only change the file's last modified time, the content is untouched.
#>
Invoke-Prod {
    Copy-Item .\wib\Invoke-Payday.ps1 .\wib\Old.ps1
    (Get-Item .\wib\Old.ps1).LastWriteTime = '1999-12-31'
    Get-AuthenticodeSignature .\wib\Old.ps1
}
#endregion

#region Will it break? Whitespace after the signature block
# NOTE: Poll first. Only newlines are tolerated after the end marker.
<#
Append a line of spaces after the 'SIG # End signature block' marker. The
signed script text before the signature block is unchanged.
#>
Invoke-Prod {
    Copy-Item .\wib\Invoke-Payday.ps1 .\wib\Trailing.ps1
    Add-Content .\wib\Trailing.ps1 -Value '   '
    Get-AuthenticodeSignature .\wib\Trailing.ps1
}
#endregion
