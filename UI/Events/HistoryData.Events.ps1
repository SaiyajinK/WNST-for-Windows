$OpenHostsButton.Add_Click({ try { Open-TextFile -Path (Join-Path $env:SystemRoot 'System32\drivers\etc\hosts') } catch { Show-AppError $_.Exception.Message } })
$OpenBackupFolderButton.Add_Click({ try { New-Item -ItemType Directory -Path $script:Paths.BackupRoot -Force | Out-Null; Start-Process -FilePath 'explorer.exe' -ArgumentList @($script:Paths.BackupRoot) } catch { Show-AppError $_.Exception.Message } })
$ChooseDataFolderButton.Add_Click({
    try {
        Add-Type -AssemblyName System.Windows.Forms
        $browser = New-Object Windows.Forms.FolderBrowserDialog
        try {
            $browser.Description = T 'DataFolder'
            $browser.SelectedPath = [string]$script:Paths.DataRoot
            $browser.ShowNewFolderButton = $true
            if ($browser.ShowDialog() -eq [Windows.Forms.DialogResult]::OK) { [void](Switch-WNSTDataRoot -TargetRoot $browser.SelectedPath) }
        }
        finally { $browser.Dispose() }
    }
    catch { Show-AppError $_.Exception.Message }
})
$ResetDataFolderButton.Add_Click({ try { [void](Switch-WNSTDataRoot -TargetRoot (Get-HuStandardDataRoot)) } catch { Show-AppError $_.Exception.Message } })
$OpenDataFolderButton.Add_Click({ try { New-Item -ItemType Directory -Path $script:Paths.DataRoot -Force | Out-Null; Start-Process -FilePath 'explorer.exe' -ArgumentList @($script:Paths.DataRoot) } catch { Show-AppError $_.Exception.Message } })
$RefreshHistoryButton.Add_Click({ Refresh-BackupHistory })
$RestoreLatestButton.Add_Click({ Show-Page History })
$BackupPreviewCloseButton.Add_Click({ $BackupGrid.SelectedItem = $null; Hide-BackupPreview })
$BackupPreviewScroll.Add_SizeChanged({ Update-BackupPreviewCustomScrollbar })
$BackupPreviewScroll.Add_ScrollChanged({ Update-BackupPreviewCustomScrollbar })
$BackupPreviewCustomScrollTrack.Add_SizeChanged({ Update-BackupPreviewCustomScrollbar })

