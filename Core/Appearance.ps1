function Set-AppBrushColor {
    param([Parameter(Mandatory = $true)][string]$Name, [Parameter(Mandatory = $true)][string]$Color)
    $brush = [Windows.Media.SolidColorBrush]::new([Windows.Media.ColorConverter]::ConvertFromString($Color))
    $window.Resources.Remove($Name)
    $window.Resources.Add($Name, $brush)
}

function Get-AppCornerRadiusValue {
    $value = 5
    try { $value = [int]$script:Settings.CornerRadius } catch { }
    if ($value -notin @(0,5,10)) { $value = 5 }
    return $value
}

function Apply-AppCornerRadius {
    $value = Get-AppCornerRadiusValue
    $script:Settings.CornerRadius = $value
    $window.Resources['AppCornerRadius'] = [Windows.CornerRadius]::new([double]$value)
    $window.Resources['AppCornerRadiusValue'] = [double]$value
    $window.Resources['AppTopCornerRadius'] = [Windows.CornerRadius]::new([double]$value,[double]$value,0,0)
    try {
        $chrome = [Windows.Shell.WindowChrome]::GetWindowChrome($window)
        if ($chrome) { $chrome.CornerRadius = [Windows.CornerRadius]::new([double]$value) }
    } catch { }
    try { if (Get-Command Sync-WindowFrame -ErrorAction SilentlyContinue) { Sync-WindowFrame } } catch { }
    try { if (Get-Command Update-AppThemeEditorCornerRadius -ErrorAction SilentlyContinue) { Update-AppThemeEditorCornerRadius } } catch { }
}

function Apply-AppUiScale {
    param([int]$Percent = [int]$script:Settings.UiScalePercent)

    if ($Percent -notin @(100,125,150,175,200)) { $Percent = 100 }
    $scale = [double]$Percent / 100.0
    $WindowFrame.LayoutTransform = [Windows.Media.ScaleTransform]::new($scale,$scale)
}

function Refresh-UiScaleOptions {
    $selected = [int]$script:Settings.UiScalePercent
    if ($selected -notin @(100,125,150,175,200)) { $selected = 100 }
    $options = @(
        [pscustomobject]@{Code=100;Name='100% (x1)'},
        [pscustomobject]@{Code=125;Name='125% (x1,25)'},
        [pscustomobject]@{Code=150;Name='150% (x1,5)'},
        [pscustomobject]@{Code=175;Name='175% (x1,75)'},
        [pscustomobject]@{Code=200;Name='200% (x2)'}
    )
    $UiScaleCombo.ItemsSource = $options
    $UiScaleCombo.SelectedItem = $options | Where-Object { [int]$_.Code -eq $selected } | Select-Object -First 1
}

function Get-SystemThemeMode {
    try {
        $personalize = Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name AppsUseLightTheme -ErrorAction Stop
        if ([int]$personalize.AppsUseLightTheme -eq 1) { return 'Light' }
    }
    catch { }
    return 'Dark'
}

function Get-AccentTextColor {
    param([Parameter(Mandatory = $true)][string]$Accent)
    $color = [Windows.Media.ColorConverter]::ConvertFromString($Accent)
    $luminance = (0.299 * $color.R) + (0.587 * $color.G) + (0.114 * $color.B)
    if ($luminance -ge 155) { return '#101215' }
    return '#FFFFFF'
}

function ConvertTo-AccentHex {
    param([AllowEmptyString()][string]$Value)
    $text = ([string]$Value).Trim()
    if ($text -match '^#?([0-9A-Fa-f]{6})$') { return ('#' + $Matches[1].ToUpperInvariant()) }
    if ($text -match '^(?:rgb\s*\()?\s*(\d{1,3})\s*[,; ]\s*(\d{1,3})\s*[,; ]\s*(\d{1,3})\s*\)?$') {
        $values = @([int]$Matches[1],[int]$Matches[2],[int]$Matches[3])
        if (($values | Where-Object { $_ -lt 0 -or $_ -gt 255 }).Count -eq 0) { return ('#{0:X2}{1:X2}{2:X2}' -f $values[0],$values[1],$values[2]) }
    }
    return $null
}

function Set-SavedAccent {
    param([Parameter(Mandatory = $true)][string]$Value)
    $normalized = ConvertTo-AccentHex $Value
    if (-not $normalized) { throw (T 'InvalidAccentColor') }
    $script:Settings.AccentColor = $normalized; $AccentColorBox.Text = $normalized
    $script:Settings = Save-AppSettingsObject -Settings $script:Settings
    Apply-AppTheme
    try { if ($script:ThemeEditorState) { Apply-AppThemePreview -Palette $script:ThemeEditorState.PreviewPalette -Base $script:ThemeEditorState.Base } } catch { }
}

function Set-RoundedTextBoxTemplate {
    param([Parameter(Mandatory=$true)][object[]]$TextBoxes)
    foreach ($textBox in $TextBoxes) {
        if (-not $textBox) { continue }
        $corner = [string](Get-AppCornerRadiusValue)
        [xml]$templateXaml = ('<ControlTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" TargetType="TextBox"><Border Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="__CORNER__"><ScrollViewer x:Name="PART_ContentHost" Focusable="False"/></Border></ControlTemplate>').Replace('__CORNER__',$corner)
        $reader = New-Object Xml.XmlNodeReader($templateXaml)
        $textBox.Template = [Windows.Markup.XamlReader]::Load($reader)
    }
}

function Enable-RoundedDialogFrame {
    param([Parameter(Mandatory=$true)][Windows.Window]$Dialog)
    $syncClip = {
        if ($Dialog.ActualWidth -gt 0 -and $Dialog.ActualHeight -gt 0) {
            $corner = [double](Get-AppCornerRadiusValue)
            $Dialog.Clip = [Windows.Media.RectangleGeometry]::new([Windows.Rect]::new(0,0,$Dialog.ActualWidth,$Dialog.ActualHeight),$corner,$corner)
        }
    }.GetNewClosure()
    $Dialog.Add_SizeChanged($syncClip)
    & $syncClip
}

