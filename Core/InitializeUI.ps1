for ($hour = 0; $hour -lt 24; $hour++) {
    foreach ($minute in @(0, 30)) { [void]$UpdateTimeCombo.Items.Add(('{0:D2}:{1:D2}' -f $hour, $minute)) }
}

$primaryNavigationOrder = @(
    $SidebarToggleButton,$NavHome,$NavHistory,$NavCommands,$NavPerformance,$NavDebloat,$NavDiagnostics,$NavAdvanced,
    $NavNetwork,$NavConnections,$NavDns,$NavFirewall,$NavGames,$NavApplications
)
foreach ($navigationControl in $primaryNavigationOrder) {
    if ($navigationControl -and $PrimaryNavPanel.Children.Contains($navigationControl)) {
        [void]$PrimaryNavPanel.Children.Remove($navigationControl)
        [void]$PrimaryNavPanel.Children.Add($navigationControl)
    }
}

$SourceUrlBox.Text = [string]$script:Settings.SourceUrl
$DailyUpdateCheck.IsChecked = [bool]$script:Settings.DailyEnabled
$UpdateTimeCombo.SelectedItem = [string]$script:Settings.UpdateTime
if (-not $UpdateTimeCombo.SelectedItem) { $UpdateTimeCombo.SelectedItem = '09:00' }
$MergeModeRadio.IsChecked = [string]$script:Settings.UpdateMode -ne 'Replace'
$ReplaceModeRadio.IsChecked = [string]$script:Settings.UpdateMode -eq 'Replace'
$AutomaticBackupCheck.IsChecked = [bool]$script:Settings.BackupBeforeChange
$FlushDnsCheck.IsChecked = [bool]$script:Settings.FlushDns
$LanguageCombo.ItemsSource = $availableLanguages
$LanguageCombo.SelectedItem = $availableLanguages | Where-Object Code -eq $script:Settings.Language | Select-Object -First 1
$AccentColorBox.Text = if ([string]$script:Settings.AccentColor -match '^#[0-9A-Fa-f]{6}$') { ([string]$script:Settings.AccentColor).ToUpperInvariant() } else { '#1A9FFF' }
$TitlebarAnimationToggle.IsChecked = [bool]$script:Settings.TitlebarAnimation
Apply-AppCornerRadius
Refresh-CornerOptions
Apply-AppUiScale
Refresh-UiScaleOptions
$DataFolderValue.Text = $script:Paths.DataRoot
$ChooseDataFolderButton.IsEnabled = -not [bool]$script:DataRootArgument
$ResetDataFolderButton.IsEnabled = (-not [bool]$script:DataRootArgument) -and ([IO.Path]::GetFullPath($script:Paths.DataRoot).TrimEnd('\') -ne [IO.Path]::GetFullPath((Get-HuStandardDataRoot)).TrimEnd('\'))

$script:AvatarWebClient = $null
$script:AvatarDownloadStarted = $false

function Start-HuRemoteAvatarLoad {
    if ($script:AvatarDownloadStarted) { return }
    $script:AvatarDownloadStarted = $true

    try {
        $client = New-Object Net.WebClient
        $script:AvatarWebClient = $client
        $client.Add_DownloadDataCompleted({
            param($sender,$eventArgs)
            try {
                if ($eventArgs.Cancelled -or $eventArgs.Error -or -not $eventArgs.Result) { return }
                $bytes = [byte[]]$eventArgs.Result
                $action = [Action]({
                    try {
                        $stream = [IO.MemoryStream]::new($bytes)
                        try {
                            $bitmap = New-Object Windows.Media.Imaging.BitmapImage
                            $bitmap.BeginInit()
                            $bitmap.CacheOption = [Windows.Media.Imaging.BitmapCacheOption]::OnLoad
                            $bitmap.StreamSource = $stream
                            $bitmap.EndInit()
                            $bitmap.Freeze()
                            $AboutAvatar.Source = $bitmap
                        }
                        finally { $stream.Dispose() }
                    }
                    catch { }
                }.GetNewClosure())
                [void]$window.Dispatcher.BeginInvoke($action)
            }
            finally {
                try { $sender.Dispose() } catch { }
                $script:AvatarWebClient = $null
            }
        })
        $client.DownloadDataAsync([Uri]'https://github.com/SaiyajinK.png?size=200')
    }
    catch {
        $script:AvatarWebClient = $null
    }
}

$window.Add_Loaded({ Start-HuRemoteAvatarLoad })

$saveTimer = New-Object Windows.Threading.DispatcherTimer
$saveTimer.Interval = [TimeSpan]::FromMilliseconds(650)
$saveTimer.Add_Tick({
    $saveTimer.Stop()
    if (-not $script:Initializing) {
        try { Save-CurrentSettings; $StatusBarText.Text = T 'SourceNotTested' } catch { Show-AppError $_.Exception.Message }
    }
})
