function Write-HuDiagnosticsProgress {
    param(
        [object]$ProgressQueue,
        [AllowEmptyString()][string]$Text='',
        [ValidateSet('Normal','Success','Error')][string]$Level='Normal',
        [AllowEmptyString()][string]$Key='',
        [object[]]$Args=@(),
        [AllowEmptyString()][string]$Prefix=''
    )
    if (-not $ProgressQueue) { return }
    if (-not [string]::IsNullOrWhiteSpace($Key)) {
        $ProgressQueue.Enqueue([pscustomobject]@{Key=$Key;Args=@($Args);Prefix=$Prefix;Level=$Level})
    }
    else {
        $ProgressQueue.Enqueue([pscustomobject]@{Text=$Text;Level=$Level})
    }
}

function Get-HuDiagnosticsState {
    $crashPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl'
    $systemPolicyPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
    $displayParameters = 0
    $verboseStatus = 0
    try { $displayParameters = [int](Get-ItemPropertyValue -LiteralPath $crashPath -Name 'DisplayParameters' -ErrorAction Stop) } catch { }
    try { $verboseStatus = [int](Get-ItemPropertyValue -LiteralPath $systemPolicyPath -Name 'VerboseStatus' -ErrorAction Stop) } catch { }

    $legacyBootMenu = $false
    try {
        $bcdedit = Join-Path (Get-HuNativeSystemDirectory) 'bcdedit.exe'
        $bcdText = (& $bcdedit /enum '{current}' 2>$null | Out-String)
        $legacyBootMenu = $bcdText -match '(?im)bootmenupolicy\s+Legacy\s*$'
    }
    catch { }

    [pscustomobject]@{
        BootDetails  = ($displayParameters -eq 1) -and $legacyBootMenu
        VerboseLogon = $verboseStatus -eq 1
    }
}

function Set-HuBootDiagnostics {
    param([Parameter(Mandatory=$true)][bool]$Enabled,[object]$ProgressQueue)
    if (-not (Test-HuAdministrator)) { throw 'AdministratorRequired' }

    $crashPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl'
    Write-HuDiagnosticsProgress $ProgressQueue '[REG] CrashControl\DisplayParameters'
    if (-not (Test-Path -LiteralPath $crashPath)) { New-Item -Path $crashPath -Force | Out-Null }
    New-ItemProperty -LiteralPath $crashPath -Name 'DisplayParameters' -PropertyType DWord -Value $(if ($Enabled) { 1 } else { 0 }) -Force | Out-Null

    $bcdedit = Get-HuSystemExecutablePath 'bcdedit.exe'
    $commands = if ($Enabled) {
        @(@('/set','{current}','bootmenupolicy','Legacy'), @('/set','{current}','bootlog','Yes'), @('/set','{current}','sos','Yes'))
    } else {
        @(@('/set','{current}','bootmenupolicy','Standard'), @('/set','{current}','bootlog','No'), @('/set','{current}','sos','No'))
    }
    foreach ($arguments in $commands) {
        Write-HuDiagnosticsProgress $ProgressQueue ('[CMD] bcdedit {0}' -f ($arguments -join ' '))
        & $bcdedit @arguments 2>&1 | ForEach-Object { Write-HuDiagnosticsProgress $ProgressQueue ([string]$_) }
        if ($LASTEXITCODE -ne 0) { throw ('CommandFailedWithCode:{0}' -f $LASTEXITCODE) }
    }
    Write-HuDiagnosticsProgress $ProgressQueue '[VERIFY] BootDiagnostics'
    $verified = (Get-HuDiagnosticsState).BootDetails -eq $Enabled
    Write-HuDiagnosticsProgress -ProgressQueue $ProgressQueue -Key $(if($verified){'ChangeVerified'}else{'ChangeNotVerified'}) -Prefix $(if($verified){'[OK]'}else{'[FAIL]'}) -Level $(if($verified){'Success'}else{'Error'})
    [pscustomobject]@{ Enabled=$Enabled; Verified=$verified; RestartRequired=$true }
}

function Set-HuVerboseLogonStatus {
    param([Parameter(Mandatory=$true)][bool]$Enabled,[object]$ProgressQueue)
    if (-not (Test-HuAdministrator)) { throw 'AdministratorRequired' }

    $path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
    Write-HuDiagnosticsProgress $ProgressQueue '[REG] Policies\System\VerboseStatus'
    if (-not (Test-Path -LiteralPath $path)) { New-Item -Path $path -Force | Out-Null }
    New-ItemProperty -LiteralPath $path -Name 'VerboseStatus' -PropertyType DWord -Value $(if ($Enabled) { 1 } else { 0 }) -Force | Out-Null
    New-ItemProperty -LiteralPath $path -Name 'DisableStatusMessages' -PropertyType DWord -Value 0 -Force | Out-Null
    Write-HuDiagnosticsProgress $ProgressQueue '[VERIFY] VerboseStatus'
    $verified = (Get-HuDiagnosticsState).VerboseLogon -eq $Enabled
    Write-HuDiagnosticsProgress -ProgressQueue $ProgressQueue -Key $(if($verified){'ChangeVerified'}else{'ChangeNotVerified'}) -Prefix $(if($verified){'[OK]'}else{'[FAIL]'}) -Level $(if($verified){'Success'}else{'Error'})
    [pscustomobject]@{ Enabled=$Enabled; Verified=$verified; RestartRequired=$false }
}

