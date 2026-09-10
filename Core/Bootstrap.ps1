function Get-HuUiFontFamily {
    try {
        # Windows 11 inclut Segoe UI Variable Text : pas besoin d'énumérer toutes
        # les familles de polices à chaque démarrage.
        if ([Environment]::OSVersion.Version.Build -ge 22000) {
            return New-Object Windows.Media.FontFamily 'Segoe UI Variable Text'
        }
    }
    catch { }
    try {
        if ([Windows.SystemFonts]::MessageFontFamily) { return [Windows.SystemFonts]::MessageFontFamily }
    }
    catch { }
    return New-Object Windows.Media.FontFamily 'Segoe UI'
}

function Save-AppSettingsObject {
    param([object]$Settings)
    if ($script:DataRootArgument) { return Save-HuSettings -Settings $Settings -DataRoot $script:DataRootArgument }
    return Save-HuSettings -Settings $Settings
}

function Get-AppBackups {
    if ($script:DataRootArgument) { return @(Get-HuBackup -DataRoot $script:DataRootArgument) }
    return @(Get-HuBackup)
}
