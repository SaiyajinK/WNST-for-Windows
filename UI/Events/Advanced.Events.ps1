$script:AdvancedUiState = [pscustomobject]@{
    OperationRunning = $false
}

$script:AdvancedButtons = @(
    $AdvancedOneDriveButton,
    $AdvancedTelemetryPushedButton,
    $AdvancedTelemetryAggressiveButton,
    $AdvancedTelemetryDisableHostsButton,
    $AdvancedEdgeButton,
    $AdvancedAiButton
)

function Update-AdvancedTelemetryBlockState {
    param([object]$Enabled = $null)

    $isEnabled = $false
    if ($null -ne $Enabled) {
        $isEnabled = [bool]$Enabled
    }
    else {
        try {
            $persisted = Get-HuSettings -DataRoot ([string]$script:Paths.DataRoot)
            $isEnabled = [bool]$persisted.TelemetryHostsBlockEnabled
        }
        catch {
            $isEnabled = [bool]$script:Settings.TelemetryHostsBlockEnabled
        }
    }

    # Synchroniser aussi l'objet Settings déjà chargé par l'interface.
    try { $script:Settings.TelemetryHostsBlockEnabled = $isEnabled } catch { }

    if ($AdvancedTelemetryBlockStatus) {
        $AdvancedTelemetryBlockStatus.Text = T $(if ($isEnabled) { 'AdvancedTelemetryBlockEnabled' } else { 'AdvancedTelemetryBlockDisabled' })
    }
    if ($AdvancedTelemetryDisableHostsButton) {
        $AdvancedTelemetryDisableHostsButton.Visibility = if ($isEnabled) { 'Visible' } else { 'Collapsed' }
        $AdvancedTelemetryDisableHostsButton.IsEnabled = $isEnabled -and -not [bool]$script:AdvancedUiState.OperationRunning
    }
}

$script:AdvancedLogScrollViewer = $null
$script:UpdatingAdvancedLogCustomScroll = $false
$script:AdvancedLogThumbDragStartOffset = 0.0
$script:AdvancedLogThumbDragDelta = 0.0

function Get-AdvancedLogScrollViewer {
    if ($script:AdvancedLogScrollViewer -is [Windows.Controls.ScrollViewer]) {
        return $script:AdvancedLogScrollViewer
    }

    $script:AdvancedLogScrollViewer = $null

    try {
        $AdvancedLogBox.ApplyTemplate()
        $viewer = $AdvancedLogBox.Template.FindName('PART_ContentHost',$AdvancedLogBox)
        if ($viewer -is [Windows.Controls.ScrollViewer]) {
            $script:AdvancedLogScrollViewer = $viewer
        }
    }
    catch {
        $script:AdvancedLogScrollViewer = $null
    }

    return $script:AdvancedLogScrollViewer
}

