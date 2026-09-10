$script:ThemePaletteKeys = @(
    'WindowBrush','WindowBorderBrush','SidebarBrush','TitleBarBrush','StatusBarBrush',
    'CardBrush','ClickableCardHoverBrush','AboutCardHoverBrush','CardBorderBrush','ProgressTrackBrush','InputBrush','ComboBrush','ComboHoverBrush','TextBrush','MutedBrush',
    'SubtleTextBrush','ControlBrush','ControlHoverBrush','ControlBorderBrush','NavTextBrush','NavHoverBrush','NavSelectedBrush','SidebarToggleHoverBrush','TitleButtonHoverBrush',
    'GridBrush','GridAlternateBrush','SeparatorBrush','ScrollThumbBrush','ScrollThumbHoverBrush','CardTextBrush','CardTitleBrush'
)

$script:ThemeEditorWindow = $null
$script:ThemeEditorState = $null
$script:ThemeRootCaseChecked = $false
$script:ThemeUtf8NoBom = [System.Text.UTF8Encoding]::new($false)
$script:ThemeEditorGroupTargets = @{
    BorderGroup = @('WindowBorderBrush','CardBorderBrush','ControlBorderBrush','SeparatorBrush')
    CardHoverGroup = @('ClickableCardHoverBrush','AboutCardHoverBrush')
    GridBackgroundGroup = @('GridBrush','GridAlternateBrush')
}

function Get-AppUserThemeRoot {
    $dataRoot = Get-HuStandardDataRoot
    $root = Join-Path $dataRoot 'Themes'

    if (-not (Test-Path -LiteralPath $root -PathType Container)) {
        New-Item -ItemType Directory -Path $root -Force -ErrorAction Stop | Out-Null
    }

    # Windows ignore la casse des chemins : on corrige une seule fois le nom physique
    # d'un éventuel dossier "themes" créé par une version antérieure.
    if (-not $script:ThemeRootCaseChecked) {
        try {
            $rootItem = Get-Item -LiteralPath $root -Force -ErrorAction Stop
            if ($rootItem.Name -cne 'Themes') {
                $temporaryName = ('Themes.__casefix__.{0}' -f [Guid]::NewGuid().ToString('N'))
                Rename-Item -LiteralPath $rootItem.FullName -NewName $temporaryName -ErrorAction Stop
                Rename-Item -LiteralPath (Join-Path $dataRoot $temporaryName) -NewName 'Themes' -ErrorAction Stop
            }
            $script:ThemeRootCaseChecked = $true
        }
        catch { }
    }

    return $root
}

function Get-AppThemeDraftPath {
    param([switch]$EnsureParent)
    $root = Join-Path (Get-AppUserThemeRoot) '_draft'
    if ($EnsureParent -and -not (Test-Path -LiteralPath $root -PathType Container)) {
        New-Item -ItemType Directory -Path $root -Force -ErrorAction Stop | Out-Null
    }
    return Join-Path $root 'theme_draft.json'
}

function Get-AppThemeColor {
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [string]$Fallback = '#20242B'
    )
    try {
        if ($script:CurrentThemePalette -and $script:CurrentThemePalette.Contains($Name)) {
            $value = [string]$script:CurrentThemePalette[$Name]
            if ($value -match '^#[0-9A-Fa-f]{6}$') { return $value.ToUpperInvariant() }
        }
    }
    catch { }
    return $Fallback
}

function Get-AppEmergencyPalette {
    param([ValidateSet('Dark','Light')][string]$Mode = 'Dark')
    if ($Mode -eq 'Light') {
        return [ordered]@{
            WindowBrush='#F4F5F7'; WindowBorderBrush='#9DA5AF'; SidebarBrush='#ECEEF1'; TitleBarBrush='#E7E9ED'; StatusBarBrush='#ECEEF1';
            CardBrush='#FFFFFF'; ClickableCardHoverBrush='#F6F7F8'; AboutCardHoverBrush='#F3F4F6'; CardBorderBrush='#C8CDD4'; ProgressTrackBrush='#E7E9ED'; InputBrush='#FFFFFF'; ComboBrush='#FFFFFF'; ComboHoverBrush='#E2E5E9'; TextBrush='#17191D'; MutedBrush='#5F6670';
            SubtleTextBrush='#737A84'; ControlBrush='#F2F3F5'; ControlHoverBrush='#E2E5E9'; ControlBorderBrush='#B8BEC7';
            NavTextBrush='#2A2E34'; NavHoverBrush='#DFE3E8'; NavSelectedBrush='#D4D9E0'; SidebarToggleHoverBrush='#E2E5E9'; TitleButtonHoverBrush='#E2E5E9'; GridBrush='#FFFFFF';
            GridAlternateBrush='#F5F6F8'; SeparatorBrush='#D7DBE0'; ScrollThumbBrush='#9AA1AA'; ScrollThumbHoverBrush='#747C86';
            CardTextBrush='#17191D'; CardTitleBrush='#17191D'
        }
    }
    return [ordered]@{
        WindowBrush='#191C21'; WindowBorderBrush='#59616B'; SidebarBrush='#171A1F'; TitleBarBrush='#20242B'; StatusBarBrush='#171A1F';
        CardBrush='#252930'; ClickableCardHoverBrush='#30353D'; AboutCardHoverBrush='#2C3139'; CardBorderBrush='#3B414A'; ProgressTrackBrush='#20242B'; InputBrush='#20242B'; ComboBrush='#20242B'; ComboHoverBrush='#3A4049'; TextBrush='#F4F4F4'; MutedBrush='#A8ADB5';
        SubtleTextBrush='#7F8690'; ControlBrush='#30353D'; ControlHoverBrush='#3A4049'; ControlBorderBrush='#555C66';
        NavTextBrush='#DDE1E6'; NavHoverBrush='#292E35'; NavSelectedBrush='#31363E'; SidebarToggleHoverBrush='#3A4049'; TitleButtonHoverBrush='#3A4049'; GridBrush='#20242B';
        GridAlternateBrush='#23272E'; SeparatorBrush='#343941'; ScrollThumbBrush='#59616B'; ScrollThumbHoverBrush='#747D88';
        CardTextBrush='#F4F4F4'; CardTitleBrush='#F4F4F4'
    }
}

function Copy-AppThemePalette {
    param([Parameter(Mandatory=$true)][object]$Palette)
    $copy = [ordered]@{}
    foreach ($key in $script:ThemePaletteKeys) {
        $value = $null
        try {
            if ($Palette -is [System.Collections.IDictionary]) {
                if ($Palette.Contains($key)) { $value = [string]$Palette[$key] }
            }
            else {
                $property = $Palette.PSObject.Properties[$key]
                if ($property) { $value = [string]$property.Value }
            }
        }
        catch { }
        if ($value) { $copy[$key] = $value }
    }
    return $copy
}

function Get-AppThemeObjectColor {
    param([object]$Object,[string]$Name)
    if (-not $Object) { return $null }
    try {
        if ($Object -is [System.Collections.IDictionary]) {
            if ($Object.Contains($Name)) { return [string]$Object[$Name] }
        }
        else {
            $property = $Object.PSObject.Properties[$Name]
            if ($property) { return [string]$property.Value }
        }
    }
    catch { }
    return $null
}

