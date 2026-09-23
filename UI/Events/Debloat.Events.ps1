$script:AppxFunctionalDescriptionData = $null

function Get-AppxFunctionalDescription {
    param(
        [Parameter(Mandatory=$true)][object]$Item,
        [string]$Language = ''
    )

    $packageName = ''
    try { $packageName = [string]$Item.CatalogId } catch {}
    if ([string]::IsNullOrWhiteSpace($packageName)) { $packageName = [string]$Item.PackageName }
    if ([string]::IsNullOrWhiteSpace($packageName)) { return '' }

    if ([string]::IsNullOrWhiteSpace($Language)) {
        try { $Language = [string]$script:Settings.Language } catch {}
    }
    if ([string]::IsNullOrWhiteSpace($Language)) { $Language = 'en-US' }

    if ($null -eq $script:AppxFunctionalDescriptionData) {
        $descriptionPath = Join-Path $script:AppRoot 'Data\AppxDescriptions.json'
        if (-not (Test-Path -LiteralPath $descriptionPath)) { return '' }

        try {
            $raw = [IO.File]::ReadAllText($descriptionPath, [Text.Encoding]::UTF8)
            $script:AppxFunctionalDescriptionData = $raw | ConvertFrom-Json
        }
        catch {
            return ''
        }
    }

    $languageNode = $script:AppxFunctionalDescriptionData.PSObject.Properties[$Language]
    if ($null -eq $languageNode) { return '' }

    $packageNode = $languageNode.Value.PSObject.Properties[$packageName]
    if ($null -eq $packageNode) { return '' }

    return [string]$packageNode.Value
}



function Update-AppxLocalizedDescriptions {
    if (-not $AppxGrid) { return }

    $language = ''
    try { $language = [string]$script:Settings.Language } catch {}
    if ([string]::IsNullOrWhiteSpace($language)) { $language = 'en-US' }

    $descriptionItems = if ($script:AppxState -and $script:AppxState.AllItems) { @($script:AppxState.AllItems) } elseif ($AppxGrid.ItemsSource) { @($AppxGrid.ItemsSource) } else { @() }

    foreach ($item in $descriptionItems) {
        # Le catalogue WNST reste prioritaire. Pour les nouvelles entrées qui
        # n'ont pas encore de traduction dédiée, le code utilise ensuite les
        # métadonnées localisées fournies par Windows avant le repli anglais.
        $functionalDescription = Get-AppxFunctionalDescription -Item $item -Language $language

        # Si une nouvelle entrée n'a pas encore de traduction dédiée, privilégier
        # d'abord la description réellement résolue par Windows dans la langue du système.
        if ([string]::IsNullOrWhiteSpace($functionalDescription)) {
            $metadataDescription = [string]$item.MetadataDescription
            if (-not [string]::IsNullOrWhiteSpace($metadataDescription) -and $metadataDescription -notmatch '^(?i:ms-resource:|@\{)') {
                $functionalDescription = $metadataDescription.Trim()
            }
        }

        # Dernier repli : description anglaise du catalogue WNST.
        if ([string]::IsNullOrWhiteSpace($functionalDescription) -and $language -ne 'en-US') {
            $functionalDescription = Get-AppxFunctionalDescription -Item $item -Language 'en-US'
        }

        # Pour un package réellement absent du catalogue, ne pas inventer sa fonction.
        if ([string]::IsNullOrWhiteSpace($functionalDescription)) {
            $display = if ([string]::IsNullOrWhiteSpace([string]$item.DisplayName)) { [string]$item.PackageName } else { [string]$item.DisplayName }
            $functionalDescription = TF 'AppxDescriptionUnavailableExact' @($display)
        }

        if ([bool]$item.IsStartSuggestion) {
            $item.Description = TF 'AppxStartSuggestionDescription' @($functionalDescription)
        }
        else {
            $item.Description = $functionalDescription
        }
    }
}

$script:AppxState = [pscustomobject]@{
    InventoryLoaded  = $false
    InventoryLoading = $false
    AllItems         = @()
    HiddenNames      = @{}
}

function Get-AppxHiddenStorePath {
    return (Join-Path ([string]$script:Paths.DataRoot) 'AppxHidden.json')
}

function Get-AppxHiddenPackageSet {
    $set = @{}
    $path = Get-AppxHiddenStorePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $set }

    try {
        $raw = [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8)
        if ([string]::IsNullOrWhiteSpace($raw)) { return $set }
        $data = $raw | ConvertFrom-Json -ErrorAction Stop
        foreach ($name in @($data.Packages)) {
            if (-not [string]::IsNullOrWhiteSpace([string]$name)) { $set[[string]$name] = $true }
        }
    }
    catch { }
    return $set
}

function Save-AppxHiddenPackageSet {
    param([Parameter(Mandatory=$true)][hashtable]$Set)

    $path = Get-AppxHiddenStorePath
    $folder = Split-Path -Parent $path
    New-Item -ItemType Directory -Path $folder -Force -ErrorAction Stop | Out-Null

    $payload = [ordered]@{
        Version = 1
        Packages = @($Set.Keys | Sort-Object)
    }
    $json = $payload | ConvertTo-Json -Depth 4
    $tmp = $path + '.tmp'
    try {
        [IO.File]::WriteAllText($tmp, $json, (New-Object Text.UTF8Encoding($false)))
        Copy-Item -LiteralPath $tmp -Destination $path -Force -ErrorAction Stop
    }
    finally {
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
    }
}

function Format-AppxLegendWithCount {
    param(
        [Parameter(Mandatory=$true)][string]$Text,
        [Parameter(Mandatory=$true)][int]$Count
    )

    $separatorIndex = $Text.IndexOf(':')
    if ($separatorIndex -lt 0) {
        return ('{0} ({1})' -f $Text.Trim(),$Count)
    }

    $name = $Text.Substring(0,$separatorIndex).Trim()
    $description = $Text.Substring($separatorIndex + 1).Trim()
    return ('{0} ({1}) : {2}' -f $name,$Count,$description)
}

function Update-AppxLegendCounts {
    if (-not $script:AppxState -or -not [bool]$script:AppxState.InventoryLoaded) { return }

    $green = 0
    $yellow = 0
    $red = 0
    $hidden = 0
    foreach ($item in @($script:AppxState.AllItems)) {
        switch ([string]$item.Indicator) {
            'Green'  { $green++ }
            'Yellow' { $yellow++ }
            'Red'    { $red++ }
        }
        if ([bool]$item.IsHidden) { $hidden++ }
    }

    $AppxLegendRecommended.Text = Format-AppxLegendWithCount -Text (T 'AppxLegendRecommended') -Count $green
    $AppxLegendOptional.Text = Format-AppxLegendWithCount -Text (T 'AppxLegendOptional') -Count $yellow
    $AppxLegendProtected.Text = Format-AppxLegendWithCount -Text (T 'AppxLegendProtected') -Count $red
    $AppxLegendHidden.Text = Format-AppxLegendWithCount -Text (T 'AppxLegendHidden') -Count $hidden
}

function Update-AppxHiddenFilterUi {
    $state = $script:AppxState
    $hiddenCount = @($state.AllItems | Where-Object { [bool]$_.IsHidden }).Count
    $hasHidden = ($hiddenCount -gt 0)

    $AppxHiddenFilterPanel.Visibility = if ($hasHidden) { 'Visible' } else { 'Collapsed' }
    $AppxSelectHiddenButton.Visibility = if ($hasHidden) { 'Visible' } else { 'Collapsed' }
    $AppxFilterHiddenCheck.IsEnabled = $hasHidden -and [bool]$state.InventoryLoaded -and -not [bool]$state.InventoryLoading
    $AppxSelectHiddenButton.IsEnabled = $hasHidden -and [bool]$state.InventoryLoaded -and -not [bool]$state.InventoryLoading

    if (-not $hasHidden -and [bool]$AppxFilterHiddenCheck.IsChecked) {
        $AppxFilterHiddenCheck.IsChecked = $false
    }

    Update-AppxLegendCounts
}

