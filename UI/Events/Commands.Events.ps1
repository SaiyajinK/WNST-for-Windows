function Add-HuWindowsLogLine {
    param([object]$Item)
    if ($null -eq $Item) { return }
    $text = Resolve-WnstLogItemText -Item $Item
    if ([string]::IsNullOrWhiteSpace($text)) { return }
    $level = if ($Item.PSObject.Properties['Level']) { [string]$Item.Level } else { 'Auto' }
    if ($level -notin @('Auto','Normal','Success','Error')) { $level='Auto' }
    $line = '[{0}] {1}' -f ([DateTime]::Now.ToString('HH:mm:ss')),(ConvertTo-WnstLocalizedLogText -Text $text)
    $spacing = if ($text -match '^\[START\](?:\s|$)') { 2 } else { 1 }
    Add-WnstLogText -Control $WindowsOutputBox -Text $line -Level $level -LeadingNewLines $spacing
}

function Get-HuLocalUserErrorText {
    param([string]$Message)
    if ($script:Translations -and $script:Translations.ContainsKey($Message)) { return T $Message }
    return $Message
}

function Update-HuLocalUserControls {
    $name = [string]$LocalUserNameBox.Text
    $DeleteLocalUserButton.Visibility = 'Collapsed'
    $DeleteLocalUserButton.IsEnabled = $false
    $CreateLocalUserButton.IsEnabled = -not [string]::IsNullOrWhiteSpace($name)
    if ([string]::IsNullOrWhiteSpace($name)) { return }

    try {
        $state = Get-HuLocalUserState -Name $name.Trim()
        if ($state.Exists) {
            $CreateLocalUserButton.IsEnabled = $false
            if ($state.CanDelete) {
                $DeleteLocalUserButton.Content = TF 'DeleteLocalUser' @($state.Name)
                $DeleteLocalUserButton.IsEnabled = $true
                $DeleteLocalUserButton.Visibility = 'Visible'
            }
        }
    }
    catch { }
}

$KillPowerShellButton.Add_Click({
    $others=@(Get-Process -Name 'powershell','pwsh' -ErrorAction SilentlyContinue|Where-Object Id -ne $PID)
    if($others.Count -eq 0){Show-AppInfo (T 'NoOtherPowerShell');return}
    if(-not(Show-AppConfirm (TF 'ConfirmKillPowerShell' @($others.Count)))){return}
    $KillPowerShellButton.IsEnabled=$false
    Add-HuWindowsLogLine ([pscustomobject]@{Text=('[START] {0}' -f (T 'KillPowerShellTitle'));Level='Normal'})
    $worker={param($processIdText,$progressQueue);$stopped=0;foreach($processId in @([string]$processIdText -split ',')){try{Stop-Process -Id ([int]$processId) -Force -ErrorAction Stop;$stopped++;$progressQueue.Enqueue([pscustomobject]@{Text=('[PROC] powershell PID {0} -> STOPPED' -f $processId);Level='Success'})}catch{$progressQueue.Enqueue([pscustomobject]@{Text=('[FAIL] PID {0}: {1}' -f $processId,$_.Exception.Message);Level='Error'})}};[pscustomobject]@{Stopped=$stopped}}
    $queue=[Collections.Concurrent.ConcurrentQueue[object]]::new()
    $progress={param($item)Add-HuWindowsLogLine $item}.GetNewClosure()
    $completed={param($output)$KillPowerShellButton.IsEnabled=$true;$result=@($output)|Where-Object{$_.PSObject.Properties['Stopped']}|Select-Object -Last 1;$message=TF 'PowerShellKilled' @([int]$result.Stopped);Add-HuWindowsLogLine ([pscustomobject]@{Text=('[OK] {0}' -f $message);Level='Success'});Show-AppInfo $message}.GetNewClosure()
    $failed={param($message)$KillPowerShellButton.IsEnabled=$true;Add-HuWindowsLogLine ([pscustomobject]@{Text=('[FAIL] {0}' -f $message);Level='Error'});Show-AppError $message}.GetNewClosure()
    [void](Invoke-HuAsyncWork -Key 'Windows.KillPowerShell' -ScriptBlock $worker -ArgumentList @(($others.Id -join ','),$queue) -OnCompleted $completed -OnError $failed -OnProgress $progress -ProgressQueue $queue -TimeoutSeconds 30 -Replace)
})

