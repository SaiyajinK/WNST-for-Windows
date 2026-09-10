function Get-HuManagedHostsText {
    param(
        [Parameter(Mandatory = $true)][string]$CurrentContent,
        [Parameter(Mandatory = $true)][string]$ManagedEntries,
        [Parameter(Mandatory = $true)][string]$SourceUrl,
        [ValidateSet('Merge', 'Replace')][string]$UpdateMode = 'Merge'
    )

    $lines = @($CurrentContent -split "`r?`n")
    $beginIndexes = New-Object System.Collections.Generic.List[int]
    $endIndexes = New-Object System.Collections.Generic.List[int]
    for ($index = 0; $index -lt $lines.Count; $index++) {
        if ($lines[$index].Trim() -in @($script:BeginMarker, $script:LegacyBeginMarker)) { $beginIndexes.Add($index) }
        if ($lines[$index].Trim() -in @($script:EndMarker, $script:LegacyEndMarker)) { $endIndexes.Add($index) }
    }

    if ($beginIndexes.Count -ne $endIndexes.Count -or $beginIndexes.Count -gt 1) {
        throw (Get-HuModuleText 'HostsMarkersInvalid')
    }
    if ($beginIndexes.Count -eq 1 -and $beginIndexes[0] -ge $endIndexes[0]) {
        throw (Get-HuModuleText 'HostsMarkersOrderInvalid')
    }

    $preserved = New-Object System.Collections.Generic.List[string]
    if ($UpdateMode -eq 'Merge') {
        if ($beginIndexes.Count -eq 1) {
            for ($index = 0; $index -lt $beginIndexes[0]; $index++) { $preserved.Add($lines[$index]) }
            for ($index = $endIndexes[0] + 1; $index -lt $lines.Count; $index++) { $preserved.Add($lines[$index]) }
        }
        else {
            foreach ($line in $lines) { $preserved.Add($line) }
        }
        while ($preserved.Count -gt 0 -and [string]::IsNullOrWhiteSpace($preserved[$preserved.Count - 1])) {
            $preserved.RemoveAt($preserved.Count - 1)
        }
    }
    else {
        $preserved.Add('# Windows hosts file managed with WNST')
        $preserved.Add('# Repository: ' + $script:RepositoryUrl)
    }

    $output = New-Object System.Collections.Generic.List[string]
    foreach ($line in $preserved) { $output.Add($line) }
    if ($output.Count -gt 0) { $output.Add('') }
    $output.Add($script:BeginMarker)
    $output.Add('# Source: ' + $SourceUrl)
    $output.Add('# Updated: ' + (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss') + ' UTC')
    foreach ($entryLine in @($ManagedEntries -split "`r?`n")) { $output.Add($entryLine) }
    $output.Add($script:EndMarker)
    $output.Add('')
    return ($output -join "`r`n")
}

function Remove-HuTelemetryHostsBlockFromText {
    param([AllowEmptyString()][string]$Content)

    $begin = [Regex]::Escape($script:TelemetryBeginMarker)
    $end = [Regex]::Escape($script:TelemetryEndMarker)
    $pattern = '(?ms)^[ \t]*' + $begin + '[ \t]*\r?\n.*?^[ \t]*' + $end + '[ \t]*(?:\r?\n)?'
    return ([Regex]::Replace([string]$Content, $pattern, '').TrimEnd())
}

function Get-HuTelemetryHostsBlockText {
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add($script:TelemetryBeginMarker)
    foreach ($endpoint in @($script:TelemetryEndpoints)) {
        $lines.Add('0.0.0.0 ' + $endpoint)
    }
    $lines.Add($script:TelemetryEndMarker)
    return ($lines -join "`r`n")
}

function Get-HuHostsTextWithTelemetrySetting {
    param(
        [AllowEmptyString()][string]$Content,
        [bool]$Enabled
    )

    $clean = Remove-HuTelemetryHostsBlockFromText -Content $Content
    if (-not $Enabled) {
        if ([string]::IsNullOrWhiteSpace($clean)) { return '' }
        return ($clean.TrimEnd() + "`r`n")
    }

    $block = Get-HuTelemetryHostsBlockText
    if ([string]::IsNullOrWhiteSpace($clean)) { return ($block + "`r`n") }
    return ($clean.TrimEnd() + "`r`n`r`n" + $block + "`r`n")
}

function Get-HuHostsTextWithTelemetryState {
    param(
        [AllowEmptyString()][string]$Content,
        [string]$DataRoot = (Get-HuDefaultDataRoot)
    )
    $settings = Get-HuSettings -DataRoot $DataRoot
    return Get-HuHostsTextWithTelemetrySetting -Content $Content -Enabled ([bool]$settings.TelemetryHostsBlockEnabled)
}

function Set-HuTelemetryHostsBlock {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][bool]$Enabled,
        [string]$HostsPath = (Get-HuHostsPath),
        [string]$DataRoot = (Get-HuDefaultDataRoot),
        [bool]$FlushDns = $true,
        [switch]$SkipAdministratorCheck,
        [switch]$SkipDnsFlush
    )

    if (-not $SkipAdministratorCheck) { Assert-HuAdministrator }
    if (-not (Test-Path -LiteralPath $HostsPath -PathType Leaf)) {
        throw (Format-HuModuleText 'HostsFileMissing' @($HostsPath))
    }

    $currentContent = [IO.File]::ReadAllText($HostsPath)
    $updatedContent = Get-HuHostsTextWithTelemetrySetting -Content $currentContent -Enabled $Enabled
    $changed = -not [string]::Equals($currentContent, $updatedContent, [StringComparison]::Ordinal)
    $temporaryPath = $null
    $hostsWritten = $false

    try {
        if ($changed) {
            $temporaryPath = Join-Path (Split-Path -Parent $HostsPath) ('hosts.wnst.telemetry.' + [Guid]::NewGuid().ToString('N') + '.tmp')
            [IO.File]::WriteAllText($temporaryPath, $updatedContent, (New-Object Text.UTF8Encoding($false)))
            Copy-Item -LiteralPath $temporaryPath -Destination $HostsPath -Force -ErrorAction Stop
            $hostsWritten = $true
        }

        $settings = Get-HuSettings -DataRoot $DataRoot
        $settings.TelemetryHostsBlockEnabled = [bool]$Enabled
        Save-HuSettings -Settings $settings -DataRoot $DataRoot | Out-Null
    }
    catch {
        if ($hostsWritten) {
            try { [IO.File]::WriteAllText($HostsPath, $currentContent, (New-Object Text.UTF8Encoding($false))) } catch { }
        }
        throw
    }
    finally {
        if ($temporaryPath -and (Test-Path -LiteralPath $temporaryPath)) {
            Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
        }
    }

    $dnsFlushed = $false
    if ($FlushDns) { $dnsFlushed = Invoke-HuDnsFlush -SkipDnsFlush:$SkipDnsFlush }

    Write-HuLog -DataRoot $DataRoot -Message ('Blocage endpoints télémétrie : {0}. Bloc hosts modifié : {1}.' -f $(if ($Enabled) { 'activé' } else { 'désactivé' }), $changed)

    return [pscustomobject]@{
        Enabled       = [bool]$Enabled
        Changed       = [bool]$changed
        EndpointCount = @($script:TelemetryEndpoints).Count
        HostsPath     = $HostsPath
        DnsFlushed    = [bool]$dnsFlushed
    }
}

