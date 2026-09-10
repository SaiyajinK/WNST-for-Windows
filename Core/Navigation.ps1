$script:PageControlMap = @{
    Home        = $HomePage
    History     = $HistoryPage
    Diagnostics = $DiagnosticsPage
    Performance = $PerformancePage
    Games       = $GamesPage
    Applications = $ApplicationsPage
    Connections = $ConnectionsPage
    Network     = $NetworkPage
    Commands    = $CommandsPage
    Debloat     = $DebloatPage
    Advanced    = $AdvancedPage
    Firewall    = $FirewallPage
    Dns         = $DnsPage
    ThisPc      = $ThisPcPage
    Settings    = $SettingsPage
    About       = $AboutPage
}

$script:NavControlMap = @{
    Home        = $NavHome
    History     = $NavHistory
    Diagnostics = $NavDiagnostics
    Performance = $NavPerformance
    Games       = $NavGames
    Applications = $NavApplications
    Connections = $NavConnections
    Network     = $NavNetwork
    Commands    = $NavCommands
    Debloat     = $NavDebloat
    Advanced    = $NavAdvanced
    Firewall    = $NavFirewall
    Dns         = $NavDns
    ThisPc      = $NavThisPc
    Settings    = $NavSettings
    About       = $NavAbout
}

$script:CurrentPage = 'Home'
$script:PendingRefreshPage = ''
$script:PageRefreshTimer = New-Object Windows.Threading.DispatcherTimer
$script:PageRefreshTimer.Interval = [TimeSpan]::FromMilliseconds(40)
$script:PageRefreshTimer.Add_Tick({
    $script:PageRefreshTimer.Stop()
    $page = [string]$script:PendingRefreshPage
    if ([string]::IsNullOrWhiteSpace($page) -or $page -ne $script:CurrentPage) { return }

    switch ($page) {
        'Home'        { Update-StatusPanel; break }
        'History'     { Refresh-BackupHistory; break }
        'Diagnostics' { Refresh-DiagnosticsState; break }
        'Performance' { Refresh-PerformanceState; break }
        'Games'       { Refresh-GamesState; break }
        'Applications' { Refresh-HuDownloadsButtons; break }
        'Commands'    { Refresh-WindowsActionState; break }
        'Debloat'     { Refresh-DebloatCleanupState; break }
        'Connections' { Refresh-ConnectionsList; Refresh-NetworkToggleState; break }
        'Network'     { Refresh-OpenPorts; Refresh-ProxyStatus; break }
        'Firewall'    { Refresh-FirewallRules; break }
        'Dns'         { Refresh-DnsAdapters; break }
        'ThisPc'      { if (-not $script:SpecsLoaded) { Refresh-ThisPcInformation } elseif (-not $script:DisplayInventoryLoaded -and (Get-Command Update-HuDisplayInventory -ErrorAction SilentlyContinue)) { Update-HuDisplayInventory }; break }
    }
})


function Show-Page {
    param([ValidateSet('Home','History','Diagnostics','Performance','Games','Applications','Connections','Network','Firewall','Dns','Commands','Debloat','Advanced','ThisPc','Settings','About')][string]$Page)

    if ($script:CurrentPage -eq $Page) {
        if ($Page -eq 'ThisPc' -and -not $script:SpecsLoaded) {
            $script:PendingRefreshPage = $Page
            $script:PageRefreshTimer.Stop()
            $script:PageRefreshTimer.Start()
        }
        return
    }

    $previousPage = [string]$script:CurrentPage
    if ($previousPage -and $script:PageControlMap.ContainsKey($previousPage)) {
        $script:PageControlMap[$previousPage].Visibility = 'Collapsed'
        $script:NavControlMap[$previousPage].Tag = ''
    }

    $script:PageControlMap[$Page].Visibility = 'Visible'
    $script:NavControlMap[$Page].Tag = 'Selected'
    $script:CurrentPage = $Page

    # Laisser WPF afficher immédiatement la nouvelle page avant les requêtes
    # réseau/système potentiellement plus lentes.
    $script:PendingRefreshPage = $Page
    $script:PageRefreshTimer.Stop()
    $script:PageRefreshTimer.Start()
}

function Sync-MaximizeGlyph {
    $geometry = if ($window.WindowState -eq 'Maximized') { 'M4,2 L12,2 L12,10 M2,4 L10,4 L10,12 L2,12 Z' } else { 'M2,2 L12,2 L12,12 L2,12 Z' }
    $MaximizeGlyph.Data = [Windows.Media.Geometry]::Parse($geometry)
}

function Toggle-WNSTWindowState {
    if ($window.WindowState -eq [Windows.WindowState]::Maximized) {
        $window.WindowState = [Windows.WindowState]::Normal
        return
    }

    # Retirer la bordure invisible avant WM_GETMINMAXINFO : sinon WindowChrome
    # peut décaler la zone cliente au-dessus de l'écran et sous la barre des tâches.
    try {
        $chrome = [Windows.Shell.WindowChrome]::GetWindowChrome($window)
        if ($chrome) { $chrome.ResizeBorderThickness = [Windows.Thickness]::new(0) }
    }
    catch { }

    $window.WindowState = [Windows.WindowState]::Maximized
}

function Sync-WindowFrame {
    $maximized = $window.WindowState -eq 'Maximized'
    $selectedRadius = [double](Get-AppCornerRadiusValue)
    $frameRadius = if ($maximized) { 0.0 } else { $selectedRadius }
    try {
        $chrome = [Windows.Shell.WindowChrome]::GetWindowChrome($window)
        if ($chrome) {
            $chrome.ResizeBorderThickness = if ($maximized) {
                [Windows.Thickness]::new(0)
            }
            else {
                [Windows.Thickness]::new(6)
            }
        }
    }
    catch { }
    $WindowFrame.CornerRadius = [Windows.CornerRadius]::new($frameRadius)
    $WindowFrame.Margin = if ($maximized) { [Windows.Thickness]::new(0) } else { [Windows.Thickness]::new(1) }
    $WindowBorderOverlay.CornerRadius = [Windows.CornerRadius]::new($frameRadius)
    $WindowBorderOverlay.Margin = if ($maximized) { [Windows.Thickness]::new(0) } else { [Windows.Thickness]::new(-1) }
    if ($window.ActualWidth -gt 0 -and $window.ActualHeight -gt 0) {
        $window.Clip = [Windows.Media.RectangleGeometry]::new([Windows.Rect]::new(0,0,$window.ActualWidth,$window.ActualHeight),$frameRadius,$frameRadius)
    }
}
