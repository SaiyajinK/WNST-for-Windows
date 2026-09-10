#requires -Version 5.1

Set-StrictMode -Version 2.0

$script:ToolVersion = '1.0.0'
$script:TaskName = 'WNST Daily Update'
$script:LegacyTaskName = 'H.0.S.T Daily Update'
$script:BeginMarker = '# BEGIN WNST - managed entries'
$script:EndMarker = '# END WNST - managed entries'
$script:ManualBeginMarker = '# BEGIN WNST - manual entries'
$script:ManualEndMarker = '# END WNST - manual entries'
$script:LegacyBeginMarker = '# BEGIN H.0.S.T - managed entries'
$script:LegacyEndMarker = '# END H.0.S.T - managed entries'
$script:LegacyManualBeginMarker = '# BEGIN H.0.S.T - manual entries'
$script:LegacyManualEndMarker = '# END H.0.S.T - manual entries'
$script:TelemetryBeginMarker = '# WNST TELEMETRY BLOCK BEGIN'
$script:TelemetryEndMarker = '# WNST TELEMETRY BLOCK END'
$script:TelemetryEndpoints = @(
    'vortex.data.microsoft.com',
    'vortex-win.data.microsoft.com',
    'telecommand.telemetry.microsoft.com',
    'telecommand.telemetry.microsoft.com.nsatc.net',
    'oca.telemetry.microsoft.com',
    'oca.telemetry.microsoft.com.nsatc.net',
    'sqm.telemetry.microsoft.com',
    'sqm.telemetry.microsoft.com.nsatc.net',
    'watson.telemetry.microsoft.com',
    'watson.telemetry.microsoft.com.nsatc.net',
    'watson.ppe.telemetry.microsoft.com',
    'settings-win.data.microsoft.com'
)
$script:RepositoryUrl = 'https://github.com/SaiyajinK/WNST-for-Windows'


$script:ModuleLanguageCode = 'en-US'
$script:ModuleTranslations = @{}
$script:ModuleLanguageDictionaryCache = @{}

function Get-HuModuleLanguageDictionary {
    param([Parameter(Mandatory = $true)][string]$Code)

    if ($script:ModuleLanguageDictionaryCache.ContainsKey($Code)) {
        return $script:ModuleLanguageDictionaryCache[$Code]
    }

    $path = Join-Path (Join-Path $PSScriptRoot 'Locales') ($Code + '.json')
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }

    $data = [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8) | ConvertFrom-Json -ErrorAction Stop
    $dictionary = @{}
    foreach ($property in $data.PSObject.Properties) {
        $dictionary[$property.Name] = [string]$property.Value
    }
    $script:ModuleLanguageDictionaryCache[$Code] = $dictionary
    return $dictionary
}

function Set-HuModuleLanguage {
    [CmdletBinding()]
    param([AllowEmptyString()][string]$Code)

    $localeRoot = Join-Path $PSScriptRoot 'Locales'
    $requestedCode = ([string]$Code).Trim()
    if ([string]::IsNullOrWhiteSpace($requestedCode)) {
        $requestedCode = [Globalization.CultureInfo]::CurrentUICulture.Name
    }

    $resolvedCode = $requestedCode
    $selectedPath = Join-Path $localeRoot ($resolvedCode + '.json')
    if (-not (Test-Path -LiteralPath $selectedPath -PathType Leaf)) {
        $neutral = ($requestedCode -split '-')[0]
        $match = Get-ChildItem -LiteralPath $localeRoot -Filter ($neutral + '-*.json') -File -ErrorAction SilentlyContinue | Sort-Object Name | Select-Object -First 1
        $resolvedCode = if ($match) { [IO.Path]::GetFileNameWithoutExtension($match.Name) } else { 'en-US' }
    }

    $fallback = Get-HuModuleLanguageDictionary -Code 'en-US'
    if (-not $fallback) { $fallback = @{} }
    $dictionary = $fallback.Clone()
    if ($resolvedCode -ne 'en-US') {
        $selected = Get-HuModuleLanguageDictionary -Code $resolvedCode
        if ($selected) {
            foreach ($key in $selected.Keys) { $dictionary[$key] = [string]$selected[$key] }
        }
    }

    $script:ModuleLanguageCode = $resolvedCode
    $script:ModuleTranslations = $dictionary
    # Background runspaces import this module independently. Persist the
    # language chosen in WNST at process scope so those imports do not fall
    # back to the Windows UI culture.
    $env:WNST_UI_LANGUAGE = $resolvedCode
    return $resolvedCode
}

function Get-HuModuleText {
    param([Parameter(Mandatory = $true)][string]$Key)
    if ($script:ModuleTranslations.ContainsKey($Key)) { return [string]$script:ModuleTranslations[$Key] }
    return $Key
}

function Format-HuModuleText {
    param([Parameter(Mandatory = $true)][string]$Key, [object[]]$Arguments)
    return [string]::Format((Get-HuModuleText -Key $Key), $Arguments)
}

$initialModuleLanguage = if ([string]::IsNullOrWhiteSpace([string]$env:WNST_UI_LANGUAGE)) {
    [Globalization.CultureInfo]::CurrentUICulture.Name
}
else {
    [string]$env:WNST_UI_LANGUAGE
}
try { [void](Set-HuModuleLanguage -Code $initialModuleLanguage) } catch { }

. (Join-Path $PSScriptRoot 'Modules\WNST\Data.ps1')
. (Join-Path $PSScriptRoot 'Modules\WNST\Settings.ps1')
. (Join-Path $PSScriptRoot 'Modules\WNST\Admin.ps1')
. (Join-Path $PSScriptRoot 'Modules\WNST\Sources.ps1')
. (Join-Path $PSScriptRoot 'Modules\WNST\Hosts.ps1')
. (Join-Path $PSScriptRoot 'Modules\WNST\Backups.ps1')
. (Join-Path $PSScriptRoot 'Modules\WNST\ScheduledTasks.ps1')

Export-ModuleMember -Function @(
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