function Get-HuHostsPath {
    if (-not $env:SystemRoot) { throw (Get-HuModuleText 'SystemRootMissing') }
    return (Join-Path $env:SystemRoot 'System32\drivers\etc\hosts')
}

function New-HuHostsBackup {
    param(
        [Parameter(Mandatory = $true)][string]$HostsPath,
        [string]$DataRoot = (Get-HuDefaultDataRoot),
        [string]$Prefix = 'hosts'
    )

    if (-not (Test-Path -LiteralPath $HostsPath -PathType Leaf)) {
        throw (Format-HuModuleText 'HostsFileMissing' @($HostsPath))
    }
    $paths = Get-HuPaths -DataRoot $DataRoot
    New-Item -ItemType Directory -Path $paths.BackupRoot -Force -ErrorAction Stop | Out-Null
    $stamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss-fff'
    $backupPath = Join-Path $paths.BackupRoot ("{0}_{1}.hosts" -f $Prefix, $stamp)
    Copy-Item -LiteralPath $HostsPath -Destination $backupPath -Force -ErrorAction Stop
    return $backupPath
}

function Invoke-HuDnsFlush {
    param([switch]$SkipDnsFlush)

    if ($SkipDnsFlush) { return $false }
    $ipconfig = Join-Path $env:SystemRoot 'System32\ipconfig.exe'
    if (-not (Test-Path -LiteralPath $ipconfig -PathType Leaf)) { return $false }
    $process = Start-Process -FilePath $ipconfig -ArgumentList '/flushdns' -WindowStyle Hidden -Wait -PassThru
    if ($process.ExitCode -ne 0) {
        throw (Format-HuModuleText 'DnsFlushFailed' @($process.ExitCode))
    }
    return $true
}

