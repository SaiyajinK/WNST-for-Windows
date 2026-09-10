function Get-HuDefaultSettings {
    [ordered]@{
        SchemaVersion           = 11
        FirstRunCompleted       = $false
        Language                = ''
        Theme                   = 'System'
        AccentColor             = '#1A9FFF'
        TitlebarAnimation       = $true
        CornerRadius            = 5
        UiScalePercent          = 100
        SourceUrl               = ''
        DailyEnabled            = $false
        UpdateTime              = '09:00'
        UpdateMode              = 'Merge'
        BackupBeforeChange      = $true
        SidebarCollapsed        = $false
        FlushDns                = $true
        TelemetryHostsBlockEnabled = $false
        LastUpdateUtc           = $null
        LastEntryCount          = 0
        LastResult              = 'Jamais exécuté'
    }
}

function Write-HuLog {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet('INFO', 'WARNING', 'ERROR')][string]$Level = 'INFO',
        [string]$DataRoot = (Get-HuDefaultDataRoot)
    )

    try {
        $paths = Get-HuPaths -DataRoot $DataRoot
        New-Item -ItemType Directory -Path $paths.LogRoot -Force -ErrorAction Stop | Out-Null
        $line = '{0} [{1}] {2}' -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'), $Level, $Message
        Add-Content -LiteralPath $paths.LogPath -Value $line -Encoding UTF8 -ErrorAction Stop
    }
    catch { }
}

function Get-HuSettings {
    [CmdletBinding()]
    param([string]$DataRoot = (Get-HuDefaultDataRoot))

    $defaults = Get-HuDefaultSettings
    $paths = Get-HuPaths -DataRoot $DataRoot
    if (-not (Test-Path -LiteralPath $paths.SettingsPath -PathType Leaf)) {
        return [pscustomobject]$defaults
    }

    try {
        $loaded = Get-Content -LiteralPath $paths.SettingsPath -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        $loadedSchema = if ($loaded.PSObject.Properties.Name -contains 'SchemaVersion') { [int]$loaded.SchemaVersion } else { 1 }
        foreach ($name in @($defaults.Keys)) {
            if ($loaded.PSObject.Properties.Name -contains $name) {
                $defaults[$name] = $loaded.$name
            }
        }
        if ($loadedSchema -lt 3 -and [string]$defaults.AccentColor -eq '#60CDFF') { $defaults.AccentColor = '#1A9FFF' }
        $defaults.SchemaVersion = 11
        return [pscustomobject]$defaults
    }
    catch {
        Write-HuLog -DataRoot $DataRoot -Level WARNING -Message ("Paramètres illisibles, valeurs par défaut utilisées : {0}" -f $_.Exception.Message)
        return [pscustomobject]$defaults
    }
}

function Save-HuSettings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Settings,
        [string]$DataRoot = (Get-HuDefaultDataRoot)
    )

    $paths = Get-HuPaths -DataRoot $DataRoot
    New-Item -ItemType Directory -Path $paths.DataRoot -Force -ErrorAction Stop | Out-Null

    $normalized = Get-HuDefaultSettings
    foreach ($name in @($normalized.Keys)) {
        if ($Settings.PSObject.Properties.Name -contains $name) {
            $normalized[$name] = $Settings.$name
        }
    }

    $normalized.SourceUrl = ([string]$normalized.SourceUrl).Trim()
    if ([string]$normalized.Theme -notin @('System', 'Dark', 'Light', 'Minimal') -and -not ([string]$normalized.Theme).StartsWith('User:', [StringComparison]::OrdinalIgnoreCase)) {
        $normalized.Theme = 'System'
    }
    $normalized.AccentColor = ([string]$normalized.AccentColor).Trim().ToUpperInvariant()
    if ($normalized.AccentColor -notmatch '^#[0-9A-F]{6}$') {
        throw (Get-HuModuleText 'AccentHexFormatRequired')
    }
    if ($normalized.UpdateTime -notmatch '^(?:[01]\d|2[0-3]):[0-5]\d$') {
        throw (Get-HuModuleText 'UpdateTimeFormatRequired')
    }
    $normalized.DailyEnabled = [bool]$normalized.DailyEnabled
    $normalized.FirstRunCompleted = [bool]$normalized.FirstRunCompleted
    $normalized.BackupBeforeChange = [bool]$normalized.BackupBeforeChange
    $normalized.SidebarCollapsed = [bool]$normalized.SidebarCollapsed
    $normalized.TitlebarAnimation = [bool]$normalized.TitlebarAnimation
    $normalized.CornerRadius = [int]$normalized.CornerRadius
    if ($normalized.CornerRadius -notin @(0,5,10)) { $normalized.CornerRadius = 5 }
    $normalized.UiScalePercent = [int]$normalized.UiScalePercent
    if ($normalized.UiScalePercent -notin @(100,125,150,175,200)) { $normalized.UiScalePercent = 100 }
    if ([string]$normalized.UpdateMode -notin @('Merge', 'Replace')) {
        throw (Get-HuModuleText 'UpdateModeInvalid')
    }
    $normalized.FlushDns = [bool]$normalized.FlushDns
    $normalized.TelemetryHostsBlockEnabled = [bool]$normalized.TelemetryHostsBlockEnabled
    $normalized.LastEntryCount = [int]$normalized.LastEntryCount

    $temporaryPath = $paths.SettingsPath + '.tmp'
    $json = $normalized | ConvertTo-Json -Depth 5
    try {
        [IO.File]::WriteAllText($temporaryPath, $json, (New-Object Text.UTF8Encoding($false)))
        Copy-Item -LiteralPath $temporaryPath -Destination $paths.SettingsPath -Force -ErrorAction Stop
    }
    finally {
        if (Test-Path -LiteralPath $temporaryPath) {
            Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
        }
    }
    return [pscustomobject]$normalized
}

function Reset-HuConfiguration {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param([string]$DataRoot = (Get-HuDefaultDataRoot))

    $paths = Get-HuPaths -DataRoot $DataRoot
    $target = [IO.Path]::GetFullPath($paths.DataRoot).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    if (-not (Test-Path -LiteralPath $target -PathType Container)) { return $false }
    $item = Get-Item -LiteralPath $target -Force -ErrorAction Stop
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw (Format-HuModuleText 'ModuleConfigFolderInvalid' @($target)) }

    $removed = $false
    foreach ($name in @(Get-HuManagedDataNames)) {
        if ($name -eq 'Logs') { continue }
        $managedPath = Join-Path $target $name
        if (-not (Test-Path -LiteralPath $managedPath)) { continue }
        if ($PSCmdlet.ShouldProcess($managedPath, 'Supprimer une donnée appartenant à WNST')) {
            if ($name -eq 'StartMenu') { [void](Clear-HuManagedStartMenuPolicy -DataRoot $target) }
            Remove-Item -LiteralPath $managedPath -Recurse -Force -ErrorAction Stop
            $removed = $true
        }
    }
    return $removed
}