function Update-AdvancedLogCustomScrollbar {
    try {
        if ($script:UpdatingAdvancedLogCustomScroll) { return }

        $viewer = Get-AdvancedLogScrollViewer
        if (-not $viewer) { return }

        $script:UpdatingAdvancedLogCustomScroll = $true
        try {
            $extent = [double]$viewer.ExtentHeight
            $viewport = [double]$viewer.ViewportHeight
            $useCustom = $false

            if ($extent -gt $viewport -and $viewport -gt 0) {
                $naturalThumbHeight = ([double]$AdvancedLogCustomScrollTrack.ActualHeight) * ($viewport / $extent)
                $useCustom = $naturalThumbHeight -lt 24
            }

            if (-not $useCustom) {
                $AdvancedLogCustomScrollTrack.Visibility = 'Collapsed'
                $AdvancedLogBox.VerticalScrollBarVisibility = [Windows.Controls.ScrollBarVisibility]::Auto
                return
            }

            $AdvancedLogBox.VerticalScrollBarVisibility = [Windows.Controls.ScrollBarVisibility]::Hidden
            if ($AdvancedLogCustomScrollTrack.Visibility -ne 'Visible') {
                $AdvancedLogCustomScrollTrack.Visibility = 'Visible'
                $AdvancedLogCustomScrollTrack.UpdateLayout()
            }

            $trackHeight = [double]$AdvancedLogCustomScrollTrack.ActualHeight
            if ($trackHeight -le 0) { return }

            $proportionalHeight = $trackHeight * ($viewport / $extent)
            $thumbHeight = [Math]::Min($trackHeight,[Math]::Max(24.0,$proportionalHeight))
            $AdvancedLogCustomScrollThumb.Height = $thumbHeight

            $maxTop = [Math]::Max(0.0,$trackHeight - $thumbHeight)
            $scrollable = [double]$viewer.ScrollableHeight
            $top = 0.0
            if ($scrollable -gt 0 -and $maxTop -gt 0) {
                $ratio = [Math]::Max(0.0,[Math]::Min(1.0,([double]$viewer.VerticalOffset / $scrollable)))
                $top = $maxTop * $ratio
            }
            [Windows.Controls.Canvas]::SetTop($AdvancedLogCustomScrollThumb,$top)
        }
        finally { $script:UpdatingAdvancedLogCustomScroll = $false }
    }
    catch {
        try {
            $AdvancedLogCustomScrollTrack.Visibility = 'Collapsed'
            $AdvancedLogBox.VerticalScrollBarVisibility = [Windows.Controls.ScrollBarVisibility]::Auto
        }
        catch {}
    }
}

function Set-AdvancedControlsEnabled {
    param([bool]$Enabled)
    foreach ($button in $script:AdvancedButtons) {
        if ($button) { $button.IsEnabled = $Enabled }
    }
    if ($AdvancedTelemetryDisableHostsButton) {
        $AdvancedTelemetryDisableHostsButton.IsEnabled = $Enabled -and [bool]$script:Settings.TelemetryHostsBlockEnabled
    }
}

function Get-AdvancedOperationDisplayName {
    param([Parameter(Mandatory=$true)][string]$Operation)

    switch ($Operation) {
        'OneDrive'   { return 'Microsoft OneDrive' }
        'Telemetry'  { return (T 'AdvancedTelemetryTitle') }
        'TelemetryHostsDisable' { return (T 'AdvancedTelemetryTitle') }
        'Edge'       { return 'Microsoft Edge' }
        'WindowsAI'  { return 'Windows AI' }
        default      { return $Operation }
    }
}

function Add-AdvancedLogLine {
    param(
        [AllowEmptyString()][string]$Text,
        [ValidateSet('Auto','Normal','Success','Error')][string]$Level = 'Auto'
    )

    if (-not $AdvancedLogBox -or [string]::IsNullOrWhiteSpace($Text)) { return }

    $localizedText = ConvertTo-WnstLocalizedLogText -Text $Text
    $line = '[{0}] {1}' -f ([DateTime]::Now.ToString('HH:mm:ss')), $localizedText
    $spacing = if ($Text -match '^\[START\](?:\s|$)') { 2 } else { 1 }
    Add-WnstLogText -Control $AdvancedLogBox -Text $line -Level $Level -LeadingNewLines $spacing
    Update-AdvancedLogCustomScrollbar
}

