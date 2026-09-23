$script:UpdatingPerformanceUi = $false

function Add-HuPerformanceLogLine {
    param([object]$Item,[object]$Target = $PerformanceOutputBox)
    if (-not $Target -or $null -eq $Item) { return }
    $text = Resolve-WnstLogItemText -Item $Item
    if ([string]::IsNullOrWhiteSpace($text)) { return }
    $level = if ($Item.PSObject.Properties['Level']) { [string]$Item.Level } else { 'Auto' }
    if ($level -notin @('Auto','Normal','Success','Error')) { $level = 'Auto' }
    $localizedText = ConvertTo-WnstLocalizedLogText -Text $text
    $line = '[{0}] {1}' -f ([DateTime]::Now.ToString('HH:mm:ss')),$localizedText
    $spacing = if ($text -match '^\[START\](?:\s|$)') { 2 } else { 1 }
    Add-WnstLogText -Control $Target -Text $line -Level $level -LeadingNewLines $spacing
    if ($Target -eq $AppxLogBox -and (Get-Command Update-AppxLogCustomScrollbar -ErrorAction SilentlyContinue)) { Update-AppxLogCustomScrollbar }
}

function Apply-HuPerformanceStateToUi {
    param([object]$State)
    if (-not $State) { return }
    $script:UpdatingPerformanceUi = $true
    try {
        $DefenderCpuSlider.Value = [double]$State.DefenderCpu
        $DefenderCpuValue.Text = ('{0} %' -f $State.DefenderCpu)
        $TransparencyToggle.IsChecked = [bool]$State.Transparency
        $AnimationsToggle.IsChecked = [bool]$State.AnimationsDisabled
        $ShutdownAnimationToggle.IsChecked = [bool]$State.ShutdownAnimationDisabled
        $NotificationsToggle.IsChecked = [bool]$State.NotificationsDisabled
        $EndTaskToggle.IsChecked = [bool]$State.EndTask
        $LegacyContextToggle.IsChecked = [bool]$State.LegacyContextMenu
        $LegacyExplorerToggle.IsChecked = [bool]$State.LegacyExplorer
        $LegacyExplorerToggle.IsEnabled = [bool]$State.LegacyExplorerSupported
        $LegacyExplorerHint.Text = T $(if([bool]$State.LegacyExplorerSupported){'LegacyExplorerHint'}else{'LegacyExplorerUnsupported'})
        $GameDvrToggle.IsChecked = [bool]$State.GameFeaturesDisabled
        $BackgroundThrottleToggle.IsChecked = [bool]$State.BackgroundThrottleDisabled
        $LatencyToggle.IsChecked = [bool]$State.LatencyOptimized
        $GamingTasksToggle.IsChecked = [bool]$State.TasksDisabled
        $BackgroundServicesToggle.IsChecked = [bool]$State.ServicesDisabled
        $TaskbarOptimizeToggle.IsChecked = [bool]$State.TaskbarOptimized
        $StartupOptimizeToggle.IsChecked = [bool]$State.StartupOptimized
        $PowerModeStatus.Text = T ('PowerMode' + [string]$State.ActivePowerMode)
        $PerformanceStateText.Text = T 'StatesReadFromWindows'
    }
    finally { $script:UpdatingPerformanceUi = $false }
}

function Refresh-PerformanceState {
    $PerformanceStateText.Text = T 'AdvancedStatusRunning'
    $worker = {
        param($root)
        Import-Module (Join-Path $root 'WNST.psd1') -Force
        . (Join-Path $root 'Modules\System.ps1')
        . (Join-Path $root 'Modules\Performance.ps1')
        Get-HuPerformanceState
    }
    $completed = {
        param($output)
        $state = @($output) | Where-Object { $_.PSObject.Properties['DefenderCpu'] } | Select-Object -Last 1
        if ($state) { Apply-HuPerformanceStateToUi -State $state }
        else { $PerformanceStateText.Text = T 'ChangeNotVerified' }
    }.GetNewClosure()
    $failed = { param($message) $PerformanceStateText.Text = [string]$message }.GetNewClosure()
    [void](Invoke-HuAsyncWork -Key 'Page.Performance.State' -ScriptBlock $worker -ArgumentList @($script:AppRoot) -OnCompleted $completed -OnError $failed -TimeoutSeconds 20 -Replace)
}

