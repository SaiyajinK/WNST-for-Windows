# WNST - actions communes pour les journaux persistants

function Get-WnstLogSnapshotPath {
    param([Parameter(Mandatory=$true)][string]$Name)
    return (Get-WnstPersistentLogPath -Name $Name)
}

function Write-WnstLogTextFile {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [AllowEmptyString()][string]$Text
    )

    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        [void](New-Item -ItemType Directory -Path $parent -Force)
    }
    [IO.File]::WriteAllText($Path,[string]$Text,(New-Object Text.UTF8Encoding($true)))
}

function Export-WnstLogSnapshot {
    param(
        [Parameter(Mandatory=$true)][object]$TextBox,
        [Parameter(Mandatory=$true)][string]$Name
    )

    try {
        $dialog = New-Object Microsoft.Win32.SaveFileDialog
        $dialog.Title = T 'ExportLog'
        $dialog.Filter = ('{0} (*.log)|*.log|{1} (*.txt)|*.txt|{2} (*.*)|*.*' -f (T 'LogFileFilter'),(T 'TextFileFilter'),(T 'AllFilesFilter'))
        $dialog.DefaultExt = '.log'
        $dialog.AddExtension = $true
        $dialog.FileName = ('WNST-{0}-{1}.log' -f $Name,(Get-Date -Format 'yyyyMMdd-HHmmss'))
        if ($dialog.ShowDialog($window) -eq $true) {
            $sourcePath = Get-WnstLogSnapshotPath -Name $Name
            $content = if (Test-Path -LiteralPath $sourcePath -PathType Leaf) {
                [IO.File]::ReadAllText($sourcePath,[Text.Encoding]::UTF8)
            }
            else { Get-WnstLogText -Control $TextBox }
            Write-WnstLogTextFile -Path ([string]$dialog.FileName) -Text $content
        }
    }
    catch { Show-AppError $_.Exception.Message }
}

function Open-WnstLogSnapshot {
    param(
        [Parameter(Mandatory=$true)][object]$TextBox,
        [Parameter(Mandatory=$true)][string]$Name
    )

    try {
        $path = Get-WnstLogSnapshotPath -Name $Name
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            Write-WnstLogTextFile -Path $path -Text (Get-WnstLogText -Control $TextBox)
        }
        Start-Process -FilePath 'notepad.exe' -ArgumentList @(('"{0}"' -f $path)) | Out-Null
    }
    catch { Show-AppError $_.Exception.Message }
}

function Open-WnstLogFolder {
    param([Parameter(Mandatory=$true)][string]$Name)

    try {
        $path = Get-WnstLogSnapshotPath -Name $Name
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            Write-WnstLogTextFile -Path $path -Text ''
        }
        Start-Process -FilePath 'explorer.exe' -ArgumentList @(('/select,"{0}"' -f $path)) | Out-Null
    }
    catch { Show-AppError $_.Exception.Message }
}

$ExportNetworkLogButton.Add_Click({ Export-WnstLogSnapshot -TextBox $NetworkOutputBox -Name 'Network' })
$OpenNetworkLogButton.Add_Click({ Open-WnstLogSnapshot -TextBox $NetworkOutputBox -Name 'Network' })
$OpenNetworkLogFolderButton.Add_Click({ Open-WnstLogFolder -Name 'Network' })
$ExportPingLogButton.Add_Click({ Export-WnstLogSnapshot -TextBox $PingOutputBox -Name 'Ping' })
$OpenPingLogButton.Add_Click({ Open-WnstLogSnapshot -TextBox $PingOutputBox -Name 'Ping' })
$OpenPingLogFolderButton.Add_Click({ Open-WnstLogFolder -Name 'Ping' })
$ExportAppxLogButton.Add_Click({ Export-WnstLogSnapshot -TextBox $AppxLogBox -Name 'AppX' })
$OpenAppxLogButton.Add_Click({ Open-WnstLogSnapshot -TextBox $AppxLogBox -Name 'AppX' })
$OpenAppxLogFolderButton.Add_Click({ Open-WnstLogFolder -Name 'AppX' })
$ExportAdvancedLogButton.Add_Click({ Export-WnstLogSnapshot -TextBox $AdvancedLogBox -Name 'Advanced' })
$OpenAdvancedLogButton.Add_Click({ Open-WnstLogSnapshot -TextBox $AdvancedLogBox -Name 'Advanced' })
$OpenAdvancedLogFolderButton.Add_Click({ Open-WnstLogFolder -Name 'Advanced' })
$ExportIntegrityLogButton.Add_Click({ Export-WnstLogSnapshot -TextBox $IntegrityOutputBox -Name 'Integrity' })
$OpenIntegrityLogButton.Add_Click({ Open-WnstLogSnapshot -TextBox $IntegrityOutputBox -Name 'Integrity' })
$OpenIntegrityLogFolderButton.Add_Click({ Open-WnstLogFolder -Name 'Integrity' })
$ExportPerformanceLogButton.Add_Click({ Export-WnstLogSnapshot -TextBox $PerformanceOutputBox -Name 'Performance' })
$OpenPerformanceLogButton.Add_Click({ Open-WnstLogSnapshot -TextBox $PerformanceOutputBox -Name 'Performance' })
$OpenPerformanceLogFolderButton.Add_Click({ Open-WnstLogFolder -Name 'Performance' })
$ExportWindowsLogButton.Add_Click({ Export-WnstLogSnapshot -TextBox $WindowsOutputBox -Name 'Windows' })
$OpenWindowsLogButton.Add_Click({ Open-WnstLogSnapshot -TextBox $WindowsOutputBox -Name 'Windows' })
$OpenWindowsLogFolderButton.Add_Click({ Open-WnstLogFolder -Name 'Windows' })
$ExportCleanupLogButton.Add_Click({ Export-WnstLogSnapshot -TextBox $CleanupOutputBox -Name 'Cleanup' })
$OpenCleanupLogButton.Add_Click({ Open-WnstLogSnapshot -TextBox $CleanupOutputBox -Name 'Cleanup' })
$OpenCleanupLogFolderButton.Add_Click({ Open-WnstLogFolder -Name 'Cleanup' })
