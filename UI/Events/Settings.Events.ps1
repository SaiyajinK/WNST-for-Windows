$DailyUpdateCheck.Add_Click({ try { Sync-ScheduledTask } catch { $DailyUpdateCheck.IsChecked = -not $DailyUpdateCheck.IsChecked; try { Save-CurrentSettings } catch { }; Show-AppError $_.Exception.Message } })
$UpdateTimeCombo.Add_SelectionChanged({ if (-not $script:Initializing -and $DailyUpdateCheck.IsChecked) { try { Sync-ScheduledTask } catch { Show-AppError $_.Exception.Message } } elseif (-not $script:Initializing) { Save-CurrentSettings } })
$MergeModeRadio.Add_Checked({ if (-not $script:Initializing) { try { Save-CurrentSettings } catch { Show-AppError $_.Exception.Message } } })
$ReplaceModeRadio.Add_Checked({ if (-not $script:Initializing) { try { Save-CurrentSettings } catch { Show-AppError $_.Exception.Message } } })
$AutomaticBackupCheck.Add_Click({ if (-not $script:Initializing) { try { Save-CurrentSettings } catch { Show-AppError $_.Exception.Message } } })
$FlushDnsCheck.Add_Click({ if (-not $script:Initializing) { try { Save-CurrentSettings } catch { Show-AppError $_.Exception.Message } } })

$LanguageCombo.Add_SelectionChanged({
    if ($script:Initializing -or -not $LanguageCombo.SelectedItem) { return }
    try {
        $script:Settings.Language = [string]$LanguageCombo.SelectedItem.Code
        $script:Settings = Save-AppSettingsObject -Settings $script:Settings
        [void](Import-AppLanguage -Code ([string]$script:Settings.Language))
        [void](Set-HuModuleLanguage -Code ([string]$script:Settings.Language))
        Apply-Language
    }
    catch { Show-AppError $_.Exception.Message }
})

$ThemeCombo.Add_SelectionChanged({
    if ($script:Initializing -or $script:UpdatingThemeOptions -or -not $ThemeCombo.SelectedItem) { return }
    try {
        $script:Settings.Theme = [string]$ThemeCombo.SelectedItem.Code
        $script:Settings = Save-AppSettingsObject -Settings $script:Settings
        Apply-AppTheme
        Update-AppThemeActionButtons
    }
    catch { Show-AppError $_.Exception.Message }
})

$CreateThemeButton.Add_Click({
    try { Show-AppThemeCreator }
    catch { Show-AppError $_.Exception.Message }
})

$ModifyThemeButton.Add_Click({
    if (-not $ThemeCombo.SelectedItem) { return }
    $code = [string]$ThemeCombo.SelectedItem.Code
    if (-not $code.StartsWith('User:',[StringComparison]::OrdinalIgnoreCase)) { return }
    try { Show-AppThemeEditor -ThemeCode $code }
    catch { Show-AppError $_.Exception.Message }
})

$DeleteThemeButton.Add_Click({
    if (-not $ThemeCombo.SelectedItem) { return }
    $code = [string]$ThemeCombo.SelectedItem.Code
    if (-not $code.StartsWith('User:',[StringComparison]::OrdinalIgnoreCase)) { return }
    $name = [string]$ThemeCombo.SelectedItem.Name
    if (-not (Show-AppConfirm (TF 'ThemeDeleteConfirm' @($name)))) { return }
    try {
        if (Remove-AppUserTheme -Code $code) {
            $script:Settings.Theme = 'System'
            $script:Settings = Save-AppSettingsObject -Settings $script:Settings
            Refresh-ThemeOptions
            Apply-AppTheme
            Show-AppInfo (T 'ThemeDeleted')
        }
    }
    catch { Show-AppError $_.Exception.Message }
})

$CornerCombo.Add_SelectionChanged({
    if ($script:Initializing -or $script:UpdatingCornerOptions -or -not $CornerCombo.SelectedItem) { return }
    try {
        $script:Settings.CornerRadius = [int]$CornerCombo.SelectedItem.Code
        $script:Settings = Save-AppSettingsObject -Settings $script:Settings
        Apply-AppCornerRadius
    }
    catch {
        Refresh-CornerOptions
        Show-AppError $_.Exception.Message
    }
})

$ApplyUiScaleButton.Add_Click({
    if (-not $UiScaleCombo.SelectedItem) { return }
    try {
        $script:Settings.UiScalePercent = [int]$UiScaleCombo.SelectedItem.Code
        $script:Settings = Save-AppSettingsObject -Settings $script:Settings
        Apply-AppUiScale -Percent ([int]$script:Settings.UiScalePercent)
        $StatusBarText.Text = T 'UiScaleApplied'
        $StatusBarText.Visibility = 'Visible'
    }
    catch {
        Refresh-UiScaleOptions
        Show-AppError $_.Exception.Message
    }
})

$TitlebarAnimationToggle.Add_Click({
    if ($script:Initializing) { return }
    try {
        $script:Settings.TitlebarAnimation = [bool]$TitlebarAnimationToggle.IsChecked
        $script:Settings = Save-AppSettingsObject -Settings $script:Settings
        Set-TitleTypewriterEnabled -Enabled ([bool]$script:Settings.TitlebarAnimation)
    }
    catch {
        $TitlebarAnimationToggle.IsChecked = [bool]$script:Settings.TitlebarAnimation
        Show-AppError $_.Exception.Message
    }
})

$ChooseAccentButton.Add_Click({
    try {
        $selectedColor = Show-AccentPicker -InitialColor ([string]$script:Settings.AccentColor)
        if ($selectedColor) { Set-SavedAccent -Value $selectedColor }
    }
    catch { Show-AppError $_.Exception.Message }
})
$ResetAccentButton.Add_Click({ try { Set-SavedAccent -Value '#1A9FFF' } catch { Show-AppError $_.Exception.Message } })
$AccentColorBox.Add_KeyDown({
    if ($_.Key -eq [Windows.Input.Key]::Enter) {
        try { Set-SavedAccent -Value $AccentColorBox.Text; [Windows.Input.Keyboard]::ClearFocus() | Out-Null }
        catch { $AccentColorBox.Text=[string]$script:Settings.AccentColor; Show-AppError $_.Exception.Message }
    }
})
$AccentColorBox.Add_LostKeyboardFocus({
    $normalized = ConvertTo-AccentHex $AccentColorBox.Text
    if ($normalized) {
        if ($normalized -ne [string]$script:Settings.AccentColor) { try { Set-SavedAccent -Value $normalized } catch { Show-AppError $_.Exception.Message } }
        else { $AccentColorBox.Text = $normalized }
    }
    else { $AccentColorBox.Text = [string]$script:Settings.AccentColor }
})