function Invoke-HuPerformanceToggleAction {
    param([Parameter(Mandatory=$true)][object]$Control,[Parameter(Mandatory=$true)][object]$Metadata)

        if ($script:UpdatingPerformanceUi -or -not $Control.IsEnabled) { return }
        $desired = [bool]$Control.IsChecked
        if ($Metadata.ConfirmKey -and -not (Show-AppConfirm (T ([string]$Metadata.ConfirmKey)))) { Refresh-PerformanceState; return }

        $Control.IsEnabled = $false
        $title = T ([string]$Metadata.TitleKey)
        Add-HuPerformanceLogLine -Item ([pscustomobject]@{Text=('[START] {0}' -f $title);Level='Normal'})
        Add-HuPerformanceLogLine -Item ([pscustomobject]@{Text=('[CHECK] {0} -> {1}' -f (T $(if($desired){'StateDisabled'}else{'StateEnabled'})),(T $(if($desired){'StateEnabled'}else{'StateDisabled'})));Level='Normal'})
        $queue = [Collections.Concurrent.ConcurrentQueue[object]]::new()
        $worker = {
            param($root,$functionName,$desiredValue,$propertyName,$operationTitle,$progressQueue)
            Import-Module (Join-Path $root 'WNST.psd1') -Force
            . (Join-Path $root 'Modules\System.ps1')
        . (Join-Path $root 'Modules\Performance.ps1')
            $progressQueue.Enqueue([pscustomobject]@{Text=('[REG] {0} -> {1}' -f $functionName,$desiredValue);Level='Normal'})
            $applyOutput = & $functionName $desiredValue
            $applyResult = @($applyOutput) | Select-Object -Last 1
            $progressQueue.Enqueue([pscustomobject]@{Text=('[VERIFY] {0}' -f $propertyName);Level='Normal'})
            $state = Get-HuPerformanceState
            $actual = [bool]$state.$propertyName
            $functionVerified = $true
            $infrastructureErrors = @()
            if($applyResult -and $applyResult.PSObject.Properties['InfrastructureVerified']){
                $functionVerified = [bool]$applyResult.InfrastructureVerified
            }
            if($applyResult -and $applyResult.PSObject.Properties['InfrastructureErrors']){
                $infrastructureErrors = @($applyResult.InfrastructureErrors)
            }
            $verified = ($actual -eq [bool]$desiredValue) -and $functionVerified
            [pscustomobject]@{
                Actual=$actual
                Verified=$verified
                RestartRequired=($applyResult -and $applyResult.PSObject.Properties['RestartRequired'] -and [bool]$applyResult.RestartRequired)
                InfrastructureErrors=$infrastructureErrors
            }
        }
        $progress = { param($item) Add-HuPerformanceLogLine -Item $item }.GetNewClosure()
        $completed = {
            param($output)
            $result = @($output) | Where-Object { $_.PSObject.Properties['Verified'] } | Select-Object -Last 1
            $script:UpdatingPerformanceUi = $true
            try { if ($result) { $Control.IsChecked = [bool]$result.Actual } }
            finally { $script:UpdatingPerformanceUi = $false; $Control.IsEnabled = $true }
            if ($result -and [bool]$result.Verified) {
                $PerformanceStateText.Text = T $(if([bool]$result.RestartRequired){'ChangeVerifiedRestart'}else{'ChangeVerified'})
                Add-HuPerformanceLogLine -Item ([pscustomobject]@{Text=('[OK] {0}' -f $PerformanceStateText.Text);Level='Success'})
            }
            else {
                $PerformanceStateText.Text = T 'ChangeNotVerified'
                Add-HuPerformanceLogLine -Item ([pscustomobject]@{Text=('[FAIL] {0}' -f $PerformanceStateText.Text);Level='Error'})
                foreach($detail in @($result.InfrastructureErrors)){
                    if(-not [string]::IsNullOrWhiteSpace([string]$detail)){
                        Add-HuPerformanceLogLine -Item ([pscustomobject]@{Text=[string]$detail;Level='Error'})
                    }
                }
            }
        }.GetNewClosure()
        $failed = {
            param($message)
            $Control.IsEnabled = $true
            Add-HuPerformanceLogLine -Item ([pscustomobject]@{Text=('[FAIL] {0}' -f [string]$message);Level='Error'})
            $PerformanceStateText.Text = if ([string]$message -in @('AdministratorRequired','LegacyExplorerUnsupported')) { T ([string]$message) } else { [string]$message }
            Refresh-PerformanceState
        }.GetNewClosure()
        [void](Invoke-HuAsyncWork -Key ('Performance.' + [string]$Metadata.StateProperty) -ScriptBlock $worker -ArgumentList @($script:AppRoot,[string]$Metadata.FunctionName,$desired,[string]$Metadata.StateProperty,$title,$queue) -OnCompleted $completed -OnError $failed -OnProgress $progress -ProgressQueue $queue -TimeoutSeconds 45 -Replace)
}