function Get-AppxPrimaryInstallLocation {
    param([Parameter(Mandatory=$true)][object]$Item)

    foreach ($candidate in @($Item.InstallLocations)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$candidate) -and (Test-Path -LiteralPath ([string]$candidate) -PathType Container)) {
            return [string]$candidate
        }
    }
    return ''
}

function Find-AppxVisualDescendant {
    param(
        [Parameter(Mandatory=$true)][Windows.DependencyObject]$Root,
        [Parameter(Mandatory=$true)][Type]$Type,
        [string]$Name=''
    )

    $count = 0
    try { $count = [Windows.Media.VisualTreeHelper]::GetChildrenCount($Root) } catch { return $null }
    for ($index = 0; $index -lt $count; $index++) {
        $child = [Windows.Media.VisualTreeHelper]::GetChild($Root,$index)
        if ($Type.IsInstanceOfType($child)) {
            if ([string]::IsNullOrWhiteSpace($Name) -or [string]$child.Name -eq $Name) { return $child }
        }
        $found = Find-AppxVisualDescendant -Root $child -Type $Type -Name $Name
        if ($found) { return $found }
    }
    return $null
}

$script:AppxGridScrollViewer = $null

function Get-AppxGridScrollViewer {
    if ($script:AppxGridScrollViewer -is [Windows.Controls.ScrollViewer]) {
        return $script:AppxGridScrollViewer
    }

    $script:AppxGridScrollViewer = $null
    try {
        $AppxGrid.ApplyTemplate()
        $viewer = Find-AppxVisualDescendant -Root $AppxGrid -Type ([Windows.Controls.ScrollViewer]) -Name 'DG_ScrollViewer'
        if ($viewer -isnot [Windows.Controls.ScrollViewer]) {
            $viewer = Find-AppxVisualDescendant -Root $AppxGrid -Type ([Windows.Controls.ScrollViewer])
        }
        if ($viewer -is [Windows.Controls.ScrollViewer]) {
            $script:AppxGridScrollViewer = $viewer
        }
    }
    catch {
        $script:AppxGridScrollViewer = $null
    }

    return $script:AppxGridScrollViewer
}

$script:AppxLogScrollViewer = $null
$script:UpdatingAppxLogCustomScroll = $false
$script:AppxLogThumbDragStartOffset = 0.0
$script:AppxLogThumbDragDelta = 0.0

function Get-AppxLogScrollViewer {
    if ($script:AppxLogScrollViewer -is [Windows.Controls.ScrollViewer]) {
        return $script:AppxLogScrollViewer
    }

    $script:AppxLogScrollViewer = $null

    try {
        $AppxLogBox.ApplyTemplate()
        $viewer = $AppxLogBox.Template.FindName('PART_ContentHost',$AppxLogBox)
        if ($viewer -is [Windows.Controls.ScrollViewer]) {
            $script:AppxLogScrollViewer = $viewer
        }
    }
    catch {
        $script:AppxLogScrollViewer = $null
    }

    return $script:AppxLogScrollViewer
}

function Update-AppxLogCustomScrollbar {
    try {
        if ($script:UpdatingAppxLogCustomScroll) { return }
        $viewer = Get-AppxLogScrollViewer
        if (-not $viewer) { return }

        $script:UpdatingAppxLogCustomScroll = $true
        try {
            $extent = [double]$viewer.ExtentHeight
            $viewport = [double]$viewer.ViewportHeight
            $useCustom = $false

            if ($extent -gt $viewport -and $viewport -gt 0) {
                $naturalThumbHeight = ([double]$AppxLogCustomScrollTrack.ActualHeight) * ($viewport / $extent)
                $useCustom = $naturalThumbHeight -lt 24
            }

            if (-not $useCustom) {
                $AppxLogCustomScrollTrack.Visibility = 'Collapsed'
                $AppxLogBox.VerticalScrollBarVisibility = [Windows.Controls.ScrollBarVisibility]::Auto
                return
            }

            $AppxLogBox.VerticalScrollBarVisibility = [Windows.Controls.ScrollBarVisibility]::Hidden
            if ($AppxLogCustomScrollTrack.Visibility -ne 'Visible') {
                $AppxLogCustomScrollTrack.Visibility = 'Visible'
                $AppxLogCustomScrollTrack.UpdateLayout()
            }

            $trackHeight = [double]$AppxLogCustomScrollTrack.ActualHeight
            if ($trackHeight -le 0) { return }

            $proportionalHeight = $trackHeight * ($viewport / $extent)
            $thumbHeight = [Math]::Min($trackHeight,[Math]::Max(24.0,$proportionalHeight))
            $AppxLogCustomScrollThumb.Height = $thumbHeight

            $maxTop = [Math]::Max(0.0,$trackHeight - $thumbHeight)
            $scrollable = [double]$viewer.ScrollableHeight
            $top = 0.0
            if ($scrollable -gt 0 -and $maxTop -gt 0) {
                $ratio = [Math]::Max(0.0,[Math]::Min(1.0,([double]$viewer.VerticalOffset / $scrollable)))
                $top = $maxTop * $ratio
            }
            [Windows.Controls.Canvas]::SetTop($AppxLogCustomScrollThumb,$top)
        }
        finally { $script:UpdatingAppxLogCustomScroll = $false }
    }
    catch {
        try {
            $AppxLogCustomScrollTrack.Visibility = 'Collapsed'
            $AppxLogBox.VerticalScrollBarVisibility = [Windows.Controls.ScrollBarVisibility]::Auto
        }
        catch {}
    }
}

function Add-AppxLogLine {
    param(
        [AllowEmptyString()][string]$Text,
        [ValidateSet('Auto','Normal','Success','Error')][string]$Level = 'Auto'
    )
    if (-not $AppxLogBox -or [string]::IsNullOrWhiteSpace($Text)) { return }

    $localizedText = ConvertTo-WnstLocalizedLogText -Text $Text
    $line = '[{0}] {1}' -f ([DateTime]::Now.ToString('HH:mm:ss')), $localizedText
    $spacing = if ($Text -match '^\[START\](?:\s|$)') { 2 } else { 1 }
    Add-WnstLogText -Control $AppxLogBox -Text $line -Level $Level -LeadingNewLines $spacing
    Update-AppxLogCustomScrollbar
}

function Get-AppxLocalizedResultStatus {
    param([AllowEmptyString()][string]$Status)

    switch ($Status) {
        'Removed'  { return (T 'AppxResultRemoved') }
        'PendingRestart' { return (T 'AppxResultPendingRestart') }
        'Partial'  { return (T 'AppxResultPartial') }
        'Blocked'  { return (T 'AppxResultBlocked') }
        'NotFound' { return (T 'AppxResultNotFound') }
        default    { return $Status }
    }
}

function Get-AppxLocalizedSuggestionAction {
    param([AllowEmptyString()][string]$Action)

    switch ($Action) {
        'StartPinsPolicyArmed'       { return (T 'AppxStartActionPolicyArmed') }
        'StartPinsPendingRestart'    { return (T 'AppxStartActionPendingRestart') }
        'StartPinsCleanupCompleted'  { return (T 'AppxStartActionCleanupCompleted') }
        'StartMenuCacheCleanup'      { return (T 'AppxStartActionCacheCleanup') }
        'StartMenuCacheUpdated'      { return (T 'AppxStartActionCacheUpdated') }
        default                      { return $Action }
    }
}

function Get-AppxLocalizedResultError {
    param([AllowEmptyString()][string]$ErrorText)

    if ($ErrorText.StartsWith('StartLayoutApplyFailed|',[StringComparison]::Ordinal)) {
        $detail = $ErrorText.Substring('StartLayoutApplyFailed|'.Length)
        return '{0} [{1}]' -f (T 'AppxStartLayoutApplyFailed'),$detail
    }

    switch ($ErrorText) {
        'RemainingInstalled'          { return (T 'AppxResultRemainingInstalled') }
        'RemainingProvisioned'        { return (T 'AppxResultRemainingProvisioned') }
        'StartLayoutUnsupported'      { return (T 'AppxStartLayoutUnsupported') }
        'StartPinsPolicyManaged'      { return (T 'AppxStartPinsPolicyManaged') }
        'StartSuggestionStillPinned'  { return (T 'AppxStartSuggestionStillPinned') }
        'StartLayoutApplyFailed'      { return (T 'AppxStartLayoutApplyFailed') }
        default                       { return $ErrorText }
    }
}

