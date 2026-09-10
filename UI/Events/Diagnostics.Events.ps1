$script:UpdatingDiagnosticsUi = $false

function Add-HuDiagnosticsLogLine {
    param([object]$Item)
    if ($null -eq $Item) { return }
    $text = Resolve-WnstLogItemText -Item $Item
    if ([string]::IsNullOrWhiteSpace($text)) { return }
    $level = if ($Item.PSObject.Properties['Level']) { [string]$Item.Level } else { 'Auto' }
    if ($level -notin @('Auto','Normal','Success','Error')) { $level='Auto' }
    $localizedText = ConvertTo-WnstLocalizedLogText -Text $text
    $line = '[{0}] {1}' -f ([DateTime]::Now.ToString('HH:mm:ss')),$localizedText
    $spacing = if ($text -match '^\[START\](?:\s|$)') { 2 } else { 1 }
    Add-WnstLogText -Control $IntegrityOutputBox -Text $line -Level $level -LeadingNewLines $spacing
}

function Refresh-DiagnosticsState {
    $worker = {
        param($root)
        Import-Module (Join-Path $root 'WNST.psd1') -Force
        . (Join-Path $root 'Modules\System.ps1')
        . (Join-Path $root 'Modules\Diagnostics.ps1')
        Get-HuDiagnosticsState
    }
    $completed = {
        param($output)
        $state = @($output) | Where-Object { $_.PSObject.Properties['BootDetails'] } | Select-Object -Last 1
        if (-not $state) { return }
        $script:UpdatingDiagnosticsUi = $true
        try {
            $BootDiagnosticsToggle.IsChecked = [bool]$state.BootDetails
            $VerboseLogonToggle.IsChecked = [bool]$state.VerboseLogon
            $BootDiagnosticsStatus.Text = T $(if ($state.BootDetails) { 'StateEnabled' } else { 'StateDisabled' })
            $VerboseLogonStatus.Text = T $(if ($state.VerboseLogon) { 'StateEnabled' } else { 'StateDisabled' })
        }
        finally { $script:UpdatingDiagnosticsUi = $false }
    }.GetNewClosure()
    [void](Invoke-HuAsyncWork -Key 'Page.Diagnostics.State' -ScriptBlock $worker -ArgumentList @($script:AppRoot) -OnCompleted $completed -TimeoutSeconds 12 -Replace)
}

function Invoke-HuDiagnosticsToggle {
    param([object]$Control,[string]$FunctionName,[bool]$Enabled,[string]$TitleKey,[string]$StateProperty)
    $Control.IsEnabled = $false
    $title = T $TitleKey
    $queue = [Collections.Concurrent.ConcurrentQueue[object]]::new()
    $worker = {
        param($root,$functionName,$enabledValue,$propertyName,$operationTitle,$progressQueue)
        Import-Module (Join-Path $root 'WNST.psd1') -Force
        . (Join-Path $root 'Modules\System.ps1')
        . (Join-Path $root 'Modules\Diagnostics.ps1')
        $progressQueue.Enqueue([pscustomobject]@{Text=('[START] {0}' -f $operationTitle);Level='Normal'})
        $operationResult = & $functionName $enabledValue $progressQueue
        $state = Get-HuDiagnosticsState
        $actual = [bool]$state.$propertyName
        [pscustomobject]@{Actual=$actual;Verified=($actual -eq $enabledValue);RestartRequired=[bool]$operationResult.RestartRequired}
    }
    $progress = { param($item) Add-HuDiagnosticsLogLine -Item $item }.GetNewClosure()
    $completed = {
        param($output)
        $result = @($output) | Where-Object { $_.PSObject.Properties['Verified'] } | Select-Object -Last 1
        $script:UpdatingDiagnosticsUi = $true
        try { if($result){$Control.IsChecked=[bool]$result.Actual} }
        finally { $script:UpdatingDiagnosticsUi=$false; $Control.IsEnabled=$true }
        $message = T $(if($result -and $result.Verified){if($result.RestartRequired){'ChangeVerifiedRestart'}else{'ChangeVerified'}}else{'ChangeNotVerified'})
        if($StateProperty -eq 'BootDetails'){$BootDiagnosticsStatus.Text=$message}else{$VerboseLogonStatus.Text=$message}
        Add-HuDiagnosticsLogLine -Item ([pscustomobject]@{Text=($(if($result -and $result.Verified){'[OK] '}else{'[FAIL] '}) + $message);Level=$(if($result -and $result.Verified){'Success'}else{'Error'})})
    }.GetNewClosure()
    $failed = {
        param($message)
        $Control.IsEnabled=$true
        $text=if([string]$message -eq 'AdministratorRequired'){T 'AdministratorRequired'}else{[string]$message}
        Add-HuDiagnosticsLogLine -Item ([pscustomobject]@{Text=('[FAIL] {0}' -f $text);Level='Error'})
        if($StateProperty -eq 'BootDetails'){$BootDiagnosticsStatus.Text=$text}else{$VerboseLogonStatus.Text=$text}
        Refresh-DiagnosticsState
    }.GetNewClosure()
    [void](Invoke-HuAsyncWork -Key ('Diagnostics.'+$StateProperty) -ScriptBlock $worker -ArgumentList @($script:AppRoot,$FunctionName,$Enabled,$StateProperty,$title,$queue) -OnCompleted $completed -OnError $failed -OnProgress $progress -ProgressQueue $queue -TimeoutSeconds 45 -Replace)
}