function Set-DialogCloseButtonAppearance {
    param(
        [Parameter(Mandatory=$true)][Windows.Controls.Button]$Button,
        [Parameter(Mandatory=$true)][string]$ForegroundColor
    )
    $normalForeground = New-Object Windows.Media.SolidColorBrush ([Windows.Media.ColorConverter]::ConvertFromString($ForegroundColor))
    $corner = [string](Get-AppCornerRadiusValue)
    $closeTemplateText = '<ControlTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" TargetType="Button"><Border x:Name="CloseBorder" Background="Transparent" CornerRadius="__CORNER__"><Viewbox Width="11" Height="11"><Canvas Width="12" Height="12"><Path Stroke="{Binding Foreground, RelativeSource={RelativeSource TemplatedParent}}" StrokeThickness="1.5" StrokeStartLineCap="Round" StrokeEndLineCap="Round" Data="M1,1 L11,11 M11,1 L1,11"/></Canvas></Viewbox></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="CloseBorder" Property="Background" Value="#D13438"/><Setter Property="Foreground" Value="#FFFFFF"/></Trigger><Trigger Property="IsPressed" Value="True"><Setter TargetName="CloseBorder" Property="Opacity" Value="0.78"/></Trigger></ControlTemplate.Triggers></ControlTemplate>'
    [xml]$closeTemplateXaml = $closeTemplateText.Replace('__CORNER__',$corner)
    $reader = New-Object Xml.XmlNodeReader($closeTemplateXaml)
    $Button.Width = 30
    $Button.Height = 26
    $Button.MinWidth = 0
    $Button.MinHeight = 0
    $Button.Padding = 0
    $Button.Background = [Windows.Media.Brushes]::Transparent
    $Button.BorderThickness = 0
    $Button.Foreground = $normalForeground
    $Button.Content = $null
    $Button.Template = [Windows.Markup.XamlReader]::Load($reader)
}

function Apply-SidebarLayout {
    $collapsed = [bool]$script:Settings.SidebarCollapsed
    if ($collapsed) {
        $SidebarColumn.MinWidth = 64
        $SidebarColumn.MaxWidth = 64
        $SidebarColumn.Width = [Windows.GridLength]::new(64)
    }
    else {
        $SidebarColumn.MaxWidth = 320
        $SidebarColumn.MinWidth = 185
        $SidebarColumn.Width = [Windows.GridLength]::Auto
    }
    foreach ($text in @($NavHomeText,$NavHistoryText,$NavDiagnosticsText,$NavPerformanceText,$NavGamesText,$NavApplicationsText,$NavConnectionsText,$NavNetworkText,$NavFirewallText,$NavDnsText,$NavCommandsText,$NavDebloatText,$NavAdvancedText,$NavThisPcText,$NavSettingsText,$NavAboutText)) { $text.Visibility = if ($collapsed) { 'Collapsed' } else { 'Visible' } }
    foreach ($button in @($NavHome,$NavHistory,$NavDiagnostics,$NavPerformance,$NavGames,$NavApplications,$NavConnections,$NavNetwork,$NavFirewall,$NavDns,$NavCommands,$NavDebloat,$NavAdvanced,$NavThisPc,$NavSettings,$NavAbout)) {
        $button.HorizontalContentAlignment = if ($collapsed) { 'Center' } else { 'Left' }
        $button.Padding = if ($collapsed) { '0' } else { '12,0' }
        if ($button.Content -is [Windows.FrameworkElement]) { $button.Content.HorizontalAlignment = if ($collapsed) { 'Center' } else { 'Left' } }
    }
    $SidebarStatusPanel.Visibility = 'Visible'
    $SidebarStatusPanel.HorizontalAlignment = if ($collapsed) { 'Center' } else { 'Left' }
    $SidebarStatusPanel.Margin = if ($collapsed) { '0,0,0,13' } else { '18,0,10,13' }
    $TxtAdminMode.Visibility = if ($collapsed) { 'Collapsed' } else { 'Visible' }
    $SidebarAdminShield.Visibility = if ($collapsed) { 'Visible' } else { 'Collapsed' }
    $SidebarReadyPanel.HorizontalAlignment = if ($collapsed) { 'Center' } else { 'Left' }
    $SidebarReadyPanel.Margin = if ($collapsed) { '0,8,0,0' } else { '0,6,0,0' }
    $SidebarReadyDot.Margin = if ($collapsed) { '0' } else { '0,0,7,0' }
    $TxtReady.Visibility = if ($collapsed) { 'Collapsed' } else { 'Visible' }
    $SidebarToggleButton.HorizontalAlignment = if ($collapsed) { 'Center' } else { 'Right' }
    $SidebarToggleButton.Margin = if ($collapsed) { '0,0,0,4' } else { '0,0,8,4' }
    $SidebarToggleGlyph.Data = [Windows.Media.Geometry]::Parse($(if ($collapsed) { 'M6,3 L11,8 L6,13' } else { 'M10,3 L5,8 L10,13' }))
    $SidebarToggleButton.ToolTip = T $(if ($collapsed) { 'ExpandMenu' } else { 'CollapseMenu' })
}

function Refresh-CornerOptions {
    if (-not $CornerCombo) { return }
    $script:UpdatingCornerOptions = $true
    try {
        $selectedCode = [int](Get-AppCornerRadiusValue)
        $items = @(
            [pscustomobject]@{ Code=0; Name='0 px' },
            [pscustomobject]@{ Code=5; Name='5 px' },
            [pscustomobject]@{ Code=10; Name='10 px' }
        )
        $CornerCombo.ItemsSource = $items
        $CornerCombo.SelectedItem = $items | Where-Object { [int]$_.Code -eq $selectedCode } | Select-Object -First 1
        if (-not $CornerCombo.SelectedItem) { $CornerCombo.SelectedItem = $items[1] }
    }
    finally { $script:UpdatingCornerOptions = $false }
}


