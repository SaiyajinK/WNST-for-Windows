function Update-SourceBanner {
    $hasText = -not [string]::IsNullOrWhiteSpace($SourceUrlBox.Text)
    $hasValidUrl = $hasText -and (Test-HuSourceAddress -SourceUrl $SourceUrlBox.Text)
    $SourcePlaceholder.Visibility = if ($hasText) { 'Collapsed' } else { 'Visible' }
    $UpdateNowButton.IsEnabled = $hasValidUrl -and -not $script:Busy
    $TestSourceButton.IsEnabled = $hasValidUrl -and -not $script:Busy

    $bannerText = '#F1D39C'
    if ($hasValidUrl) {
        $SourceBannerTitle.Text = T 'SourceReadyTitle'
        $SourceBannerHint.Text = '  ·  ' + (T 'SourceReadyHint')
        if ($script:ResolvedTheme -eq 'Light') {
            $SourceBanner.Background = '#E7F5EE'; $SourceBanner.BorderBrush = '#9BCDB2'; $bannerText = '#236B45'; $SourceDot.Fill = '#3BAF78'
        }
        else {
            $SourceBanner.Background = '#1E322A'; $SourceBanner.BorderBrush = '#365D4B'; $bannerText = '#B6F0D2'; $SourceDot.Fill = '#4CC38A'
        }
    }
    elseif ($hasText) {
        $SourceBannerTitle.Text = T 'SourceInvalidTitle'
        $SourceBannerHint.Text = '  ·  ' + (T 'SourceInvalidHint')
        if ($script:ResolvedTheme -eq 'Light') {
            $SourceBanner.Background = '#FDEBEC'; $SourceBanner.BorderBrush = '#E1A2A7'; $bannerText = '#9B2C34'; $SourceDot.Fill = '#D13438'
        }
        else {
            $SourceBanner.Background = '#342124'; $SourceBanner.BorderBrush = '#6B3A40'; $bannerText = '#FFB3B8'; $SourceDot.Fill = '#E85D68'
        }
    }
    else {
        $SourceBannerTitle.Text = T 'NoSourceTitle'
        $SourceBannerHint.Text = '  ·  ' + (T 'NoSourceHint')
        if ($script:ResolvedTheme -eq 'Light') {
            $SourceBanner.Background = '#FFF4DD'; $SourceBanner.BorderBrush = '#D8B66E'; $bannerText = '#7A5500'; $SourceDot.Fill = '#D39A2C'
        }
        else {
            $SourceBanner.Background = '#2C2921'; $SourceBanner.BorderBrush = '#574B33'; $bannerText = '#F1D39C'; $SourceDot.Fill = '#E5AA42'
        }
    }

    $SourceBannerTitle.Foreground = $bannerText
    $SourceBannerHint.Foreground = $bannerText
}