function Invoke-HuHostsUpdate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$SourceUrl,
        [ValidateSet('Merge', 'Replace')][string]$UpdateMode = 'Merge',
        [bool]$FlushDns = $true,
        [bool]$CreateBackup = $true,
        [string]$HostsPath = (Get-HuHostsPath),
        [string]$DataRoot = (Get-HuDefaultDataRoot),
        [AllowEmptyString()][string]$DownloadedContent,
        [switch]$SkipAdministratorCheck,
        [switch]$SkipDnsFlush
    )

    if (-not $SkipAdministratorCheck) { Assert-HuAdministrator }
    $uri = Resolve-HuSourceUri -SourceUrl $SourceUrl
    Write-HuLog -DataRoot $DataRoot -Message ("Début de mise à jour depuis {0}" -f $uri.AbsoluteUri)

    try {
        $content = if ($PSBoundParameters.ContainsKey('DownloadedContent')) {
            $DownloadedContent
        }
        else {
            Get-HuRemoteText -SourceUrl $uri.AbsoluteUri
        }
        $parsed = ConvertFrom-HuHostsContent -Content $content

        if (-not (Test-Path -LiteralPath $HostsPath -PathType Leaf)) {
            throw (Format-HuModuleText 'HostsFileMissing' @($HostsPath))
        }
        $currentContent = [IO.File]::ReadAllText($HostsPath)
        $updatedContent = Get-HuManagedHostsText -CurrentContent $currentContent -ManagedEntries $parsed.CanonicalText -SourceUrl $uri.AbsoluteUri -UpdateMode $UpdateMode
        $updatedContent = Get-HuHostsTextWithTelemetryState -Content $updatedContent -DataRoot $DataRoot
        $backupPath = if ($CreateBackup) { New-HuHostsBackup -HostsPath $HostsPath -DataRoot $DataRoot } else { $null }

        $temporaryPath = Join-Path (Split-Path -Parent $HostsPath) ('hosts.hu.' + [Guid]::NewGuid().ToString('N') + '.tmp')
        try {
            [IO.File]::WriteAllText($temporaryPath, $updatedContent, (New-Object Text.UTF8Encoding($false)))
            Copy-Item -LiteralPath $temporaryPath -Destination $HostsPath -Force -ErrorAction Stop
        }
        catch {
            try {
                if ($backupPath) { Copy-Item -LiteralPath $backupPath -Destination $HostsPath -Force -ErrorAction SilentlyContinue }
                else { [IO.File]::WriteAllText($HostsPath, $currentContent, (New-Object Text.UTF8Encoding($false))) }
            }
            catch { }
            throw (Format-HuModuleText 'HostsWriteFailed' @($_.Exception.Message))
        }
        finally {
            if (Test-Path -LiteralPath $temporaryPath) {
                Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
            }
        }

        $dnsFlushed = $false
        if ($FlushDns) { $dnsFlushed = Invoke-HuDnsFlush -SkipDnsFlush:$SkipDnsFlush }

        $settings = Get-HuSettings -DataRoot $DataRoot
        $settings.SourceUrl = $uri.AbsoluteUri
        $settings.UpdateMode = $UpdateMode
        $settings.BackupBeforeChange = $CreateBackup
        $settings.FlushDns = $FlushDns
        $settings.LastUpdateUtc = (Get-Date).ToUniversalTime().ToString('o')
        $settings.LastEntryCount = $parsed.EntryCount
        $settings.LastResult = 'Succès'
        Save-HuSettings -Settings $settings -DataRoot $DataRoot | Out-Null

        Write-HuLog -DataRoot $DataRoot -Message ("Mise à jour terminée : {0} entrée(s). Sauvegarde : {1}" -f $parsed.EntryCount, $backupPath)
        return [pscustomobject]@{
            Success       = $true
            SourceUrl     = $uri.AbsoluteUri
            EntryCount    = $parsed.EntryCount
            IgnoredLines  = $parsed.IgnoredLines
            BackupPath    = $backupPath
            HostsPath     = $HostsPath
            DnsFlushed    = $dnsFlushed
            Sha256        = Get-HuSha256Text -Text $parsed.CanonicalText
            UpdatedAt     = Get-Date
        }
    }
    catch {
        Write-HuLog -DataRoot $DataRoot -Level ERROR -Message $_.Exception.Message
        try {
            $settings = Get-HuSettings -DataRoot $DataRoot
            $settings.LastResult = 'Échec : ' + $_.Exception.Message
            Save-HuSettings -Settings $settings -DataRoot $DataRoot | Out-Null
        }
        catch { }
        throw
    }
}

