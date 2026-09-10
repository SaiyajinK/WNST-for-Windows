function Get-HuBackup {
    [CmdletBinding()]
    param([string]$DataRoot = (Get-HuDefaultDataRoot))

    $paths = Get-HuPaths -DataRoot $DataRoot
    if (-not (Test-Path -LiteralPath $paths.BackupRoot -PathType Container)) { return @() }
    return @(
        Get-ChildItem -LiteralPath $paths.BackupRoot -File -Filter '*.hosts' -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            ForEach-Object {
                [pscustomobject]@{
                    Name         = $_.Name
                    Path         = $_.FullName
                    CreatedAt    = $_.LastWriteTime
                    SizeBytes    = [int64]$_.Length
                    IsPreRestore = $_.Name -like 'before-restore_*'
                }
            }
    )
}

function Test-HuPathWithinRoot {
    param([string]$Root, [string]$Candidate)
    $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd('\') + '\'
    $candidateFull = [IO.Path]::GetFullPath($Candidate)
    return $candidateFull.StartsWith($rootFull, [StringComparison]::OrdinalIgnoreCase)
}

function Remove-HuBackup {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory = $true)][string]$BackupPath,
        [string]$DataRoot = (Get-HuDefaultDataRoot)
    )
    $paths = Get-HuPaths -DataRoot $DataRoot
    if (-not (Test-HuPathWithinRoot -Root $paths.BackupRoot -Candidate $BackupPath)) { throw (Get-HuModuleText 'BackupOutsideManagedFolder') }
    if (-not (Test-Path -LiteralPath $BackupPath -PathType Leaf)) { throw (Get-HuModuleText 'BackupFileMissing') }
    if ([IO.Path]::GetExtension($BackupPath) -ne '.hosts') { throw (Get-HuModuleText 'BackupFileInvalid') }
    if ($PSCmdlet.ShouldProcess($BackupPath, 'Supprimer la sauvegarde')) {
        Remove-Item -LiteralPath $BackupPath -Force -ErrorAction Stop
        Write-HuLog -DataRoot $DataRoot -Message ("Sauvegarde supprimée : {0}" -f $BackupPath)
        return $true
    }
    return $false
}

function Clear-HuBackup {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param([string]$DataRoot = (Get-HuDefaultDataRoot))
    $paths = Get-HuPaths -DataRoot $DataRoot
    $backups = @(Get-HuBackup -DataRoot $DataRoot)
    if ($backups.Count -eq 0) { return 0 }
    if ($PSCmdlet.ShouldProcess($paths.BackupRoot, "Supprimer $($backups.Count) sauvegarde(s)")) {
        $deleted = 0
        foreach ($backup in $backups) {
            if (Test-HuPathWithinRoot -Root $paths.BackupRoot -Candidate $backup.Path) {
                Remove-Item -LiteralPath $backup.Path -Force -ErrorAction Stop
                $deleted++
            }
        }
        Write-HuLog -DataRoot $DataRoot -Message ("Historique supprimé : {0} sauvegarde(s)." -f $deleted)
        return $deleted
    }
    return 0
}

function Restore-HuBackup {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [string]$BackupPath,
        [string]$HostsPath = (Get-HuHostsPath),
        [string]$DataRoot = (Get-HuDefaultDataRoot),
        [bool]$CreateBackup = $true,
        [switch]$SkipAdministratorCheck,
        [switch]$SkipDnsFlush
    )

    if (-not $SkipAdministratorCheck) { Assert-HuAdministrator }
    $paths = Get-HuPaths -DataRoot $DataRoot
    if (-not $BackupPath) {
        $latest = Get-HuBackup -DataRoot $DataRoot | Where-Object { -not $_.IsPreRestore } | Select-Object -First 1
        if (-not $latest) { throw (Get-HuModuleText 'NoBackup') }
        $BackupPath = $latest.Path
    }
    if (-not (Test-Path -LiteralPath $BackupPath -PathType Leaf)) { throw (Get-HuModuleText 'BackupFileMissing') }
    if (-not (Test-HuPathWithinRoot -Root $paths.BackupRoot -Candidate $BackupPath)) {
        throw (Get-HuModuleText 'BackupOutsideManagedFolder')
    }

    if ($PSCmdlet.ShouldProcess($HostsPath, "Restaurer '$BackupPath'")) {
        $currentContent = [IO.File]::ReadAllText($HostsPath)
        $preRestoreBackup = if ($CreateBackup) { New-HuHostsBackup -HostsPath $HostsPath -DataRoot $DataRoot -Prefix 'before-restore' } else { $null }
        try {
            $backupContent = [IO.File]::ReadAllText($BackupPath)
            $restoreContent = Get-HuHostsTextWithTelemetryState -Content $backupContent -DataRoot $DataRoot
            $temporaryPath = Join-Path (Split-Path -Parent $HostsPath) ('hosts.hu.restore.' + [Guid]::NewGuid().ToString('N') + '.tmp')
            try {
                [IO.File]::WriteAllText($temporaryPath, $restoreContent, (New-Object Text.UTF8Encoding($false)))
                Copy-Item -LiteralPath $temporaryPath -Destination $HostsPath -Force -ErrorAction Stop
            }
            finally {
                if (Test-Path -LiteralPath $temporaryPath) { Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue }
            }
            $dnsFlushed = Invoke-HuDnsFlush -SkipDnsFlush:$SkipDnsFlush
            Write-HuLog -DataRoot $DataRoot -Message ("Sauvegarde restaurée : {0}" -f $BackupPath)
            return [pscustomobject]@{
                RestoredFrom     = $BackupPath
                PreRestoreBackup = $preRestoreBackup
                DnsFlushed       = $dnsFlushed
                RestoredAt       = Get-Date
            }
        }
        catch {
            try {
                if ($preRestoreBackup) { Copy-Item -LiteralPath $preRestoreBackup -Destination $HostsPath -Force -ErrorAction SilentlyContinue }
                else { [IO.File]::WriteAllText($HostsPath, $currentContent, (New-Object Text.UTF8Encoding($false))) }
            }
            catch { }
            Write-HuLog -DataRoot $DataRoot -Level ERROR -Message ("Échec de restauration : {0}" -f $_.Exception.Message)
            throw (Format-HuModuleText 'BackupRestoreFailed' @($_.Exception.Message))
        }
    }
}