function Update-StatusPanel {
    if (-not (Get-Variable -Name HostStatusCache -Scope Script -ErrorAction SilentlyContinue)) { $script:HostStatusCache = $null }
    # Les informations locales sont instantanées ; les appels au Planificateur de tâches
    # restent hors du thread WPF pour ne jamais bloquer le hover ou la navigation depuis Host.
    $ManagedEntriesValue.Text = [string]$script:Settings.LastEntryCount
    if ($script:Settings.LastUpdateUtc) {
        try { $LastUpdateValue.Text = ([DateTime]::Parse([string]$script:Settings.LastUpdateUtc, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind)).ToLocalTime().ToString('g') } catch { $LastUpdateValue.Text = T 'Never' }
    }
    else { $LastUpdateValue.Text = T 'Never' }

    if ($script:HostStatusCache) {
        $cached = $script:HostStatusCache
        $TaskStatusValue.Text = if ($cached.Exists) { [string]$cached.State } else { T 'NotConfigured' }
        $NextRunValue.Text = if ($cached.Exists -and $cached.NextRunTime -and $cached.NextRunTime -gt [DateTime]::MinValue) { ([DateTime]$cached.NextRunTime).ToString('g') } else { T 'Disabled' }
        $RestoreLatestButton.IsEnabled = -not $script:Busy
    }

    $completed = {
        param($output)
        $status = @($output | Where-Object { $_ -and $_.PSObject.Properties['Kind'] -and $_.Kind -eq 'HostStatus' } | Select-Object -Last 1)[0]
        if (-not $status) { return }
        $script:HostStatusCache = $status
        $TaskStatusValue.Text = if ($status.Exists) { [string]$status.State } else { T 'NotConfigured' }
        $NextRunValue.Text = if ($status.Exists -and $status.NextRunTime -and $status.NextRunTime -gt [DateTime]::MinValue) { ([DateTime]$status.NextRunTime).ToString('g') } else { T 'Disabled' }
        $RestoreLatestButton.IsEnabled = -not $script:Busy
    }

    $worker = {
        param($backupRoot)
        $exists = $false
        $state = ''
        $nextRun = $null
        foreach ($taskName in @('WNST Daily Update','H.0.S.T Daily Update')) {
            try {
                $task = Get-ScheduledTask -TaskName $taskName -ErrorAction Stop
                $info = Get-ScheduledTaskInfo -TaskName $taskName -ErrorAction SilentlyContinue
                $exists = $true
                $state = [string]$task.State
                if ($info) { $nextRun = $info.NextRunTime }
                break
            }
            catch { }
        }
        $backupCount = 0
        try {
            if (Test-Path -LiteralPath $backupRoot -PathType Container) {
                $backupCount = @(Get-ChildItem -LiteralPath $backupRoot -File -Filter '*.hosts' -ErrorAction SilentlyContinue).Count
            }
        }
        catch { }
        [pscustomobject]@{ Kind='HostStatus'; Exists=$exists; State=$state; NextRunTime=$nextRun; BackupCount=$backupCount }
    }

    [void](Invoke-HuAsyncWork -Key 'Host.Status' -ScriptBlock $worker -ArgumentList @([string]$script:Paths.BackupRoot) -OnCompleted $completed -TimeoutSeconds 5 -Replace)
}

function Refresh-BackupHistory {
    $rows = foreach ($backup in Get-AppBackups) {
        [pscustomobject]@{ DisplayDate = $backup.CreatedAt.ToString('g'); Name = $backup.Name; DisplaySize = Format-Size $backup.SizeBytes; Path = $backup.Path }
    }
    $BackupGrid.ItemsSource = @($rows)
    $ClearHistoryButton.IsEnabled = @($rows).Count -gt 0 -and -not $script:Busy
    $DeleteSelectedBackupButton.IsEnabled = $false; $RestoreSelectedButton.IsEnabled = $false
    Hide-BackupPreview
}

function Hide-BackupPreview {
    $BackupPreviewPanel.Visibility = 'Collapsed'
    $BackupPreviewText.Text = ''
    $BackupPreviewMeta.Text = ''
    $BackupPreviewCustomScrollTrack.Visibility = 'Collapsed'
    $BackupPreviewScroll.VerticalScrollBarVisibility = 'Auto'
    $BackupPreviewScroll.Padding = [Windows.Thickness]::new(0)
}