$ClearTempButton.Add_Click({
    if(-not(Show-AppConfirm (T 'ConfirmClearTemp'))){return}
    $ClearTempButton.IsEnabled=$false
    Add-HuWindowsLogLine ([pscustomobject]@{Text=('[START] {0}' -f (T 'ClearTempTitle'));Level='Normal'})
    $worker={param($root,$progressQueue);Import-Module (Join-Path $root 'WNST.psd1') -Force;. (Join-Path $root 'Modules\System.ps1');$progressQueue.Enqueue([pscustomobject]@{Text='[SCAN] TEMP';Level='Normal'});Clear-SafeTempFolders}
    $queue=[Collections.Concurrent.ConcurrentQueue[object]]::new()
    $progress={param($item)Add-HuWindowsLogLine $item}.GetNewClosure()
    $completed={param($output)$ClearTempButton.IsEnabled=$true;$result=@($output)|Where-Object{$_.PSObject.Properties['Deleted']}|Select-Object -Last 1;$message=TF 'TempCleared' @([int]$result.Deleted,[int]$result.Skipped);Add-HuWindowsLogLine ([pscustomobject]@{Text=('[OK] {0}' -f $message);Level='Success'});Show-AppInfo $message}.GetNewClosure()
    $failed={param($message)$ClearTempButton.IsEnabled=$true;Add-HuWindowsLogLine ([pscustomobject]@{Text=('[FAIL] {0}' -f $message);Level='Error'});Show-AppError $message}.GetNewClosure()
    [void](Invoke-HuAsyncWork -Key 'Windows.ClearTemp' -ScriptBlock $worker -ArgumentList @($script:AppRoot,$queue) -OnCompleted $completed -OnError $failed -OnProgress $progress -ProgressQueue $queue -TimeoutSeconds 120 -Replace)
})

$RestartExplorerButton.Add_Click({
    if(-not(Show-AppConfirm (T 'ConfirmRestartExplorer'))){return}
    $RestartExplorerButton.IsEnabled=$false
    Add-HuWindowsLogLine ([pscustomobject]@{Text=('[START] {0}' -f (T 'RestartExplorerTitle'));Level='Normal'})
    $worker={param($root,$progressQueue);Import-Module (Join-Path $root 'WNST.psd1') -Force;. (Join-Path $root 'Modules\System.ps1');$progressQueue.Enqueue([pscustomobject]@{Text='[PROC] explorer.exe -> STOP';Level='Normal'});Restart-HuExplorerShell}
    $queue=[Collections.Concurrent.ConcurrentQueue[object]]::new()
    $progress={param($item)Add-HuWindowsLogLine $item}.GetNewClosure()
    $completed={param($output)$RestartExplorerButton.IsEnabled=$true;$message=T 'ExplorerRestarted';Add-HuWindowsLogLine ([pscustomobject]@{Text=('[OK] {0}' -f $message);Level='Success'});Show-AppInfo $message}.GetNewClosure()
    $failed={param($message)$RestartExplorerButton.IsEnabled=$true;Add-HuWindowsLogLine ([pscustomobject]@{Text=('[FAIL] {0}' -f $message);Level='Error'});Show-AppError $message}.GetNewClosure()
    [void](Invoke-HuAsyncWork -Key 'Windows.RestartExplorer' -ScriptBlock $worker -ArgumentList @($script:AppRoot,$queue) -OnCompleted $completed -OnError $failed -OnProgress $progress -ProgressQueue $queue -TimeoutSeconds 30 -Replace)
})

$LocalUserNameBox.Add_TextChanged({ Update-HuLocalUserControls })
$CreateLocalUserButton.Add_Click({
    $name = [string]$LocalUserNameBox.Text
    $CreateLocalUserButton.IsEnabled = $false
    try {
        Add-HuWindowsLogLine ([pscustomobject]@{Text=('[START] {0}: {1}' -f (T 'LocalUserTitle'),$name.Trim());Level='Normal'})
        $result = New-HuLocalUser -Name $name.Trim() -Password ([string]$LocalUserPasswordBox.Password) -Administrator ([bool]$LocalUserAdminCheck.IsChecked)
        $LocalUserPasswordBox.Clear()
        $message = TF 'LocalUserCreated' @($result.Name)
        Add-HuWindowsLogLine ([pscustomobject]@{Text=('[OK] {0}' -f $message);Level='Success'})
        Show-AppInfo $message
    }
    catch {
        $message = Get-HuLocalUserErrorText -Message ([string]$_.Exception.Message)
        Add-HuWindowsLogLine ([pscustomobject]@{Text=('[FAIL] {0}' -f $message);Level='Error'})
        Show-AppError $message
    }
    finally { Update-HuLocalUserControls }
})