function ConvertTo-AppThemePalette {
    param(
        [object]$Colors,
        [ValidateSet('Dark','Light')][string]$Base = 'Dark',
        [object]$SeedPalette = $null
    )
    $palette = if ($SeedPalette) { Copy-AppThemePalette -Palette $SeedPalette } else { Get-AppEmergencyPalette -Mode $Base }
    foreach ($key in $script:ThemePaletteKeys) {
        $raw = Get-AppThemeObjectColor -Object $Colors -Name $key
        if ($null -eq $raw) { continue }
        $value = ConvertTo-AccentHex $raw
        if ($value) { $palette[$key] = $value }
    }

    if (-not (Get-AppThemeObjectColor -Object $Colors -Name 'CardTextBrush')) {
        $palette['CardTextBrush'] = [string]$palette['TextBrush']
    }
    if (-not (Get-AppThemeObjectColor -Object $Colors -Name 'CardTitleBrush')) {
        $palette['CardTitleBrush'] = [string]$palette['TextBrush']
    }
    return $palette
}

function Read-AppThemeFile {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [string]$FallbackName = '',
        [object]$SeedPalette = $null
    )
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    try {
        $theme = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        $name = ([string]$theme.Name).Trim()
        if ([string]::IsNullOrWhiteSpace($name)) { $name = $FallbackName }
        if ([string]::IsNullOrWhiteSpace($name)) { $name = [IO.Path]::GetFileNameWithoutExtension($Path) }
        if (-not $theme.Colors) { return $null }
        $base = if ([string]$theme.Base -eq 'Light') { 'Light' } else { 'Dark' }
        $palette = ConvertTo-AppThemePalette -Colors $theme.Colors -Base $base -SeedPalette $SeedPalette
        return [pscustomobject]@{ Name=$name; Base=$base; Palette=$palette; Path=$Path }
    }
    catch { return $null }
}

function Get-AppPackagedThemeDefinition {
    param([ValidateSet('Dark','Light','Minimal')][string]$Code)
    $fileName = switch ($Code) {
        'Light' { 'light_system.json' }
        'Minimal' { 'minimal.json' }
        default { 'dark_system.json' }
    }
    $fallbackName = switch ($Code) {
        'Light' { 'Light' }
        'Minimal' { 'Minimal Dark' }
        default { 'Dark' }
    }
    $path = Join-Path (Join-Path $script:AppRoot 'Themes') $fileName
    $definition = Read-AppThemeFile -Path $path -FallbackName $fallbackName
    if ($definition) { return $definition }
    $mode = if ($Code -eq 'Light') { 'Light' } else { 'Dark' }
    return [pscustomobject]@{ Name=$fallbackName; Base=$mode; Palette=(Get-AppEmergencyPalette -Mode $mode); Path=$path }
}

function Get-AppNativeThemeDefinition {
    param([ValidateSet('System','Dark','Light','Minimal')][string]$Code)

    if ($Code -eq 'System') {
        $mode = Get-SystemThemeMode
        $packaged = Get-AppPackagedThemeDefinition -Code $mode
        return [pscustomobject]@{ Name='System'; Base=$mode; Palette=$packaged.Palette; Path=$packaged.Path }
    }

    $packaged = Get-AppPackagedThemeDefinition -Code $Code
    return [pscustomobject]@{ Name=$packaged.Name; Base=$packaged.Base; Palette=$packaged.Palette; Path=$packaged.Path }
}

function Get-AppUserThemeOptions {
    $items = [System.Collections.Generic.List[object]]::new()
    try {
        $root = Get-AppUserThemeRoot
        foreach ($file in @(Get-ChildItem -LiteralPath $root -Filter '*.json' -File -ErrorAction SilentlyContinue | Sort-Object Name)) {
            try {
                $theme = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
                if (-not $theme.Colors) { continue }
                $name = ([string]$theme.Name).Trim()
                if ([string]::IsNullOrWhiteSpace($name)) { $name = $file.BaseName }
                $items.Add([pscustomobject]@{ Code=('User:' + $file.BaseName); Name=$name })
            }
            catch { }
        }
    }
    catch { }
    return $items.ToArray()
}

function Resolve-AppThemeDefinition {
    param([AllowEmptyString()][string]$Code)
    $requested = if ([string]::IsNullOrWhiteSpace($Code)) { 'System' } else { $Code }

    if ($requested -in @('System','Dark','Light','Minimal')) {
        $definition = Get-AppNativeThemeDefinition -Code $requested
        return [pscustomobject]@{
            Code=$requested; Name=$definition.Name; Base=$definition.Base; Palette=$definition.Palette;
            Path=$definition.Path; IsUser=$false; Fallback=$false
        }
    }

    if ($requested.StartsWith('User:',[StringComparison]::OrdinalIgnoreCase)) {
        $id = $requested.Substring(5)
        if (-not [string]::IsNullOrWhiteSpace($id) -and $id -eq [IO.Path]::GetFileName($id) -and $id.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -lt 0) {
            $path = Join-Path (Get-AppUserThemeRoot) ($id + '.json')
            $definition = Read-AppThemeFile -Path $path -FallbackName $id
            if ($definition) {
                return [pscustomobject]@{
                    Code=('User:' + $id); Name=$definition.Name; Base=$definition.Base; Palette=$definition.Palette;
                    Path=$definition.Path; IsUser=$true; Fallback=$false
                }
            }
        }
    }

    $definition = Get-AppNativeThemeDefinition -Code 'System'
    return [pscustomobject]@{
        Code='System'; Name='System'; Base=$definition.Base; Palette=$definition.Palette;
        Path=$definition.Path; IsUser=$false; Fallback=$true
    }
}

function Set-AppThemePaletteResources {
    param([Parameter(Mandatory=$true)][object]$Palette)
    $script:CurrentThemePalette = Copy-AppThemePalette -Palette $Palette
    foreach ($entry in $script:CurrentThemePalette.GetEnumerator()) {
        Set-AppBrushColor -Name $entry.Key -Color ([string]$entry.Value)
    }

    $accent = ConvertTo-AccentHex ([string]$script:Settings.AccentColor)
    if (-not $accent) { $accent = '#1A9FFF' }
    Set-AppBrushColor -Name 'AccentBrush' -Color $accent
    Set-AppBrushColor -Name 'ScrollThumbHoverBrush' -Color $accent
    Set-AppBrushColor -Name 'AccentHalfBrush' -Color ('#80' + $accent.Substring(1))
    Set-AppBrushColor -Name 'AccentTextBrush' -Color (Get-AccentTextColor -Accent $accent)
    if ($AccentColorBox) { $AccentColorBox.Text = $accent }

    try { Update-SourceBanner } catch { }
    if ($UpdateResultPanel -and $UpdateResultPanel.Visibility -eq 'Visible' -and $UpdateResultPanel.Tag) {
        Set-UpdateCheckResult -State ([string]$UpdateResultPanel.Tag) -Message ([string]$UpdateResultText.Text) -ReleaseUrl ([string]$script:PendingReleaseUrl)
    }
}

function Apply-AppTheme {
    $definition = Resolve-AppThemeDefinition -Code ([string]$script:Settings.Theme)
    if ($definition.Fallback) { $script:Settings.Theme = 'System' }
    $script:ResolvedTheme = [string]$definition.Base
    Set-AppThemePaletteResources -Palette $definition.Palette
}

