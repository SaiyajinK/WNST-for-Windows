#requires -Version 5.1

[CmdletBinding()]
param([switch]$Scheduled)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'WNST.psd1') -Force

try {
    $settings = Get-HuSettings
    [void](Set-HuModuleLanguage -Code ([string]$settings.Language))
    if ([string]::IsNullOrWhiteSpace([string]$settings.SourceUrl)) {
        throw (Get-HuModuleText 'UrlRequired')
    }

    $result = Invoke-HuHostsUpdate `
        -SourceUrl ([string]$settings.SourceUrl) `
        -UpdateMode ([string]$settings.UpdateMode) `
        -FlushDns ([bool]$settings.FlushDns) `
        -CreateBackup ([bool]$settings.BackupBeforeChange)

    Write-Output (Format-HuModuleText 'ScheduledUpdateSuccess' @($result.EntryCount, $result.UpdatedAt))
    exit 0
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}
