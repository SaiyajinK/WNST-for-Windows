$script:SharedRunspacePool = $null
$script:AsyncJobs = @{}
$script:AsyncJobTimer = $null

function Get-HuAsyncExceptionMessage {
    param([object]$Exception)
    if (-not $Exception) { return '' }
    $current=$Exception
    while ($current.InnerException) { $current=$current.InnerException }
    $message=[string]$current.Message
    if ([string]::IsNullOrWhiteSpace($message)) { $message=[string]$Exception.Message }
    return $message
}

function Get-HuSharedRunspacePool {
    if ($script:SharedRunspacePool) { return $script:SharedRunspacePool }
    $pool = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspacePool(1,8)
    $pool.ApartmentState = [Threading.ApartmentState]::MTA
    $pool.Open()
    $script:SharedRunspacePool = $pool
    return $pool
}

function Stop-HuAsyncWork {
    param([Parameter(Mandatory=$true)][string]$Key)
    if (-not $script:AsyncJobs.ContainsKey($Key)) { return }
    $job = $script:AsyncJobs[$Key]
    try { if ($job.Async -and -not $job.Async.IsCompleted) { $job.PowerShell.Stop() } } catch { }
    try { $job.PowerShell.Dispose() } catch { }
    $script:AsyncJobs.Remove($Key)
}

function Start-HuAsyncJobTimer {
    if ($script:AsyncJobTimer) {
        if (-not $script:AsyncJobTimer.IsEnabled) { $script:AsyncJobTimer.Start() }
        return
    }

    $script:AsyncJobTimer = New-Object Windows.Threading.DispatcherTimer
    $script:AsyncJobTimer.Interval = [TimeSpan]::FromMilliseconds(100)
    $script:AsyncJobTimer.Add_Tick({
        if ($script:AsyncJobs.Count -eq 0) {
            $script:AsyncJobTimer.Stop()
            return
        }

        foreach ($key in @($script:AsyncJobs.Keys)) {
            if (-not $script:AsyncJobs.ContainsKey($key)) { continue }
            $job = $script:AsyncJobs[$key]

            if ($job.ProgressQueue -and $job.OnProgress) {
                try {
                    $progressItem = $null
                    while ($job.ProgressQueue.TryDequeue([ref]$progressItem)) {
                        try { & $job.OnProgress $progressItem } catch {}
                        $progressItem = $null
                    }
                }
                catch {}
            }

            $timedOut = ((Get-Date) - $job.StartedAt).TotalSeconds -ge $job.TimeoutSeconds
            if (-not $timedOut -and -not $job.Async.IsCompleted) { continue }

            $output = @()
            $errorMessage = ''
            try {
                if ($timedOut -and -not $job.Async.IsCompleted) {
                    try { $job.PowerShell.Stop() } catch { }
                    $errorMessage = 'Timeout'
                }
                else {
                    $output = @($job.PowerShell.EndInvoke($job.Async))
                    if ($job.PowerShell.Streams.Error.Count -gt 0) {
                        $errorMessage = Get-HuAsyncExceptionMessage $job.PowerShell.Streams.Error[$job.PowerShell.Streams.Error.Count-1].Exception
                    }
                }
            }
            catch {
                $errorMessage=Get-HuAsyncExceptionMessage $_.Exception
                if ($job.PowerShell.Streams.Error.Count -gt 0) {
                    $streamMessage=Get-HuAsyncExceptionMessage $job.PowerShell.Streams.Error[$job.PowerShell.Streams.Error.Count-1].Exception
                    if (-not [string]::IsNullOrWhiteSpace($streamMessage)) { $errorMessage=$streamMessage }
                }
            }
            finally {
                try { $job.PowerShell.Dispose() } catch { }
                $script:AsyncJobs.Remove($key)
            }

            if ($errorMessage) {
                if ($job.OnError) { try { & $job.OnError $errorMessage } catch { } }
            }
            elseif ($job.OnCompleted) {
                try { & $job.OnCompleted $output } catch { }
            }
        }
    })
    $script:AsyncJobTimer.Start()
}

function Invoke-HuAsyncWork {
    param(
        [Parameter(Mandatory=$true)][string]$Key,
        [Parameter(Mandatory=$true)][scriptblock]$ScriptBlock,
        [object[]]$ArgumentList = @(),
        [scriptblock]$OnCompleted,
        [scriptblock]$OnError,
        [scriptblock]$OnProgress,
        [object]$ProgressQueue,
        [int]$TimeoutSeconds = 6,
        [switch]$Replace
    )

    if ($script:AsyncJobs.ContainsKey($Key)) {
        if (-not $Replace) { return $false }
        Stop-HuAsyncWork -Key $Key
    }

    $worker = [System.Management.Automation.PowerShell]::Create()
    $pool = Get-HuSharedRunspacePool
    $worker.RunspacePool = $pool
    [void]$worker.AddScript($ScriptBlock.ToString())
    foreach ($argument in @($ArgumentList)) { [void]$worker.AddArgument($argument) }

    $script:AsyncJobs[$Key] = [pscustomobject]@{
        PowerShell = $worker
        Async = $worker.BeginInvoke()
        StartedAt = Get-Date
        TimeoutSeconds = [math]::Max(1,$TimeoutSeconds)
        OnCompleted = $OnCompleted
        OnError = $OnError
        OnProgress = $OnProgress
        ProgressQueue = $ProgressQueue
    }
    Start-HuAsyncJobTimer
    return $true
}

function Close-HuSharedRunspacePool {
    foreach ($key in @($script:AsyncJobs.Keys)) { Stop-HuAsyncWork -Key $key }
    if ($script:AsyncJobTimer) { try { $script:AsyncJobTimer.Stop() } catch { } }
    if ($script:SharedRunspacePool) {
        try { $script:SharedRunspacePool.Close() } catch { }
        try { $script:SharedRunspacePool.Dispose() } catch { }
    }
    $script:SharedRunspacePool = $null
}