function New-HuSystemRestorePoint {
    param([string]$Description = 'WNST - Point de restauration',[object]$ProgressQueue)
    if (-not (Test-HuAdministrator)) { throw 'AdministratorRequired' }

    $systemDrive = [IO.Path]::GetPathRoot($env:SystemRoot).TrimEnd('\') + '\'
    $frequencyPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore'
    $frequencyName = 'SystemRestorePointCreationFrequency'
    $frequencyExists = $false
    $frequencyValue = $null
    try { $frequencyValue = Get-ItemPropertyValue -LiteralPath $frequencyPath -Name $frequencyName -ErrorAction Stop; $frequencyExists = $true } catch { }
    $startedAt = Get-Date

    try {
        Write-HuDiagnosticsProgress -ProgressQueue $ProgressQueue -Key 'RestorePointDescription' -Prefix '[START]'
        Write-HuDiagnosticsProgress $ProgressQueue ('[SYSTEM] Enable-ComputerRestore {0}' -f $systemDrive)
        Enable-ComputerRestore -Drive $systemDrive -ErrorAction Stop
        if (-not (Test-Path -LiteralPath $frequencyPath)) { New-Item -Path $frequencyPath -Force | Out-Null }
        Write-HuDiagnosticsProgress $ProgressQueue '[REG] SystemRestorePointCreationFrequency = 0'
        New-ItemProperty -LiteralPath $frequencyPath -Name $frequencyName -PropertyType DWord -Value 0 -Force | Out-Null

        $returnValue = [uint32]0
        try {
            Write-HuDiagnosticsProgress $ProgressQueue '[CMD] Checkpoint-Computer'
            Checkpoint-Computer -Description $Description -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
        }
        catch {
            Write-HuDiagnosticsProgress $ProgressQueue ('[CHECK] Checkpoint-Computer -> {0}' -f $_.Exception.Message)
            Write-HuDiagnosticsProgress $ProgressQueue '[CMD] SystemRestore.CreateRestorePoint'
            $creation = Invoke-CimMethod -Namespace 'root/default' -ClassName 'SystemRestore' -MethodName 'CreateRestorePoint' -Arguments @{Description=$Description;RestorePointType=[uint32]12;EventType=[uint32]100} -ErrorAction Stop
            $returnValue = [uint32]$creation.ReturnValue
            if ($returnValue -ne 0) { throw ('SystemRestoreReturnCode:{0}' -f $returnValue) }
        }

        Write-HuDiagnosticsProgress $ProgressQueue '[VERIFY] Get-ComputerRestorePoint'
        $latest = Get-ComputerRestorePoint -ErrorAction Stop | Where-Object { [string]$_.Description -eq $Description } | Sort-Object SequenceNumber -Descending | Select-Object -First 1
        $created = $null -ne $latest
        Write-HuDiagnosticsProgress -ProgressQueue $ProgressQueue -Key $(if($created){'RestorePointCreated'}else{'ChangeNotVerified'}) -Prefix $(if($created){'[OK]'}else{'[FAIL]'}) -Level $(if($created){'Success'}else{'Error'})
        [pscustomobject]@{ Created=$created; Description=$(if($latest){[string]$latest.Description}else{$Description});ReturnValue=$returnValue;StartedAt=$startedAt }
    }
    finally {
        try {
            if ($frequencyExists) { New-ItemProperty -LiteralPath $frequencyPath -Name $frequencyName -PropertyType DWord -Value $frequencyValue -Force | Out-Null }
            else { Remove-ItemProperty -LiteralPath $frequencyPath -Name $frequencyName -ErrorAction SilentlyContinue }
            Write-HuDiagnosticsProgress $ProgressQueue '[REG] SystemRestorePointCreationFrequency -> VERIFIED' 'Success'
        }
        catch { Write-HuDiagnosticsProgress $ProgressQueue ('[FAIL] SystemRestorePointCreationFrequency -> {0}' -f $_.Exception.Message) 'Error' }
    }
}

function Open-HuSystemRestore {
    $path = Get-HuSystemExecutablePath 'rstrui.exe'
    Start-Process -FilePath $path | Out-Null
}
