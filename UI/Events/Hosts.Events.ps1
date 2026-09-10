$ClearSourceButton.Add_Click({ $SourceUrlBox.Clear(); $SourceUrlBox.Focus() })

$TestSourceButton.Add_Click({
    if (-not (Test-HuSourceAddress -SourceUrl $SourceUrlBox.Text)) { Show-AppError (T 'UrlRequired'); return }
    Set-Busy $true (T 'Downloading')
    try {
        Save-CurrentSettings
        $result = Test-HuSource -SourceUrl $SourceUrlBox.Text.Trim()
        Show-AppInfo (TF 'SourceTestSuccess' @($result.EntryCount))
        $StatusBarText.Text = TF 'SourceTestSuccess' @($result.EntryCount)
    }
    catch { Show-AppError $_.Exception.Message }
    finally { Set-Busy $false '' }
})

$ManualAddButton.Add_Click({
    try { $manualContent = Show-ManualEntryDialog }
    catch { Show-AppError $_.Exception.Message; return }
    if ([string]::IsNullOrWhiteSpace($manualContent)) { return }
    if (-not (Show-AppConfirm (T 'ConfirmManualAdd'))) { return }
    Set-Busy $true (T 'ManualAdding')
    try {
        Save-CurrentSettings
        $parameters = @{ Content=$manualContent; CreateBackup=[bool]$AutomaticBackupCheck.IsChecked; FlushDns=[bool]$FlushDnsCheck.IsChecked }
        if ($script:DataRootArgument) { $parameters.DataRoot = $script:DataRootArgument }
        $result = Add-HuManualHostsEntries @parameters
        Show-AppInfo (TF 'ManualSuccess' @($result.AddedCount,$result.TotalManualCount))
        Update-StatusPanel
        Refresh-BackupHistory
    }
    catch { Show-AppError $_.Exception.Message }
    finally { Set-Busy $false '' }
})

$UpdateNowButton.Add_Click({
    if (-not (Test-HuSourceAddress -SourceUrl $SourceUrlBox.Text)) { Show-AppError (T 'UrlRequired'); return }
    if ($ReplaceModeRadio.IsChecked -and -not (Show-AppConfirm (T $(if ($AutomaticBackupCheck.IsChecked) { 'ConfirmUpdateReplace' } else { 'ConfirmUpdateReplaceNoBackup' })))) { return }
    Set-Busy $true (T 'Updating')
    try {
        Save-CurrentSettings
        $parameters = @{ SourceUrl = $SourceUrlBox.Text.Trim(); UpdateMode = $(if ($ReplaceModeRadio.IsChecked) { 'Replace' } else { 'Merge' }); FlushDns = [bool]$FlushDnsCheck.IsChecked; CreateBackup = [bool]$AutomaticBackupCheck.IsChecked }
        if ($script:DataRootArgument) { $parameters.DataRoot = $script:DataRootArgument }
        $result = Invoke-HuHostsUpdate @parameters
        Show-AppInfo (TF 'UpdateSuccess' @($result.EntryCount))
        Update-StatusPanel; Refresh-BackupHistory
    }
    catch { Show-AppError $_.Exception.Message }
    finally { Set-Busy $false '' }
})