function Register-HuPerformanceToggle {
    param([object]$Control,[string]$TitleKey,[string]$StateProperty,[string]$FunctionName,[string]$ConfirmKey='')
    $Control.Tag = [pscustomobject]@{TitleKey=$TitleKey;StateProperty=$StateProperty;FunctionName=$FunctionName;ConfirmKey=$ConfirmKey}
    $Control.Add_Click({
        param($sender,$eventArgs)
        Invoke-HuPerformanceToggleAction -Control $sender -Metadata $sender.Tag
    })
}

function Invoke-HuMovedToggleAction {
    param([Parameter(Mandatory=$true)][object]$Control,[Parameter(Mandatory=$true)][object]$Metadata)
        if ($script:UpdatingPerformanceUi -or -not $Control.IsEnabled) { return }
        $desired = [bool]$Control.IsChecked
        if ($Metadata.StateProperty -eq 'HomeHidden' -and $desired -and -not (Show-AppConfirm (T 'ConfirmHomeHidden'))) {
            $script:UpdatingPerformanceUi = $true
            try { $Control.IsChecked = $false }
            finally { $script:UpdatingPerformanceUi = $false }
            return
        }
        $Control.IsEnabled = $false
        $title = T ([string]$Metadata.TitleKey)
        $logTarget = $Metadata.LogTarget
        if ($logTarget) {
            Add-HuPerformanceLogLine -Item ([pscustomobject]@{Text=('[START] {0}' -f $title);Level='Normal'}) -Target $logTarget
            Add-HuPerformanceLogLine -Item ([pscustomobject]@{Text=('[CHECK] {0} -> {1}' -f (T $(if($desired){'StateDisabled'}else{'StateEnabled'})),(T $(if($desired){'StateEnabled'}else{'StateDisabled'})));Level='Normal'}) -Target $logTarget
        }
        $queue = [Collections.Concurrent.ConcurrentQueue[object]]::new()
        $worker = {
            param($root,$functionName,$desiredValue,$propertyName,$operationTitle,$progressQueue)
            Import-Module (Join-Path $root 'WNST.psd1') -Force
            . (Join-Path $root 'Modules\System.ps1')
        . (Join-Path $root 'Modules\Performance.ps1')
            $progressQueue.Enqueue([pscustomobject]@{Text=('[REG] {0} -> {1}' -f $functionName,$desiredValue);Level='Normal'})
            & $functionName $desiredValue | Out-Null
            $actual = [bool](Get-HuPerformanceState).$propertyName
            $verified = $actual -eq [bool]$desiredValue
            [pscustomobject]@{Actual=$actual;Verified=$verified}
        }
        $progress = { param($item) if ($logTarget) { Add-HuPerformanceLogLine -Item $item -Target $logTarget } }.GetNewClosure()
        $completed = {
            param($output)
            $result = @($output) | Where-Object { $_.PSObject.Properties['Verified'] } | Select-Object -Last 1
            $script:UpdatingPerformanceUi = $true
            try { if ($result) { $Control.IsChecked = [bool]$result.Actual } }
            finally { $script:UpdatingPerformanceUi = $false; $Control.IsEnabled = $true }
            $StatusBarText.Text = T $(if($result -and [bool]$result.Verified){'ChangeVerified'}else{'ChangeNotVerified'})
            if ($logTarget) {
                Add-HuPerformanceLogLine -Item ([pscustomobject]@{Text=($(if($result -and [bool]$result.Verified){'[OK] '}else{'[FAIL] '}) + $StatusBarText.Text);Level=$(if($result -and [bool]$result.Verified){'Success'}else{'Error'})}) -Target $logTarget
            }
        }.GetNewClosure()
        $failed = {
            param($message)
            $Control.IsEnabled = $true
            if ($logTarget) { Add-HuPerformanceLogLine -Item ([pscustomobject]@{Text=('[FAIL] {0}' -f [string]$message);Level='Error'}) -Target $logTarget }
            $StatusBarText.Text = if ([string]$message -eq 'AdministratorRequired') { T 'AdministratorRequired' } else { [string]$message }
        }.GetNewClosure()
        [void](Invoke-HuAsyncWork -Key ('Moved.' + [string]$Metadata.StateProperty) -ScriptBlock $worker -ArgumentList @($script:AppRoot,[string]$Metadata.FunctionName,$desired,[string]$Metadata.StateProperty,$title,$queue) -OnCompleted $completed -OnError $failed -OnProgress $progress -ProgressQueue $queue -TimeoutSeconds 30 -Replace)
}