function Add-AppxRemovalResultLog {
    param([Parameter(Mandatory=$true)][AllowEmptyCollection()][object[]]$Results)

    foreach ($result in @($Results)) {
        $name = if ([string]::IsNullOrWhiteSpace([string]$result.DisplayName)) { [string]$result.PackageName } else { [string]$result.DisplayName }
        $statusText = Get-AppxLocalizedResultStatus -Status ([string]$result.Status)
        $lineLevel = switch ([string]$result.Status) {
            'Removed' { 'Success' }
            { $_ -in @('Partial','Blocked','NotFound') } { 'Error' }
            default { 'Auto' }
        }
        if ([bool]$result.IsStartSuggestion) {
            Add-AppxLogLine (TF 'AppxLogSuggestionResult' @($name,$statusText)) -Level $lineLevel
        }
        else {
            Add-AppxLogLine (TF 'AppxLogResult' @($name,$statusText,[int]$result.InstalledRemoved,[int]$result.ProvisionedRemoved,[int]$result.UserDataRemoved)) -Level $lineLevel
        }
        foreach ($errorText in @($result.Errors)) {
            if (-not [string]::IsNullOrWhiteSpace([string]$errorText)) {
                $localizedError = Get-AppxLocalizedResultError -ErrorText ([string]$errorText)
                Add-AppxLogLine (TF 'AdvancedLogError' @('{0}: {1}' -f $name,$localizedError)) -Level Error
            }
        }
    }
}

function Get-AppxRemovalSummaryData {
    param([Parameter(Mandatory=$true)][AllowEmptyCollection()][object[]]$Results)

    $removed = @($Results | Where-Object Status -eq 'Removed').Count
    $pendingRestart = @($Results | Where-Object {
        $_.Status -eq 'PendingRestart' -or ($null -ne $_.PSObject.Properties['RestartRequired'] -and [bool]$_.RestartRequired)
    }).Count
    $partial = @($Results | Where-Object Status -eq 'Partial').Count
    $blocked = @($Results | Where-Object { $_.Status -in @('Blocked','NotFound') }).Count
    $text = if ($pendingRestart -gt 0) {
        TF 'AppxRemoveSummaryWithRestart' @($removed,$pendingRestart,$partial,$blocked)
    }
    else { TF 'AppxRemoveSummary' @($removed,$partial,$blocked) }
    return [pscustomobject]@{ Text=$text; PendingRestart=$pendingRestart }
}

function Unregister-WnstResumeAfterRestart {
    try { Unregister-ScheduledTask -TaskName 'WNST Resume After Restart' -Confirm:$false -ErrorAction SilentlyContinue }
    catch {}
}

function Register-WnstResumeAfterRestart {
    $taskName = 'WNST Resume After Restart'
    $userId = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    $hostExecutable = (Get-Process -Id $PID).Path
    $arguments = @(
        '-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-STA',
        '-File',('"{0}"' -f $script:EntryScriptPath),'-HiddenHost','-ResumeAfterRestart'
    )
    if ($script:DataRootArgument) { $arguments += @('-DataRoot',('"{0}"' -f [string]$script:DataRootArgument)) }

    $action = New-ScheduledTaskAction -Execute $hostExecutable -Argument ($arguments -join ' ')
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $userId
    $principal = New-ScheduledTaskPrincipal -UserId $userId -LogonType Interactive -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 5)
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force -ErrorAction Stop | Out-Null
}

function Invoke-AppxRecommendedRestart {
    if (-not (Show-AppRestartRecommendedDialog)) { return }
    $resumeRegistered = $false
    try {
        Register-WnstResumeAfterRestart
        $resumeRegistered = $true
        Start-Process (Join-Path $env:SystemRoot 'System32\shutdown.exe') -ArgumentList '/r','/t','0' -ErrorAction Stop
    }
    catch {
        if ($resumeRegistered) { Unregister-WnstResumeAfterRestart }
        Show-AppError $_.Exception.Message
    }
}

function Invoke-AppxPendingStartMenuCleanupCheck {
    $worker = {
        param($root,$dataRoot)
        . (Join-Path $root 'Modules\Debloat.ps1')
        Complete-WnstPendingStartMenuCleanup -DataRoot $dataRoot
    }
    $completed = {
        param($output)
        $result = @($output) | Select-Object -Last 1
        if (-not $result) { return }
        switch ([string]$result.State) {
            'Completed' {
                Add-AppxLogLine ('[OK] {0}' -f (T 'AppxStartCleanupCompletedAfterRestart')) -Level Success
                $script:AppxState.InventoryLoaded = $false
            }
            'PendingRestart' {
                Add-AppxLogLine (TF 'AppxStartCleanupStillPending' @([int]$result.RemainingCount))
            }
            'Failed' {
                $errorText = Get-AppxLocalizedResultError -ErrorText ([string]$result.ErrorCode)
                Add-AppxLogLine (TF 'AdvancedLogError' @($errorText)) -Level Error
                Show-AppError $errorText
            }
        }
    }.GetNewClosure()
    $failed = {
        param($message)
        Add-AppxLogLine (TF 'AdvancedLogError' @([string]$message)) -Level Error
    }.GetNewClosure()
    [void](Invoke-HuAsyncWork -Key 'PendingStartMenuCleanup' -ScriptBlock $worker -ArgumentList @($script:AppRoot,[string]$script:Paths.DataRoot) -OnCompleted $completed -OnError $failed -TimeoutSeconds 30 -Replace)
}

function Test-AppxItemSelected {
    param([Parameter(Mandatory=$true)][object]$Item)
    if (-not [bool]$Item.IsChecked) { return $false }
    if ([bool]$Item.IsSelectable) { return $true }
    return ([string]$Item.Indicator -eq 'Red' -and [bool]$Item.ProtectedApproved)
}

function Update-AppxSelectionControls {
    $state = $script:AppxState
    $canUse = (-not [bool]$state.InventoryLoading) -and [bool]$state.InventoryLoaded
    if (-not $canUse) {
        $AppxSelectRecommendedButton.IsEnabled = $false
        $AppxSelectOptionalButton.IsEnabled = $false
        $AppxSelectProtectedButton.IsEnabled = $false
        $AppxSelectHiddenButton.IsEnabled = $false
        $AppxClearSelectionButton.IsEnabled = $false
        $AppxRemoveButton.IsEnabled = $false
        return
    }

    $items = @($state.AllItems | Where-Object { -not [bool]$_.IsHidden })
    $hasRecommended = @($items | Where-Object { [string]$_.Indicator -eq 'Green' }).Count -gt 0
    $hasOptional = @($items | Where-Object { [string]$_.Indicator -eq 'Yellow' }).Count -gt 0
    $hasProtected = @($items | Where-Object { [string]$_.Indicator -eq 'Red' }).Count -gt 0
    $hasHidden = @($state.AllItems | Where-Object { [bool]$_.IsHidden }).Count -gt 0
    $selectedCount = @($state.AllItems | Where-Object { Test-AppxItemSelected $_ }).Count

    $AppxSelectRecommendedButton.IsEnabled = $hasRecommended
    $AppxSelectOptionalButton.IsEnabled = $hasOptional
    $AppxSelectProtectedButton.IsEnabled = $hasProtected
    $AppxSelectHiddenButton.IsEnabled = $hasHidden
    $AppxClearSelectionButton.IsEnabled = ($selectedCount -gt 0)
    $AppxRemoveButton.IsEnabled = ($selectedCount -gt 0)
}