function Add-HuManualHostsEntries {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Content,
        [bool]$CreateBackup = $true,
        [bool]$FlushDns = $true,
        [string]$HostsPath = (Get-HuHostsPath),
        [string]$DataRoot = (Get-HuDefaultDataRoot),
        [switch]$SkipAdministratorCheck,
        [switch]$SkipDnsFlush
    )

    if (-not $SkipAdministratorCheck) { Assert-HuAdministrator }
    if (-not (Test-Path -LiteralPath $HostsPath -PathType Leaf)) { throw (Format-HuModuleText 'HostsFileMissing' @($HostsPath)) }
    $validation = Test-HuManualHostsEntries -Content $Content
    if (-not $validation.IsValid) { throw $validation.ErrorMessage }
    $newEntries = ConvertFrom-HuHostsContent -Content $Content
    $currentContent = [IO.File]::ReadAllText($HostsPath)
    $manualBeginPattern = '(?:' + [Regex]::Escape($script:ManualBeginMarker) + '|' + [Regex]::Escape($script:LegacyManualBeginMarker) + ')'
    $manualEndPattern = '(?:' + [Regex]::Escape($script:ManualEndMarker) + '|' + [Regex]::Escape($script:LegacyManualEndMarker) + ')'
    $manualBeginCount = [Regex]::Matches($currentContent, '(?m)^\s*' + $manualBeginPattern + '\s*$').Count
    $manualEndCount = [Regex]::Matches($currentContent, '(?m)^\s*' + $manualEndPattern + '\s*$').Count
    if ($manualBeginCount -ne $manualEndCount -or $manualBeginCount -gt 1) { throw (Get-HuModuleText 'ManualMarkersInvalid') }
    $pattern = '(?ms)^\s*' + $manualBeginPattern + '\s*\r?\n(?<body>.*?)^\s*' + $manualEndPattern + '\s*(?:\r?\n)?'
    $blocks = [Regex]::Matches($currentContent, $pattern)
    if ($blocks.Count -gt 1) { throw (Get-HuModuleText 'ManualMarkersDuplicate') }

    $existingCanonical = ''
    $existingCount = 0
    if ($blocks.Count -eq 1 -and -not [string]::IsNullOrWhiteSpace($blocks[0].Groups['body'].Value)) {
        try {
            $existing = ConvertFrom-HuHostsContent -Content $blocks[0].Groups['body'].Value
            $existingCanonical = $existing.CanonicalText
            $existingCount = $existing.EntryCount
        }
        catch { }
    }
    $combinedContent = @($existingCanonical, $newEntries.CanonicalText) -join "`r`n"
    $combined = ConvertFrom-HuHostsContent -Content $combinedContent
    $preserved = [Regex]::Replace($currentContent, $pattern, '').TrimEnd()
    $manualBlock = @($script:ManualBeginMarker, '# Added manually with WNST', $combined.CanonicalText, $script:ManualEndMarker) -join "`r`n"
    $updatedContent = if ($preserved) { $preserved + "`r`n`r`n" + $manualBlock + "`r`n" } else { $manualBlock + "`r`n" }
    $updatedContent = Get-HuHostsTextWithTelemetryState -Content $updatedContent -DataRoot $DataRoot
    $backupPath = if ($CreateBackup) { New-HuHostsBackup -HostsPath $HostsPath -DataRoot $DataRoot -Prefix 'before-manual' } else { $null }
    $temporaryPath = Join-Path (Split-Path -Parent $HostsPath) ('hosts.hu.manual.' + [Guid]::NewGuid().ToString('N') + '.tmp')
    try {
        [IO.File]::WriteAllText($temporaryPath, $updatedContent, (New-Object Text.UTF8Encoding($false)))
        Copy-Item -LiteralPath $temporaryPath -Destination $HostsPath -Force -ErrorAction Stop
        $dnsFlushed = $false
        if ($FlushDns) { $dnsFlushed = Invoke-HuDnsFlush -SkipDnsFlush:$SkipDnsFlush }
        $settings = Get-HuSettings -DataRoot $DataRoot
        $settings.LastUpdateUtc = (Get-Date).ToUniversalTime().ToString('o')
        $settings.LastResult = 'Entrées manuelles ajoutées'
        Save-HuSettings -Settings $settings -DataRoot $DataRoot | Out-Null
        Write-HuLog -DataRoot $DataRoot -Message ("Entrées manuelles : {0} nouvelle(s), {1} au total." -f ($combined.EntryCount - $existingCount), $combined.EntryCount)
        return [pscustomobject]@{ AddedCount=($combined.EntryCount-$existingCount); TotalManualCount=$combined.EntryCount; BackupPath=$backupPath; HostsPath=$HostsPath; DnsFlushed=$dnsFlushed }
    }
    catch {
        try {
            if ($backupPath) { Copy-Item -LiteralPath $backupPath -Destination $HostsPath -Force -ErrorAction SilentlyContinue }
            else { [IO.File]::WriteAllText($HostsPath, $currentContent, (New-Object Text.UTF8Encoding($false))) }
        }
        catch { }
        throw (Format-HuModuleText 'ManualAddFailed' @($_.Exception.Message))
    }
    finally { if (Test-Path -LiteralPath $temporaryPath) { Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue } }
}

