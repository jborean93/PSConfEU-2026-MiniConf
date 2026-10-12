Function Get-DemoConfig {
    [CmdletBinding()]
    param ()

    $script:Config
}

Function Get-DemoPath {
    <#
    .SYNOPSIS
    Gets a path relative to the repo root.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Position = 0)]
        [string[]]
        $ChildPath = @()
    )

    $path = $script:RepoRoot
    foreach ($child in $ChildPath) {
        $path = Join-Path $path $child
    }
    $path
}

Function Get-DemoSshKey {
    <#
    .SYNOPSIS
    Gets the path to the demo's own SSH private key, generating it on first
    use. Nothing in ~/.ssh is used for the demo.
    #>
    [CmdletBinding()]
    param ()

    $keyPath = Join-Path $script:StatePath 'ssh' 'id_ed25519'
    if (-not (Test-Path -LiteralPath $keyPath)) {
        $null = New-Item -Path (Split-Path -Path $keyPath -Parent) -ItemType Directory -Force
        ssh-keygen -q -t ed25519 -N '' -C 'psconfeu-demo' -f $keyPath
        if ($LASTEXITCODE) {
            throw "ssh-keygen failed with exit code $LASTEXITCODE"
        }
    }

    $keyPath
}

Function Get-DemoSshPath {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, Position = 0)]
        [ValidateSet('Config', 'KnownHosts', 'AskPass')]
        [string]
        $Name
    )

    $file = @{ Config = 'config'; KnownHosts = 'known_hosts'; AskPass = 'askpass.sh' }[$Name]
    Join-Path $script:StatePath 'ssh' $file
}

Function Initialize-DemoSshConfig {
    <#
    .SYNOPSIS
    Writes the demo's own SSH config and known_hosts so 'ssh win-prod' works
    without touching ~/.ssh.

    .DESCRIPTION
    The prod host key is scanned once and pinned in state/ssh/known_hosts,
    connections then use StrictHostKeyChecking. Also writes an SSH_ASKPASS
    helper that echoes the password from an environment variable so the first
    connection can use password auth without a prompt.
    #>
    [CmdletBinding()]
    param ()

    $computerName = $script:Config.ProdComputerName
    $keyPath = Get-DemoSshKey
    $knownHosts = Get-DemoSshPath KnownHosts

    $hostKeys = ssh-keyscan -T 10 $computerName 2>$null | Where-Object { $_ -and -not $_.StartsWith('#') }
    if (-not $hostKeys) {
        throw "Failed to get the SSH host keys for '$computerName'"
    }
    $hostKeys | Set-Content -LiteralPath $knownHosts

    @"
Host $($script:Config.ProdHost)
    HostName $computerName
    User $($script:Config.ProdUserName)
    IdentityFile $keyPath
    IdentitiesOnly yes
    UserKnownHostsFile $knownHosts
    StrictHostKeyChecking yes
    # Win32-OpenSSH has no post-quantum key exchange yet, don't warn about it
    # on every connection during the talk.
    WarnWeakCrypto no
"@ | Set-Content -LiteralPath (Get-DemoSshPath Config)

    $askPass = Get-DemoSshPath AskPass
    @'
#!/bin/sh
printf '%s
' "$PSCONFEU_SSH_PASSWORD"
'@ | Set-Content -LiteralPath $askPass
    chmod 700 $askPass
}

Function Get-DemoSshArgument {
    # The demo SSH config replaces ~/.ssh/config, only the demo key and known
    # hosts are used.
    $config = Get-DemoSshPath Config
    if (-not (Test-Path -LiteralPath $config)) {
        throw 'No demo SSH config found, run tools/Initialize-Demo.ps1 first'
    }
    @('-F', $config)
}

