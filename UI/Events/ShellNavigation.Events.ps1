$script:TitleBarDragPending = $false
$script:TitleBarDragWasMaximized = $false
$script:TitleBarDragStartPoint = $null
$script:TitleBarDragStartRatio = 0.5
$script:TitleBarDragStartYOffset = 0.0

$TitleBar.Add_MouseLeftButtonDown({
    param($sender, $eventArgs)
    if ($eventArgs.ChangedButton -ne 'Left') { return }

    $source = $eventArgs.OriginalSource
    while ($source) {
        if ($source -is [Windows.Controls.Button]) { return }
        try { $source = [Windows.Media.VisualTreeHelper]::GetParent($source) } catch { $source = $null }
    }

    if ($eventArgs.ClickCount -eq 2) {
        $script:TitleBarDragPending = $false
        try { $TitleBar.ReleaseMouseCapture() } catch { }
        Toggle-WNSTWindowState
        $eventArgs.Handled = $true
        return
    }

    $startPoint = $eventArgs.GetPosition($window)
    $script:TitleBarDragPending = $true
    $script:TitleBarDragWasMaximized = ($window.WindowState -eq 'Maximized')
    $script:TitleBarDragStartPoint = $startPoint
    $script:TitleBarDragStartRatio = if ($window.ActualWidth -gt 0) {
        [Math]::Max(0.0, [Math]::Min(1.0, $startPoint.X / $window.ActualWidth))
    }
    else { 0.5 }
    $script:TitleBarDragStartYOffset = [Math]::Max(0.0, $startPoint.Y)

    try { [void]$TitleBar.CaptureMouse() } catch { }
    $eventArgs.Handled = $true
})

$TitleBar.Add_MouseMove({
    param($sender, $eventArgs)

    if (-not $script:TitleBarDragPending) { return }

    if ($eventArgs.LeftButton -ne [Windows.Input.MouseButtonState]::Pressed) {
        $script:TitleBarDragPending = $false
        try { $TitleBar.ReleaseMouseCapture() } catch { }
        return
    }

    $currentPoint = $eventArgs.GetPosition($window)
    $deltaX = [Math]::Abs($currentPoint.X - $script:TitleBarDragStartPoint.X)
    $deltaY = [Math]::Abs($currentPoint.Y - $script:TitleBarDragStartPoint.Y)

    if ($deltaX -lt [Windows.SystemParameters]::MinimumHorizontalDragDistance -and
        $deltaY -lt [Windows.SystemParameters]::MinimumVerticalDragDistance) {
        return
    }

    $script:TitleBarDragPending = $false

    if ($script:TitleBarDragWasMaximized) {
        $restoreBounds = $window.RestoreBounds
        $screenPoint = $window.PointToScreen($currentPoint)

        try {
            $presentationSource = [Windows.PresentationSource]::FromVisual($window)
            if ($presentationSource -and $presentationSource.CompositionTarget) {
                $screenPoint = $presentationSource.CompositionTarget.TransformFromDevice.Transform($screenPoint)
            }
        }
        catch { }

        $restoreWidth = if ($restoreBounds.Width -gt 0 -and -not [Double]::IsInfinity($restoreBounds.Width)) {
            $restoreBounds.Width
        }
        else { $window.ActualWidth }

        $window.WindowState = 'Normal'
        $window.UpdateLayout()

        $window.Left = $screenPoint.X - ($restoreWidth * $script:TitleBarDragStartRatio)
        $window.Top = $screenPoint.Y - $script:TitleBarDragStartYOffset
        Sync-WindowFrame
    }

    try { $TitleBar.ReleaseMouseCapture() } catch { }
    try { $window.DragMove() } catch { }
    $eventArgs.Handled = $true
})

$TitleBar.Add_MouseLeftButtonUp({
    $script:TitleBarDragPending = $false
    try { $TitleBar.ReleaseMouseCapture() } catch { }
})
$MinimizeButton.Add_Click({ $window.WindowState = 'Minimized' })
$MaximizeButton.Add_Click({ Toggle-WNSTWindowState })
$window.Add_StateChanged({ Sync-MaximizeGlyph; Sync-WindowFrame })
$window.Add_SizeChanged({ Sync-WindowFrame })
$CloseButton.Add_Click({ $window.Close() })
$SidebarToggleButton.Add_Click({
    try {
        $script:Settings.SidebarCollapsed = -not [bool]$script:Settings.SidebarCollapsed
        Apply-SidebarLayout
        $saveTimer.Stop()
        $saveTimer.Start()
    }
    catch { Show-AppError $_.Exception.Message }
})
$NavHome.Add_Click({ Show-Page Home })
$NavHistory.Add_Click({ Show-Page History })
$NavDiagnostics.Add_Click({ Show-Page Diagnostics })
$NavPerformance.Add_Click({ Show-Page Performance })
$NavGames.Add_Click({ Show-Page Games })
$NavApplications.Add_Click({ Show-Page Applications })
$NavConnections.Add_Click({ Show-Page Connections })
$NavNetwork.Add_Click({ Show-Page Network })
$NavFirewall.Add_Click({ Show-Page Firewall })
$NavDns.Add_Click({ Show-Page Dns })
$NavCommands.Add_Click({ Show-Page Commands })
$NavDebloat.Add_Click({ Show-Page Debloat })
$NavAdvanced.Add_Click({ Show-Page Advanced })
$NavThisPc.Add_Click({ Show-Page ThisPc })
$NavSettings.Add_Click({ Show-Page Settings })
$NavAbout.Add_Click({ Show-Page About })

