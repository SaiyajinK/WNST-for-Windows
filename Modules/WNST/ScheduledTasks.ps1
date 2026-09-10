function Get-HuScheduledTaskStatus {
    [CmdletBinding()]
    param()

    foreach ($taskName in @($script:TaskName, $script:LegacyTaskName)) {
        try {
            $task = Get-ScheduledTask -TaskName $taskName -ErrorAction Stop
            $info = Get-ScheduledTaskInfo -TaskName $taskName -ErrorAction SilentlyContinue
            return [pscustomobject]@{
                Exists         = $true
                TaskName       = $taskName
                State          = [string]$task.State
                LastRunTime    = if ($info) { $info.LastRunTime } else { $null }
                NextRunTime    = if ($info) { $info.NextRunTime } else { $null }
                LastTaskResult = if ($info) { $info.LastTaskResult } else { $null }
            }
        }
        catch { }
    }
    return [pscustomobject]@{ Exists = $false; TaskName = $null; State = 'Absent'; LastRunTime = $null; NextRunTime = $null; LastTaskResult = $null }
}

function Install-HuScheduledTask {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$UpdateScriptPath,
        [Parameter(Mandatory = $true)][string]$At
    )

    Assert-HuAdministrator
    if (-not (Test-Path -LiteralPath $UpdateScriptPath -PathType Leaf)) {
        throw (Format-HuModuleText 'ScheduledUpdateScriptMissing' @($UpdateScriptPath))
    }
    $parsedTime = [DateTime]::MinValue
    if (-not [DateTime]::TryParseExact($At, 'HH:mm', [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$parsedTime)) {
        throw (Get-HuModuleText 'UpdateTimeFormatRequired')
    }

    $powershellPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $arguments = '-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" -Scheduled' -f $UpdateScriptPath
    $action = New-ScheduledTaskAction -Execute $powershellPath -Argument $arguments
    $trigger = New-ScheduledTaskTrigger -Daily -At $parsedTime
    $principal = New-ScheduledTaskPrincipal -UserId ([Security.Principal.WindowsIdentity]::GetCurrent().Name) -LogonType Interactive -RunLevel Highest
    $taskSettings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 15)
    try {
        if (Get-ScheduledTask -TaskName $script:LegacyTaskName -ErrorAction Stop) {
            Unregister-ScheduledTask -TaskName $script:LegacyTaskName -Confirm:$false -ErrorAction Stop
        }
    }
    catch { }
    Register-ScheduledTask -TaskName $script:TaskName -Description (Get-HuModuleText 'ScheduledTaskDescription') -Action $action -Trigger $trigger -Principal $principal -Settings $taskSettings -Force -ErrorAction Stop | Out-Null
    Write-HuLog -Message ("Tâche planifiée installée à {0}." -f $At)
    return Get-HuScheduledTaskStatus
}

function Remove-HuScheduledTask {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param()

    Assert-HuAdministrator
    $taskNames = New-Object System.Collections.Generic.List[string]
    foreach ($taskName in @($script:TaskName, $script:LegacyTaskName)) {
        try {
            if (Get-ScheduledTask -TaskName $taskName -ErrorAction Stop) { $taskNames.Add($taskName) }
        }
        catch { }
    }
    if ($taskNames.Count -eq 0) { return $false }
    if (-not $PSCmdlet.ShouldProcess(($taskNames -join ', '), 'Supprimer la tâche planifiée')) { return $false }
    foreach ($taskName in $taskNames) {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction Stop
    }
    Write-HuLog -Message 'Tâche planifiée supprimée.'
    return $true
}