function Get-HuWindowsDefaultHostsText {
    # Contenu par défaut publié par Microsoft Support pour Windows 11.
    $lines = @(
        '# Copyright (c) 1993-2009 Microsoft Corp.',
        '#',
        '# This is a sample HOSTS file used by Microsoft TCP/IP for Windows.',
        '#',
        '# This file contains the mappings of IP addresses to host names. Each',
        '# entry should be kept on an individual line. The IP address should',
        '# be placed in the first column followed by the corresponding host name.',
        '# The IP address and the host name should be separated by at least one',
        '# space.',
        '#',
        '# Additionally, comments (such as these) may be inserted on individual',
        "# lines or following the machine name denoted by a '#' symbol.",
        '#',
        '# For example:',
        '#',
        '#      102.54.94.97     rhino.acme.com          # source server',
        '#       38.25.63.10     x.acme.com              # x client host',
        '',
        '# localhost name resolution is handled within DNS itself.',
        '#    127.0.0.1       localhost',
        '#    ::1             localhost',
        ''
    )
    return ($lines -join "`r`n")
}

function Restore-HuWindowsDefault {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [string]$HostsPath = (Get-HuHostsPath),
        [string]$DataRoot = (Get-HuDefaultDataRoot),
        [bool]$CreateBackup = $true,
        [switch]$SkipAdministratorCheck,
        [switch]$SkipDnsFlush
    )

    if (-not $SkipAdministratorCheck) { Assert-HuAdministrator }
    if (-not (Test-Path -LiteralPath $HostsPath -PathType Leaf)) {
        throw (Format-HuModuleText 'HostsFileMissing' @($HostsPath))
    }
    if (-not $PSCmdlet.ShouldProcess($HostsPath, 'Restaurer le fichier hosts par défaut de Windows 11')) { return }

    $currentContent = [IO.File]::ReadAllText($HostsPath)
    $backupPath = if ($CreateBackup) { New-HuHostsBackup -HostsPath $HostsPath -DataRoot $DataRoot -Prefix 'before-windows-default' } else { $null }
    $temporaryPath = Join-Path (Split-Path -Parent $HostsPath) ('hosts.hu.default.' + [Guid]::NewGuid().ToString('N') + '.tmp')
    try {
        $defaultContent = Get-HuHostsTextWithTelemetryState -Content (Get-HuWindowsDefaultHostsText) -DataRoot $DataRoot
        [IO.File]::WriteAllText($temporaryPath, $defaultContent, (New-Object Text.UTF8Encoding($false)))
        Copy-Item -LiteralPath $temporaryPath -Destination $HostsPath -Force -ErrorAction Stop
        $dnsFlushed = Invoke-HuDnsFlush -SkipDnsFlush:$SkipDnsFlush

        $settings = Get-HuSettings -DataRoot $DataRoot
        $settings.LastUpdateUtc = (Get-Date).ToUniversalTime().ToString('o')
        $settings.LastEntryCount = 0
        $settings.LastResult = 'Fichier Windows 11 restauré'
        Save-HuSettings -Settings $settings -DataRoot $DataRoot | Out-Null
        Write-HuLog -DataRoot $DataRoot -Message 'Fichier hosts Windows 11 par défaut restauré.'

        return [pscustomobject]@{
            Success     = $true
            BackupPath  = $backupPath
            HostsPath   = $HostsPath
            DnsFlushed  = $dnsFlushed
            RestoredAt  = Get-Date
        }
    }
    catch {
        try {
            if ($backupPath) { Copy-Item -LiteralPath $backupPath -Destination $HostsPath -Force -ErrorAction SilentlyContinue }
            else { [IO.File]::WriteAllText($HostsPath, $currentContent, (New-Object Text.UTF8Encoding($false))) }
        }
        catch { }
        Write-HuLog -DataRoot $DataRoot -Level ERROR -Message ("Échec de restauration Windows 11 : {0}" -f $_.Exception.Message)
        throw (Format-HuModuleText 'WindowsHostsRestoreFailed' @($_.Exception.Message))
    }
    finally {
        if (Test-Path -LiteralPath $temporaryPath) {
            Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
        }
    }
}