function Register-HuMovedToggle {
    param([object]$Control,[string]$TitleKey,[string]$StateProperty,[string]$FunctionName,[object]$LogTarget=$null)
    $Control.Tag = [pscustomobject]@{TitleKey=$TitleKey;StateProperty=$StateProperty;FunctionName=$FunctionName;LogTarget=$LogTarget}
    $Control.Add_Click({
        param($sender,$eventArgs)
        Invoke-HuMovedToggleAction -Control $sender -Metadata $sender.Tag
    })
}

function Refresh-WindowsActionState {
    $script:UpdatingPerformanceUi = $true
    try {
        $HomeToggle.IsChecked = [int](Get-HuRegistryValue 'HKCU:\Software\Classes\CLSID\{f874310e-b6b7-47dc-bc84-b9e6b38f5903}' 'System.IsPinnedToNameSpaceTree' 1) -eq 0
        $GalleryToggle.IsChecked = [int](Get-HuRegistryValue 'HKCU:\Software\Classes\CLSID\{e88865ea-0e1c-4e20-9aa6-edcd0212c87c}' 'System.IsPinnedToNameSpaceTree' 1) -eq 0
        $ClockSecondsToggle.IsChecked = [int](Get-HuRegistryValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'ShowSecondsInSystemClock' 0) -eq 1
        if (Get-Command Update-HuLocalUserControls -ErrorAction SilentlyContinue) { Update-HuLocalUserControls }
        if (Get-Command Update-HuSafeModeBootControls -ErrorAction SilentlyContinue) { Update-HuSafeModeBootControls }
    }
    finally { $script:UpdatingPerformanceUi = $false }
}