$script:BackupPreviewThumbDragStartOffset = 0.0
$script:BackupPreviewThumbDragDelta = 0.0
$BackupPreviewCustomScrollThumb.Add_DragStarted({
    $script:BackupPreviewThumbDragStartOffset = [double]$BackupPreviewScroll.VerticalOffset
    $script:BackupPreviewThumbDragDelta = 0.0
})
$BackupPreviewCustomScrollThumb.Add_DragDelta({
    if ($BackupPreviewCustomScrollTrack.Visibility -ne 'Visible') { return }
    $trackHeight = [double]$BackupPreviewCustomScrollTrack.ActualHeight
    $thumbHeight = [double]$BackupPreviewCustomScrollThumb.ActualHeight
    $travel = [Math]::Max(0.0, $trackHeight - $thumbHeight)
    $scrollable = [double]$BackupPreviewScroll.ScrollableHeight
    if ($travel -le 0 -or $scrollable -le 0) { return }
    $script:BackupPreviewThumbDragDelta += [double]$_.VerticalChange
    $target = $script:BackupPreviewThumbDragStartOffset + (($script:BackupPreviewThumbDragDelta / $travel) * $scrollable)
    $target = [Math]::Max(0.0, [Math]::Min($scrollable, $target))
    $BackupPreviewScroll.ScrollToVerticalOffset($target)
})
$BackupPreviewCustomScrollThumb.Add_DragCompleted({
    $script:BackupPreviewThumbDragDelta = 0.0
})
$BackupPreviewCustomScrollTrack.Add_MouseLeftButtonDown({
    if ($BackupPreviewCustomScrollTrack.Visibility -ne 'Visible') { return }
    if ($_.OriginalSource -ne $BackupPreviewCustomScrollTrack) { return }
    $y = [double]$_.GetPosition($BackupPreviewCustomScrollTrack).Y
    $top = [Windows.Controls.Canvas]::GetTop($BackupPreviewCustomScrollThumb)
    if ([double]::IsNaN($top)) { $top = 0.0 }
    $bottom = $top + [double]$BackupPreviewCustomScrollThumb.ActualHeight
    if ($y -lt $top) {
        $BackupPreviewScroll.ScrollToVerticalOffset([Math]::Max(0.0, [double]$BackupPreviewScroll.VerticalOffset - [double]$BackupPreviewScroll.ViewportHeight))
    }
    elseif ($y -gt $bottom) {
        $BackupPreviewScroll.ScrollToVerticalOffset([Math]::Min([double]$BackupPreviewScroll.ScrollableHeight, [double]$BackupPreviewScroll.VerticalOffset + [double]$BackupPreviewScroll.ViewportHeight))
    }
    $_.Handled = $true
})
$BackupGrid.Add_SelectionChanged({
    $hasSelection = $null -ne $BackupGrid.SelectedItem
    $DeleteSelectedBackupButton.IsEnabled = $hasSelection -and -not $script:Busy
    $RestoreSelectedButton.IsEnabled = $hasSelection -and -not $script:Busy
    if ($hasSelection) { Show-BackupPreview -Row $BackupGrid.SelectedItem } else { Hide-BackupPreview }
})
$BackupGrid.Add_PreviewMouseRightButtonDown({
    if ($script:ContextSelectedBackupRow) { $script:ContextSelectedBackupRow.Tag = $null; $script:ContextSelectedBackupRow = $null }
    $element = $BackupGrid.InputHitTest($_.GetPosition($BackupGrid))
    while ($element -and -not ($element -is [Windows.Controls.DataGridRow])) {
        try { $element = [Windows.Media.VisualTreeHelper]::GetParent($element) }
        catch { $element = [Windows.LogicalTreeHelper]::GetParent($element) }
    }
    if ($element -is [Windows.Controls.DataGridRow]) { $BackupGrid.SelectedItem = $element.Item; $element.Tag='ContextSelected'; $script:ContextSelectedBackupRow=$element }
})
$BackupGrid.Add_PreviewMouseLeftButtonDown({ if ($script:ContextSelectedBackupRow) { $script:ContextSelectedBackupRow.Tag=$null; $script:ContextSelectedBackupRow=$null } })
$BackupContextMenu.Add_Opened({
    $enabled = $null -ne $BackupGrid.SelectedItem
    $ModifyBackupMenuItem.IsEnabled = $enabled
    $DeleteBackupMenuItem.IsEnabled = $enabled
    $DetailBackupMenuItem.IsEnabled = $enabled
})
$BackupContextMenu.Add_Closed({ if ($script:ContextSelectedBackupRow) { $script:ContextSelectedBackupRow.Tag=$null; $script:ContextSelectedBackupRow=$null } })
$BackupGrid.Add_MouseDoubleClick({ if ($BackupGrid.SelectedItem) { try { Open-TextFile -Path ([string]$BackupGrid.SelectedItem.Path) } catch { Show-AppError $_.Exception.Message } } })
$ModifyBackupMenuItem.Add_Click({ if ($BackupGrid.SelectedItem) { try { Open-TextFile -Path ([string]$BackupGrid.SelectedItem.Path) } catch { Show-AppError $_.Exception.Message } } })
$DeleteBackupMenuItem.Add_Click({ Remove-SelectedBackupFromUi })
$DetailBackupMenuItem.Add_Click({ if ($BackupGrid.SelectedItem) { try { Show-BackupDetailsDialog -Row $BackupGrid.SelectedItem } catch { Show-AppError $_.Exception.Message } } })
$DeleteSelectedBackupButton.Add_Click({ Remove-SelectedBackupFromUi })
$RestoreSelectedButton.Add_Click({
    if (-not $BackupGrid.SelectedItem) { Show-AppError (T 'BackupRequired'); return }
    if (-not (Show-AppConfirm (T $(if ($AutomaticBackupCheck.IsChecked) { 'ConfirmRestore' } else { 'ConfirmRestoreNoBackup' })))) { return }
    Set-Busy $true (T 'Restoring')
    try {
        $parameters = @{
            BackupPath = [string]$BackupGrid.SelectedItem.Path
            Confirm = $false
            CreateBackup = [bool]$AutomaticBackupCheck.IsChecked
        }
        if ($script:DataRootArgument) { $parameters.DataRoot = $script:DataRootArgument }
        Restore-HuBackup @parameters | Out-Null
        Show-AppInfo (T 'RestoreSuccess')
        Update-StatusPanel
        Refresh-BackupHistory
    }
    catch { Show-AppError $_.Exception.Message }
    finally { Set-Busy $false '' }
})
$ClearHistoryButton.Add_Click({
    $count = @(Get-AppBackups).Count
    if ($count -eq 0) { Show-AppError (T 'NoBackup'); return }
    if (-not (Show-AppConfirm (TF 'ConfirmClearHistory' @($count)))) { return }
    try {
        $parameters = @{ Confirm=$false }
        if ($script:DataRootArgument) { $parameters.DataRoot = $script:DataRootArgument }
        $deleted = Clear-HuBackup @parameters
        Refresh-BackupHistory
        Show-AppInfo (TF 'ClearHistorySuccess' @($deleted))
    }
    catch { Show-AppError $_.Exception.Message }
})