Function ssh {
    <#
    .SYNOPSIS
    Runs the real ssh client with the demo SSH config so the demo steps can
    use a plain 'ssh win-prod' command.
    #>
    $sshExe = Get-Command -Name ssh -CommandType Application | Select-Object -First 1

    # Only redirect stdin when something is piped in, 'ssh -t' needs the
    # terminal.
    if ($MyInvocation.ExpectingInput) {
        $input | & $sshExe @(Get-DemoSshArgument) @args
    }
    else {
        & $sshExe @(Get-DemoSshArgument) @args
    }
}

Function Get-ProdSession {
    <#
    .SYNOPSIS
    Gets the cached PSSession to the prod host, creating it if needed.
    #>
    [CmdletBinding()]
    param ()

    if (-not $script:Config.ProdComputerName) {
        throw 'No prod host configured, run tools/Initialize-Demo.ps1 first'
    }

    if (-not $script:ProdSession -or $script:ProdSession.State -ne 'Opened') {
        $sessionParams = @{
            # New-PSSession can't use the SSH config file, pass the same
            # settings directly.
            HostName = $script:Config.ProdComputerName
            UserName = $script:Config.ProdUserName
            KeyFilePath = Get-DemoSshKey
            Options = @{
                IdentitiesOnly = 'yes'
                UserKnownHostsFile = Get-DemoSshPath KnownHosts
                StrictHostKeyChecking = 'yes'
                WarnWeakCrypto = 'no'
            }
        }
        $script:ProdSession = New-PSSession @sessionParams
        Invoke-Command -Session $script:ProdSession -ScriptBlock {
            param ($Path)
            $null = New-Item -Path $Path -ItemType Directory -Force
            Set-Location -LiteralPath $Path
        } -ArgumentList $script:Config.ProdPath
    }

    $script:ProdSession
}

Function Reset-ProdSession {
    <#
    .SYNOPSIS
    Closes the cached prod session so the next call starts a fresh process.
    Needed after WDAC changes as the language mode is set at process start.
    #>
    [CmdletBinding()]
    param ()

    if ($script:ProdSession) {
        $script:ProdSession | Remove-PSSession -ErrorAction SilentlyContinue
        $script:ProdSession = $null
    }
}

Function Write-ProdBanner {
    [CmdletBinding()]
    param ()

    Write-SpectreHost "[$($script:Colors.Trust)]🪟 prod[/] [$($script:Colors.Dim)]($($script:Config.ProdUserName)@$($script:Config.ProdComputerName))[/]"
}

Function Invoke-Prod {
    <#
    .SYNOPSIS
    Runs a ScriptBlock on the prod host. Output comes back serialized so
    visuals are always rendered locally.

    .NOTES
    Keep the ScriptBlocks ConstrainedLanguage friendly, once WDAC is enforced
    the remote session runs in CLM.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, Position = 0)]
        [ScriptBlock]
        $ScriptBlock,

        [Parameter(ValueFromRemainingArguments)]
        [object[]]
        $ArgumentList = @()
    )

    Write-ProdBanner
    $invokeParams = @{
        Session = Get-ProdSession
        ScriptBlock = $ScriptBlock
        ArgumentList = $ArgumentList
        HideComputerName = $true
    }
    Invoke-Command @invokeParams
}

Function Copy-ToProd {
    <#
    .SYNOPSIS
    Copies local files to the prod demo folder with scp so the bytes are
    unchanged.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, Position = 0)]
        [string[]]
        $Path,

        [Parameter(Position = 1)]
        [string]
        $Destination = ''
    )

    $source = @(Resolve-Path -Path $Path | ForEach-Object ProviderPath)
    $target = "$($script:Config.ProdHost):$($script:Config.ProdPath)/$Destination"

    scp @(Get-DemoSshArgument) -q -r @source $target
    if ($LASTEXITCODE) {
        throw "scp failed with exit code $LASTEXITCODE"
    }

    $names = ($source | Split-Path -Leaf) -join ', '
    Write-SpectreHost "[$($script:Colors.Dim)]📤 $(Get-SpectreEscapedText $names) → prod:$(Get-SpectreEscapedText "$($script:Config.ProdPath)/$Destination")[/]"
}

