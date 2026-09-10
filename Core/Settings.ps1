function Save-CurrentSettings {
    $script:Settings.SourceUrl = $SourceUrlBox.Text.Trim()
    $script:Settings.DailyEnabled = [bool]$DailyUpdateCheck.IsChecked
    $script:Settings.UpdateTime = [string]$UpdateTimeCombo.SelectedItem
    $script:Settings.UpdateMode = if ($ReplaceModeRadio.IsChecked) { 'Replace' } else { 'Merge' }
    $script:Settings.BackupBeforeChange = [bool]$AutomaticBackupCheck.IsChecked
    $script:Settings.SidebarCollapsed = [bool]$script:Settings.SidebarCollapsed
    $script:Settings.TitlebarAnimation = [bool]$TitlebarAnimationToggle.IsChecked
    $script:Settings.FlushDns = [bool]$FlushDnsCheck.IsChecked
    if ($LanguageCombo.SelectedItem) { $script:Settings.Language = [string]$LanguageCombo.SelectedItem.Code }
    if ($ThemeCombo.SelectedItem) { $script:Settings.Theme = [string]$ThemeCombo.SelectedItem.Code }
    if ($AccentColorBox.Text -match '^#[0-9A-Fa-f]{6}$') { $script:Settings.AccentColor = $AccentColorBox.Text.ToUpperInvariant() }
    $script:Settings = Save-AppSettingsObject -Settings $script:Settings
}

function Switch-WNSTDataRoot {
    param([Parameter(Mandatory = $true)][string]$TargetRoot)

    if ($script:DataRootArgument) { throw (T 'DataFolderLocked') }
    Save-CurrentSettings
    $currentRoot = [IO.Path]::GetFullPath($script:Paths.DataRoot).TrimEnd('\')
    $newRoot = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($TargetRoot)).TrimEnd('\')
    if ($newRoot -eq $currentRoot) { return $false }
    $separator = [string][IO.Path]::DirectorySeparatorChar
    if (($newRoot + $separator).StartsWith($currentRoot + $separator, [StringComparison]::OrdinalIgnoreCase) -or ($currentRoot + $separator).StartsWith($newRoot + $separator, [StringComparison]::OrdinalIgnoreCase)) {
        throw (T 'DataFolderOverlap')
    }
    if (Test-Path -LiteralPath $newRoot -PathType Leaf) { throw (TF 'DataFolderFile' @($newRoot)) }
    New-Item -ItemType Directory -Path $newRoot -Force -ErrorAction Stop | Out-Null
    $movedNames = @()
    try {
        $movedNames = @(Move-HuDataRootContent -SourceRoot $currentRoot -DestinationRoot $newRoot)
        [void](Set-HuConfiguredDataRoot -DataRoot $newRoot)
    }
    catch {
        if ($movedNames.Count -gt 0) {
            try { [void](Move-HuDataRootContent -SourceRoot $newRoot -DestinationRoot $currentRoot) } catch { }
        }
        throw
    }
    $script:Paths = Get-HuPaths -DataRoot $newRoot
    $script:Settings = Get-HuSettings -DataRoot $newRoot
    $DataFolderValue.Text = $script:Paths.DataRoot
    $ResetDataFolderButton.IsEnabled = ([IO.Path]::GetFullPath($script:Paths.DataRoot).TrimEnd('\') -ne [IO.Path]::GetFullPath((Get-HuStandardDataRoot)).TrimEnd('\'))
    Refresh-BackupHistory
    Update-StatusPanel
    return $true
}

function Sync-ScheduledTask {
    if ($script:Initializing) { return }
    Save-CurrentSettings
    if ($DailyUpdateCheck.IsChecked) {
        if (-not (Test-HuSourceAddress -SourceUrl $SourceUrlBox.Text)) {
            $DailyUpdateCheck.IsChecked = $false
            Save-CurrentSettings
            Show-AppError (T 'UrlRequired')
            return
        }
        Install-HuScheduledTask -UpdateScriptPath (Join-Path $script:AppRoot 'Invoke-WNSTUpdate.ps1') -At ([string]$UpdateTimeCombo.SelectedItem) | Out-Null
    }
    else {
        Remove-HuScheduledTask -Confirm:$false | Out-Null
    }
    Update-StatusPanel
}