function Set-AppxControlsEnabled {
    param([bool]$Enabled)
    $state = $script:AppxState
    $canUseInventory = $Enabled -and [bool]$state.InventoryLoaded

    $AppxScanButton.IsEnabled = $Enabled
    $AppxFilterRecommendedCheck.IsEnabled = $canUseInventory
    $AppxFilterOptionalCheck.IsEnabled = $canUseInventory
    $AppxFilterProtectedCheck.IsEnabled = $canUseInventory
    $AppxFilterHiddenCheck.IsEnabled = $canUseInventory -and ($AppxHiddenFilterPanel.Visibility -eq 'Visible')
    $AppxRemoveUserDataCheck.IsEnabled = $canUseInventory

    if ($canUseInventory) {
        Update-AppxSelectionControls
    }
    else {
        $AppxSelectRecommendedButton.IsEnabled = $false
        $AppxSelectOptionalButton.IsEnabled = $false
        $AppxSelectProtectedButton.IsEnabled = $false
        $AppxSelectHiddenButton.IsEnabled = $false
        $AppxClearSelectionButton.IsEnabled = $false
        $AppxRemoveButton.IsEnabled = $false
    }
}

function Update-AppxFilter {
    if ($script:UpdatingAppxFilter) { return }
    $state = $script:AppxState
    if (-not [bool]$state.InventoryLoaded) { return }

    $script:UpdatingAppxFilter = $true
    try {

    $indicators = [Collections.Generic.List[string]]::new()
    if ([bool]$AppxFilterRecommendedCheck.IsChecked) { $indicators.Add('Green') }
    if ([bool]$AppxFilterOptionalCheck.IsChecked) { $indicators.Add('Yellow') }
    if ([bool]$AppxFilterProtectedCheck.IsChecked) { $indicators.Add('Red') }

    $showHidden = [bool]$AppxFilterHiddenCheck.IsChecked

    $sourceItems = if ($showHidden) {
        @($state.AllItems | Where-Object { [bool]$_.IsHidden })
    }
    else {
        @($state.AllItems | Where-Object { -not [bool]$_.IsHidden })
    }

    $visible = if ($indicators.Count -eq 0) {
        @($sourceItems)
    }
    else {
        @($sourceItems | Where-Object { $indicators.Contains([string]$_.Indicator) })
    }

    # WPF ItemsSource doit toujours recevoir un IEnumerable réel.
    # ObservableCollection reste une collection même avec 0 ou 1 élément,
    # contrairement à la sortie pipeline PowerShell qui peut se dérouler en objet simple.
    $collection = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
    foreach ($entry in @($visible)) {
        [void]$collection.Add($entry)
    }
        $AppxGrid.ItemsSource = $collection
    }
    finally {
        $script:UpdatingAppxFilter = $false
    }
}

function Get-AppxDataGridRowFromSource {
    param([object]$Source)
    $current = $Source
    while ($null -ne $current) {
        if ($current -is [Windows.Controls.DataGridRow]) { return $current }
        try { $current = [Windows.Media.VisualTreeHelper]::GetParent($current) }
        catch { break }
    }
    return $null
}

function Request-AppxInventory {
    param([switch]$Force)
    $state = $script:AppxState
    if ([bool]$state.InventoryLoading) { return }
    if ([bool]$state.InventoryLoaded -and -not $Force) { return }

    $state.InventoryLoading = $true
    $AppxStatusText.Text = T 'AppxStatusScanning'
    Add-AppxLogLine (T 'AppxStatusScanning')
    Set-AppxControlsEnabled -Enabled $false

    $worker = {
        param($root)
        . (Join-Path $root 'Modules\Debloat.ps1')
        @(Get-WnstAppxInventory)
    }
    $completed = {
        param($output)
        $state.InventoryLoading = $false
        $items = @($output)
        $hiddenNames = Get-AppxHiddenPackageSet
        $state.HiddenNames = $hiddenNames

        foreach ($item in $items) {
            # Toujours démarrer avec une liste entièrement décochée. La sélection est
            # ensuite explicitement faite par l'utilisateur ou par les boutons de catégorie.
            $item.IsChecked = $false
            Add-Member -InputObject $item -NotePropertyName ProtectedApproved -NotePropertyValue $false -Force
            Add-Member -InputObject $item -NotePropertyName CanToggle -NotePropertyValue ([bool]$item.IsSelectable) -Force
            Add-Member -InputObject $item -NotePropertyName IsHidden -NotePropertyValue ($hiddenNames.ContainsKey([string]$item.PackageName)) -Force

            # Conserver séparément la description de Windows/éditeur afin de pouvoir
            # recalculer les descriptions localisées sans perdre la source d'origine.
            $metadataDescription = [string]$item.Description
            Add-Member -InputObject $item -NotePropertyName MetadataDescription -NotePropertyValue $metadataDescription -Force
        }

        $state.AllItems = @($items)
        $state.InventoryLoaded = $true
        Update-AppxLocalizedDescriptions
        Update-AppxHiddenFilterUi
        Update-AppxFilter
        Set-AppxControlsEnabled -Enabled $true
        $AppxStatusText.Text = TF 'AppxStatusReady' @($items.Count)
        $green = @($items | Where-Object { [string]$_.Indicator -eq 'Green' }).Count
        $yellow = @($items | Where-Object { [string]$_.Indicator -eq 'Yellow' }).Count
        $red = @($items | Where-Object { [string]$_.Indicator -eq 'Red' }).Count
        Add-AppxLogLine ((TF 'AppxStatusReady' @($items.Count)) + ' ' + (TF 'AppxLogCategoryCounts' @($green,$yellow,$red)))
    }.GetNewClosure()
    $failed = {
        param($message)
        $state.InventoryLoading = $false
        $state.InventoryLoaded = $false
        $state.AllItems = @()
        $AppxGrid.ItemsSource = $null
        Set-AppxControlsEnabled -Enabled $true
        $text = if ($message -eq 'AdministratorRequired') { T 'AdministratorRequired' } else { $message }
        $AppxStatusText.Text = $text
        Add-AppxLogLine (TF 'AdvancedLogError' @($text)) -Level Error
        Show-AppError $text
    }.GetNewClosure()

    if (-not (Invoke-HuAsyncWork -Key 'AppxInventory' -ScriptBlock $worker -ArgumentList @($script:AppRoot) -OnCompleted $completed -OnError $failed -TimeoutSeconds 45 -Replace)) {
        $state.InventoryLoading = $false
        Set-AppxControlsEnabled -Enabled $true
        $AppxStatusText.Text = T 'CommandStartFailed'
        Add-AppxLogLine (T 'CommandStartFailed') -Level Error
    }
}

$AppxScanButton.Add_Click({ Request-AppxInventory -Force })

function Select-AppxCategory {
    param(
        [Parameter(Mandatory=$true)][ValidateSet('Green','Yellow','Red')][string]$Indicator
    )

    $targets = @($script:AppxState.AllItems | Where-Object {
        [string]$_.Indicator -eq $Indicator -and -not [bool]$_.IsHidden
    })
    if ($targets.Count -eq 0) { return }

    if ($Indicator -eq 'Red') {
        $pendingProtected = @($targets | Where-Object { -not ([bool]$_.IsChecked -and [bool]$_.ProtectedApproved) })
        if ($pendingProtected.Count -gt 0) {
            if (-not (Show-AppConfirm (TF 'AppxProtectedBulkSelectionWarning' @($pendingProtected.Count)))) { return }
        }

        foreach ($item in $targets) {
            $item.ProtectedApproved = $true
            $item.CanToggle = $true
            $item.IsChecked = $true
        }
    }
    else {
        foreach ($item in $targets) {
            $item.IsChecked = $true
        }
    }

    try { $AppxGrid.Items.Refresh() } catch {}
    Update-AppxSelectionControls
}

$AppxSelectRecommendedButton.Add_Click({ Select-AppxCategory -Indicator 'Green' })
$AppxSelectOptionalButton.Add_Click({ Select-AppxCategory -Indicator 'Yellow' })
$AppxSelectProtectedButton.Add_Click({ Select-AppxCategory -Indicator 'Red' })