$DeleteLocalUserButton.Add_Click({
    $name = [string]$LocalUserNameBox.Text
    if ([string]::IsNullOrWhiteSpace($name) -or -not (Show-AppConfirm (TF 'ConfirmDeleteLocalUser' @($name.Trim())))) { return }
    $DeleteLocalUserButton.IsEnabled = $false
    try {
        Add-HuWindowsLogLine ([pscustomobject]@{Text=('[START] {0}' -f (TF 'DeleteLocalUser' @($name.Trim())));Level='Normal'})
        $result = Remove-HuLocalUser -Name $name.Trim()
        $LocalUserPasswordBox.Clear()
        $message = TF 'LocalUserDeleted' @($result.Name)
        Add-HuWindowsLogLine ([pscustomobject]@{Text=('[OK] {0}' -f $message);Level='Success'})
        Show-AppInfo $message
    }
    catch {
        $message = Get-HuLocalUserErrorText -Message ([string]$_.Exception.Message)
        Add-HuWindowsLogLine ([pscustomobject]@{Text=('[FAIL] {0}' -f $message);Level='Error'})
        Show-AppError $message
    }
    finally { Update-HuLocalUserControls }
})

Update-HuLocalUserControls

function Get-HuKnownSafeModeBootDescriptions {
    $descriptions = New-Object 'System.Collections.Generic.List[string]'
    foreach ($localeFile in @(Get-ChildItem -LiteralPath (Join-Path $script:AppRoot 'Locales') -Filter '*.json' -File -ErrorAction SilentlyContinue)) {
        try {
            $locale = [IO.File]::ReadAllText($localeFile.FullName,[Text.Encoding]::UTF8) | ConvertFrom-Json -ErrorAction Stop
            $description = [string]$locale.SafeModeBootDescription
            if (-not [string]::IsNullOrWhiteSpace($description) -and -not $descriptions.Contains($description)) { $descriptions.Add($description) }
        }
        catch { }
    }
    return @($descriptions)
}

function Set-HuSafeModeBootControlsAbsent {
    $SafeModeBootButton.Visibility = 'Visible'
    $SafeModeBootButton.IsEnabled = $true
    $DeleteSafeModeBootButton.Visibility = 'Collapsed'
    $DeleteSafeModeBootButton.IsEnabled = $false
    $DeleteSafeModeBootButton.Tag = $null
}

function Update-HuSafeModeBootControls {
    Set-HuSafeModeBootControlsAbsent
    try {
        $state = Get-HuSafeModeBootEntryState -Descriptions @(Get-HuKnownSafeModeBootDescriptions)
        if ($state.Exists) {
            $SafeModeBootButton.Visibility = 'Collapsed'
            $DeleteSafeModeBootButton.Tag = [string]$state.Guid
            $DeleteSafeModeBootButton.IsEnabled = $true
            $DeleteSafeModeBootButton.Visibility = 'Visible'
        }
    }
    catch { }
}

$SafeModeBootButton.Add_Click({
    $SafeModeBootButton.IsEnabled = $false
    $description = T 'SafeModeBootDescription'
    try {
        Add-HuWindowsLogLine ([pscustomobject]@{Text=('[START] {0}' -f (T 'SafeModeBootTitle'));Level='Normal'})
        $result = Add-HuSafeModeBootEntry -Description $description
        Add-HuWindowsLogLine ([pscustomobject]@{Text=('[OK] {0} | {1}' -f $result.Description,$result.Guid);Level='Success'})
        Show-AppInfo (TF 'SafeModeBootCreated' @($result.Description))
    }
    catch {
        $message = Get-HuLocalUserErrorText -Message ([string]$_.Exception.Message)
        Add-HuWindowsLogLine ([pscustomobject]@{Text=('[FAIL] {0}' -f $message);Level='Error'})
        Show-AppError $message
    }
    finally { Update-HuSafeModeBootControls }
})

