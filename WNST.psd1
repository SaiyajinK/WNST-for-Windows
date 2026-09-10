@{
    RootModule        = 'WNST.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = '5ec6361c-63b1-4d6d-88e7-493c16d912c4'
    Author            = 'SaiyajinK'
    Copyright         = '© 2026 SaiyajinK'
    Description       = 'WNST — Windows Network & System Toolkit pour Windows.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        'Set-HuModuleLanguage',
        'Get-HuModuleText',
        'Format-HuModuleText',
        'Get-HuStandardDataRoot',
        'Get-HuConfiguredDataRoot',
        'Set-HuConfiguredDataRoot',
        'Reset-HuConfiguredDataRoot',
        'Move-HuDataRootContent',
        'Get-HuPaths',
        'Get-HuSettings',
        'Save-HuSettings',
        'Test-HuAdministrator',
        'Test-HuSourceAddress',
        'Test-HuSource',
        'Invoke-HuHostsUpdate',
        'Test-HuManualHostsEntries',
        'Add-HuManualHostsEntries',
        'Get-HuBackup',
        'Remove-HuBackup',
        'Clear-HuBackup',
        'Restore-HuBackup',
        'Restore-HuWindowsDefault',
        'Set-HuTelemetryHostsBlock',
        'Get-HuScheduledTaskStatus',
        'Install-HuScheduledTask',
        'Remove-HuScheduledTask',
        'Reset-HuConfiguration'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{
        PSData = @{
            Tags       = @('Windows', 'Hosts', 'Updater', 'WPF')
        }
    }
}
