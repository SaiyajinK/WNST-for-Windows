function Get-HuStandardDataRoot {
    $localAppData = [Environment]::GetFolderPath('LocalApplicationData')
    if ([string]::IsNullOrWhiteSpace($localAppData)) {
        throw (Get-HuModuleText 'ModuleLocalAppDataMissing')
    }
    return [IO.Path]::GetFullPath((Join-Path $localAppData 'WNST'))
}

function Get-HuConfiguredDataRoot {
    [CmdletBinding()]
    param([string]$PreferenceRoot = (Get-HuStandardDataRoot))

    $fallbackRoot = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($PreferenceRoot))
    $preferencePath = Join-Path $fallbackRoot 'data-root.json'
    if (-not (Test-Path -LiteralPath $preferencePath -PathType Leaf)) { return $fallbackRoot }
    try {
        $preference = Get-Content -LiteralPath $preferencePath -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        $configured = [string]$preference.DataRoot
        if ([string]::IsNullOrWhiteSpace($configured) -or -not [IO.Path]::IsPathRooted([Environment]::ExpandEnvironmentVariables($configured))) { return $fallbackRoot }
        return [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($configured))
    }
    catch { return $fallbackRoot }
}

function Reset-HuConfiguredDataRoot {
    [CmdletBinding()]
    param([string]$PreferenceRoot = (Get-HuStandardDataRoot))

    $fallbackRoot = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($PreferenceRoot))
    $preferencePath = Join-Path $fallbackRoot 'data-root.json'
    if (Test-Path -LiteralPath $preferencePath -PathType Leaf) { Remove-Item -LiteralPath $preferencePath -Force -ErrorAction Stop }
    return $fallbackRoot
}

function Set-HuConfiguredDataRoot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$DataRoot,
        [string]$PreferenceRoot = (Get-HuStandardDataRoot)
    )

    $fallbackRoot = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($PreferenceRoot))
    $configuredRoot = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($DataRoot))
    if ($configuredRoot.TrimEnd([IO.Path]::DirectorySeparatorChar) -eq $fallbackRoot.TrimEnd([IO.Path]::DirectorySeparatorChar)) {
        [void](Reset-HuConfiguredDataRoot -PreferenceRoot $fallbackRoot)
        return $fallbackRoot
    }
    New-Item -ItemType Directory -Path $fallbackRoot -Force -ErrorAction Stop | Out-Null
    $preferencePath = Join-Path $fallbackRoot 'data-root.json'
    $temporaryPath = $preferencePath + '.' + [Guid]::NewGuid().ToString('N') + '.tmp'
    try {
        $payload = [ordered]@{ SchemaVersion = 1; DataRoot = $configuredRoot } | ConvertTo-Json
        [IO.File]::WriteAllText($temporaryPath, $payload, (New-Object Text.UTF8Encoding($false)))
        Move-Item -LiteralPath $temporaryPath -Destination $preferencePath -Force -ErrorAction Stop
    }
    finally { if (Test-Path -LiteralPath $temporaryPath) { Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue } }
    return $configuredRoot
}

function Get-HuDefaultDataRoot {
    return Get-HuConfiguredDataRoot
}

function Get-HuPaths {
    [CmdletBinding()]
    param([string]$DataRoot = (Get-HuDefaultDataRoot))

    $root = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($DataRoot))
    [pscustomobject]@{
        DataRoot     = $root
        SettingsPath = Join-Path $root 'settings.json'
        BackupRoot   = Join-Path $root 'Backups'
        LogRoot      = Join-Path $root 'Logs'
        LogPath      = Join-Path (Join-Path $root 'Logs') 'WNST.log'
    }
}

function Get-HuManagedDataNames {
    @('settings.json', 'thispc-cache.json', 'AppxHidden.json', 'Backups', 'Logs', 'StartMenu')
}

function Get-HuManagedDataFileNames {
    @('settings.json', 'thispc-cache.json', 'AppxHidden.json')
}

function Get-HuManagedStartMenuLayoutPath {
    param([Parameter(Mandatory = $true)][string]$DataRoot)

    $root = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($DataRoot))
    return Join-Path (Join-Path $root 'StartMenu') 'LayoutModification.json'
}