$BootDiagnosticsToggle.Add_Click({
    if ($script:UpdatingDiagnosticsUi) { return }
    $enabled=[bool]$BootDiagnosticsToggle.IsChecked
    if(-not(Show-AppConfirm (T $(if($enabled){'ConfirmEnableBootDiagnostics'}else{'ConfirmDisableBootDiagnostics'})))){Refresh-DiagnosticsState;return}
    Invoke-HuDiagnosticsToggle -Control $BootDiagnosticsToggle -FunctionName 'Set-HuBootDiagnostics' -Enabled $enabled -TitleKey 'BootDiagnosticsTitle' -StateProperty 'BootDetails'
})

$VerboseLogonToggle.Add_Click({
    if ($script:UpdatingDiagnosticsUi) { return }
    Invoke-HuDiagnosticsToggle -Control $VerboseLogonToggle -FunctionName 'Set-HuVerboseLogonStatus' -Enabled ([bool]$VerboseLogonToggle.IsChecked) -TitleKey 'VerboseLogonTitle' -StateProperty 'VerboseLogon'
})

$CreateRestorePointButton.Add_Click({
    if(-not(Show-AppConfirm (T 'ConfirmCreateRestorePoint'))){return}
    $CreateRestorePointButton.IsEnabled=$false
    $SystemRestoreStatus.Text=T 'AdvancedStatusRunning'
    $queue=[Collections.Concurrent.ConcurrentQueue[object]]::new();$description=T 'RestorePointDescription'
    $worker={
        param($root,$restoreDescription,$progressQueue)
        Import-Module (Join-Path $root 'WNST.psd1') -Force
        . (Join-Path $root 'Modules\System.ps1')
        . (Join-Path $root 'Modules\Diagnostics.ps1')
        New-HuSystemRestorePoint -Description $restoreDescription -ProgressQueue $progressQueue
    }
    $progress={param($item)Add-HuDiagnosticsLogLine -Item $item}.GetNewClosure()
    $completed={
        param($output)
        $result=@($output)|Where-Object{$_.PSObject.Properties['Created']}|Select-Object -Last 1
        $CreateRestorePointButton.IsEnabled=$true
        $SystemRestoreStatus.Text=T $(if($result -and $result.Created){'RestorePointCreated'}else{'ChangeNotVerified'})
    }.GetNewClosure()
    $failed={
        param($message)
        $CreateRestorePointButton.IsEnabled=$true
        $text=if([string]$message -eq 'AdministratorRequired'){T 'AdministratorRequired'}else{[string]$message}
        $SystemRestoreStatus.Text=$text
        Add-HuDiagnosticsLogLine -Item ([pscustomobject]@{Text=('[FAIL] {0}' -f $text);Level='Error'})
    }.GetNewClosure()
    [void](Invoke-HuAsyncWork -Key 'Diagnostics.RestorePoint' -ScriptBlock $worker -ArgumentList @($script:AppRoot,$description,$queue) -OnCompleted $completed -OnError $failed -OnProgress $progress -ProgressQueue $queue -TimeoutSeconds 180 -Replace)
})

$OpenSystemRestoreButton.Add_Click({
    try {
        Add-HuDiagnosticsLogLine -Item ([pscustomobject]@{Text=('[START] {0}' -f (T 'RestoreSystem'));Level='Normal'})
        Open-HuSystemRestore
        Add-HuDiagnosticsLogLine -Item ([pscustomobject]@{Text=('[OK] {0}: {1}' -f (T 'RestoreSystem'),(T 'ChangeVerified'));Level='Success'})
    }
    catch { Add-HuDiagnosticsLogLine -Item ([pscustomobject]@{Text=('[FAIL] {0}' -f $_.Exception.Message);Level='Error'}) }
})