function Apply-AppThemePreview {
    param(
        [Parameter(Mandatory=$true)][object]$Palette,
        [ValidateSet('Dark','Light')][string]$Base = 'Dark'
    )
    $script:ResolvedTheme = $Base
    Set-AppThemePaletteResources -Palette $Palette
}

function Update-AppThemeActionButtons {
    $editorOpen = $null -ne $script:ThemeEditorWindow
    if ($CreateThemeButton) { $CreateThemeButton.IsEnabled = -not $editorOpen }
    if ($ThemeCombo) { $ThemeCombo.IsEnabled = -not $editorOpen }

    $selectedCode = ''
    if ($ThemeCombo -and $ThemeCombo.SelectedItem) { $selectedCode = [string]$ThemeCombo.SelectedItem.Code }
    if ($ModifyThemeButton) { $ModifyThemeButton.IsEnabled = (-not $editorOpen -and $selectedCode.StartsWith('User:',[StringComparison]::OrdinalIgnoreCase)) }
    if ($DeleteThemeButton) { $DeleteThemeButton.IsEnabled = (-not $editorOpen -and $selectedCode.StartsWith('User:',[StringComparison]::OrdinalIgnoreCase)) }
}

function Clear-AppThemeEditorSession {
    $script:ThemeEditorWindow = $null
    $script:ThemeEditorState = $null
    Update-AppThemeActionButtons
}

function Update-AppThemeEditorCornerRadius {
    if (-not $script:ThemeEditorWindow) { return }
    try {
        $value = [int](Get-AppCornerRadiusValue)
        $dialog = $script:ThemeEditorWindow
        $dialog.Resources['ThemeEditorCorner'] = [Windows.CornerRadius]::new([double]$value)
        $dialog.Resources['ThemeEditorTopCorner'] = [Windows.CornerRadius]::new([double]$value,[double]$value,0,0)
        $chrome = [Windows.Shell.WindowChrome]::GetWindowChrome($dialog)
        if ($chrome) { $chrome.CornerRadius = [Windows.CornerRadius]::new([double]$value) }
        if ($dialog.ActualWidth -gt 0 -and $dialog.ActualHeight -gt 0) {
            $dialog.Clip = [Windows.Media.RectangleGeometry]::new([Windows.Rect]::new(0,0,$dialog.ActualWidth,$dialog.ActualHeight),[double]$value,[double]$value)
        }
        if ($script:ThemeEditorState) { $script:ThemeEditorState.Corner = $value }
    }
    catch { }
}

function Refresh-ThemeOptions {
    if (-not $ThemeCombo) { return }
    $script:UpdatingThemeOptions = $true
    try {
        $selectedCode = [string]$script:Settings.Theme
        $items = [System.Collections.Generic.List[object]]::new()
        $items.Add([pscustomobject]@{ Code='System'; Name=(T 'ThemeSystem') })
        $items.Add([pscustomobject]@{ Code='Dark'; Name=(T 'ThemeDark') })
        $items.Add([pscustomobject]@{ Code='Light'; Name=(T 'ThemeLight') })
        $items.Add([pscustomobject]@{ Code='Minimal'; Name=(T 'ThemeMinimal') })
        foreach ($custom in @(Get-AppUserThemeOptions)) { $items.Add($custom) }
        $array = $items.ToArray()
        $ThemeCombo.ItemsSource = $array
        $ThemeCombo.SelectedItem = $array | Where-Object Code -eq $selectedCode | Select-Object -First 1
        if (-not $ThemeCombo.SelectedItem) {
            $script:Settings.Theme = 'System'
            $ThemeCombo.SelectedItem = $array[0]
        }
    }
    finally {
        $script:UpdatingThemeOptions = $false
        Update-AppThemeActionButtons
    }
}

function Write-AppThemeFile {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$Name,
        [ValidateSet('Dark','Light')][string]$Base = 'Dark',
        [Parameter(Mandatory=$true)][object]$Palette
    )
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force -ErrorAction Stop | Out-Null
    }
    $payload = [ordered]@{
        SchemaVersion = 2
        Name = $Name
        Base = $Base
        Colors = Copy-AppThemePalette -Palette $Palette
    }
    $temporaryPath = $Path + '.tmp.' + [Guid]::NewGuid().ToString('N')
    try {
        [IO.File]::WriteAllText($temporaryPath, ($payload | ConvertTo-Json -Depth 8), $script:ThemeUtf8NoBom)
        if (Test-Path -LiteralPath $Path -PathType Leaf) { [IO.File]::Replace($temporaryPath,$Path,$null) }
        else { [IO.File]::Move($temporaryPath,$Path) }
    }
    finally {
        if (Test-Path -LiteralPath $temporaryPath -PathType Leaf) { Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue }
    }
}

function New-AppUserThemeFromPalette {
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [ValidateSet('Dark','Light')][string]$Base = 'Dark',
        [Parameter(Mandatory=$true)][object]$Palette
    )
    $displayName = $Name.Trim()
    if ([string]::IsNullOrWhiteSpace($displayName)) { throw (T 'ThemeNameRequired') }

    $safeName = ($displayName -replace '[\\/:*?"<>|]', '-').Trim().Trim('.')
    if ([string]::IsNullOrWhiteSpace($safeName)) { $safeName = 'theme' }

    $root = Get-AppUserThemeRoot
    $baseFileName = $safeName
    $fileName = $baseFileName + '.json'
    $index = 2
    while (Test-Path -LiteralPath (Join-Path $root $fileName) -PathType Leaf) {
        $fileName = ('{0}-{1}.json' -f $baseFileName,$index)
        $index++
    }

    $path = Join-Path $root $fileName
    Write-AppThemeFile -Path $path -Name $displayName -Base $Base -Palette $Palette
    return ('User:' + [IO.Path]::GetFileNameWithoutExtension($fileName))
}

function Save-AppEditedTheme {
    param(
        [Parameter(Mandatory=$true)][string]$Code,
        [Parameter(Mandatory=$true)][string]$Name,
        [ValidateSet('Dark','Light')][string]$Base = 'Dark',
        [Parameter(Mandatory=$true)][object]$Palette
    )

    if (-not $Code.StartsWith('User:',[StringComparison]::OrdinalIgnoreCase)) { throw (T 'ThemeUserOnlyEditable') }
    $definition = Resolve-AppThemeDefinition -Code $Code
    if ($definition.Fallback -or -not $definition.IsUser) { throw (T 'ThemeUserOnlyEditable') }
    Write-AppThemeFile -Path ([string]$definition.Path) -Name $Name.Trim() -Base $Base -Palette $Palette
    return $Code
}

function Remove-AppUserTheme {
    param([Parameter(Mandatory=$true)][string]$Code)
    if (-not $Code.StartsWith('User:',[StringComparison]::OrdinalIgnoreCase)) { return $false }
    $definition = Resolve-AppThemeDefinition -Code $Code
    if ($definition.Fallback -or -not $definition.IsUser) { return $false }
    if (Test-Path -LiteralPath ([string]$definition.Path) -PathType Leaf) {
        Remove-Item -LiteralPath ([string]$definition.Path) -Force -ErrorAction Stop
        return $true
    }
    return $false
}