function Test-HuManagedStartMenuPolicy {
    param([Parameter(Mandatory = $true)][string]$DataRoot)

    $policyPath = 'HKCU:\Software\Policies\Microsoft\Windows\Explorer'
    try {
        $expectedPath = Get-HuManagedStartMenuLayoutPath -DataRoot $DataRoot
        $configured = Get-ItemPropertyValue -Path $policyPath -Name 'ConfigureStartPins' -ErrorAction Stop
        $configuredJson = [string](Get-ItemPropertyValue -Path $policyPath -Name 'ConfigureStartPinsJSON' -ErrorAction SilentlyContinue)
        if ($configured -isnot [string] -and [int]$configured -eq 1 -and -not [string]::IsNullOrWhiteSpace($configuredJson)) {
            $configuredJsonPath = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($configuredJson))
            if ([string]::Equals($configuredJsonPath, $expectedPath, [StringComparison]::OrdinalIgnoreCase)) { return $true }
        }
        if ($configured -is [string]) {
            $configuredPath = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables([string]$configured))
            if ([string]::Equals($configuredPath, $expectedPath, [StringComparison]::OrdinalIgnoreCase)) { return $true }
        }
        return $false
    }
    catch { return $false }
}

function Move-HuManagedStartMenuPolicy {
    param(
        [Parameter(Mandatory = $true)][string]$SourceRoot,
        [Parameter(Mandatory = $true)][string]$DestinationRoot
    )

    if (-not (Test-HuManagedStartMenuPolicy -DataRoot $SourceRoot)) { return $false }
    $policyPath = 'HKCU:\Software\Policies\Microsoft\Windows\Explorer'
    $destinationLayout = Get-HuManagedStartMenuLayoutPath -DataRoot $DestinationRoot
    Remove-ItemProperty -Path $policyPath -Name 'ConfigureStartPins' -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path $policyPath -Name 'ConfigureStartPinsJSON' -ErrorAction SilentlyContinue
    New-ItemProperty -Path $policyPath -Name 'ConfigureStartPinsJSON' -PropertyType ExpandString -Value $destinationLayout -Force -ErrorAction Stop | Out-Null
    New-ItemProperty -Path $policyPath -Name 'ConfigureStartPins' -PropertyType DWord -Value 1 -Force -ErrorAction Stop | Out-Null
    return $true
}

function Clear-HuManagedStartMenuPolicy {
    param([Parameter(Mandatory = $true)][string]$DataRoot)

    if (-not (Test-HuManagedStartMenuPolicy -DataRoot $DataRoot)) { return $false }
    $policyPath = 'HKCU:\Software\Policies\Microsoft\Windows\Explorer'
    Remove-ItemProperty -Path $policyPath -Name 'ConfigureStartPins' -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path $policyPath -Name 'ConfigureStartPinsJSON' -ErrorAction SilentlyContinue
    return $true
}