$AppxSelectHiddenButton.Add_Click({
    $targets = @($script:AppxState.AllItems | Where-Object { [bool]$_.IsHidden })
    if ($targets.Count -eq 0) { return }

    $pendingProtected = @($targets | Where-Object {
        [string]$_.Indicator -eq 'Red' -and -not ([bool]$_.IsChecked -and [bool]$_.ProtectedApproved)
    })
    if ($pendingProtected.Count -gt 0) {
        if (-not (Show-AppConfirm (TF 'AppxProtectedBulkSelectionWarning' @($pendingProtected.Count)))) { return }
    }

    foreach ($item in $targets) {
        if ([string]$item.Indicator -eq 'Red') {
            $item.ProtectedApproved = $true
            $item.CanToggle = $true
        }
        $item.IsChecked = $true
    }

    try { $AppxGrid.Items.Refresh() } catch {}
    Update-AppxSelectionControls
})

$AppxClearSelectionButton.Add_Click({
    foreach ($item in @($script:AppxState.AllItems)) {
        $item.IsChecked = $false
        if ([string]$item.Indicator -eq 'Red') {
            $item.ProtectedApproved = $false
            $item.CanToggle = $false
        }
    }
    try { $AppxGrid.Items.Refresh() } catch {}
    Update-AppxSelectionControls
})

# Les quatre filtres sont cumulables. Aucun filtre de catégorie coché = afficher toute la liste.
foreach ($filterCheck in @($AppxFilterRecommendedCheck,$AppxFilterOptionalCheck,$AppxFilterProtectedCheck,$AppxFilterHiddenCheck)) {
    $filterCheck.Add_Checked({ Update-AppxFilter })
    $filterCheck.Add_Unchecked({ Update-AppxFilter })
}

# Un clic simple sur une ligne ne coche pas automatiquement l'application : la case reste
# l'action explicite pour une sélection simple. En revanche, dès qu'une sélection multiple
# Ctrl/Shift est constituée, les lignes sélectionnées sont aussi cochées.
# Les composants protégés conservent leur confirmation explicite.
$script:UpdatingAppxMultiRowSelection = $false
$AppxGrid.Add_SelectionChanged({
    param($sender,$eventArgs)

    if (-not $script:UpdatingAppxMultiRowSelection) {
        $selectedRows = @($AppxGrid.SelectedItems)
        if ($selectedRows.Count -gt 1) {
            $script:UpdatingAppxMultiRowSelection = $true
            try {
                foreach ($item in @($selectedRows | Where-Object { [string]$_.Indicator -ne 'Red' })) {
                    $item.IsChecked = $true
                }

                $pendingProtected = @($selectedRows | Where-Object {
                    [string]$_.Indicator -eq 'Red' -and -not ([bool]$_.IsChecked -and [bool]$_.ProtectedApproved)
                })
                if ($pendingProtected.Count -gt 0) {
                    if (Show-AppConfirm (TF 'AppxProtectedBulkSelectionWarning' @($pendingProtected.Count))) {
                        foreach ($item in $pendingProtected) {
                            $item.ProtectedApproved = $true
                            $item.CanToggle = $true
                            $item.IsChecked = $true
                        }
                    }
                }

                try { $AppxGrid.Items.Refresh() } catch {}
            }
            finally { $script:UpdatingAppxMultiRowSelection = $false }
        }
    }

    Update-AppxSelectionControls
})

# Les composants rouges ne peuvent pas être cochés normalement. Un double-clic sur
# leur ligne demande une confirmation explicite et bascule ensuite leur sélection.
$AppxGrid.Add_MouseDoubleClick({
    param($sender,$eventArgs)
    if ($eventArgs.ChangedButton -ne [Windows.Input.MouseButton]::Left) { return }
    $row = Get-AppxDataGridRowFromSource -Source $eventArgs.OriginalSource
    if ($null -eq $row) { return }
    $item = $row.Item
    if ($null -eq $item -or [string]$item.Indicator -ne 'Red') { return }

    if ([bool]$item.IsChecked -and [bool]$item.ProtectedApproved) { return }

    $eventArgs.Handled = $true
    $name = if ([string]::IsNullOrWhiteSpace([string]$item.DisplayName)) { [string]$item.PackageName } else { [string]$item.DisplayName }
    if (Show-AppConfirm (TF 'AppxProtectedSelectionWarning' @($name))) {
        $item.ProtectedApproved = $true
        $item.CanToggle = $true
        $item.IsChecked = $true
    }

    try { $AppxGrid.Items.Refresh() } catch {}
    Update-AppxSelectionControls
})

# Après un clic dans une case normale, le binding a déjà mis à jour IsChecked lorsque
# l'événement remonte au DataGrid. On synchronise alors immédiatement les boutons.
$AppxGrid.AddHandler(
    [Windows.Controls.Primitives.ButtonBase]::ClickEvent,
    [Windows.RoutedEventHandler]{
        param($sender,$eventArgs)

        $row = Get-AppxDataGridRowFromSource -Source $eventArgs.OriginalSource
        if ($row) {
            $item = $row.Item
            if ($item -and [string]$item.Indicator -eq 'Red' -and [bool]$item.ProtectedApproved -and -not [bool]$item.IsChecked) {
                $item.ProtectedApproved = $false
                $item.CanToggle = $false
                try { $AppxGrid.Items.Refresh() } catch {}
            }
        }

        Update-AppxSelectionControls
    }
)

$script:ContextSelectedAppxRow = $null

$AppxGrid.Add_PreviewMouseWheel({
    param($sender,$eventArgs)

    $viewer = Get-AppxGridScrollViewer
    if ($viewer -isnot [Windows.Controls.ScrollViewer]) { return }

    # En mode pixel-scroll, on défile d'environ deux lignes par cran.
    $rowHeight = if ([double]$AppxGrid.RowHeight -gt 0) { [double]$AppxGrid.RowHeight } else { 42.0 }
    $step = $rowHeight * 2.0
    if ($eventArgs.Delta -gt 0) {
        $viewer.ScrollToVerticalOffset([Math]::Max(0.0,[double]$viewer.VerticalOffset - $step))
    }
    elseif ($eventArgs.Delta -lt 0) {
        $viewer.ScrollToVerticalOffset([Math]::Min([double]$viewer.ScrollableHeight,[double]$viewer.VerticalOffset + $step))
    }

    $eventArgs.Handled = $true
})

$AppxGrid.Add_PreviewMouseRightButtonDown({
    if ($script:ContextSelectedAppxRow) {
        $script:ContextSelectedAppxRow.Tag = $null
        $script:ContextSelectedAppxRow = $null
    }

    $row = Get-AppxDataGridRowFromSource -Source $_.OriginalSource
    if ($row) {
        # Conserver la sélection multiple lors d'un clic droit sur une ligne déjà sélectionnée.
        # Un clic droit sur une ligne hors sélection repart uniquement de cette ligne.
        if (-not [bool]$row.IsSelected) {
            $AppxGrid.SelectedItems.Clear()
            $row.IsSelected = $true
        }
        try { $AppxGrid.CurrentItem = $row.Item } catch {}
        $row.Tag = 'ContextSelected'
        $script:ContextSelectedAppxRow = $row
    }
    else {
        $AppxGrid.SelectedItems.Clear()
    }
})

$AppxGrid.Add_PreviewMouseLeftButtonDown({
    if ($script:ContextSelectedAppxRow) {
        $script:ContextSelectedAppxRow.Tag = $null
        $script:ContextSelectedAppxRow = $null
    }
})