$DeleteSafeModeBootButton.Add_Click({
    $DeleteSafeModeBootButton.IsEnabled = $false
    $removedSuccessfully = $false
    try {
        Add-HuWindowsLogLine ([pscustomobject]@{Text=('[START] {0}' -f (T 'SafeModeBootDeleteTitle'));Level='Normal'})
        $result = Remove-HuSafeModeBootEntry -Guid ([string]$DeleteSafeModeBootButton.Tag)
        $removedSuccessfully = $true
        $message = T 'SafeModeBootDeleted'
        Add-HuWindowsLogLine ([pscustomobject]@{Text=('[OK] {0} | {1}' -f $message,$result.Guid);Level='Success'})
        Show-AppInfo $message
    }
    catch {
        $message = Get-HuLocalUserErrorText -Message ([string]$_.Exception.Message)
        Add-HuWindowsLogLine ([pscustomobject]@{Text=('[FAIL] {0}' -f $message);Level='Error'})
        Show-AppError $message
    }
    finally {
        if ($removedSuccessfully) { Set-HuSafeModeBootControlsAbsent }
        else { Update-HuSafeModeBootControls }
    }
})

Update-HuSafeModeBootControls

$ShutdownButton.Add_Click({if(Show-AppConfirm (T 'ConfirmShutdown')){try{Add-HuWindowsLogLine ([pscustomobject]@{Text='[CMD] shutdown.exe /s /t 0';Level='Normal'});Start-Process (Join-Path $env:SystemRoot 'System32\shutdown.exe') -ArgumentList '/s','/t','0'}catch{Add-HuWindowsLogLine ([pscustomobject]@{Text=('[FAIL] {0}' -f $_.Exception.Message);Level='Error'});Show-AppError $_.Exception.Message}}})
$RestartComputerButton.Add_Click({if(Show-AppConfirm (T 'ConfirmRestartComputer')){try{Add-HuWindowsLogLine ([pscustomobject]@{Text='[CMD] shutdown.exe /r /t 0';Level='Normal'});Start-Process (Join-Path $env:SystemRoot 'System32\shutdown.exe') -ArgumentList '/r','/t','0'}catch{Add-HuWindowsLogLine ([pscustomobject]@{Text=('[FAIL] {0}' -f $_.Exception.Message);Level='Error'});Show-AppError $_.Exception.Message}}})
$MsConfigButton.Add_Click({Open-HuSystemTool (Join-Path $env:SystemRoot 'System32\msconfig.exe')})
$ServicesButton.Add_Click({Open-HuSystemTool (Join-Path $env:SystemRoot 'System32\services.msc')})
$GroupPolicyButton.Add_Click({Open-HuSystemTool (Join-Path $env:SystemRoot 'System32\gpedit.msc')})
$RegeditButton.Add_Click({Open-HuSystemTool (Join-Path $env:SystemRoot 'regedit.exe')})
$TaskSchedulerButton.Add_Click({Open-HuSystemTool (Join-Path $env:SystemRoot 'System32\taskschd.msc')})
$EventViewerButton.Add_Click({Open-HuSystemTool (Join-Path $env:SystemRoot 'System32\eventvwr.msc')})
$ThisPcTaskManagerButton.Add_Click({Open-HuSystemTool (Join-Path $env:SystemRoot 'System32\taskmgr.exe')})
$WingetUpgradeButton.Add_Click({if(-not(Show-AppConfirm (T 'ConfirmWingetUpgrade'))){return};try{if(-not(Get-Command 'winget.exe' -ErrorAction SilentlyContinue)){throw (T 'WingetUnavailable')};Add-HuWindowsLogLine ([pscustomobject]@{Text='[CMD] winget upgrade --all';Level='Normal'});Start-HuVisibleCommand -Title 'winget upgrade --all' -Command 'winget upgrade --all'}catch{Add-HuWindowsLogLine ([pscustomobject]@{Text=('[FAIL] {0}' -f $_.Exception.Message);Level='Error'});Show-AppError $_.Exception.Message}})