Function Set-ProdWdac {
    <#
    .SYNOPSIS
    Enforces or removes the demo WDAC policy on prod.

    .DESCRIPTION
    Enforcing copies tools/Enable-DemoWdac.ps1 to prod and runs it, the policy
    applies straight away without a reboot. Removing follows the same steps
    as the ansible.windows tests: CiTool --remove-policy, delete the policy
    file and reboot. Nothing happens if prod is already in the requested
    state.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, Position = 0)]
        [ValidateSet('Enforced', 'Absent')]
        [string]
        $State
    )

    $prodPath = $script:Config.ProdPath
    $isEnforced = Invoke-Prod -ErrorAction Stop {
        param ($ProdPath)
        Test-Path -LiteralPath "$ProdPath/policy/enforced.json"
    } $prodPath
    if ($isEnforced -eq ($State -eq 'Enforced')) {
        Write-SpectreHost "[$($script:Colors.Dim)]WDAC policy is already $State[/]"
        return
    }

    if ($State -eq 'Enforced') {
        Copy-ToProd -Path (Join-Path $script:RepoRoot 'tools' 'Enable-DemoWdac.ps1') -Destination 'policy/'
        Invoke-Prod -ErrorAction Stop {
            param ($ProdPath)
            & "$ProdPath/policy/Enable-DemoWdac.ps1" -CertificatePath "$ProdPath/certs/CA.cer"
        } $prodPath

        # Language mode is decided when the process starts, reconnect so the
        # next Invoke-Prod runs under the policy.
        Reset-ProdSession
        return
    }

    # Plain cmdlets and Windows binaries only, this runs in ConstrainedLanguage.
    Invoke-Prod -ErrorAction Stop {
        param ($ProdPath)

        $marker = "$ProdPath/policy/enforced.json"
        $policy = Get-Content -LiteralPath $marker -Raw | ConvertFrom-Json
        if ($policy.PolicyId -and (Get-Command -Name CiTool.exe -ErrorAction SilentlyContinue)) {
            $null = CiTool.exe --remove-policy $policy.PolicyId
        }
        Remove-Item -LiteralPath $policy.Path -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $marker

        $null = shutdown.exe /r /t 5 /c 'Removing the demo WDAC policy'
    } $prodPath

    Reset-ProdSession
    Wait-ProdReboot
}

Function Wait-ProdReboot {
    <#
    .SYNOPSIS
    Waits for prod to go down and come back with SSH available.
    #>
    [CmdletBinding()]
    param (
        [Parameter()]
        [int]
        $TimeoutSeconds = 300
    )

    $dim = $script:Colors.Dim
    $hostName = $script:Config.ProdComputerName
    $start = [DateTime]::UtcNow
    $testParams = @{
        TargetName = $hostName
        TcpPort = 22
        TimeoutSeconds = 1
        Quiet = $true
    }

    Write-SpectreHost "[$dim]🔄 prod is rebooting...[/]"
    while (Test-Connection @testParams) {
        if (([DateTime]::UtcNow - $start).TotalSeconds -gt 60) {
            throw 'Prod did not go down for the reboot'
        }
        Start-Sleep -Seconds 1
    }

    while ($true) {
        if (([DateTime]::UtcNow - $start).TotalSeconds -gt $TimeoutSeconds) {
            throw "Prod did not come back within $TimeoutSeconds seconds"
        }

        # sshd can accept connections before the user session is usable,
        # keep trying until a session opens.
        if (Test-Connection @testParams) {
            try {
                $null = Get-ProdSession
                break
            }
            catch {
                Reset-ProdSession
            }
        }
        Start-Sleep -Seconds 2
    }

    $elapsed = [int]([DateTime]::UtcNow - $start).TotalSeconds
    Write-SpectreHost "[$($script:Colors.Pass)]✅ prod is back[/] [$dim]($elapsed seconds)[/]"
}