$AppxContextMenu.Add_Opened({
    $item = $AppxGrid.CurrentItem
    $selectedItems = @($AppxGrid.SelectedItems)
    $enabled = $null -ne $item
    $AppxDetailsMenuItem.IsEnabled = $enabled
    $AppxStandaloneRemoveMenuItem.IsEnabled = ($selectedItems.Count -gt 0)
    $AppxStandaloneRemoveMenuItem.Header = if ($selectedItems.Count -gt 1) { T 'AppxUninstallSelection' } else { T 'AppxContextStandaloneRemove' }
    $AppxHideMenuItem.IsEnabled = ($selectedItems.Count -gt 0)

    $location = if ($enabled) { Get-AppxPrimaryInstallLocation -Item $item } else { '' }
    $AppxOpenLocationMenuItem.IsEnabled = $enabled -and -not [string]::IsNullOrWhiteSpace($location)

    $allHidden = ($selectedItems.Count -gt 0 -and @($selectedItems | Where-Object { [bool]$_.IsHidden }).Count -eq $selectedItems.Count)
    if ($allHidden) {
        $AppxHideMenuItem.Header = T 'AppxContextUnhide'
    }
    else {
        $AppxHideMenuItem.Header = T 'AppxContextHide'
    }
})

$AppxContextMenu.Add_Closed({
    if ($script:ContextSelectedAppxRow) {
        $script:ContextSelectedAppxRow.Tag = $null
        $script:ContextSelectedAppxRow = $null
    }
})

$AppxOpenLocationMenuItem.Add_Click({
    $item = $AppxGrid.CurrentItem
    if (-not $item) { return }

    $location = Get-AppxPrimaryInstallLocation -Item $item
    if ([string]::IsNullOrWhiteSpace($location)) {
        Show-AppError (T 'Unavailable')
        return
    }

    try { Start-Process -FilePath 'explorer.exe' -ArgumentList @($location) }
    catch { Show-AppError $_.Exception.Message }
})

$AppxDetailsMenuItem.Add_Click({
    $item = $AppxGrid.CurrentItem
    if (-not $item) { return }
    try { Show-AppxDetailsDialog -Row $item }
    catch { Show-AppError $_.Exception.Message }
})

$AppxHideMenuItem.Add_Click({
    $items = @($AppxGrid.SelectedItems)
    if ($items.Count -eq 0) {
        $fallbackItem = $AppxGrid.SelectedItem
        if ($fallbackItem) { $items = @($fallbackItem) }
    }
    if ($items.Count -eq 0) { return }

    try {
        $allHidden = (@($items | Where-Object { [bool]$_.IsHidden }).Count -eq $items.Count)

        foreach ($item in $items) {
            $name = [string]$item.PackageName
            $displayName = if ([string]::IsNullOrWhiteSpace([string]$item.DisplayName)) { $name } else { [string]$item.DisplayName }

            if ($allHidden) {
                if ($script:AppxState.HiddenNames.ContainsKey($name)) { $script:AppxState.HiddenNames.Remove($name) }
                $item.IsHidden = $false
                Add-AppxLogLine (TF 'AppxLogUnhidden' @($displayName))
            }
            else {
                $script:AppxState.HiddenNames[$name] = $true
                $item.IsHidden = $true
                $item.IsChecked = $false
                if ([string]$item.Indicator -eq 'Red') {
                    $item.ProtectedApproved = $false
                    $item.CanToggle = $false
                }
                Add-AppxLogLine (TF 'AppxLogHidden' @($displayName))
            }
        }

        Save-AppxHiddenPackageSet -Set $script:AppxState.HiddenNames
        Update-AppxHiddenFilterUi
        Update-AppxFilter
        Update-AppxSelectionControls
    }
    catch { Show-AppError $_.Exception.Message }
})

function Invoke-AppxStandaloneRemoval {
    param([Parameter(Mandatory=$true)][object]$Item)

    if ([bool]$script:AppxState.InventoryLoading) { return }

    $displayName = if ([string]::IsNullOrWhiteSpace([string]$Item.DisplayName)) { [string]$Item.PackageName } else { [string]$Item.DisplayName }
    $allowedProtected = @()

    if ([string]$Item.Indicator -eq 'Red') {
        if (-not (Show-AppConfirm (TF 'AppxProtectedSelectionWarning' @($displayName)))) { return }
        $allowedProtected = @([string]$Item.PackageName)
    }

    $isStartSuggestion = [bool]$Item.IsStartSuggestion
    $confirmKey = if ($isStartSuggestion) { 'AppxConfirmStandaloneSuggestionRemove' } else { 'AppxConfirmStandaloneRemove' }
    if (-not (Show-AppConfirm (TF $confirmKey @($displayName)))) { return }

    $state = $script:AppxState
    $state.InventoryLoading = $true
    Set-AppxControlsEnabled -Enabled $false
    $AppxStatusText.Text = T 'AppxStatusRemoving'
    if ($isStartSuggestion) { Add-AppxLogLine (TF 'AppxLogSuggestionStandalone' @($displayName)) }
    else { Add-AppxLogLine (TF 'AppxLogStandalone' @($displayName)) }

    $progressQueue = [System.Collections.Concurrent.ConcurrentQueue[object]]::new()
    $progress = {
        param($progressItem)
        if (-not $progressItem) { return }

        $display = if ([string]::IsNullOrWhiteSpace([string]$progressItem.DisplayName)) {
            [string]$progressItem.PackageName
        } else {
            [string]$progressItem.DisplayName
        }

        switch ([string]$progressItem.Kind) {
            'PackageStart'     { Add-AppxLogLine ('[APPX] {0}' -f $display) }
            'SuggestionStart'  { Add-AppxLogLine ('[START] {0}' -f $display) }
            'SuggestionAction' { Add-AppxLogLine ('[START] {0}' -f (Get-AppxLocalizedSuggestionAction -Action ([string]$progressItem.Text))) }
            'Command'          { Add-AppxLogLine ('[CMD] {0}' -f [string]$progressItem.Text) }
            'Ok'               { Add-AppxLogLine ('[OK] {0}' -f [string]$progressItem.Text) -Level Success }
            'DeferredWarning'  { }
            'FinalError' {
                $errorText = Get-AppxLocalizedResultError -ErrorText ([string]$progressItem.Text)
                Add-AppxLogLine (TF 'AdvancedLogError' @('{0}: {1}' -f $display,$errorText)) -Level Error
            }
            'Verified' {
                $statusText = Get-AppxLocalizedResultStatus -Status ([string]$progressItem.Text)
                $verifyLevel = if ([string]$progressItem.Text -eq 'Removed') { 'Success' } elseif ([string]$progressItem.Text -in @('Partial','Blocked','NotFound')) { 'Error' } else { 'Auto' }
                Add-AppxLogLine ('[VERIFY] {0} -> {1}' -f $display,$statusText) -Level $verifyLevel
            }
        }
    }.GetNewClosure()

    $worker = {
        param($root,$dataRoot,$packageName,$displayName,$protectedNames,$isStartSuggestion,$startPinId,$progressQueue)
        . (Join-Path $root 'Modules\Debloat.ps1')
        if ([bool]$isStartSuggestion) {
            $target = [pscustomobject]@{ PackageName=[string]$packageName; DisplayName=[string]$displayName; StartPinId=[string]$startPinId; ReportResult=$true }
            $suggestionResults = @(Remove-WnstStartMenuSuggestions -Suggestions @($target) -DataRoot $dataRoot -ProgressQueue $progressQueue)
            Invoke-WnstStartMenuPostDebloatCleanup -ProgressQueue $progressQueue
            @($suggestionResults | Where-Object { $null -eq $_.PSObject.Properties['ReportResult'] -or [bool]$_.ReportResult })
        }
        else {
            $packageResults = @(Remove-WnstAppxPackages -PackageNames @($packageName) -AllowedProtectedPackageNames @($protectedNames) -ProgressQueue $progressQueue)
            $clearedCurrentUser = @($packageResults | Where-Object {
                [int]$_.InstalledRemoved -gt 0 -and ($null -eq $_.PSObject.Properties['RemainingInstalled'] -or [int]$_.RemainingInstalled -eq 0)
            } | ForEach-Object { [string]$_.PackageName })
            if ($clearedCurrentUser.Count -gt 0) {
                $pinTargets = @(Get-WnstStartPinTargetsForPackageNames -PackageNames $clearedCurrentUser)
                if ($pinTargets.Count -gt 0) {
                    $pinResults = @(Remove-WnstStartMenuSuggestions -Suggestions $pinTargets -DataRoot $dataRoot -ProgressQueue $progressQueue)
                    if (@($pinResults | Where-Object { [bool]$_.RestartRequired }).Count -gt 0) {
                        foreach ($packageResult in $packageResults) {
                            Add-Member -InputObject $packageResult -NotePropertyName RestartRequired -NotePropertyValue $true -Force
                        }
                    }
                }
                Invoke-WnstStartMenuPostDebloatCleanup -ProgressQueue $progressQueue
            }
            @($packageResults)
        }
    }

    $completed = {
        param($output)

        $results = @($output)
        Add-AppxRemovalResultLog -Results $results
        $summaryData = Get-AppxRemovalSummaryData -Results $results
        $summary = [string]$summaryData.Text
        Add-AppxLogLine $summary
        $AppxStatusText.Text = $summary

        $state.InventoryLoading = $false
        $state.InventoryLoaded = $false
        $state.AllItems = @()
        if ([int]$summaryData.PendingRestart -gt 0) { Invoke-AppxRecommendedRestart }
        else { Show-AppInfo $summary }
        Request-AppxInventory -Force
    }.GetNewClosure()

    $failed = {
        param($message)
        $state.InventoryLoading = $false
        $text = if ($message -eq 'AdministratorRequired') { T 'AdministratorRequired' } else { [string]$message }
        $AppxStatusText.Text = $text
        Add-AppxLogLine (TF 'AdvancedLogError' @($text)) -Level Error
        Set-AppxControlsEnabled -Enabled $true
        Show-AppError $text
    }.GetNewClosure()

    if (-not (Invoke-HuAsyncWork -Key 'AppxStandaloneRemove' -ScriptBlock $worker -ArgumentList @($script:AppRoot,[string]$script:Paths.DataRoot,[string]$Item.PackageName,$displayName,$allowedProtected,[bool]$isStartSuggestion,[string]$Item.StartPinId,$progressQueue) -OnCompleted $completed -OnError $failed -OnProgress $progress -ProgressQueue $progressQueue -TimeoutSeconds 180 -Replace)) {
        $state.InventoryLoading = $false
        Set-AppxControlsEnabled -Enabled $true
        $AppxStatusText.Text = T 'CommandStartFailed'
        Add-AppxLogLine (T 'CommandStartFailed') -Level Error
    }
}