function Move-HuDataRootContent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$SourceRoot,
        [Parameter(Mandatory = $true)][string]$DestinationRoot
    )

    $source = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($SourceRoot)).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $destination = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($DestinationRoot)).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    if ($source -eq $destination) { return @() }

    $separator = [string][IO.Path]::DirectorySeparatorChar
    if (($destination + $separator).StartsWith($source + $separator, [StringComparison]::OrdinalIgnoreCase) -or ($source + $separator).StartsWith($destination + $separator, [StringComparison]::OrdinalIgnoreCase)) {
        throw (Get-HuModuleText 'ModuleDataRootsOverlap')
    }
    if (-not (Test-Path -LiteralPath $source -PathType Container)) {
        New-Item -ItemType Directory -Path $destination -Force -ErrorAction Stop | Out-Null
        return @()
    }

    $sourceDirectory = Get-Item -LiteralPath $source -Force -ErrorAction Stop
    if ($sourceDirectory.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw (Format-HuModuleText 'ModuleSourceDataRootInvalid' @($source)) }
    if (Test-Path -LiteralPath $destination) {
        $destinationDirectory = Get-Item -LiteralPath $destination -Force -ErrorAction Stop
        if (-not $destinationDirectory.PSIsContainer -or ($destinationDirectory.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw (Format-HuModuleText 'ModuleDestinationDataRootInvalid' @($destination)) }
    }
    else { New-Item -ItemType Directory -Path $destination -Force -ErrorAction Stop | Out-Null }

    $transactionId = [Guid]::NewGuid().ToString('N')
    $stagingRoot = Join-Path $destination ('.wnst-transfer-' + $transactionId)
    $rollbackRoot = Join-Path $destination ('.wnst-rollback-' + $transactionId)
    $managedNames = @(Get-HuManagedDataNames)
    $stagedNames = New-Object 'System.Collections.Generic.List[string]'
    $replacedNames = New-Object 'System.Collections.Generic.List[string]'
    $committedNames = New-Object 'System.Collections.Generic.List[string]'
    $destinationCommitted = $false

    try {
        New-Item -ItemType Directory -Path $stagingRoot -Force -ErrorAction Stop | Out-Null
        foreach ($name in $managedNames) {
            $sourcePath = Join-Path $source $name
            if (-not (Test-Path -LiteralPath $sourcePath)) { continue }
            $sourceItem = Get-Item -LiteralPath $sourcePath -Force -ErrorAction Stop
            if ($sourceItem.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw (Format-HuModuleText 'ModuleDataItemLinkInvalid' @($sourcePath)) }
            $mustBeFile = $name -in @(Get-HuManagedDataFileNames)
            if (($mustBeFile -and $sourceItem.PSIsContainer) -or (-not $mustBeFile -and -not $sourceItem.PSIsContainer)) {
                throw (Format-HuModuleText 'ModuleDataItemTypeInvalid' @($sourcePath))
            }
            Copy-Item -LiteralPath $sourcePath -Destination (Join-Path $stagingRoot $name) -Recurse -Force -ErrorAction Stop
            $stagedNames.Add($name)
        }
        if ($stagedNames.Count -eq 0) { return @() }

        New-Item -ItemType Directory -Path $rollbackRoot -Force -ErrorAction Stop | Out-Null
        foreach ($name in $stagedNames) {
            $destinationPath = Join-Path $destination $name
            if (Test-Path -LiteralPath $destinationPath) {
                Move-Item -LiteralPath $destinationPath -Destination (Join-Path $rollbackRoot $name) -Force -ErrorAction Stop
                $replacedNames.Add($name)
            }
        }
        foreach ($name in $stagedNames) {
            Move-Item -LiteralPath (Join-Path $stagingRoot $name) -Destination (Join-Path $destination $name) -Force -ErrorAction Stop
            $committedNames.Add($name)
        }
        if ($stagedNames.Contains('StartMenu')) {
            [void](Move-HuManagedStartMenuPolicy -SourceRoot $source -DestinationRoot $destination)
        }
        $destinationCommitted = $true

        foreach ($name in $stagedNames) {
            $sourcePath = Join-Path $source $name
            if (Test-Path -LiteralPath $sourcePath) { Remove-Item -LiteralPath $sourcePath -Recurse -Force -ErrorAction Stop }
        }
        return $stagedNames.ToArray()
    }
    catch {
        if (-not $destinationCommitted) {
            foreach ($name in $committedNames) {
                $destinationPath = Join-Path $destination $name
                if (Test-Path -LiteralPath $destinationPath) { Remove-Item -LiteralPath $destinationPath -Recurse -Force -ErrorAction SilentlyContinue }
            }
            foreach ($name in $replacedNames) {
                $rollbackPath = Join-Path $rollbackRoot $name
                if (Test-Path -LiteralPath $rollbackPath) { Move-Item -LiteralPath $rollbackPath -Destination (Join-Path $destination $name) -Force -ErrorAction SilentlyContinue }
            }
        }
        throw
    }
    finally {
        if (Test-Path -LiteralPath $stagingRoot) { Remove-Item -LiteralPath $stagingRoot -Recurse -Force -ErrorAction SilentlyContinue }
        if ($destinationCommitted -and (Test-Path -LiteralPath $rollbackRoot)) { Remove-Item -LiteralPath $rollbackRoot -Recurse -Force -ErrorAction SilentlyContinue }
        elseif ((Test-Path -LiteralPath $rollbackRoot) -and -not (Get-ChildItem -LiteralPath $rollbackRoot -Force -ErrorAction SilentlyContinue | Select-Object -First 1)) { Remove-Item -LiteralPath $rollbackRoot -Force -ErrorAction SilentlyContinue }
    }
}