function Get-AppThemeEditorFieldDefinitions {
    param([Parameter(Mandatory=$true)][object]$Palette)
    return @(
        [pscustomobject]@{ Key='WindowBrush'; Label=(T 'ThemeColorWindow'); Default=[string]$Palette['WindowBrush'] },
        [pscustomobject]@{ Key='TitleBarBrush'; Label=(T 'ThemeColorTopbar'); Default=[string]$Palette['TitleBarBrush'] },
        [pscustomobject]@{ Key='SidebarBrush'; Label=(T 'ThemeColorSidebar'); Default=[string]$Palette['SidebarBrush'] },
        [pscustomobject]@{ Key='NavHoverBrush'; Label=(T 'ThemeColorSidebarHover'); Default=[string]$Palette['NavHoverBrush'] },
        [pscustomobject]@{ Key='NavSelectedBrush'; Label=(T 'ThemeColorSidebarSelected'); Default=[string]$Palette['NavSelectedBrush'] },
        [pscustomobject]@{ Key='SidebarToggleHoverBrush'; Label=(T 'ThemeColorSidebarToggleHover'); Default=[string]$Palette['SidebarToggleHoverBrush'] },
        [pscustomobject]@{ Key='TitleButtonHoverBrush'; Label=(T 'ThemeColorWindowButtonsHover'); Default=[string]$Palette['TitleButtonHoverBrush'] },
        [pscustomobject]@{ Key='CardBrush'; Label=(T 'ThemeColorCard'); Default=[string]$Palette['CardBrush'] },
        [pscustomobject]@{ Key='CardHoverGroup'; Label=(T 'ThemeColorCardHover'); Default=[string]$Palette['ClickableCardHoverBrush'] },
        [pscustomobject]@{ Key='GridBackgroundGroup'; Label=(T 'ThemeColorTable'); Default=[string]$Palette['GridBrush'] },
        [pscustomobject]@{ Key='CardTextBrush'; Label=(T 'ThemeColorText'); Default=[string]$Palette['CardTextBrush'] },
        [pscustomobject]@{ Key='CardTitleBrush'; Label=(T 'ThemeColorTitle'); Default=[string]$Palette['CardTitleBrush'] },
        [pscustomobject]@{ Key='BorderGroup'; Label=(T 'ThemeColorBorder'); Default=[string]$Palette['CardBorderBrush'] },
        [pscustomobject]@{ Key='ProgressTrackBrush'; Label=(T 'ThemeColorProgressTrack'); Default=[string]$Palette['ProgressTrackBrush'] },
        [pscustomobject]@{ Key='InputBrush'; Label=(T 'ThemeColorInput'); Default=[string]$Palette['InputBrush'] },
        [pscustomobject]@{ Key='ComboBrush'; Label=(T 'ThemeColorDropdown'); Default=[string]$Palette['ComboBrush'] },
        [pscustomobject]@{ Key='ComboHoverBrush'; Label=(T 'ThemeColorDropdownHover'); Default=[string]$Palette['ComboHoverBrush'] },
        [pscustomobject]@{ Key='ScrollThumbBrush'; Label=(T 'ThemeColorScrollbar'); Default=[string]$Palette['ScrollThumbBrush'] },
        [pscustomobject]@{ Key='ControlBrush'; Label=(T 'ThemeColorControl'); Default=[string]$Palette['ControlBrush'] }
    )
}

function Set-AppThemeEditorPaletteField {
    param(
        [Parameter(Mandatory=$true)][object]$Palette,
        [Parameter(Mandatory=$true)][string]$Key,
        [Parameter(Mandatory=$true)][string]$Value
    )
    $targets = $script:ThemeEditorGroupTargets[$Key]
    if ($targets) {
        foreach ($target in $targets) { $Palette[$target] = $Value }
        return
    }
    if ($Palette.Contains($Key)) { $Palette[$Key] = $Value }
}

function Apply-AppThemeEditorFieldPreview {
    param(
        [Parameter(Mandatory=$true)][object]$State,
        [Parameter(Mandatory=$true)][string]$Key,
        [Parameter(Mandatory=$true)][string]$Value
    )
    Set-AppThemeEditorPaletteField -Palette $State.PreviewPalette -Key $Key -Value $Value
    if (-not $script:CurrentThemePalette) { $script:CurrentThemePalette = Copy-AppThemePalette -Palette $State.PreviewPalette }

    $targets = $script:ThemeEditorGroupTargets[$Key]
    if (-not $targets) { $targets = @($Key) }
    foreach ($target in $targets) {
        if (-not $State.PreviewPalette.Contains($target)) { continue }
        $color = [string]$State.PreviewPalette[$target]
        $script:CurrentThemePalette[$target] = $color
        Set-AppBrushColor -Name $target -Color $color
    }
}

function Get-AppThemeEditorInputs {
    param([Parameter(Mandatory=$true)][object]$State)
    $inputs = [ordered]@{}
    foreach ($key in @($State.Controls.Keys)) {
        $inputs[$key] = [string]$State.Controls[$key].Box.Text
    }
    return $inputs
}

function Save-AppThemeDraftState {
    param([Parameter(Mandatory=$true)][object]$State)
    if (-not $State -or -not $State.HasWork) { return }

    $path = Get-AppThemeDraftPath -EnsureParent
    $payload = [ordered]@{
        SchemaVersion = 1
        Mode = [string]$State.Mode
        ThemeCode = [string]$State.ThemeCode
        Name = [string]$State.NameBox.Text
        Base = [string]$State.Base
        BasePalette = Copy-AppThemePalette -Palette $State.BasePalette
        Inputs = Get-AppThemeEditorInputs -State $State
        UpdatedAt = [DateTime]::UtcNow.ToString('o')
    }
    $json = $payload | ConvertTo-Json -Depth 10
    $temporaryPath = $path + '.tmp'
    try {
        [IO.File]::WriteAllText($temporaryPath, $json, $script:ThemeUtf8NoBom)
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            [IO.File]::Replace($temporaryPath,$path,$null)
        }
        else {
            [IO.File]::Move($temporaryPath,$path)
        }
    }
    finally {
        if (Test-Path -LiteralPath $temporaryPath -PathType Leaf) {
            Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
        }
    }
}

function Queue-AppThemeDraftSave {
    param([Parameter(Mandatory=$true)][object]$State)
    $State.HasWork = $true
    if ($State.DraftTimer) {
        $State.DraftTimer.Stop()
        $State.DraftTimer.Start()
    }
}

function Read-AppThemeDraft {
    $path = Get-AppThemeDraftPath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
    try {
        return Get-Content -LiteralPath $path -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        return $null
    }
}

function Remove-AppThemeDraft {
    $path = Get-AppThemeDraftPath
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
    }
}