function Refresh-DebloatCleanupState {
    $script:UpdatingPerformanceUi = $true
    try {
        $BingSearchToggle.IsChecked = [int](Get-HuRegistryValue 'HKCU:\Software\Policies\Microsoft\Windows\Explorer' 'DisableSearchBoxSuggestions' 0) -eq 1
        $SponsoredAppsToggle.IsChecked = [int](Get-HuRegistryValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableWindowsConsumerFeatures' 0) -eq 1
        $SuggestionsToggle.IsChecked = [int](Get-HuRegistryValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SilentInstalledAppsEnabled' 1) -eq 0
    }
    finally { $script:UpdatingPerformanceUi = $false }
}

$DefenderCpuSlider.Add_ValueChanged({ if (-not $script:UpdatingPerformanceUi) { $DefenderCpuValue.Text = ('{0} %' -f [int]$DefenderCpuSlider.Value) } })
$ApplyDefenderCpuButton.Add_Click({
    $percent = [int]$DefenderCpuSlider.Value
    $ApplyDefenderCpuButton.IsEnabled = $false
    $queue = [Collections.Concurrent.ConcurrentQueue[object]]::new()
    $title = T 'DefenderCpuTitle'
    Add-HuPerformanceLogLine -Item ([pscustomobject]@{Text=('[START] {0}' -f $title);Level='Normal'})
    Add-HuPerformanceLogLine -Item ([pscustomobject]@{Text=('[CHECK] {0} %' -f $percent);Level='Normal'})
    $worker = {
        param($root,$requested,$operationTitle,$progressQueue)
        Import-Module (Join-Path $root 'WNST.psd1') -Force
        . (Join-Path $root 'Modules\System.ps1')
        . (Join-Path $root 'Modules\Performance.ps1')
        $progressQueue.Enqueue([pscustomobject]@{Text=('[REG] Defender policy AvgCPULoadFactor -> {0} %' -f $requested);Level='Normal'})
        $result = Set-HuDefenderCpuLimit -Percent $requested
        $progressQueue.Enqueue([pscustomobject]@{Text=('[VERIFY] requested={0} policy={1} defender={2}' -f $result.Requested,$result.PolicyActual,$result.DefenderActual);Level='Normal'})
        $result
    }
    $progress = { param($item) Add-HuPerformanceLogLine -Item $item }.GetNewClosure()
    $completed = {
        param($output)
        $result = @($output) | Where-Object { $_.PSObject.Properties['Requested'] } | Select-Object -Last 1
        $script:UpdatingPerformanceUi = $true
        try { if($result){$DefenderCpuSlider.Value=[double]$result.Actual;$DefenderCpuValue.Text=('{0} %' -f $result.Actual)} }
        finally { $script:UpdatingPerformanceUi=$false; $ApplyDefenderCpuButton.IsEnabled=$true }
        $PerformanceStateText.Text=T $(if($result -and $result.Verified){'ChangeVerified'}else{'ChangeNotVerified'})
        Add-HuPerformanceLogLine -Item ([pscustomobject]@{Text=($(if($result -and $result.Verified){'[OK] '}else{'[FAIL] '}) + $PerformanceStateText.Text);Level=$(if($result -and $result.Verified){'Success'}else{'Error'})})
    }.GetNewClosure()
    $failed = { param($message) $ApplyDefenderCpuButton.IsEnabled=$true; Add-HuPerformanceLogLine -Item ([pscustomobject]@{Text=('[FAIL] {0}' -f [string]$message);Level='Error'}); $PerformanceStateText.Text=[string]$message }.GetNewClosure()
    [void](Invoke-HuAsyncWork -Key 'Performance.DefenderCpu' -ScriptBlock $worker -ArgumentList @($script:AppRoot,$percent,$title,$queue) -OnCompleted $completed -OnError $failed -OnProgress $progress -ProgressQueue $queue -TimeoutSeconds 30 -Replace)
})

Register-HuPerformanceToggle $TransparencyToggle 'TransparencyTitle' 'Transparency' 'Set-HuTransparency'
Register-HuPerformanceToggle $AnimationsToggle 'AnimationsTitle' 'AnimationsDisabled' 'Set-HuAnimationsDisabled'
Register-HuPerformanceToggle $ShutdownAnimationToggle 'ShutdownAnimationTitle' 'ShutdownAnimationDisabled' 'Set-HuShutdownAnimationDisabled'
Register-HuPerformanceToggle $NotificationsToggle 'NotificationsTitle' 'NotificationsDisabled' 'Set-HuNotificationsDisabled' 'ConfirmNotificationsChange'
Register-HuPerformanceToggle $EndTaskToggle 'EndTaskTitle' 'EndTask' 'Set-HuEndTask'
Register-HuPerformanceToggle $LegacyContextToggle 'LegacyContextTitle' 'LegacyContextMenu' 'Set-HuLegacyContextMenu'
Register-HuPerformanceToggle $LegacyExplorerToggle 'LegacyExplorerTitle' 'LegacyExplorer' 'Set-HuLegacyExplorer' 'ConfirmLegacyExplorer'
Register-HuPerformanceToggle $GameDvrToggle 'GameDvrTitle' 'GameFeaturesDisabled' 'Set-HuGameFeaturesDisabled'
Register-HuPerformanceToggle $BackgroundThrottleToggle 'BackgroundThrottleTitle' 'BackgroundThrottleDisabled' 'Set-HuBackgroundThrottleDisabled'
Register-HuPerformanceToggle $LatencyToggle 'LatencyTitle' 'LatencyOptimized' 'Set-HuLatencyOptimized'
Register-HuPerformanceToggle $GamingTasksToggle 'GamingTasksTitle' 'TasksDisabled' 'Set-HuGamingTasksDisabled'
Register-HuPerformanceToggle $BackgroundServicesToggle 'BackgroundServicesTitle' 'ServicesDisabled' 'Set-HuBackgroundServicesDisabled' 'ConfirmBackgroundServices'
Register-HuPerformanceToggle $TaskbarOptimizeToggle 'TaskbarOptimizeTitle' 'TaskbarOptimized' 'Set-HuTaskbarOptimized'
Register-HuPerformanceToggle $StartupOptimizeToggle 'StartupOptimizeTitle' 'StartupOptimized' 'Set-HuStartupOptimized'

Register-HuMovedToggle $HomeToggle 'ExplorerHomeTitle' 'HomeHidden' 'Set-HuHomeHidden' $WindowsOutputBox
Register-HuMovedToggle $GalleryToggle 'GalleryTitle' 'GalleryHidden' 'Set-HuGalleryHidden' $WindowsOutputBox
Register-HuMovedToggle $ClockSecondsToggle 'ClockSecondsTitle' 'ClockSeconds' 'Set-HuClockSeconds' $WindowsOutputBox
Register-HuMovedToggle $BingSearchToggle 'BingSearchTitle' 'BingDisabled' 'Set-HuBingSearchDisabled' $CleanupOutputBox
Register-HuMovedToggle $SponsoredAppsToggle 'SponsoredAppsTitle' 'SponsoredBlocked' 'Set-HuSponsoredAppsBlocked' $CleanupOutputBox
Register-HuMovedToggle $SuggestionsToggle 'SuggestionsTitle' 'SuggestionsBlocked' 'Set-HuSuggestionsBlocked' $CleanupOutputBox

try {
    $homeGalleryMigration = Repair-HuHomeGalleryFolderDescriptions
    if ($homeGalleryMigration.RemovedCount -gt 0) {
        Add-HuWindowsLogLine ([pscustomobject]@{Text=('[OK] {0}' -f (TF 'HomeGalleryMigrationRepaired' @($homeGalleryMigration.RemovedCount)));Level='Success'})
    }
}
catch {
    Add-HuWindowsLogLine ([pscustomobject]@{Text=('[FAIL] {0}' -f $_.Exception.Message);Level='Error'})
}

function Invoke-HuPowerModeButton {
    param([ValidateSet('Eco','Normal','High')][string]$Mode)
    foreach($button in @($PowerEcoButton,$PowerNormalButton,$PowerHighButton)){$button.IsEnabled=$false}
    $queue=[Collections.Concurrent.ConcurrentQueue[object]]::new();$title=T 'PowerModeTitle'
    $worker={param($root,$modeValue,$operationTitle,$progressQueue);Import-Module (Join-Path $root 'WNST.psd1') -Force;. (Join-Path $root 'Modules\System.ps1')
        . (Join-Path $root 'Modules\Performance.ps1');$progressQueue.Enqueue([pscustomobject]@{Text=('[START] {0} -> {1}' -f $operationTitle,$modeValue);Level='Normal'});$result=Set-HuPowerMode $modeValue;$progressQueue.Enqueue([pscustomobject]@{Key=$(if($result.Verified){'ChangeVerified'}else{'PowerModeUnavailable'});Level=$(if($result.Verified){'Success'}else{'Error'})});$result}
    $progress={param($item)Add-HuPerformanceLogLine -Item $item}.GetNewClosure()
    $completed={param($output)$result=@($output)|Where-Object{$_.PSObject.Properties['Mode']}|Select-Object -Last 1;foreach($button in @($PowerEcoButton,$PowerNormalButton,$PowerHighButton)){$button.IsEnabled=$true};if($result){$PowerModeStatus.Text=T ('PowerMode'+[string]$result.Mode)}}.GetNewClosure()
    $failed={param($message)foreach($button in @($PowerEcoButton,$PowerNormalButton,$PowerHighButton)){$button.IsEnabled=$true};Add-HuPerformanceLogLine -Item ([pscustomobject]@{Text=('[FAIL] {0}' -f [string]$message);Level='Error'})}.GetNewClosure()
    [void](Invoke-HuAsyncWork -Key 'Performance.PowerMode' -ScriptBlock $worker -ArgumentList @($script:AppRoot,$Mode,$title,$queue) -OnCompleted $completed -OnError $failed -OnProgress $progress -ProgressQueue $queue -TimeoutSeconds 20 -Replace)
}

$PowerEcoButton.Add_Click({Invoke-HuPowerModeButton 'Eco'})
$PowerNormalButton.Add_Click({Invoke-HuPowerModeButton 'Normal'})
$PowerHighButton.Add_Click({Invoke-HuPowerModeButton 'High'})
$RefreshPerformanceButton.Add_Click({Refresh-PerformanceState})
$ClearPerformanceLogButton.Add_Click({Clear-WnstLogContent -Control $PerformanceOutputBox})
$ClearCleanupLogButton.Add_Click({Clear-WnstLogContent -Control $CleanupOutputBox})