function Update-BackupPreviewCustomScrollbar {
    if ($script:UpdatingBackupPreviewCustomScroll) { return }
    $script:UpdatingBackupPreviewCustomScroll = $true
    try {
        $extent = [double]$BackupPreviewScroll.ExtentHeight
        $viewport = [double]$BackupPreviewScroll.ViewportHeight
        $useCustom = $false

        if ($extent -gt $viewport -and $viewport -gt 0) {
            $naturalThumbHeight = ($viewport * $viewport) / $extent
            $useCustom = $naturalThumbHeight -lt 24
        }

        if (-not $useCustom) {
            if ($BackupPreviewCustomScrollTrack.Visibility -ne 'Collapsed') {
                $BackupPreviewCustomScrollTrack.Visibility = 'Collapsed'
            }
            if ($BackupPreviewScroll.VerticalScrollBarVisibility -ne 'Auto') {
                $BackupPreviewScroll.VerticalScrollBarVisibility = 'Auto'
                $BackupPreviewScroll.Padding = [Windows.Thickness]::new(0)
            }
            return
        }

        if ($BackupPreviewScroll.VerticalScrollBarVisibility -ne 'Hidden') {
            $BackupPreviewScroll.VerticalScrollBarVisibility = 'Hidden'
            $BackupPreviewScroll.Padding = [Windows.Thickness]::new(0,0,9,0)
        }
        if ($BackupPreviewCustomScrollTrack.Visibility -ne 'Visible') {
            $BackupPreviewCustomScrollTrack.Visibility = 'Visible'
            $BackupPreviewCustomScrollTrack.UpdateLayout()
        }

        $trackHeight = [double]$BackupPreviewCustomScrollTrack.ActualHeight
        if ($trackHeight -le 0) { return }

        $proportionalHeight = $trackHeight * ($viewport / $extent)
        $thumbHeight = [Math]::Min($trackHeight, [Math]::Max(24.0, $proportionalHeight))
        $BackupPreviewCustomScrollThumb.Height = $thumbHeight

        $maxTop = [Math]::Max(0.0, $trackHeight - $thumbHeight)
        $scrollable = [double]$BackupPreviewScroll.ScrollableHeight
        $top = 0.0
        if ($scrollable -gt 0 -and $maxTop -gt 0) {
            $ratio = [Math]::Max(0.0, [Math]::Min(1.0, ([double]$BackupPreviewScroll.VerticalOffset / $scrollable)))
            $top = $maxTop * $ratio
        }
        [Windows.Controls.Canvas]::SetTop($BackupPreviewCustomScrollThumb, $top)
    }
    finally { $script:UpdatingBackupPreviewCustomScroll = $false }
}

function Show-BackupPreview {
    param([object]$Row)
    if (-not $Row) { Hide-BackupPreview; return }
    try {
        $root = [IO.Path]::GetFullPath($script:Paths.BackupRoot).TrimEnd('\') + '\'
        $path = [IO.Path]::GetFullPath([string]$Row.Path)
        if (-not $path.StartsWith($root, [StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $path -PathType Leaf)) { throw (T 'PreviewUnavailable') }
        $content = [IO.File]::ReadAllText($path)
        if ($content.Length -gt 300000) { $content = $content.Substring(0,300000) + "`r`n`r`n" + (T 'PreviewTruncated') }
        $BackupPreviewTitle.Text = [string]$Row.Name
        $BackupPreviewMeta.Text = [string]$Row.DisplayDate + '  ·  ' + [string]$Row.DisplaySize
        $BackupPreviewText.Text = $content
        $BackupPreviewScroll.ScrollToHorizontalOffset(0)
        $BackupPreviewScroll.ScrollToVerticalOffset(0)
        $BackupPreviewPanel.Visibility = 'Visible'
        [void]$BackupPreviewScroll.Dispatcher.BeginInvoke([Action]{ Update-BackupPreviewCustomScrollbar }, [Windows.Threading.DispatcherPriority]::Loaded)
    }
    catch { Hide-BackupPreview; Show-AppError $_.Exception.Message }
}

function Remove-SelectedBackupFromUi {
    if (-not $BackupGrid.SelectedItem) { Show-AppError (T 'BackupRequired'); return }
    $selected = $BackupGrid.SelectedItem
    if (-not (Show-AppConfirm (TF 'ConfirmDeleteBackup' @([string]$selected.Name)))) { return }
    try {
        $parameters = @{ BackupPath=[string]$selected.Path; Confirm=$false }
        if ($script:DataRootArgument) { $parameters.DataRoot = $script:DataRootArgument }
        Remove-HuBackup @parameters | Out-Null
        Refresh-BackupHistory
        Show-AppInfo (T 'DeleteBackupSuccess')
    }
    catch { Show-AppError $_.Exception.Message }
}