function Show-AppThemeDraftCloseChoice {
    param(
        [Parameter(Mandatory=$true)][Windows.Window]$Owner,
        [Parameter(Mandatory=$true)][string]$DialogBackground,
        [Parameter(Mandatory=$true)][string]$DialogSurface,
        [Parameter(Mandatory=$true)][string]$DialogText,
        [Parameter(Mandatory=$true)][string]$DialogMuted,
        [Parameter(Mandatory=$true)][string]$DialogBorder,
        [Parameter(Mandatory=$true)][string]$DialogAccent,
        [Parameter(Mandatory=$true)][int]$Corner
    )

    [xml]$choiceXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" xmlns:shell="clr-namespace:System.Windows.Shell;assembly=PresentationFramework" Width="560" Height="205" WindowStartupLocation="CenterOwner" WindowStyle="None" ResizeMode="NoResize" AllowsTransparency="True" Background="Transparent" Foreground="$DialogText" ShowInTaskbar="False">
  <shell:WindowChrome.WindowChrome><shell:WindowChrome CaptionHeight="0" ResizeBorderThickness="6" CornerRadius="$Corner" GlassFrameThickness="0" UseAeroCaptionButtons="False"/></shell:WindowChrome.WindowChrome>
  <Window.Resources>
    <Style x:Key="DraftChoiceButton" TargetType="Button"><Setter Property="Height" Value="32"/><Setter Property="MinWidth" Value="118"/><Setter Property="Padding" Value="12,4"/><Setter Property="Foreground" Value="$DialogText"/><Setter Property="Background" Value="$DialogSurface"/><Setter Property="BorderBrush" Value="$DialogBorder"/><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Border x:Name="B" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="1" CornerRadius="$Corner" Padding="{TemplateBinding Padding}"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="B" Property="Background" Value="$DialogAccent"/><Setter TargetName="B" Property="BorderBrush" Value="$DialogAccent"/><Setter Property="Foreground" Value="#FFFFFF"/></Trigger><MultiTrigger><MultiTrigger.Conditions><Condition Property="IsMouseOver" Value="True"/><Condition Property="Tag" Value="Danger"/></MultiTrigger.Conditions><Setter TargetName="B" Property="Background" Value="#D13438"/><Setter TargetName="B" Property="BorderBrush" Value="#D13438"/><Setter Property="Foreground" Value="#FFFFFF"/></MultiTrigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>
  </Window.Resources>
  <Border Margin="1" Background="$DialogBackground" BorderBrush="$DialogBorder" BorderThickness="1" CornerRadius="$Corner">
    <Grid><Grid.RowDefinitions><RowDefinition Height="42"/><RowDefinition Height="*"/></Grid.RowDefinitions>
      <Border Grid.Row="0" Background="$DialogSurface" CornerRadius="$Corner,$Corner,0,0"><Grid x:Name="DraftTitleBar"><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="34"/><ColumnDefinition Width="8"/></Grid.ColumnDefinitions><TextBlock x:Name="DraftTitle" Margin="14,0" VerticalAlignment="Center" FontSize="15" FontWeight="SemiBold"/><Button x:Name="DraftClose" Grid.Column="1" Style="{StaticResource DraftChoiceButton}" Padding="0" MinWidth="0" Width="28" Height="28"/></Grid></Border>
      <Grid Grid.Row="1" Margin="16,14"><Grid.RowDefinitions><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions><TextBlock x:Name="DraftMessage" Foreground="$DialogMuted" TextWrapping="Wrap" VerticalAlignment="Center"/><StackPanel Grid.Row="1" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,14,0,0"><Button x:Name="DraftKeep" Style="{StaticResource DraftChoiceButton}"/><Button x:Name="DraftDiscard" Style="{StaticResource DraftChoiceButton}" Tag="Danger" Margin="8,0,0,0"/><Button x:Name="DraftCancelClose" Style="{StaticResource DraftChoiceButton}" Margin="8,0,0,0"/></StackPanel></Grid>
    </Grid>
  </Border>
</Window>
"@
    $reader = [Xml.XmlNodeReader]::new($choiceXaml)
    $dialog = [Windows.Markup.XamlReader]::Load($reader)
    $dialog.Owner = $Owner
    $dialog.FontFamily = $script:UiFontFamily
    Enable-RoundedDialogFrame $dialog

    $titleBar=$dialog.FindName('DraftTitleBar'); $title=$dialog.FindName('DraftTitle'); $close=$dialog.FindName('DraftClose'); $message=$dialog.FindName('DraftMessage'); $keep=$dialog.FindName('DraftKeep'); $discard=$dialog.FindName('DraftDiscard'); $cancelClose=$dialog.FindName('DraftCancelClose')
    Set-DialogCloseButtonAppearance -Button $close -ForegroundColor $DialogText
    $title.Text = T 'ThemeDraftTitle'
    $message.Text = T 'ThemeDraftClosePrompt'
    $keep.Content = T 'ThemeDraftKeep'
    $discard.Content = T 'ThemeDraftDiscard'
    $cancelClose.Content = T 'ThemeDraftCancelClose'

    $titleBar.Add_MouseLeftButtonDown({ try { $dialog.DragMove() } catch { } })
    $close.Add_Click({ $dialog.Tag='Cancel'; $dialog.DialogResult=$false; $dialog.Close() })
    $cancelClose.Add_Click({ $dialog.Tag='Cancel'; $dialog.DialogResult=$false; $dialog.Close() })
    $keep.Add_Click({ $dialog.Tag='Keep'; $dialog.DialogResult=$true; $dialog.Close() })
    $discard.Add_Click({ $dialog.Tag='Discard'; $dialog.DialogResult=$true; $dialog.Close() })

    [void]$dialog.ShowDialog()
    if ($dialog.Tag) { return [string]$dialog.Tag }
    return 'Cancel'
}