function Apply-Language {
    $TxtAppTitle.Text = T 'AppTitle'
    $TxtAdminMode.Text = T 'AdminMode'; $TxtReady.Text = T 'Ready'
    $NavHomeText.Text = T 'NavHome'; $NavHistoryText.Text = T 'NavHistory'; $NavDiagnosticsText.Text = T 'NavDiagnostics'; $NavPerformanceText.Text = T 'NavPerformance'; $NavGamesText.Text=T 'NavGames'; $NavApplicationsText.Text=T 'NavApplications'; $NavConnectionsText.Text=T 'NavConnections'; $NavNetworkText.Text=T 'NavNetwork'; $NavFirewallText.Text=T 'NavFirewall'; $NavDnsText.Text='DNS'; $NavCommandsText.Text = T 'NavCommands'; $NavDebloatText.Text=T 'NavDebloat'; $NavAdvancedText.Text=T 'NavAdvanced'; $NavThisPcText.Text=T 'NavThisPc'; $NavSettingsText.Text = T 'NavSettings'; $NavAboutText.Text = T 'NavAbout'; $NavHome.ToolTip=T 'NavHome'; $NavHistory.ToolTip=T 'NavHistory'; $NavDiagnostics.ToolTip=T 'NavDiagnostics'; $NavPerformance.ToolTip=T 'NavPerformance'; $NavGames.ToolTip=T 'NavGames'; $NavApplications.ToolTip=T 'NavApplications'; $NavConnections.ToolTip=T 'NavConnections'; $NavNetwork.ToolTip=T 'NavNetwork'; $NavFirewall.ToolTip=T 'NavFirewall'; $NavDns.ToolTip='DNS'; $NavCommands.ToolTip=T 'NavCommands'; $NavDebloat.ToolTip=T 'NavDebloat'; $NavAdvanced.ToolTip=T 'NavAdvanced'; $NavThisPc.ToolTip=T 'NavThisPc'; $NavSettings.ToolTip=T 'NavSettings'; $NavAbout.ToolTip=T 'NavAbout'
    $HomeTitle.Text = T 'HomeTitle'; $HomeSubtitle.Text = T 'HomeSubtitle'
    $SourceTitle.Text = T 'SourceTitle'; $SourceLabel.Text = T 'SourceLabel'; $SourcePlaceholder.Text = T 'SourcePlaceholder'; $ClearSourceButton.ToolTip=T 'ClearSource'; $TestSourceButton.Content = T 'TestButton'; $SourcePersistence.Text = T 'SourcePersistence'; $ManualAddButton.Content = T 'ManualAdd'; $ManualAddHint.Text = T 'ManualAddHint'
    $UpdateModeTitle.Text = T 'UpdateModeTitle'; $ModeMerge.Text = T 'ModeMerge'; $ModeMergeHint.Text = T 'ModeMergeHint'; $ModeReplace.Text = T 'ModeReplace'; $ModeReplaceHint.Text = T 'ModeReplaceHint'; $AutomaticBackup.Text = T 'AutomaticBackup'
    $AutomationTitle.Text = T 'AutomationTitle'; $DailyUpdate.Text = T 'DailyUpdate'; $DailyUpdateHint.Text = T 'DailyUpdateHint'; $UpdateTimeLabel.Text = T 'UpdateTime'; $FlushDnsCheck.Content = T 'FlushDns'
    $StatusTitle.Text = T 'StatusTitle'; $LastUpdateLabel.Text = T 'LastUpdate'; $NextRunLabel.Text = T 'NextRun'; $ManagedEntriesLabel.Text = T 'ManagedEntries'; $TaskStatusLabel.Text = T 'TaskStatus'
    $ActionsTitle.Text = T 'ActionsTitle'; $UpdateNowButton.Content = T 'UpdateNow'; $RestoreLatestButton.Content = T 'RestoreLatest'; $OpenHostsButton.Content = T 'OpenHosts'
    $HistoryTitle.Text = T 'HistoryTitle'; $HistorySubtitle.Text = T 'HistorySubtitle'; $DateColumn.Header = T 'ColumnDate'; $NameColumn.Header = T 'ColumnName'; $SizeColumn.Header = T 'ColumnSize'; $BackupPreviewTitle.Text = T 'PreviewTitle'; $ModifyBackupMenuItem.Header = T 'ModifyBackup'; $DeleteBackupMenuItem.Header = T 'DeleteBackup'; $DetailBackupMenuItem.Header = T 'BackupDetails'; $DeleteSelectedBackupButton.Content = T 'DeleteSelected'; $ClearHistoryButton.Content = T 'ClearHistory'; $OpenBackupFolderButton.Content = T 'OpenBackupFolder'; $RefreshHistoryButton.Content = T 'Refresh'; $RestoreSelectedButton.Content = T 'RestoreSelected'
    $DiagnosticsTitle.Text=T 'DiagnosticsTitle'; $DiagnosticsSubtitle.Text=T 'DiagnosticsSubtitle'; $DiagnosticsAdvancedTitle.Text=T 'DiagnosticsAdvancedTitle'; $BootDiagnosticsTitle.Text=T 'BootDiagnosticsTitle'; $BootDiagnosticsHint.Text=T 'BootDiagnosticsHint'; $VerboseLogonTitle.Text=T 'VerboseLogonTitle'; $VerboseLogonHint.Text=T 'VerboseLogonHint'; $SystemRestoreTitle.Text=T 'SystemRestoreTitle'; $SystemRestoreHint.Text=T 'SystemRestoreHint'; $CreateRestorePointButton.Content=T 'CreateRestorePoint'; $OpenSystemRestoreButton.Content=T 'RestoreSystem'; $ExportIntegrityLogButton.Content=T 'ExportLog'; $OpenIntegrityLogButton.Content=T 'OpenLogFile'; $OpenIntegrityLogFolderButton.Content=T 'OpenLogFolder'; $ClearIntegrityLogButton.Content=T 'ClearLog'
    $PerformanceTitle.Text=T 'PerformanceTitle'; $PerformanceSubtitle.Text=T 'PerformanceSubtitle'; $PerformanceWindowsTitle.Text=T 'PerformanceWindowsTitle'; $PerformanceGamesTitle.Text=T 'PerformanceGamesTitle'; $RefreshPerformanceButton.Content=T 'Refresh'; $DefenderCpuTitle.Text=T 'DefenderCpuTitle'; $DefenderCpuHint.Text=T 'DefenderCpuHint'; $ApplyDefenderCpuButton.Content=T 'Apply'; $BingSearchTitle.Text=T 'BingSearchTitle'; $BingSearchHint.Text=T 'BingSearchHint'; $SponsoredAppsTitle.Text=T 'SponsoredAppsTitle'; $SponsoredAppsHint.Text=T 'SponsoredAppsHint'; $SuggestionsTitle.Text=T 'SuggestionsTitle'; $SuggestionsHint.Text=T 'SuggestionsHint'; $PowerModeTitle.Text=T 'PowerModeTitle'; $PowerModeHint.Text=T 'PowerModeHint'; $PowerEcoButton.Content=T 'PowerEco'; $PowerNormalButton.Content=T 'PowerNormal'; $PowerHighButton.Content=T 'PowerHigh'; $TransparencyTitle.Text=T 'TransparencyTitle'; $TransparencyHint.Text=T 'TransparencyHint'; $AnimationsTitle.Text=T 'AnimationsTitle'; $AnimationsHint.Text=T 'AnimationsHint'; $ShutdownAnimationTitle.Text=T 'ShutdownAnimationTitle'; $ShutdownAnimationHint.Text=T 'ShutdownAnimationHint'; $HomeGalleryTitle.Text=T 'HomeGalleryTitle'; $HomeGalleryHint.Text=T 'HomeGalleryHint'; $ClockSecondsTitle.Text=T 'ClockSecondsTitle'; $ClockSecondsHint.Text=T 'ClockSecondsHint'; $NotificationsTitle.Text=T 'NotificationsTitle'; $NotificationsHint.Text=T 'NotificationsHint'; $EndTaskTitle.Text=T 'EndTaskTitle'; $EndTaskHint.Text=T 'EndTaskHint'; $LegacyContextTitle.Text=T 'LegacyContextTitle'; $LegacyContextHint.Text=T 'LegacyContextHint'; $LegacyExplorerTitle.Text=T 'LegacyExplorerTitle'; $LegacyExplorerHint.Text=T 'LegacyExplorerHint'; $GameDvrTitle.Text=T 'GameDvrTitle'; $GameDvrHint.Text=T 'GameDvrHint'; $BackgroundThrottleTitle.Text=T 'BackgroundThrottleTitle'; $BackgroundThrottleHint.Text=T 'BackgroundThrottleHint'; $LatencyTitle.Text=T 'LatencyTitle'; $LatencyHint.Text=T 'LatencyHint'; $GamingTasksTitle.Text=T 'GamingTasksTitle'; $GamingTasksHint.Text=T 'GamingTasksHint'; $BackgroundServicesTitle.Text=T 'BackgroundServicesTitle'; $BackgroundServicesHint.Text=T 'BackgroundServicesHint'; $TaskbarOptimizeTitle.Text=T 'TaskbarOptimizeTitle'; $TaskbarOptimizeHint.Text=T 'TaskbarOptimizeHint'; $StartupOptimizeTitle.Text=T 'StartupOptimizeTitle'; $StartupOptimizeHint.Text=T 'StartupOptimizeHint'; $PerformanceLogTitle.Text=T 'PerformanceLogTitle'; $ExportPerformanceLogButton.Content=T 'ExportLog'; $OpenPerformanceLogButton.Content=T 'OpenLogFile'; $OpenPerformanceLogFolderButton.Content=T 'OpenLogFolder'; $ClearPerformanceLogButton.Content=T 'ClearLog'
    $GamesTitle.Text=T 'GamesTitle';$GamesSubtitle.Text=T 'GamesSubtitle';$GamesOpenDownloadsButton.Content=T 'OpenDownloadsFolder';$GamesLaunchersTitle.Text=T 'LaunchersCategory';$GamesTweaksTitle.Text=T 'TweaksCategory';$GamesProgressTitle.Text=T 'DownloadProgress';$GamesLogTitle.Text=T 'GamesLogTitle';$GamesExportLogButton.Content=T 'ExportLog';$GamesOpenLogButton.Content=T 'OpenLogFile';$GamesClearLogButton.Content=T 'ClearLog'
    $ApplicationsTitle.Text=T 'ApplicationsTitle';$ApplicationsSubtitle.Text=T 'ApplicationsSubtitle';$ApplicationsOpenDownloadsButton.Content=T 'OpenDownloadsFolder';$ApplicationsAppsTitle.Text=T 'AppsCategory';$ApplicationsManufacturersTitle.Text=T 'ManufacturersCategory';$ApplicationsMiscTitle.Text=T 'RedistributablesCategory';$ApplicationsProgressTitle.Text=T 'DownloadProgress';$ApplicationsLogTitle.Text=T 'ApplicationsLogTitle';$ApplicationsExportLogButton.Content=T 'ExportLog';$ApplicationsOpenLogButton.Content=T 'OpenLogFile';$ApplicationsClearLogButton.Content=T 'ClearLog';if(Get-Command Initialize-HuSoftwareCatalogUi -ErrorAction SilentlyContinue){Initialize-HuSoftwareCatalogUi}
    $ConnectionsTitle.Text=T 'ConnectionsTitle'; $ConnectionsSubtitle.Text=T 'ConnectionsSubtitle'; $LiveConnectionsTitle.Text=T 'LiveConnectionsTitle'; $LiveConnectionsHint.Text=T 'LiveConnectionsHint'; $RefreshConnectionsButton.Content=T 'Refresh'; $ConnectionAppColumn.Header=T 'FirewallApplication'; $ConnectionPidColumn.Header='PID'; $ConnectionRemoteColumn.Header=T 'RemoteAddress'; $ConnectionProtocolColumn.Header=T 'Protocol'; $ConnectionStateColumn.Header=T 'ConnectionState'; $ConnectionPathColumn.Header=T 'DetailPath'; $ConnectionOpenLocationMenuItem.Header=T 'OpenLocation'; $ConnectionStopMenuItem.Header=T 'StopProcess'; $ConnectionFirewallMenuItem.Header=T 'CreateFirewallRule'; $ConnectionPingMenuItem.Header=T 'TestWithPing'; $OpenConnectionLocationButton.Content=T 'OpenLocation'; $StopConnectionProcessButton.Content=T 'StopProcess'; $ConnectionToFirewallButton.Content=T 'CreateFirewallRule'; $ActiveConnectionCardTitle.Text=T 'ActiveConnectionTitle'; $NetworkToggleTitle.Text=T 'NetworkToggleTitle'
    $NetworkTitle.Text=T 'NetworkTitle'; $NetworkSubtitle.Text=T 'NetworkSubtitle'; $NetworkCommandsTitle.Text=T 'NetworkDiagnosticsTitle'; $NetworkTargetPlaceholder.Text=T 'NetworkTargetPlaceholder'; $NetworkDiagnosticButton.Content=T 'Diagnose'; $TraceRouteButton.Content=T 'TraceRoute'; $NetstatHint.Text=T 'NetstatHint'; $IpconfigHint.Text=T 'IpconfigHint'; $FlushDnsNowHint.Text=T 'FlushDnsNowHint'; $ReleaseIpHint.Text=T 'ReleaseIpHint'; $RenewIpHint.Text=T 'RenewIpHint'; $NetworkLogTitle.Text=T 'NetworkLogTitle'; $ExportNetworkLogButton.Content=T 'ExportLog'; $OpenNetworkLogButton.Content=T 'OpenLogFile'; $OpenNetworkLogFolderButton.Content=T 'OpenLogFolder'; $ClearNetworkLogButton.Content=T 'ClearLog'; $OpenPortsTitle.Text=T 'OpenPortsTitle'; $OpenPortsHint.Text=T 'OpenPortsHint'; $RefreshOpenPortsButton.Content=T 'Refresh'; $OpenPortProtocolColumn.Header=T 'Protocol'; $OpenPortAddressColumn.Header=T 'LocalAddress'; $OpenPortNumberColumn.Header=T 'Port'; $OpenPortAppColumn.Header=T 'FirewallApplication'; $OpenPortPidColumn.Header='PID'; $OpenPortPathColumn.Header=T 'DetailPath'; $OpenPortFirewallMenuItem.Header=T 'CreateFirewallRule'; $OpenPortToFirewallButton.Content=T 'CreateFirewallRule'; $ProxyTitle.Text=T 'ProxyTitle'; $ProxyHint.Text=T 'ProxyHint'; $EnableProxyButton.Content=T 'ApplyDnsPreset'; $DisableProxyButton.Content=T 'Disable'; $ResetProxyButton.Content=T 'ResetProxy'; $PingTitle.Text=T 'PingTitle'; $PingHint.Text=T 'PingHint'; $PingTargetPlaceholder.Text=T 'PingTargetPlaceholder'; $PingButton.Content=T 'PingButton'; $PingLogTitle.Text=T 'PingLogTitle'; $ExportPingLogButton.Content=T 'ExportLog'; $OpenPingLogButton.Content=T 'OpenLogFile'; $OpenPingLogFolderButton.Content=T 'OpenLogFolder'; $ClearPingLogButton.Content=T 'ClearLog'; foreach($b in @($NetstatButton,$IpconfigButton,$FlushDnsNowButton,$ReleaseIpButton,$RenewIpButton)){ $b.Content=T 'Execute' }; Update-NetworkTargetPlaceholders
    $DebloatTitle.Text=T 'DebloatTitle'; $DebloatSubtitle.Text=T 'DebloatSubtitle'; $DebloatCleanupTitle.Text=T 'NavDebloat'; $AppxManagerTitle.Text=T 'AppxManagerTitle'; $AppxManagerHint.Text=T 'AppxManagerHint'; $AppxScanButton.Content=T 'AppxScan'; $AppxLegendRecommended.Text=T 'AppxLegendRecommended'; $AppxLegendOptional.Text=T 'AppxLegendOptional'; $AppxLegendProtected.Text=T 'AppxLegendProtected'; $AppxLegendHidden.Text=T 'AppxLegendHidden'; $AppxOpenLocationMenuItem.Header=T 'OpenLocation'; $AppxDetailsMenuItem.Header=T 'BackupDetails'; $AppxStandaloneRemoveMenuItem.Header=T 'AppxContextStandaloneRemove'; $AppxHideMenuItem.Header=T 'AppxContextHide'; $AppxSelectRecommendedButton.Content=T 'AppxSelectRecommended'; $AppxSelectOptionalButton.Content=T 'AppxSelectOptional'; $AppxSelectProtectedButton.Content=T 'AppxSelectProtected'; $AppxSelectHiddenButton.Content=T 'AppxSelectHidden'; $AppxClearSelectionButton.Content=T 'AppxClearSelection'; $AppxNameColumn.Header=T 'AppxNameHeader'; $AppxDescriptionColumn.Header=T 'AppxDescriptionHeader'; $AppxRemoveUserDataCheck.Content=T 'AppxRemoveUserData'; $AppxRemoveButton.Content=T 'AppxRemoveSelected'; $AppxLogTitle.Text=T 'AppxLogTitle'; $ExportAppxLogButton.Content=T 'ExportLog'; $OpenAppxLogButton.Content=T 'OpenLogFile'; $OpenAppxLogFolderButton.Content=T 'OpenLogFolder'; $AppxClearLogButton.Content=T 'ClearLog'; $CleanupLogTitle.Text=T 'CleanupLogTitle'; $ExportCleanupLogButton.Content=T 'ExportLog'; $OpenCleanupLogButton.Content=T 'OpenLogFile'; $OpenCleanupLogFolderButton.Content=T 'OpenLogFolder'; $ClearCleanupLogButton.Content=T 'ClearLog'; if (-not $script:AppxState.InventoryLoaded -and -not $script:AppxState.InventoryLoading) { $AppxStatusText.Text=T 'AppxStatusInitial' }; if ($script:AppxState.InventoryLoaded -and (Get-Command Update-AppxLocalizedDescriptions -ErrorAction SilentlyContinue)) { Update-AppxLocalizedDescriptions; if (Get-Command Update-AppxLegendCounts -ErrorAction SilentlyContinue) { Update-AppxLegendCounts }; Update-AppxFilter }
    $AdvancedTitle.Text=T 'AdvancedTitle'; $AdvancedSubtitle.Text=T 'AdvancedSubtitle'; $AdvancedOneDriveTitle.Text=T 'AdvancedOneDriveTitle'; $AdvancedOneDriveHint.Text=T 'AdvancedOneDriveHint'; $AdvancedOneDriveButton.Content=T 'AdvancedOneDriveButton'; $AdvancedTelemetryTitle.Text=T 'AdvancedTelemetryTitle'; $AdvancedTelemetryHint.Text=T 'AdvancedTelemetryHint'; $AdvancedTelemetryBlockLabel.Text=T 'AdvancedTelemetryBlockLabel'; $AdvancedTelemetryPushedButton.Content=T 'AdvancedModePushed'; $AdvancedTelemetryAggressiveButton.Content=T 'AdvancedModeAggressive'; $AdvancedTelemetryDisableHostsButton.Content=T 'AdvancedTelemetryDisableHosts'; if (Get-Command Update-AdvancedTelemetryBlockState -ErrorAction SilentlyContinue) { Update-AdvancedTelemetryBlockState }; $AdvancedEdgeTitle.Text=T 'AdvancedEdgeTitle'; $AdvancedEdgeHint.Text=T 'AdvancedEdgeHint'; $AdvancedEdgeButton.Content=T 'AdvancedEdgeButton'; $AdvancedAiTitle.Text=T 'AdvancedAiTitle'; $AdvancedAiHint.Text=T 'AdvancedAiHint'; $AdvancedAiButton.Content=T 'AdvancedAiButton'; $AdvancedLogTitle.Text=T 'AdvancedLogTitle'; $ExportAdvancedLogButton.Content=T 'ExportLog'; $OpenAdvancedLogButton.Content=T 'OpenLogFile'; $OpenAdvancedLogFolderButton.Content=T 'OpenLogFolder'; $AdvancedClearLogButton.Content=T 'AdvancedClearLog'
    $CommandsTitle.Text=T 'CommandsTitle'; $CommandsSubtitle.Text=T 'CommandsSubtitle'; $WindowsCommandsTitle.Text=T 'WindowsCommandsTitle'; $KillPowerShellTitle.Text=T 'KillPowerShellTitle'; $KillPowerShellHint.Text=T 'KillPowerShellHint'; $ClearTempTitle.Text=T 'ClearTempTitle'; $ClearTempHint.Text=T 'ClearTempHint'; $RestartExplorerTitle.Text=T 'RestartExplorerTitle'; $RestartExplorerHint.Text=T 'RestartExplorerHint'; $PowerOptionsTitle.Text=T 'PowerOptionsTitle'; $PowerOptionsHint.Text=T 'PowerOptionsHint'; $ShutdownButton.Content=T 'ShutdownComputer'; $RestartComputerButton.Content=T 'RestartComputer'; $GodModeToolTitle.Text=T 'GodModeToolTitle'; $GodModeToolHint.Text=T 'GodModeToolHint'; $GodModeButton.Content=T 'OpenGodMode'; $SystemConsolesTitle.Text=T 'SystemConsolesTitle'; $ThisPcTaskManagerTitle.Text=T 'TaskManagerTitle'; $ThisPcTaskManagerHint.Text=T 'TaskManagerHint'; $ThisPcTaskManagerButton.Content=T 'OpenTool'; $MsConfigTitle.Text=T 'MsConfigTitle'; $MsConfigHint.Text=T 'MsConfigHint'; $ServicesTitle.Text=T 'ServicesTitle'; $ServicesHint.Text=T 'ServicesHint'; $GroupPolicyTitle.Text=T 'GroupPolicyTitle'; $GroupPolicyHint.Text=T 'GroupPolicyHint'; $RegistryTitle.Text=T 'RegistryTitle'; $RegistryHint.Text=T 'RegistryHint'; $TaskSchedulerTitle.Text=T 'TaskSchedulerTitle'; $TaskSchedulerHint.Text=T 'TaskSchedulerHint'; $EventViewerTitle.Text=T 'EventViewerTitle'; $EventViewerHint.Text=T 'EventViewerHint'; $WingetUpgradeTitle.Text=T 'WingetUpgradeTitle'; $WingetUpgradeHint.Text=T 'WingetUpgradeHint'; $WingetUpgradeButton.Content=T 'SearchWindowsUpdates'; foreach($b in @($MsConfigButton,$ServicesButton,$GroupPolicyButton,$RegeditButton,$TaskSchedulerButton,$EventViewerButton)){ $b.Content=T 'OpenTool' }; foreach($b in @($KillPowerShellButton,$ClearTempButton,$RestartExplorerButton)){ $b.Content=T 'Execute' }; $WindowsLogTitle.Text=T 'WindowsLogTitle'; $ExportWindowsLogButton.Content=T 'ExportLog'; $OpenWindowsLogButton.Content=T 'OpenLogFile'; $OpenWindowsLogFolderButton.Content=T 'OpenLogFolder'; $ClearWindowsLogButton.Content=T 'ClearLog'; $IntegrityTitle.Text=T 'IntegrityTitle'; $DismScanTitle.Text=T 'DismScanTitle'; $DismScanHint.Text=T 'DismScanHint'; $DismScanButton.Content=T 'Analyze'; $DismRepairTitle.Text=T 'DismRepairTitle'; $DismRepairHint.Text=T 'DismRepairHint'; $DismRepairButton.Content=T 'Repair'; $SfcToolTitle.Text=T 'SfcToolTitle'; $SfcToolHint.Text=T 'SfcToolHint'; $SfcScanButton.Content=T 'RunSfcScan'; $ChkdskTitle.Text=T 'ChkdskTitle'; $ChkdskHint.Text=T 'ChkdskHint'; $ChkdskButton.Content=T 'Analyze'; $DriveHealthTitle.Text=T 'DriveHealthTitle'; $DriveHealthHint.Text=T 'DriveHealthHint'; $DriveHealthButton.Content=T 'CheckHealth'; $PathRepairTitle.Text=T 'PathRepairTitle'; $PathRepairHint.Text=T 'PathRepairHint'; $RepairPathButton.Content=T 'RepairPath'; $IntegrityLogTitle.Text=T 'IntegrityLogTitle'; $IntegrityLogHint.Text=T 'IntegrityLogHint'
    $LocalUserTitle.Text=T 'LocalUserTitle'; $LocalUserHint.Text=T 'LocalUserHint'; $LocalUserNameLabel.Text=T 'LocalUserNameLabel'; $LocalUserPasswordLabel.Text=T 'LocalUserPasswordLabel'; $LocalUserAdminCheck.Content=T 'LocalUserAdminCheck'; $CreateLocalUserButton.Content=T 'CreateLocalUser'; if(Get-Command Update-HuLocalUserControls -ErrorAction SilentlyContinue){Update-HuLocalUserControls}
    $SafeModeBootTitle.Text=T 'SafeModeBootTitle'; $SafeModeBootHint.Text=T 'SafeModeBootHint'; $SafeModeBootButton.Content=T 'SafeModeBootButton'; $DeleteSafeModeBootButton.Content=T 'DeleteBackup'; if(Get-Command Update-HuSafeModeBootControls -ErrorAction SilentlyContinue){Update-HuSafeModeBootControls}
    $FirewallTitle.Text=T 'FirewallTitle'; $FirewallSubtitle.Text=T 'FirewallSubtitle'; $FirewallAddTitle.Text=T 'FirewallAddTitle'; $FirewallAddHint.Text=T 'FirewallAddHint'; $BrowseFirewallProgramsButton.Content=T 'BrowseApplications'; $BrowseFirewallFolderButton.Content=T 'BrowseFolder'; $FirewallPendingTitle.Text=T 'SelectedItemsTitle'; $FirewallPendingNameColumn.Header=T 'FirewallApplication'; $FirewallPendingPathColumn.Header=T 'DetailPath'; $RemovePendingFirewallButton.Content=T 'RemoveFromSelection'; $ClearPendingFirewallButton.Content=T 'ClearSelection'; $FirewallInboundCheck.Content=T 'FirewallInbound'; $FirewallOutboundCheck.Content=T 'FirewallOutbound'; $FirewallActionLabel.Text=T 'FirewallAction'; $FirewallProfileLabel.Text=T 'FirewallProfile'; $AddFirewallRulesButton.Content=T 'FirewallAddRules'; $FirewallRulesTitle.Text=T 'FirewallRulesTitle'; $FirewallNameColumn.Header=T 'FirewallApplication'; $FirewallPathColumn.Header=T 'DetailPath'; $FirewallDirectionColumn.Header=T 'FirewallDirection'; $FirewallActionColumn.Header=T 'FirewallAction'; $FirewallProfileColumn.Header=T 'FirewallProfile'; $FirewallStatusColumn.Header=T 'StatusTitle'; $DeleteFirewallMenuItem.Header=T 'DeleteSelected'; $DeleteFirewallRulesButton.Content=T 'DeleteSelected'; $EnableFirewallRulesButton.Content=T 'Enable'; $DisableFirewallRulesButton.Content=T 'Disable'; $OpenAdvancedFirewallButton.Content=T 'OpenAdvancedFirewall'; $RefreshFirewallButton.Content=T 'Refresh'; Refresh-PendingFirewallSelection; $firewallActionCode=if($FirewallActionCombo.SelectedItem){[string]$FirewallActionCombo.SelectedItem.Code}else{'Allow'}; $firewallActions=@([pscustomobject]@{Code='Allow';Name=(T 'Allow')},[pscustomobject]@{Code='Block';Name=(T 'Block')}); $FirewallActionCombo.ItemsSource=$firewallActions; $FirewallActionCombo.SelectedItem=$firewallActions|Where-Object Code -eq $firewallActionCode|Select-Object -First 1; $firewallProfileCode=if($FirewallProfileCombo.SelectedItem){[string]$FirewallProfileCombo.SelectedItem.Code}else{'Any'}; $firewallProfiles=@([pscustomobject]@{Code='Any';Name=(T 'AllProfiles')},[pscustomobject]@{Code='Private';Name=(T 'PrivateProfile')},[pscustomobject]@{Code='Public';Name=(T 'PublicProfile')},[pscustomobject]@{Code='Domain';Name=(T 'DomainProfile')}); $FirewallProfileCombo.ItemsSource=$firewallProfiles; $FirewallProfileCombo.SelectedItem=$firewallProfiles|Where-Object Code -eq $firewallProfileCode|Select-Object -First 1
    $DnsTitle.Text='DNS'; $DnsSubtitle.Text=T 'DnsSubtitle'; $DnsAdapterTitle.Text=T 'DnsAdapterTitle'; $DnsAdapterHint.Text=T 'DnsAdapterHint'; $RefreshDnsAdaptersButton.Content=T 'Refresh'; $CurrentDnsTitle.Text=T 'CurrentDnsTitle'; $DnsPresetsTitle.Text=T 'DnsPresetsTitle'; $DnsPresetsHint.Text=T 'DnsPresetsHint'; $DnsPresetIpv4Label.Text='IPv4'; $DnsPresetIpv6Label.Text='IPv6'; $ApplyDnsPresetButton.Content=T 'ApplyDnsPreset'; $CustomDnsTitle.Text=T 'CustomDnsTitle'; $CustomDnsHint.Text=T 'CustomDnsHint'; $DnsIpv4PrimaryLabel.Text=T 'DnsIpv4Primary'; $DnsIpv4SecondaryLabel.Text=T 'DnsIpv4Secondary'; $DnsIpv6PrimaryLabel.Text=T 'DnsIpv6Primary'; $DnsIpv6SecondaryLabel.Text=T 'DnsIpv6Secondary'; $ApplyCustomDnsButton.Content=T 'ApplyCustomDns'; $DnsActionsTitle.Text=T 'DnsActionsTitle'; $DnsActionsHint.Text=T 'DnsActionsHint'; $ResetAutomaticDnsButton.Content=T 'ResetAutomaticDns'; $TestDnsButton.Content=T 'TestDns'; $FlushDnsPageButton.Content=T 'FlushDnsPage'
    $ThisPcTitle.Text=T 'ThisPcTitle'; $ThisPcSubtitle.Text=T 'ThisPcSubtitle'; $CopySpecsButton.Content=T 'Copy'; $RefreshSpecsButton.Content=T 'Refresh'; $PcOverviewTitle.Text=T 'PcOverviewTitle'; $ComputerNameLabel.Text=T 'ComputerName'; $RenameComputerButton.Content=T 'RenameComputer'; $OperatingSystemLabel.Text='OS'; $BuildLabel.Text='Build'; $SystemTypeLabel.Text=T 'SystemType'; $UptimeLabel.Text=T 'Uptime'; $ProcessorTitle.Text=T 'Processor'; $MemoryTitle.Text=T 'Memory'; $GraphicsTitle.Text=T 'Graphics'; $MotherboardTitle.Text=T 'ThisPcMotherboard'; $StorageTitle.Text=T 'ThisPcStorage'; $NetworkInfoTitle.Text=T 'NetworkTitle'; $DisplayTitle.Text=T 'ThisPcDisplayTitle'; $DisplayEmptyText.Text=T 'ThisPcDisplayNone'; $DisplayConnectionLabel.Text=(T 'ThisPcDisplayConnection') + ' :'; $DisplayResolutionLabel.Text=T 'ThisPcDisplayResolution'; $DisplayRefreshLabel.Text=T 'ThisPcDisplayRefresh'; $DisplayScalingLabel.Text=T 'ThisPcDisplayScaling'; foreach($button in @($DisplayApplyResolutionButton,$DisplayApplyRefreshButton,$DisplayApplyScalingButton)){ $button.Content=T 'Apply' }; if(Get-Command Update-HuDisplayCarousel -ErrorAction SilentlyContinue){Update-HuDisplayCarousel}
    $SettingsTitle.Text = T 'SettingsTitle'; $SettingsSubtitle.Text = T 'SettingsSubtitle'; $LanguageLabel.Text = T 'Language'; $LanguageHint.Text = T 'LanguageHint'; $AppearanceTitle.Text = T 'AppearanceTitle'; $AppearanceHint.Text = T 'AppearanceHint'; $ThemeLabel.Text = T 'ThemeLabel'; $ThemeHint.Text = T 'ThemeHint'; $CreateThemeButton.Content = T 'ThemeCreate'; $ModifyThemeButton.Content = T 'ThemeModify'; $DeleteThemeButton.Content = T 'DeleteBackup'; $TitlebarAnimationLabel.Text = T 'TitlebarAnimation'; $TitlebarAnimationHint.Text = T 'TitlebarAnimationHint'; $AccentLabel.Text = T 'AccentLabel'; $AccentHint.Text = T 'AccentHint'; $CornerLabel.Text = T 'CornerLabel'; $CornerHint.Text = T 'CornerHint'; $UiScaleLabel.Text=T 'UiScaleLabel'; $UiScaleHint.Text=T 'UiScaleHint'; $ApplyUiScaleButton.Content=T 'Apply'; $ChooseAccentButton.Content = T 'ChooseAccent'; $ResetAccentButton.Content = T 'ResetAccent'; $DataFolderLabel.Text = T 'DataFolder'; $DataFolderHint.Text = T 'DataFolderHint'; $ChooseDataFolderButton.Content = T 'ChooseAccent'; $ResetDataFolderButton.Content = T 'ResetAccent'; $OpenDataFolderButton.Content = T 'OpenDataFolder'
    $AboutTitle.Text = T 'AboutTitle'; $AboutSubtitle.Text = ''; $AboutSubtitle.Visibility='Collapsed'; $AboutProductName.Text=T 'ProductName'; $AboutDescription.Text = T 'AboutDescription'; $AboutStarHint.Text=T 'AboutStarHint'; $AboutSupportTitle.Text=T 'SupportTitle'; $GitHubButtonText.Text = 'GitHub'; $RepositoryButtonText.Text='GitHub'; $KoFiButtonText.Text = 'Ko-fi'; $VersionText.Text = (TF 'Version' @('1.0.0')); $UpdateCheckTitle.Text = T 'UpdateCheckTitle'; if ([string]::IsNullOrWhiteSpace([string]$UpdateCheckStatus.Tag)) { $UpdateCheckStatus.Text = T 'UpdateCheckHint' }; $CheckUpdatesButton.Content = T 'CheckUpdates'; $UpdateResultAction.Content = T 'OpenRelease'; $UpdateResultClose.ToolTip = T 'Dismiss'
    Refresh-ThemeOptions
    Refresh-CornerOptions
    Apply-SidebarLayout
    Update-SourceBanner
    if ($FirewallGrid.ItemsSource) { Refresh-FirewallRules -Force }
    if ($script:ThisPcCurrentSnapshot) { Apply-HuThisPcSnapshot -Snapshot $script:ThisPcCurrentSnapshot -SkipCacheSave } elseif ($script:SpecsLoaded) { Refresh-ThisPcInformation }
    if (-not $script:Busy) { $StatusBarText.Text = ''; $StatusBarText.Visibility = 'Collapsed' }
}
