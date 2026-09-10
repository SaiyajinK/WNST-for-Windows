$window.Add_Closing({
    if (-not $script:SkipSaveOnClose) {
        try {
            $saveTimer.Stop()
            $script:PageRefreshTimer.Stop()
            if ($script:ThisPcRefreshTimer) { $script:ThisPcRefreshTimer.Stop() }
            if (@($script:ThisPcRefreshTasks).Count -gt 0) { try { Clear-HuThisPcRefreshWorker } catch { } }
            try { Close-HuSharedRunspacePool } catch { }
            Save-CurrentSettings
        }
        catch { }
    }
})

$window.Add_Loaded({
    $script:Initializing = $false
    Apply-Language
    Apply-AppTheme
    Refresh-DnsPresetDetails
    $thisPcCacheLoaded = Import-HuThisPcCache
    if (-not $thisPcCacheLoaded) { Initialize-HuThisPcQuickInformation }
    if ($script:ResumeAfterRestart) { Show-Page Debloat }
    else { Show-Page ThisPc }
    if ($thisPcCacheLoaded) {
        $window.Dispatcher.BeginInvoke([Action]{ Refresh-ThisPcInformation -DynamicOnly }) | Out-Null
    }

    $window.Dispatcher.BeginInvoke([Action]{ Invoke-AppxPendingStartMenuCleanupCheck }) | Out-Null

    if ($DailyUpdateCheck.IsChecked -and (Test-HuSourceAddress -SourceUrl $SourceUrlBox.Text)) {
        $window.Dispatcher.BeginInvoke([Action]{
            try {
                Install-HuScheduledTask -UpdateScriptPath (Join-Path $script:AppRoot 'Invoke-WNSTUpdate.ps1') -At ([string]$UpdateTimeCombo.SelectedItem) | Out-Null
            }
            catch { Show-AppError $_.Exception.Message }
        }) | Out-Null
    }
})