function Open-AppThemeEditor {
    param(
        [ValidateSet('Create','Edit')][string]$Mode = 'Create',
        [string]$ThemeCode = ''
    )

    if ($script:ThemeEditorWindow) {
        try {
            if ($script:ThemeEditorWindow.WindowState -eq [Windows.WindowState]::Minimized) { $script:ThemeEditorWindow.WindowState = [Windows.WindowState]::Normal }
            [void]$script:ThemeEditorWindow.Activate()
        }
        catch { }
        return
    }

    $resumeDraft = $false
    $draft = Read-AppThemeDraft
    if ($draft) {
        try {
            if (Show-AppConfirm (T 'ThemeDraftResumePrompt')) {
                $resumeDraft = $true
                if ([string]$draft.Mode -eq 'Edit') { $Mode = 'Edit' } else { $Mode = 'Create' }
                $ThemeCode = [string]$draft.ThemeCode
            }
            else { Remove-AppThemeDraft }
        }
        catch { Remove-AppThemeDraft }
    }

    if ($Mode -eq 'Edit' -and [string]::IsNullOrWhiteSpace($ThemeCode)) {
        $ThemeCode = [string]$script:Settings.Theme
    }
    if ($Mode -eq 'Edit' -and -not $ThemeCode.StartsWith('User:',[StringComparison]::OrdinalIgnoreCase)) {
        if ($resumeDraft) { Remove-AppThemeDraft }
        return
    }

    $definition = $null
    if ($Mode -eq 'Edit') {
        $definition = Resolve-AppThemeDefinition -Code $ThemeCode
        if ($ThemeCode.StartsWith('User:',[StringComparison]::OrdinalIgnoreCase) -and ($definition.Fallback -or -not $definition.IsUser)) {
            $Mode = 'Create'
            $ThemeCode = ''
            $definition = $null
        }
    }

    $originalBase = if ($script:ResolvedTheme -eq 'Light') { 'Light' } else { 'Dark' }
    $originalPalette = if ($script:CurrentThemePalette) { Copy-AppThemePalette -Palette $script:CurrentThemePalette } else { Get-AppEmergencyPalette -Mode $originalBase }

    $base = 'Dark'
    $basePalette = $null
    $themeName = ''
    if ($resumeDraft -and $draft.BasePalette) {
        $base = if ([string]$draft.Base -eq 'Light') { 'Light' } else { 'Dark' }
        $basePalette = ConvertTo-AppThemePalette -Colors $draft.BasePalette -Base $base
        $themeName = [string]$draft.Name
    }
    elseif ($Mode -eq 'Edit' -and $definition) {
        $base = [string]$definition.Base
        $basePalette = Copy-AppThemePalette -Palette $definition.Palette
        $themeName = [string]$definition.Name
    }
    else {
        $base = if ($script:ResolvedTheme -eq 'Light') { 'Light' } else { 'Dark' }
        $basePalette = if ($script:CurrentThemePalette) { Copy-AppThemePalette -Palette $script:CurrentThemePalette } else { Get-AppEmergencyPalette -Mode $base }
    }

    $dialogBackground = Get-AppThemeColor -Name 'WindowBrush' -Fallback '#191C21'
    $dialogSurface = Get-AppThemeColor -Name 'CardBrush' -Fallback '#252930'
    $dialogInput = Get-AppThemeColor -Name 'InputBrush' -Fallback '#20242B'
    $dialogText = Get-AppThemeColor -Name 'TextBrush' -Fallback '#F4F4F4'
    $dialogMuted = Get-AppThemeColor -Name 'MutedBrush' -Fallback '#A8ADB5'
    $dialogBorder = Get-AppThemeColor -Name 'CardBorderBrush' -Fallback '#3B414A'
    $dialogControl = Get-AppThemeColor -Name 'ControlBrush' -Fallback '#30353D'
    $dialogAccent = ConvertTo-AccentHex ([string]$script:Settings.AccentColor)
    if (-not $dialogAccent) { $dialogAccent = '#1A9FFF' }
    $dialogScrollThumb = [string]$basePalette['ScrollThumbBrush']
    if (-not (ConvertTo-AccentHex $dialogScrollThumb)) { $dialogScrollThumb = '#59616B' }
    $corner = [int](Get-AppCornerRadiusValue)

    [xml]$themeXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" xmlns:shell="clr-namespace:System.Windows.Shell;assembly=PresentationFramework" Width="640" MinWidth="580" MaxWidth="760" Height="700" MinHeight="520" WindowStartupLocation="CenterOwner" WindowStyle="None" ResizeMode="CanResize" AllowsTransparency="True" Background="Transparent" Foreground="$dialogText" ShowInTaskbar="False">
  <shell:WindowChrome.WindowChrome><shell:WindowChrome CaptionHeight="0" ResizeBorderThickness="6" CornerRadius="$corner" GlassFrameThickness="0" UseAeroCaptionButtons="False"/></shell:WindowChrome.WindowChrome>
  <Window.Resources>
    <CornerRadius x:Key="ThemeEditorCorner">$corner</CornerRadius>
    <CornerRadius x:Key="ThemeEditorTopCorner">$corner,$corner,0,0</CornerRadius>
    <SolidColorBrush x:Key="ThemeEditorScrollThumbBrush" Color="$dialogScrollThumb"/>
    <SolidColorBrush x:Key="ThemeEditorScrollThumbHoverBrush" Color="$dialogAccent"/>
    <Style x:Key="ThemeEditorScrollThumbStyle" TargetType="Thumb"><Setter Property="Background" Value="{DynamicResource ThemeEditorScrollThumbBrush}"/><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Thumb"><Grid Margin="1"><Border x:Name="ThumbBorder" Background="{TemplateBinding Background}" CornerRadius="{DynamicResource ThemeEditorCorner}"/></Grid><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="ThumbBorder" Property="Background" Value="{DynamicResource ThemeEditorScrollThumbHoverBrush}"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>
    <Style TargetType="ScrollBar"><Setter Property="Width" Value="9"/><Setter Property="Background" Value="Transparent"/><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="ScrollBar"><Grid Width="9" Background="Transparent"><Track x:Name="PART_Track" Orientation="{TemplateBinding Orientation}" IsDirectionReversed="True" Focusable="False"><Track.DecreaseRepeatButton><RepeatButton Command="ScrollBar.PageUpCommand" CommandTarget="{Binding RelativeSource={RelativeSource TemplatedParent}}" Opacity="0" Focusable="False"/></Track.DecreaseRepeatButton><Track.Thumb><Thumb Style="{StaticResource ThemeEditorScrollThumbStyle}" MinHeight="28"/></Track.Thumb><Track.IncreaseRepeatButton><RepeatButton Command="ScrollBar.PageDownCommand" CommandTarget="{Binding RelativeSource={RelativeSource TemplatedParent}}" Opacity="0" Focusable="False"/></Track.IncreaseRepeatButton></Track></Grid></ControlTemplate></Setter.Value></Setter><Style.Triggers><Trigger Property="Orientation" Value="Horizontal"><Setter Property="Width" Value="Auto"/><Setter Property="Height" Value="9"/><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="ScrollBar"><Grid Height="9" Background="Transparent"><Track x:Name="PART_Track" Orientation="{TemplateBinding Orientation}" Focusable="False"><Track.DecreaseRepeatButton><RepeatButton Command="ScrollBar.PageLeftCommand" CommandTarget="{Binding RelativeSource={RelativeSource TemplatedParent}}" Opacity="0" Focusable="False"/></Track.DecreaseRepeatButton><Track.Thumb><Thumb Style="{StaticResource ThemeEditorScrollThumbStyle}" MinWidth="28"/></Track.Thumb><Track.IncreaseRepeatButton><RepeatButton Command="ScrollBar.PageRightCommand" CommandTarget="{Binding RelativeSource={RelativeSource TemplatedParent}}" Opacity="0" Focusable="False"/></Track.IncreaseRepeatButton></Track></Grid></ControlTemplate></Setter.Value></Setter></Trigger></Style.Triggers></Style>
    <Style TargetType="TextBox"><Setter Property="Height" Value="34"/><Setter Property="Padding" Value="8,4"/><Setter Property="Foreground" Value="$dialogText"/><Setter Property="Background" Value="$dialogInput"/><Setter Property="BorderBrush" Value="$dialogBorder"/><Setter Property="CaretBrush" Value="$dialogText"/><Setter Property="VerticalContentAlignment" Value="Center"/><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="TextBox"><Border Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="{DynamicResource ThemeEditorCorner}"><ScrollViewer x:Name="PART_ContentHost" Focusable="False"/></Border></ControlTemplate></Setter.Value></Setter></Style>
    <Style x:Key="ThemeEditorButton" TargetType="Button"><Setter Property="Height" Value="32"/><Setter Property="Padding" Value="12,4"/><Setter Property="Foreground" Value="$dialogText"/><Setter Property="Background" Value="$dialogControl"/><Setter Property="BorderBrush" Value="$dialogBorder"/><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Border x:Name="B" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="1" CornerRadius="{DynamicResource ThemeEditorCorner}" Padding="{TemplateBinding Padding}"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border></ControlTemplate></Setter.Value></Setter></Style>
    <Style x:Key="ThemeEditorPrimaryButton" TargetType="Button"><Setter Property="Height" Value="32"/><Setter Property="Padding" Value="12,4"/><Setter Property="Foreground" Value="$dialogText"/><Setter Property="Background" Value="$dialogControl"/><Setter Property="BorderBrush" Value="$dialogBorder"/><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Border x:Name="B" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="1" CornerRadius="{DynamicResource ThemeEditorCorner}" Padding="{TemplateBinding Padding}"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="B" Property="Background" Value="$dialogAccent"/><Setter TargetName="B" Property="BorderBrush" Value="$dialogAccent"/><Setter Property="Foreground" Value="#FFFFFF"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>
    <Style x:Key="ThemeEditorCloseButton" TargetType="Button"><Setter Property="Width" Value="28"/><Setter Property="Height" Value="28"/><Setter Property="Foreground" Value="$dialogText"/><Setter Property="Background" Value="Transparent"/><Setter Property="BorderThickness" Value="0"/><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Border x:Name="CloseBorder" Background="Transparent" CornerRadius="{DynamicResource ThemeEditorCorner}"><Viewbox Width="11" Height="11"><Canvas Width="12" Height="12"><Path Stroke="{Binding Foreground, RelativeSource={RelativeSource TemplatedParent}}" StrokeThickness="1.5" StrokeStartLineCap="Round" StrokeEndLineCap="Round" Data="M1,1 L11,11 M11,1 L1,11"/></Canvas></Viewbox></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="CloseBorder" Property="Background" Value="#D13438"/><Setter Property="Foreground" Value="#FFFFFF"/></Trigger><Trigger Property="IsPressed" Value="True"><Setter TargetName="CloseBorder" Property="Opacity" Value="0.78"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>
  </Window.Resources>
  <Border x:Name="ThemeEditorRoot" Margin="1" Background="$dialogBackground" BorderBrush="$dialogBorder" BorderThickness="1" CornerRadius="{DynamicResource ThemeEditorCorner}">
    <Grid><Grid.RowDefinitions><RowDefinition Height="42"/><RowDefinition Height="*"/></Grid.RowDefinitions>
      <Border x:Name="ThemeEditorTopbar" Grid.Row="0" Background="$dialogSurface" CornerRadius="{DynamicResource ThemeEditorTopCorner}"><Grid x:Name="ThemeEditorTitleBar"><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="34"/><ColumnDefinition Width="8"/></Grid.ColumnDefinitions><TextBlock x:Name="ThemeEditorTitle" Margin="14,0" VerticalAlignment="Center" FontSize="15" FontWeight="SemiBold"/><Button x:Name="ThemeEditorClose" Grid.Column="1" Style="{StaticResource ThemeEditorCloseButton}"/></Grid></Border>
      <Grid Grid.Row="1" Margin="16"><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
        <TextBlock x:Name="ThemeEditorHint" Foreground="$dialogMuted" TextWrapping="Wrap" Margin="0,0,0,12"/>
        <Grid Grid.Row="1" Margin="0,0,0,16"><Grid.ColumnDefinitions><ColumnDefinition Width="235"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions><TextBlock x:Name="ThemeNameLabel" VerticalAlignment="Center" TextWrapping="Wrap" Margin="0,0,14,0"/><TextBox x:Name="ThemeNameBox" Grid.Column="1" HorizontalAlignment="Stretch"/></Grid>
        <ScrollViewer Grid.Row="2" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled"><StackPanel x:Name="ThemeColorRows"/></ScrollViewer>
        <Grid Grid.Row="3" Margin="0,14,0,0"><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="8"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions><TextBlock x:Name="ThemeEditorError" Foreground="#FF6B72" VerticalAlignment="Center" TextWrapping="Wrap"/><Button x:Name="ThemeEditorCancel" Grid.Column="1" Style="{StaticResource ThemeEditorPrimaryButton}"/><Button x:Name="ThemeEditorSave" Grid.Column="3" Style="{StaticResource ThemeEditorPrimaryButton}"/></Grid>
      </Grid>
    </Grid>
  </Border>
</Window>
"@

    $reader = [Xml.XmlNodeReader]::new($themeXaml)
    $dialog = [Windows.Markup.XamlReader]::Load($reader)
    $dialog.Owner = $window
    $dialog.FontFamily = $script:UiFontFamily
    Enable-RoundedDialogFrame $dialog

    $titleBar=$dialog.FindName('ThemeEditorTitleBar')
    $title=$dialog.FindName('ThemeEditorTitle')
    $close=$dialog.FindName('ThemeEditorClose')
    $hint=$dialog.FindName('ThemeEditorHint')
    $nameLabel=$dialog.FindName('ThemeNameLabel')
    $nameBox=$dialog.FindName('ThemeNameBox')
    $rows=$dialog.FindName('ThemeColorRows')
    $errorText=$dialog.FindName('ThemeEditorError')
    $cancel=$dialog.FindName('ThemeEditorCancel')
    $save=$dialog.FindName('ThemeEditorSave')


    if ($Mode -eq 'Edit') {
        $title.Text = T 'ThemeEditTitle'
        $hint.Text = T 'ThemeEditHint'
        $save.Content = T 'ThemeSaveAction'
    }
    else {
        $title.Text = T 'ThemeCreateTitle'
        $hint.Text = T 'ThemeCreateHint'
        $save.Content = T 'ThemeCreateAction'
    }
    $nameLabel.Text = T 'ThemeNameLabel'
    $close.ToolTip = T 'Close'
    $cancel.Content = T 'Cancel'
    $nameBox.Text = $themeName


    $state = [pscustomobject]@{
        Mode = $Mode
        ThemeCode = $ThemeCode
        Base = $base
        BasePalette = $basePalette
        PreviewPalette = Copy-AppThemePalette -Palette $basePalette
        OriginalBase = $originalBase
        OriginalPalette = $originalPalette
        Controls = @{}
        NameBox = $nameBox
        DraftTimer = [Windows.Threading.DispatcherTimer]::new()
        HasWork = [bool]$resumeDraft
        AllowClose = $false
        Initializing = $true
        DialogBackground = $dialogBackground
        DialogSurface = $dialogSurface
        DialogText = $dialogText
        DialogMuted = $dialogMuted
        DialogBorder = $dialogBorder
        DialogAccent = $dialogAccent
        Corner = $corner
    }
    $state.DraftTimer.Interval = [TimeSpan]::FromMilliseconds(200)

    $draftTick = {
        $state.DraftTimer.Stop()
        try { Save-AppThemeDraftState -State $state } catch { }
    }.GetNewClosure()
    $state.DraftTimer.Add_Tick($draftTick)

    $fieldDefinitions = Get-AppThemeEditorFieldDefinitions -Palette $basePalette
    $draftInputs = if ($resumeDraft) { $draft.Inputs } else { $null }
    $gridLengthConverter = [Windows.GridLengthConverter]::new()
    $previewBorderBrush = [Windows.Media.SolidColorBrush]::new([Windows.Media.ColorConverter]::ConvertFromString($dialogBorder))

    foreach ($field in $fieldDefinitions) {
        $row = [Windows.Controls.Grid]::new()
        $row.Margin = [Windows.Thickness]::new(0,0,0,12)
        foreach ($width in @('235','180','10','82','10','34')) {
            $column = [Windows.Controls.ColumnDefinition]::new()
            $column.Width = $gridLengthConverter.ConvertFromString($width)
            [void]$row.ColumnDefinitions.Add($column)
        }

        $label = [Windows.Controls.TextBlock]::new()
        $label.Text = $field.Label
        $label.VerticalAlignment = 'Center'
        $label.TextWrapping = 'Wrap'
        $label.Margin = [Windows.Thickness]::new(0,0,14,0)
        [void]$row.Children.Add($label)

        $box = [Windows.Controls.TextBox]::new()
        $initialValue = [string]$field.Default
        if ($draftInputs) {
            $draftValue = Get-AppThemeObjectColor -Object $draftInputs -Name ([string]$field.Key)
            if ($null -ne $draftValue) { $initialValue = [string]$draftValue }
        }
        $box.Text = $initialValue
        $box.MaxLength = 7
        $box.Width = 180
        $box.MaxWidth = 200
        $box.HorizontalAlignment = 'Left'
        $box.Tag = [string]$field.Key
        [Windows.Controls.Grid]::SetColumn($box,1)
        [void]$row.Children.Add($box)

        $button = [Windows.Controls.Button]::new()
        $button.Content = T 'ChooseAccent'
        $button.Style = $dialog.Resources['ThemeEditorButton']
        $button.Tag = [string]$field.Key
        [Windows.Controls.Grid]::SetColumn($button,3)
        [void]$row.Children.Add($button)

        $preview = [Windows.Controls.Border]::new()
        $preview.Width = 34
        $preview.Height = 34
        $preview.SetResourceReference([Windows.Controls.Border]::CornerRadiusProperty,'ThemeEditorCorner')
        $preview.BorderBrush = $previewBorderBrush
        $preview.BorderThickness = 1
        [Windows.Controls.Grid]::SetColumn($preview,5)
        [void]$row.Children.Add($preview)

        $state.Controls[[string]$field.Key] = [pscustomobject]@{ Box=$box; Preview=$preview; Button=$button }

        $normalized = ConvertTo-AccentHex $initialValue
        if ($normalized) {
            $preview.Background = [Windows.Media.SolidColorBrush]::new([Windows.Media.ColorConverter]::ConvertFromString($normalized))
            Set-AppThemeEditorPaletteField -Palette $state.PreviewPalette -Key ([string]$field.Key) -Value $normalized
        }

        [void]$rows.Children.Add($row)
    }

    foreach ($item in @($state.Controls.Values)) {
        $textChanged = {
            param($sender)
            if ($state.Initializing) { return }
            $key = [string]$sender.Tag
            $control = $state.Controls[$key]
            if (-not $control) { return }
            $normalized = ConvertTo-AccentHex ([string]$sender.Text)
            if ($normalized) {
                $color = [Windows.Media.ColorConverter]::ConvertFromString($normalized)
                if ($control.Preview.Background -is [Windows.Media.SolidColorBrush]) { $control.Preview.Background.Color = $color }
                else { $control.Preview.Background = [Windows.Media.SolidColorBrush]::new($color) }
                Apply-AppThemeEditorFieldPreview -State $state -Key $key -Value $normalized
                if ($key -eq 'ScrollThumbBrush') {
                    try { $dialog.Resources['ThemeEditorScrollThumbBrush'].Color = $color } catch { }
                }
                $errorText.Text = ''
            }
            Queue-AppThemeDraftSave -State $state
        }.GetNewClosure()
        $item.Box.Add_TextChanged($textChanged)

        $chooseClick = {
            param($sender)
            $key = [string]$sender.Tag
            $control = $state.Controls[$key]
            if (-not $control) { return }
            $chosen = Show-AccentPicker -InitialColor ([string]$control.Box.Text) -OwnerWindow $dialog
            if ($chosen) { $control.Box.Text = $chosen }
        }.GetNewClosure()
        $item.Button.Add_Click($chooseClick)
    }

    $nameChanged = {
        if ($state.Initializing) { return }
        Queue-AppThemeDraftSave -State $state
    }.GetNewClosure()
    $nameBox.Add_TextChanged($nameChanged)

    $titleBar.Add_MouseLeftButtonDown({ try { $dialog.DragMove() } catch { } }.GetNewClosure())
    $close.Add_Click({ $dialog.Close() }.GetNewClosure())
    $cancel.Add_Click({ $dialog.Close() }.GetNewClosure())

    $saveHandler = {
        try {
            $themeNameValue = $nameBox.Text.Trim()
            if ([string]::IsNullOrWhiteSpace($themeNameValue)) {
                $errorText.Text = T 'ThemeNameRequired'
                return
            }

            $finalPalette = Copy-AppThemePalette -Palette $state.BasePalette
            foreach ($key in @($state.Controls.Keys)) {
                $value = ConvertTo-AccentHex ([string]$state.Controls[$key].Box.Text)
                if (-not $value) {
                    $errorText.Text = T 'InvalidAccentColor'
                    return
                }
                Set-AppThemeEditorPaletteField -Palette $finalPalette -Key ([string]$key) -Value $value
            }

            if ($state.Mode -eq 'Edit') {
                [void](Save-AppEditedTheme -Code ([string]$state.ThemeCode) -Name $themeNameValue -Base $state.Base -Palette $finalPalette)
            }
            else {
                [void](New-AppUserThemeFromPalette -Name $themeNameValue -Base $state.Base -Palette $finalPalette)
            }
            $successMessage = if ($state.Mode -eq 'Edit') { T 'ThemeUpdated' } else { T 'ThemeCreated' }

            Remove-AppThemeDraft
            Apply-AppThemePreview -Palette $state.OriginalPalette -Base $state.OriginalBase
            $state.AllowClose = $true
            $dialog.Close()
            Refresh-ThemeOptions
            Show-AppInfo $successMessage
        }
        catch {
            $errorText.Text = $_.Exception.Message
        }
    }.GetNewClosure()
    $save.Add_Click($saveHandler)

    $closingHandler = {
        param($sender,$eventArgs)
        if ($state.AllowClose) { return }

        if (-not $state.HasWork) {
            Remove-AppThemeDraft
            Apply-AppTheme
            $state.AllowClose = $true
            return
        }

        try { Save-AppThemeDraftState -State $state } catch { }
        $choice = Show-AppThemeDraftCloseChoice -Owner $dialog -DialogBackground $state.DialogBackground -DialogSurface $state.DialogSurface -DialogText $state.DialogText -DialogMuted $state.DialogMuted -DialogBorder $state.DialogBorder -DialogAccent $state.DialogAccent -Corner $state.Corner
        switch ($choice) {
            'Keep' {
                try { Save-AppThemeDraftState -State $state } catch { }
                Apply-AppTheme
                $state.AllowClose = $true
            }
            'Discard' {
                Remove-AppThemeDraft
                Apply-AppTheme
                $state.AllowClose = $true
            }
            default {
                $eventArgs.Cancel = $true
            }
        }
    }.GetNewClosure()
    $dialog.Add_Closing($closingHandler)

    $closedHandler = {
        try { $state.DraftTimer.Stop() } catch { }
        Clear-AppThemeEditorSession
    }.GetNewClosure()
    $dialog.Add_Closed($closedHandler)

    $state.Initializing = $false
    $script:ThemeEditorWindow = $dialog
    $script:ThemeEditorState = $state
    Update-AppThemeActionButtons
    Apply-AppThemePreview -Palette $state.PreviewPalette -Base $state.Base

    $dialog.Add_ContentRendered({
        $nameBox.Focus() | Out-Null
        if (-not $resumeDraft -and $state.Mode -eq 'Create') { $nameBox.SelectAll() }
    }.GetNewClosure())

    [void]$dialog.Show()
}

function Show-AppThemeCreator {
    Open-AppThemeEditor -Mode 'Create'
}

function Show-AppThemeEditor {
    param([string]$ThemeCode)
    if (-not ([string]$ThemeCode).StartsWith('User:',[StringComparison]::OrdinalIgnoreCase)) { return }
    Open-AppThemeEditor -Mode 'Edit' -ThemeCode $ThemeCode
}