function Add-AdvancedResultLog {
    param(
        [Parameter(Mandatory=$true)][object]$Result,
        [Parameter(Mandatory=$true)][string]$OperationName
    )

    if (-not [bool]$Result.ActionsStreamed) {
        $actionLines = @(
            $Result.Actions |
                ForEach-Object { [string]$_ } |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        )
        if ($actionLines.Count -gt 0) {
            foreach ($actionLine in $actionLines) {
                $level = Get-WnstLogLineLevel -Text $actionLine
                Add-AdvancedLogLine -Text $actionLine -Level $level
            }
            Update-AdvancedLogCustomScrollbar
        }
    }

    switch ([string]$Result.Operation) {
        'OneDrive' {
            Add-AdvancedLogLine (TF 'AdvancedLogUninstall' @([int]$Result.UninstallSuccess,[int]$Result.UninstallAttempts))
            Add-AdvancedLogLine (TF 'AdvancedLogResiduals' @([int]$Result.RemovedFolders))
            if ([int]$Result.PendingDeleteFolders -gt 0) {
                Add-AdvancedLogLine (T 'ChangeVerifiedRestart')
            }
            if ([bool]$Result.PersonalFolderPreserved) {
                Add-AdvancedLogLine (T 'AdvancedOneDrivePersonalPreserved')
            }
        }

        'Telemetry' {
            Add-AdvancedLogLine (TF 'AdvancedLogPolicies' @([int]$Result.Policies))
            Add-AdvancedLogLine (TF 'AdvancedLogServices' @([int]$Result.Services))
            if ([string]$Result.Mode -eq 'Aggressive') {
                $flag = if ([bool]$Result.HostsBlocked) { '✓' } else { '—' }
                Add-AdvancedLogLine (TF 'AdvancedLogHosts' @($flag))
            }
        }

        'TelemetryHostsDisable' {
            Add-AdvancedLogLine (TF 'AdvancedLogHosts' @('—'))
        }

        'Edge' {
            Add-AdvancedLogLine (TF 'AdvancedLogUninstall' @([int]$Result.UninstallSuccess,[int]$Result.UninstallAttempts))
            Add-AdvancedLogLine (TF 'AdvancedLogResiduals' @([int]$Result.RemovedFolders))
            if ([bool]$Result.WebView2Preserved) {
                Add-AdvancedLogLine (T 'AdvancedEdgeWebView2Preserved')
            }
        }

        'WindowsAI' {
            Add-AdvancedLogLine (TF 'AdvancedLogPolicies' @([int]$Result.Policies))
            Add-AdvancedLogLine (TF 'AdvancedLogInstalledPackages' @([int]$Result.InstalledRemoved))
            Add-AdvancedLogLine (TF 'AdvancedLogProvisionedPackages' @([int]$Result.ProvisionedRemoved))
            $recallFlag = if ([bool]$Result.RecallRemoved) { '✓' } else { '—' }
            Add-AdvancedLogLine (TF 'AdvancedLogRecall' @($recallFlag))
            Add-AdvancedLogLine (TF 'AdvancedLogRemaining' @([int]$Result.Remaining))
        }
    }

    foreach ($errorText in @($Result.Errors)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$errorText)) {
            $localizedError = T ([string]$errorText)
            Add-AdvancedLogLine (TF 'AdvancedLogError' @($localizedError)) -Level Error
        }
    }

    if ([bool]$Result.Success -and -not [bool]$Result.Partial) {
        Add-AdvancedLogLine (TF 'AdvancedLogDone' @($OperationName)) -Level Success
    }
    else {
        Add-AdvancedLogLine (TF 'AdvancedLogPartial' @($OperationName)) -Level Error
    }
}