function Invoke-HuIntegrityProcess {
    param([object]$Button,[string]$TitleKey,[string]$Executable,[string[]]$Arguments,[string]$ConfirmKey,[int]$TimeoutSeconds=7200)
    if($ConfirmKey -and -not(Show-AppConfirm (T $ConfirmKey))){return}
    $Button.IsEnabled=$false;$title=T $TitleKey;$queue=[Collections.Concurrent.ConcurrentQueue[object]]::new()
    $worker={
        param($filePath,$argumentList,$operationTitle,$progressQueue)
        $progressQueue.Enqueue([pscustomobject]@{Text=('[START] {0}' -f $operationTitle);Level='Normal'})
        $progressQueue.Enqueue([pscustomobject]@{Text=('> {0} {1}' -f [IO.Path]::GetFileName($filePath),($argumentList -join ' '));Level='Normal'})
        & $filePath @argumentList 2>&1 | ForEach-Object {$line=[string]$_;if(-not[string]::IsNullOrWhiteSpace($line)){$progressQueue.Enqueue([pscustomobject]@{Text=$line;Level='Auto'})}}
        $code=$LASTEXITCODE
        [pscustomobject]@{ExitCode=$code}
    }
    $progress={param($item)Add-HuDiagnosticsLogLine -Item $item}.GetNewClosure()
    $completed={param($output)$Button.IsEnabled=$true;$result=@($output)|Where-Object{$_.PSObject.Properties['ExitCode']}|Select-Object -Last 1;if($result){Add-HuDiagnosticsLogLine -Item ([pscustomobject]@{Text=(TF 'CommandExitCode' @($result.ExitCode));Level=$(if($result.ExitCode -eq 0){'Success'}else{'Error'})})}}.GetNewClosure()
    $failed={param($message)$Button.IsEnabled=$true;Add-HuDiagnosticsLogLine -Item ([pscustomobject]@{Text=('[FAIL] {0}' -f [string]$message);Level='Error'})}.GetNewClosure()
    [void](Invoke-HuAsyncWork -Key ('Integrity.'+$TitleKey) -ScriptBlock $worker -ArgumentList @($Executable,$Arguments,$title,$queue) -OnCompleted $completed -OnError $failed -OnProgress $progress -ProgressQueue $queue -TimeoutSeconds $TimeoutSeconds -Replace)
}

$DismScanButton.Add_Click({Invoke-HuIntegrityProcess -Button $DismScanButton -TitleKey 'DismScanTitle' -Executable (Get-HuSystemExecutablePath 'Dism.exe') -Arguments @('/Online','/Cleanup-Image','/ScanHealth') -ConfirmKey 'ConfirmDismScan'})
$DismRepairButton.Add_Click({Invoke-HuIntegrityProcess -Button $DismRepairButton -TitleKey 'DismRepairTitle' -Executable (Get-HuSystemExecutablePath 'Dism.exe') -Arguments @('/Online','/Cleanup-Image','/RestoreHealth') -ConfirmKey 'ConfirmDismRepair'})
$SfcScanButton.Add_Click({Invoke-HuIntegrityProcess -Button $SfcScanButton -TitleKey 'SfcToolTitle' -Executable (Get-HuSystemExecutablePath 'sfc.exe') -Arguments @('/scannow') -ConfirmKey 'ConfirmSfcScan'})

$ChkdskButton.Add_Click({
    if(-not(Show-AppConfirm (T 'ConfirmChkdsk'))){return}
    $ChkdskButton.IsEnabled=$false;$title=T 'ChkdskTitle';$queue=[Collections.Concurrent.ConcurrentQueue[object]]::new();$chkdsk=Get-HuSystemExecutablePath 'chkdsk.exe'
    $worker={
        param($filePath,$operationTitle,$progressQueue)
        $progressQueue.Enqueue([pscustomobject]@{Text=('[START] {0}' -f $operationTitle);Level='Normal'})
        $letters=@(Get-Volume -ErrorAction SilentlyContinue|Where-Object{$_.DriveType -eq 'Fixed' -and $_.DriveLetter}|ForEach-Object{[string]$_.DriveLetter}|Sort-Object -Unique);if($letters.Count -eq 0){$letters=@('C')}
        $codes=@();foreach($letter in $letters){$progressQueue.Enqueue([pscustomobject]@{Text=('> chkdsk {0}: /scan' -f $letter);Level='Normal'});& $filePath ($letter+':') '/scan' 2>&1|ForEach-Object{$line=[string]$_;if(-not[string]::IsNullOrWhiteSpace($line)){$progressQueue.Enqueue([pscustomobject]@{Text=$line;Level='Auto'})}};$codes+=$LASTEXITCODE}
        $ok=@($codes|Where-Object{$_ -ne 0}).Count -eq 0;$progressQueue.Enqueue([pscustomobject]@{Key=$(if($ok){'ChangeVerified'}else{'ChangeNotVerified'});Prefix=$(if($ok){'[OK]'}else{'[FAIL]'});Level=$(if($ok){'Success'}else{'Error'})});[pscustomobject]@{Success=$ok;Codes=$codes}
    }
    $progress={param($item)Add-HuDiagnosticsLogLine -Item $item}.GetNewClosure();$completed={param($output)$ChkdskButton.IsEnabled=$true}.GetNewClosure();$failed={param($message)$ChkdskButton.IsEnabled=$true;Add-HuDiagnosticsLogLine -Item ([pscustomobject]@{Text=('[FAIL] {0}' -f [string]$message);Level='Error'})}.GetNewClosure()
    [void](Invoke-HuAsyncWork -Key 'Integrity.Chkdsk' -ScriptBlock $worker -ArgumentList @($chkdsk,$title,$queue) -OnCompleted $completed -OnError $failed -OnProgress $progress -ProgressQueue $queue -TimeoutSeconds 7200 -Replace)
})