$AppxStandaloneRemoveMenuItem.Add_Click({
    $selectedRows = @($AppxGrid.SelectedItems)
    if ($selectedRows.Count -gt 1) {
        Invoke-AppxSelectedRowsRemoval -SelectedRows $selectedRows
        return
    }

    $item = $AppxGrid.CurrentItem
    if ($item) { Invoke-AppxStandaloneRemoval -Item $item }
})

function Invoke-AppxBulkRemoval {
    param(
        [Parameter(Mandatory=$true)][AllowEmptyCollection()][object[]]$Selected,
        [AllowEmptyCollection()][string[]]$AdditionalAllowedProtectedPackageNames = @()
    )

    $selected = @($Selected)
    if ($selected.Count -eq 0) { Show-AppError (T 'AppxNoSelection'); return }

    $removeData = [bool]$AppxRemoveUserDataCheck.IsChecked
    $appxSelected = @($selected | Where-Object { -not [bool]$_.IsStartSuggestion })
    $suggestionSelected = @($selected | Where-Object { [bool]$_.IsStartSuggestion })

    if ($appxSelected.Count -eq 0 -and $suggestionSelected.Count -gt 0) {
        $confirmKey = 'AppxConfirmRemoveSuggestions'
        $confirmArgs = @($suggestionSelected.Count)
    }
    elseif ($suggestionSelected.Count -gt 0) {
        $confirmKey = if ($removeData) { 'AppxConfirmRemoveMixedWithData' } else { 'AppxConfirmRemoveMixed' }
        $confirmArgs = @($appxSelected.Count,$suggestionSelected.Count)
    }
    else {
        $confirmKey = if ($removeData) { 'AppxConfirmRemoveWithData' } else { 'AppxConfirmRemove' }
        $confirmArgs = @($selected.Count)
    }
    if (-not (Show-AppConfirm (TF $confirmKey $confirmArgs))) { return }

    $names = @($appxSelected | ForEach-Object { [string]$_.PackageName })
    $explicitAllowed = @($AdditionalAllowedProtectedPackageNames)
    $allowedProtectedNames = @($appxSelected | Where-Object {
        [string]$_.Indicator -eq 'Red' -and ([bool]$_.ProtectedApproved -or [string]$_.PackageName -in $explicitAllowed)
    } | ForEach-Object { [string]$_.PackageName })
    $suggestionPayload = [pscustomobject]@{
        PackageNames = @($suggestionSelected | ForEach-Object { [string]$_.PackageName })
        DisplayNames = @($suggestionSelected | ForEach-Object { [string]$_.DisplayName })
        StartPinIds = @($suggestionSelected | ForEach-Object { [string]$_.StartPinId })
    }
    $AppxStatusText.Text = T 'AppxStatusRemoving'
    Add-AppxLogLine ((T 'AppxStatusRemoving') + (' [{0}]' -f $selected.Count))
    $script:AppxState.InventoryLoading = $true
    Set-AppxControlsEnabled -Enabled $false

    $state = $script:AppxState
    $progressQueue = [System.Collections.Concurrent.ConcurrentQueue[object]]::new()
    $progress = {
        param($progressItem)
        if (-not $progressItem) { return }

        $display = if ([string]::IsNullOrWhiteSpace([string]$progressItem.DisplayName)) {
            [string]$progressItem.PackageName
        } else {
            [string]$progressItem.DisplayName
        }

        switch ([string]$progressItem.Kind) {
            'PackageStart'     { Add-AppxLogLine ('[APPX] {0}' -f $display) }
            'SuggestionStart'  { Add-AppxLogLine ('[START] {0}' -f $display) }
            'SuggestionAction' { Add-AppxLogLine ('[START] {0}' -f (Get-AppxLocalizedSuggestionAction -Action ([string]$progressItem.Text))) }
            'Command'          { Add-AppxLogLine ('[CMD] {0}' -f [string]$progressItem.Text) }
            'Ok'               { Add-AppxLogLine ('[OK] {0}' -f [string]$progressItem.Text) -Level Success }
            'DeferredWarning'  { }
            'FinalError' {
                $errorText = Get-AppxLocalizedResultError -ErrorText ([string]$progressItem.Text)
                Add-AppxLogLine (TF 'AdvancedLogError' @('{0}: {1}' -f $display,$errorText)) -Level Error
            }
            'Verified' {
                $statusText = Get-AppxLocalizedResultStatus -Status ([string]$progressItem.Text)
                $verifyLevel = if ([string]$progressItem.Text -eq 'Removed') { 'Success' } elseif ([string]$progressItem.Text -in @('Partial','Blocked','NotFound')) { 'Error' } else { 'Auto' }
                Add-AppxLogLine ('[VERIFY] {0} -> {1}' -f $display,$statusText) -Level $verifyLevel
            }
        }
    }.GetNewClosure()

    $worker = {
        param($root,$dataRoot,$packageNames,$protectedNames,$removeUserData,$suggestionPayload,$progressQueue)
        . (Join-Path $root 'Modules\Debloat.ps1')

        $allResults = [Collections.Generic.List[object]]::new()
        $packageResults = @()
        if (@($packageNames).Count -gt 0) {
            $packageResults = @(Remove-WnstAppxPackages -PackageNames @($packageNames) -AllowedProtectedPackageNames @($protectedNames) -RemoveUserData:([bool]$removeUserData) -ProgressQueue $progressQueue)
            foreach ($result in $packageResults) { $allResults.Add($result) }
        }

        # Retirer également les épingles des applications qui viennent réellement de
        # disparaître pour l'utilisateur courant. Cela évite qu'une ancienne épingle
        # devienne un raccourci de téléchargement ou un résidu ms-resource après retrait.
        $startTargetsById = @{}
        $clearedCurrentUser = @($packageResults | Where-Object {
            [int]$_.InstalledRemoved -gt 0 -and ($null -eq $_.PSObject.Properties['RemainingInstalled'] -or [int]$_.RemainingInstalled -eq 0)
        } | ForEach-Object { [string]$_.PackageName })
        foreach ($target in @(Get-WnstStartPinTargetsForPackageNames -PackageNames $clearedCurrentUser)) {
            if ($target.StartPinId) { $startTargetsById[[string]$target.StartPinId] = $target }
        }

        if ($suggestionPayload -and @($suggestionPayload.StartPinIds).Count -gt 0) {
            for ($index = 0; $index -lt @($suggestionPayload.StartPinIds).Count; $index++) {
                $target = [pscustomobject]@{
                    PackageName = [string]$suggestionPayload.PackageNames[$index]
                    DisplayName = [string]$suggestionPayload.DisplayNames[$index]
                    StartPinId = [string]$suggestionPayload.StartPinIds[$index]
                    ReportResult = $true
                }
                if ($target.StartPinId) { $startTargetsById[[string]$target.StartPinId] = $target }
            }
        }

        if ($startTargetsById.Count -gt 0) {
            $startResults = @(Remove-WnstStartMenuSuggestions -Suggestions @($startTargetsById.Values) -DataRoot $dataRoot -ProgressQueue $progressQueue)
            $restartPackages = @{}
            foreach ($result in @($startResults | Where-Object { [bool]$_.RestartRequired })) {
                $restartPackages[[string]$result.PackageName] = $true
            }
            foreach ($packageResult in $packageResults) {
                if ($restartPackages.ContainsKey([string]$packageResult.PackageName)) {
                    Add-Member -InputObject $packageResult -NotePropertyName RestartRequired -NotePropertyValue $true -Force
                }
            }
            foreach ($result in $startResults) {
                if ($null -eq $result.PSObject.Properties['ReportResult'] -or [bool]$result.ReportResult) { $allResults.Add($result) }
            }
        }

        if ($clearedCurrentUser.Count -gt 0 -or $startTargetsById.Count -gt 0) {
            Invoke-WnstStartMenuPostDebloatCleanup -ProgressQueue $progressQueue
        }

        @($allResults)
    }
    $completed = {
        param($output)
        $results = @($output)
        $summaryData = Get-AppxRemovalSummaryData -Results $results
        $summary = [string]$summaryData.Text
        Add-AppxRemovalResultLog -Results $results
        Add-AppxLogLine $summary
        $AppxStatusText.Text = $summary
        $state.InventoryLoading = $false
        $state.InventoryLoaded = $false
        $state.AllItems = @()
        if ([int]$summaryData.PendingRestart -gt 0) { Invoke-AppxRecommendedRestart }
        else { Show-AppInfo $summary }
        Request-AppxInventory -Force
    }.GetNewClosure()
    $failed = {
        param($message)
        $state.InventoryLoading = $false
        $text = if ($message -eq 'AdministratorRequired') { T 'AdministratorRequired' } else { $message }
        $AppxStatusText.Text = $text
        Add-AppxLogLine (TF 'AdvancedLogError' @($text)) -Level Error
        Set-AppxControlsEnabled -Enabled $true
        Show-AppError $text
    }.GetNewClosure()

    if (-not (Invoke-HuAsyncWork -Key 'AppxRemove' -ScriptBlock $worker -ArgumentList @($script:AppRoot,[string]$script:Paths.DataRoot,$names,$allowedProtectedNames,$removeData,$suggestionPayload,$progressQueue) -OnCompleted $completed -OnError $failed -OnProgress $progress -ProgressQueue $progressQueue -TimeoutSeconds 180 -Replace)) {
        $state.InventoryLoading = $false
        Set-AppxControlsEnabled -Enabled $true
        $AppxStatusText.Text = T 'CommandStartFailed'
        Add-AppxLogLine (T 'CommandStartFailed') -Level Error
    }

}