function Invoke-WnstAdvancedUiOperation {
    param(
        [Parameter(Mandatory=$true)]
        [ValidateSet('OneDrive','Telemetry','TelemetryHostsDisable','Edge','WindowsAI')]
        [string]$Operation,

        [AllowEmptyString()]
        [string]$Mode=''
    )

    if ($script:AdvancedUiState.OperationRunning) { return }

    $confirmKey = switch ($Operation) {
        'OneDrive'  { 'AdvancedConfirmOneDrive' }
        'Telemetry' { if ($Mode -eq 'Aggressive') { 'AdvancedConfirmTelemetryAggressive' } else { 'AdvancedConfirmTelemetryPushed' } }
        'TelemetryHostsDisable' { 'AdvancedConfirmTelemetryHostsDisable' }
        'Edge'      { 'AdvancedConfirmEdgeAggressive' }
        'WindowsAI' { 'AdvancedConfirmAi' }
    }

    if (-not (Show-AppConfirm (T $confirmKey))) { return }
    if ($Operation -eq 'Telemetry' -and $Mode -eq 'Aggressive' -and -not [bool]$script:Settings.TelemetryHostsBlockEnabled) {
        if (-not (Show-AppConfirm (T 'AdvancedTelemetryDefenderWarning'))) { return }
    }

    $operationName = Get-AdvancedOperationDisplayName -Operation $Operation
    $state = $script:AdvancedUiState
    $settingsState = $script:Settings

    $state.OperationRunning = $true
    Set-AdvancedControlsEnabled -Enabled $false
    $AdvancedStatusText.Text = T 'AdvancedStatusRunning'
    Add-AdvancedLogLine (TF 'AdvancedLogStart' @($operationName))

    $progressQueue = [System.Collections.Concurrent.ConcurrentQueue[object]]::new()

    $worker = {
        param($root,$dataRoot,$operation,$mode,$progressQueue)

        . (Join-Path $root 'Modules\Advanced.ps1')
        if ($operation -in @('Telemetry','TelemetryHostsDisable')) {
            Import-Module (Join-Path $root 'WNST.psd1') -Force
        }

        switch ($operation) {
            'OneDrive'  { Invoke-WnstOneDriveRemoval -ProgressQueue $progressQueue }
            'Telemetry' { Invoke-WnstTelemetryDisable -Mode $mode -DataRoot $dataRoot -ProgressQueue $progressQueue }
            'TelemetryHostsDisable' {
                $script:WnstAdvancedProgressQueue = $progressQueue
                $actions = [Collections.Generic.List[string]]::new()
                $errors = [Collections.Generic.List[string]]::new()
                Add-WnstAdvancedAction $actions '[HOSTS] WNST_TELEMETRY_BLOCK -> DISABLE'
                try {
                    $block = Set-HuTelemetryHostsBlock -Enabled $false -DataRoot $dataRoot
                    Add-WnstAdvancedAction $actions ('[OK] HOSTS -> disabled changed={0} dnsFlush={1}' -f [bool]$block.Changed,[bool]$block.DnsFlushed)
                    [pscustomobject]@{
                        Operation = 'TelemetryHostsDisable'
                        Success = $true
                        Partial = $false
                        Errors = @()
                        Actions = @($actions)
                        ActionsStreamed = $true
                        TelemetryHostsBlockEnabled = $false
                        EndpointCount = [int]$block.EndpointCount
                        RestartRecommended = $false
                    }
                }
                catch {
                    $errors.Add([string]$_.Exception.Message)
                    Add-WnstAdvancedAction $actions ('[FAIL] HOSTS -> {0}' -f [string]$_.Exception.Message)
                    [pscustomobject]@{
                        Operation = 'TelemetryHostsDisable'
                        Success = $false
                        Partial = $true
                        Errors = @($errors)
                        Actions = @($actions)
                        ActionsStreamed = $true
                        TelemetryHostsBlockEnabled = $null
                        EndpointCount = 0
                        RestartRecommended = $false
                    }
                }
            }
            'Edge'      { Invoke-WnstEdgeRemoval -ProgressQueue $progressQueue }
            'WindowsAI' { Invoke-WnstWindowsAiRemoval -ProgressQueue $progressQueue }
        }
    }

    $progress = {
        param($item)
        $line = [string]$item
        if ([string]::IsNullOrWhiteSpace($line)) { return }
        $level = 'Normal'
        if ($line -match '\[(?:FAIL|FAILED|ERROR|ERR)\]' -or $line -match '-> FAILED(?:\s|$)') {
            $level = 'Error'
        }
        elseif (
            $line -match '\[OK\]' -or
            $line -match '\[REG\]' -or
            $line -match '-> (?:DELETE|DISABLED|STOP|STOPPED|STARTED|AUTO-STARTED|LOADED|UNLOADED|BLOCKED|REMOVED)(?:\s|$)'
        ) {
            $level = 'Success'
        }
        Add-AdvancedLogLine -Text $line -Level $level
    }.GetNewClosure()

    $completed = {
        param($output)

        # Important: $state is a captured object shared with the click handler.
        # Do not use $script: here: GetNewClosure() has its own script scope.
        $state.OperationRunning = $false
        Set-AdvancedControlsEnabled -Enabled $true

        $result = @($output) | Select-Object -Last 1
        if (-not $result) {
            $AdvancedStatusText.Text = T 'AdvancedStatusFailed'
            Add-AdvancedLogLine (TF 'AdvancedLogFailure' @($operationName)) -Level Error
            Show-AppError (T 'AdvancedStatusFailed')
            return
        }

        if ($result.PSObject.Properties['TelemetryHostsBlockEnabled'] -and $null -ne $result.TelemetryHostsBlockEnabled) {
            # GetNewClosure() possède son propre scope script : utiliser l'objet capturé,
            # sinon le callback s'interrompt après l'opération sans afficher le résultat.
            $settingsState.TelemetryHostsBlockEnabled = [bool]$result.TelemetryHostsBlockEnabled
            Update-AdvancedTelemetryBlockState -Enabled ([bool]$result.TelemetryHostsBlockEnabled)
        }
        elseif ([string]$result.Operation -eq 'Telemetry') {
            Update-AdvancedTelemetryBlockState
        }

        Add-AdvancedResultLog -Result $result -OperationName $operationName

        $message = if ([bool]$result.Success -and -not [bool]$result.Partial) {
            TF 'AdvancedStatusSuccess' @($operationName)
        }
        else {
            TF 'AdvancedStatusPartial' @($operationName)
        }

        if ([bool]$result.RestartRecommended) {
            $message += ' ' + (T 'AdvancedRestartRecommended')
        }
        if ([string]$result.Operation -eq 'OneDrive' -and [bool]$result.PersonalFolderPreserved) {
            $message += ' ' + (T 'AdvancedOneDrivePersonalPreserved')
        }
        if ([string]$result.Operation -eq 'Edge' -and [bool]$result.WebView2Preserved) {
            $message += ' ' + (T 'AdvancedEdgeWebView2Preserved')
        }

        $AdvancedStatusText.Text = $message
        Show-AppInfo $message
    }.GetNewClosure()

    $failed = {
        param($message)

        $state.OperationRunning = $false
        Set-AdvancedControlsEnabled -Enabled $true

        $text = if ($message -eq 'AdministratorRequired') {
            T 'AdministratorRequired'
        }
        elseif ($message -eq 'Timeout') {
            T 'AdvancedStatusFailed'
        }
        else {
            [string]$message
        }

        $AdvancedStatusText.Text = $text
        Add-AdvancedLogLine (TF 'AdvancedLogError' @($text)) -Level Error
        Add-AdvancedLogLine (TF 'AdvancedLogFailure' @($operationName)) -Level Error
        Show-AppError $text
    }.GetNewClosure()

    if (-not (Invoke-HuAsyncWork -Key 'AdvancedOperation' -ScriptBlock $worker -ArgumentList @($script:AppRoot,[string]$script:Paths.DataRoot,$Operation,$Mode,$progressQueue) -OnCompleted $completed -OnError $failed -OnProgress $progress -ProgressQueue $progressQueue -TimeoutSeconds 240 -Replace)) {
        $state.OperationRunning = $false
        Set-AdvancedControlsEnabled -Enabled $true
        $AdvancedStatusText.Text = T 'AdvancedStatusFailed'
        Add-AdvancedLogLine (TF 'AdvancedLogFailure' @($operationName)) -Level Error
    }
}