$DriveHealthButton.Add_Click({
    $DriveHealthButton.IsEnabled=$false;$title=T 'DriveHealthTitle';$queue=[Collections.Concurrent.ConcurrentQueue[object]]::new()
    $worker={param($operationTitle,$progressQueue);$progressQueue.Enqueue([pscustomobject]@{Text=('[START] {0}' -f $operationTitle);Level='Normal'});$disks=@(Get-PhysicalDisk -ErrorAction Stop);foreach($disk in $disks){$line='{0} | {1} | {2} | {3} | {4:N1} GB' -f $disk.FriendlyName,$disk.MediaType,$disk.HealthStatus,$disk.OperationalStatus,([double]$disk.Size/1GB);$level=if([string]$disk.HealthStatus -eq 'Healthy'){'Success'}else{'Error'};$progressQueue.Enqueue([pscustomobject]@{Text=$line;Level=$level})};[pscustomobject]@{Count=$disks.Count}}
    $progress={param($item)Add-HuDiagnosticsLogLine -Item $item}.GetNewClosure();$completed={param($output)$DriveHealthButton.IsEnabled=$true}.GetNewClosure();$failed={param($message)$DriveHealthButton.IsEnabled=$true;Add-HuDiagnosticsLogLine -Item ([pscustomobject]@{Text=('[FAIL] {0}' -f [string]$message);Level='Error'})}.GetNewClosure()
    [void](Invoke-HuAsyncWork -Key 'Integrity.DriveHealth' -ScriptBlock $worker -ArgumentList @($title,$queue) -OnCompleted $completed -OnError $failed -OnProgress $progress -ProgressQueue $queue -TimeoutSeconds 30 -Replace)
})

$RepairPathButton.Add_Click({
    if(-not(Show-AppConfirm (T 'ConfirmRepairPath'))){return}
    $RepairPathButton.IsEnabled=$false;$title=T 'PathRepairTitle';$queue=[Collections.Concurrent.ConcurrentQueue[object]]::new()
    $worker={param($root,$operationTitle,$progressQueue);Import-Module (Join-Path $root 'WNST.psd1') -Force;. (Join-Path $root 'Modules\System.ps1');$progressQueue.Enqueue([pscustomobject]@{Text=('[START] {0}' -f $operationTitle);Level='Normal'});$result=Repair-HuWindowsPath;foreach($entry in @($result.Entries)){$progressQueue.Enqueue([pscustomobject]@{Text=('[PATH] {0}' -f $entry);Level='Success'})};$progressQueue.Enqueue([pscustomobject]@{Key=$(if($result.Added -gt 0){'PathRepairSuccess'}else{'PathAlreadyHealthy'});Args=@([int]$result.Added);Prefix='[OK]';Level='Success'});$result}
    $progress={param($item)Add-HuDiagnosticsLogLine -Item $item}.GetNewClosure();$completed={param($output)$RepairPathButton.IsEnabled=$true}.GetNewClosure();$failed={param($message)$RepairPathButton.IsEnabled=$true;$text=if([string]$message -eq 'AdministratorRequired'){T 'AdministratorRequired'}else{[string]$message};Add-HuDiagnosticsLogLine -Item ([pscustomobject]@{Text=('[FAIL] {0}' -f $text);Level='Error'})}.GetNewClosure()
    [void](Invoke-HuAsyncWork -Key 'Integrity.Path' -ScriptBlock $worker -ArgumentList @($script:AppRoot,$title,$queue) -OnCompleted $completed -OnError $failed -OnProgress $progress -ProgressQueue $queue -TimeoutSeconds 45 -Replace)
})

$ClearIntegrityLogButton.Add_Click({Clear-WnstLogContent -Control $IntegrityOutputBox})
$ClearWindowsLogButton.Add_Click({Clear-WnstLogContent -Control $WindowsOutputBox})