# Animation legere du sous-titre de la barre de titre.
$script:TitleTypewriterText = 'Windows Network & System Toolkit'
$script:TitleTypewriterIndex = 0
$script:TitleTypewriterPhase = 'PreBlink'
$script:TitleTypewriterPhaseElapsed = 0
$script:TitleTypewriterTypeElapsed = 0
$script:TitleTypewriterBlinkElapsed = 0
$script:TitleTypewriterCaretVisible = $true

function Reset-TitleTypewriterState {
    $script:TitleTypewriterIndex = 0
    $script:TitleTypewriterPhase = 'PreBlink'
    $script:TitleTypewriterPhaseElapsed = 0
    $script:TitleTypewriterTypeElapsed = 0
    $script:TitleTypewriterBlinkElapsed = 0
    $script:TitleTypewriterCaretVisible = $true
    $TxtAppSubtitleAnimated.Text = ''
    $TxtAppSubtitleCaret.Visibility = 'Visible'
}

function Set-TitleTypewriterEnabled {
    param([bool]$Enabled)
    if ($Enabled) {
        Reset-TitleTypewriterState
        if (-not $script:TitleTypewriterTimer.IsEnabled) { $script:TitleTypewriterTimer.Start() }
    }
    else {
        if ($script:TitleTypewriterTimer.IsEnabled) { $script:TitleTypewriterTimer.Stop() }
        $TxtAppSubtitleAnimated.Text = $script:TitleTypewriterText
        $TxtAppSubtitleCaret.Visibility = 'Collapsed'
    }
}

$script:TitleTypewriterTimer = New-Object Windows.Threading.DispatcherTimer
$script:TitleTypewriterTimer.Interval = [TimeSpan]::FromMilliseconds(50)
$script:TitleTypewriterTimer.Add_Tick({
    $step = 50
    $script:TitleTypewriterPhaseElapsed += $step
    $script:TitleTypewriterBlinkElapsed += $step

    if ($script:TitleTypewriterPhase -eq 'PreBlink') {
        if ($script:TitleTypewriterPhaseElapsed -ge 1500) {
            $script:TitleTypewriterPhase = 'Typing'
            $script:TitleTypewriterPhaseElapsed = 0
            $script:TitleTypewriterTypeElapsed = 0
            $script:TitleTypewriterCaretVisible = $true
            $script:TitleTypewriterBlinkElapsed = 0
            $TxtAppSubtitleCaret.Visibility = 'Visible'
        }
    }
    elseif ($script:TitleTypewriterPhase -eq 'Typing') {
        $script:TitleTypewriterTypeElapsed += $step
        if ($script:TitleTypewriterTypeElapsed -ge 70) {
            $script:TitleTypewriterTypeElapsed = 0
            if ($script:TitleTypewriterIndex -lt $script:TitleTypewriterText.Length) {
                $script:TitleTypewriterIndex++
                $TxtAppSubtitleAnimated.Text = $script:TitleTypewriterText.Substring(0, $script:TitleTypewriterIndex)
            }
            if ($script:TitleTypewriterIndex -ge $script:TitleTypewriterText.Length) {
                $script:TitleTypewriterPhase = 'CaretHold'
                $script:TitleTypewriterPhaseElapsed = 0
            }
        }
    }
    elseif ($script:TitleTypewriterPhase -eq 'CaretHold') {
        if ($script:TitleTypewriterPhaseElapsed -ge 1500) {
            $script:TitleTypewriterPhase = 'TextHold'
            $script:TitleTypewriterPhaseElapsed = 0
            $script:TitleTypewriterCaretVisible = $false
            $TxtAppSubtitleCaret.Visibility = 'Collapsed'
        }
    }
    elseif ($script:TitleTypewriterPhase -eq 'TextHold') {
        if ($script:TitleTypewriterPhaseElapsed -ge 5500) {
            Reset-TitleTypewriterState
        }
    }

    $blinkThreshold = if ($script:TitleTypewriterPhase -eq 'PreBlink') { 250 } else { 400 }
    if ($script:TitleTypewriterPhase -ne 'TextHold' -and $script:TitleTypewriterBlinkElapsed -ge $blinkThreshold) {
        $script:TitleTypewriterBlinkElapsed = 0
        $script:TitleTypewriterCaretVisible = -not $script:TitleTypewriterCaretVisible
        $TxtAppSubtitleCaret.Visibility = if ($script:TitleTypewriterCaretVisible) { 'Visible' } else { 'Hidden' }
    }
})
Set-TitleTypewriterEnabled -Enabled ([bool]$script:Settings.TitlebarAnimation)
$window.Add_Closed({ if ($script:TitleTypewriterTimer) { $script:TitleTypewriterTimer.Stop() } })