$AppxRemoveButton.Add_Click({
    $selected = @($script:AppxState.AllItems | Where-Object { Test-AppxItemSelected $_ })
    Invoke-AppxBulkRemoval -Selected $selected
})

function Invoke-AppxSelectedRowsRemoval {
    param([Parameter(Mandatory=$true)][AllowEmptyCollection()][object[]]$SelectedRows)

    $selectedRows = @($SelectedRows)
    if ($selectedRows.Count -eq 0) { Show-AppError (T 'AppxNoSelection'); return }

    $protectedRows = @($selectedRows | Where-Object { [string]$_.Indicator -eq 'Red' })
    $pendingProtectedRows = @($protectedRows | Where-Object { -not [bool]$_.ProtectedApproved })
    if ($pendingProtectedRows.Count -gt 0) {
        if (-not (Show-AppConfirm (TF 'AppxProtectedBulkSelectionWarning' @($pendingProtectedRows.Count)))) { return }
    }

    $allowedProtectedNames = @($protectedRows | Where-Object { -not [bool]$_.IsStartSuggestion } | ForEach-Object { [string]$_.PackageName })
    Invoke-AppxBulkRemoval -Selected $selectedRows -AdditionalAllowedProtectedPackageNames $allowedProtectedNames
}

$AppxLogCustomScrollTrack.Add_SizeChanged({ Update-AppxLogCustomScrollbar })
$AppxLogCustomScrollThumb.Add_DragStarted({
    $viewer = Get-AppxLogScrollViewer
    if ($viewer -isnot [Windows.Controls.ScrollViewer]) { return }
    $script:AppxLogThumbDragStartOffset = [double]$viewer.VerticalOffset
    $script:AppxLogThumbDragDelta = 0.0
})
$AppxLogCustomScrollThumb.Add_DragDelta({
    if ($AppxLogCustomScrollTrack.Visibility -ne 'Visible') { return }
    $viewer = Get-AppxLogScrollViewer
    if ($viewer -isnot [Windows.Controls.ScrollViewer]) { return }

    $trackHeight = [double]$AppxLogCustomScrollTrack.ActualHeight
    $thumbHeight = [double]$AppxLogCustomScrollThumb.ActualHeight
    $travel = [Math]::Max(0.0,$trackHeight - $thumbHeight)
    $scrollable = [double]$viewer.ScrollableHeight
    if ($travel -le 0 -or $scrollable -le 0) { return }

    $script:AppxLogThumbDragDelta += [double]$_.VerticalChange
    $target = $script:AppxLogThumbDragStartOffset + (($script:AppxLogThumbDragDelta / $travel) * $scrollable)
    $target = [Math]::Max(0.0,[Math]::Min($scrollable,$target))
    $viewer.ScrollToVerticalOffset($target)
})
$AppxLogCustomScrollThumb.Add_DragCompleted({ $script:AppxLogThumbDragDelta = 0.0 })
$AppxLogCustomScrollTrack.Add_MouseLeftButtonDown({
    if ($AppxLogCustomScrollTrack.Visibility -ne 'Visible' -or $_.OriginalSource -ne $AppxLogCustomScrollTrack) { return }
    $viewer = Get-AppxLogScrollViewer
    if ($viewer -isnot [Windows.Controls.ScrollViewer]) { return }

    $y = [double]$_.GetPosition($AppxLogCustomScrollTrack).Y
    $top = [Windows.Controls.Canvas]::GetTop($AppxLogCustomScrollThumb)
    if ([double]::IsNaN($top)) { $top = 0.0 }
    $bottom = $top + [double]$AppxLogCustomScrollThumb.ActualHeight

    if ($y -lt $top) {
        $viewer.ScrollToVerticalOffset([Math]::Max(0.0,[double]$viewer.VerticalOffset - [double]$viewer.ViewportHeight))
    }
    elseif ($y -gt $bottom) {
        $viewer.ScrollToVerticalOffset([Math]::Min([double]$viewer.ScrollableHeight,[double]$viewer.VerticalOffset + [double]$viewer.ViewportHeight))
    }
    $_.Handled = $true
})

$AppxClearLogButton.Add_Click({
    if ($AppxLogBox) {
        Clear-WnstLogContent -Control $AppxLogBox
        Update-AppxLogCustomScrollbar
    }
})