$AdvancedOneDriveButton.Add_Click({
    Invoke-WnstAdvancedUiOperation -Operation OneDrive
})

$AdvancedTelemetryPushedButton.Add_Click({
    Invoke-WnstAdvancedUiOperation -Operation Telemetry -Mode Pushed
})

$AdvancedTelemetryAggressiveButton.Add_Click({
    Invoke-WnstAdvancedUiOperation -Operation Telemetry -Mode Aggressive
})

$AdvancedTelemetryDisableHostsButton.Add_Click({
    Invoke-WnstAdvancedUiOperation -Operation TelemetryHostsDisable
})

$AdvancedEdgeButton.Add_Click({
    Invoke-WnstAdvancedUiOperation -Operation Edge -Mode Aggressive
})

$AdvancedAiButton.Add_Click({
    Invoke-WnstAdvancedUiOperation -Operation WindowsAI -Mode Aggressive
})


$AdvancedLogCustomScrollTrack.Add_SizeChanged({ Update-AdvancedLogCustomScrollbar })

$AdvancedLogCustomScrollThumb.Add_DragStarted({
    $viewer = Get-AdvancedLogScrollViewer
    if ($viewer -isnot [Windows.Controls.ScrollViewer]) { return }
    $script:AdvancedLogThumbDragStartOffset = [double]$viewer.VerticalOffset
    $script:AdvancedLogThumbDragDelta = 0.0
})
$AdvancedLogCustomScrollThumb.Add_DragDelta({
    if ($AdvancedLogCustomScrollTrack.Visibility -ne 'Visible') { return }
    $viewer = Get-AdvancedLogScrollViewer
    if ($viewer -isnot [Windows.Controls.ScrollViewer]) { return }

    $trackHeight = [double]$AdvancedLogCustomScrollTrack.ActualHeight
    $thumbHeight = [double]$AdvancedLogCustomScrollThumb.ActualHeight
    $travel = [Math]::Max(0.0,$trackHeight - $thumbHeight)
    $scrollable = [double]$viewer.ScrollableHeight
    if ($travel -le 0 -or $scrollable -le 0) { return }

    $script:AdvancedLogThumbDragDelta += [double]$_.VerticalChange
    $target = $script:AdvancedLogThumbDragStartOffset + (($script:AdvancedLogThumbDragDelta / $travel) * $scrollable)
    $target = [Math]::Max(0.0,[Math]::Min($scrollable,$target))
    $viewer.ScrollToVerticalOffset($target)
})
$AdvancedLogCustomScrollThumb.Add_DragCompleted({ $script:AdvancedLogThumbDragDelta = 0.0 })
$AdvancedLogCustomScrollTrack.Add_MouseLeftButtonDown({
    if ($AdvancedLogCustomScrollTrack.Visibility -ne 'Visible' -or $_.OriginalSource -ne $AdvancedLogCustomScrollTrack) { return }

    $viewer = Get-AdvancedLogScrollViewer
    if ($viewer -isnot [Windows.Controls.ScrollViewer]) { return }

    $y = [double]$_.GetPosition($AdvancedLogCustomScrollTrack).Y
    $top = [Windows.Controls.Canvas]::GetTop($AdvancedLogCustomScrollThumb)
    if ([double]::IsNaN($top)) { $top = 0.0 }
    $bottom = $top + [double]$AdvancedLogCustomScrollThumb.ActualHeight

    if ($y -lt $top) {
        $viewer.ScrollToVerticalOffset([Math]::Max(0.0,[double]$viewer.VerticalOffset - [double]$viewer.ViewportHeight))
    }
    elseif ($y -gt $bottom) {
        $viewer.ScrollToVerticalOffset([Math]::Min([double]$viewer.ScrollableHeight,[double]$viewer.VerticalOffset + [double]$viewer.ViewportHeight))
    }
    $_.Handled = $true
})


$AdvancedClearLogButton.Add_Click({
    if ($AdvancedLogBox) {
        Clear-WnstLogContent -Control $AdvancedLogBox
        Update-AdvancedLogCustomScrollbar
    }
})

Update-AdvancedTelemetryBlockState
