function Update-NetworkTargetPlaceholders {
    $NetworkTargetPlaceholder.Visibility = if ([string]::IsNullOrWhiteSpace($NetworkTargetBox.Text)) { 'Visible' } else { 'Collapsed' }
    $PingTargetPlaceholder.Visibility = if ([string]::IsNullOrWhiteSpace($PingTargetBox.Text)) { 'Visible' } else { 'Collapsed' }
}

function Resolve-HuPingTarget {
    param([Parameter(Mandatory=$true)][string]$Target)

    $ip = $null
    if ([Net.IPAddress]::TryParse($Target,[ref]$ip)) {
        return [pscustomobject]@{ Success=$true; Original=$Target; Address=$ip.ToString(); Resolver=''; Error='' }
    }

    $lastError = ''
    for($attempt=0;$attempt -lt 3;$attempt++){
        try{
            $addresses = @(
                Resolve-DnsName -Name $Target -QuickTimeout -ErrorAction Stop |
                    Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.IPAddress) } |
                    ForEach-Object { [string]$_.IPAddress } |
                    Sort-Object @{Expression={if($_ -match ':'){1}else{0}}},@{Expression={$_}} -Unique
            )
            if($addresses.Count -gt 0){
                return [pscustomobject]@{Success=$true;Original=$Target;Address=$addresses[0];Resolver='Windows';Error=''}
            }
            $lastError = 'NoAddress'
        }
        catch{$lastError=[string]$_.Exception.Message}
        if($attempt -lt 2){Start-Sleep -Milliseconds 250}
    }

    # If Windows' combined resolver fails intermittently, query each DNS server
    # already configured on active adapters. This improves reliability without
    # switching to, or leaking queries toward, an external public resolver.
    try{
        $activeIndexes = @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object Status -eq 'Up' | ForEach-Object { [uint32]$_.ifIndex })
        $dnsServers = @(
            Get-DnsClientServerAddress -ErrorAction SilentlyContinue |
                Where-Object { $activeIndexes.Count -eq 0 -or [uint32]$_.InterfaceIndex -in $activeIndexes } |
                ForEach-Object { @($_.ServerAddresses) } |
                Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
                Select-Object -Unique -First 6
        )
        foreach($server in $dnsServers){
            try{
                $addresses = @(
                    Resolve-DnsName -Name $Target -Server ([string]$server) -DnsOnly -QuickTimeout -ErrorAction Stop |
                        Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.IPAddress) } |
                        ForEach-Object { [string]$_.IPAddress } |
                        Sort-Object @{Expression={if($_ -match ':'){1}else{0}}},@{Expression={$_}} -Unique
                )
                if($addresses.Count -gt 0){return [pscustomobject]@{Success=$true;Original=$Target;Address=$addresses[0];Resolver=[string]$server;Error=''}}
            }
            catch{$lastError=[string]$_.Exception.Message}
        }
    }
    catch{}

    # Compatibility fallback for Windows editions where Resolve-DnsName is not
    # available. It still honors the computer's configured DNS servers.
    try{
        $addresses = @([Net.Dns]::GetHostAddresses($Target) | Sort-Object @{Expression={if($_.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetwork){0}else{1}}})
        if($addresses.Count -gt 0){return [pscustomobject]@{Success=$true;Original=$Target;Address=$addresses[0].ToString();Resolver='Windows';Error=''}}
    }
    catch{$lastError=[string]$_.Exception.Message}

    return [pscustomobject]@{Success=$false;Original=$Target;Address='';Resolver='';Error=$lastError}
}

function Set-HuNetworkToggleVisualState {
    param([string]$AdapterName,[bool]$IsEnabled)

    $state=[pscustomobject]@{Name=$AdapterName}
    $NetworkEnableButton.Tag=$state
    $NetworkDisableButton.Tag=$state

    if($IsEnabled){
        $NetworkEnableButton.Content=T 'Enabled'
        $NetworkEnableButton.IsEnabled=$false
        $NetworkEnableButton.Opacity=0.42
        $NetworkDisableButton.Content=T 'Disable'
        $NetworkDisableButton.IsEnabled=$true
        $NetworkDisableButton.Opacity=1.0
    }
    else{
        $NetworkEnableButton.Content=T 'Enable'
        $NetworkEnableButton.IsEnabled=$true
        $NetworkEnableButton.Opacity=1.0
        $NetworkDisableButton.Content=T 'Disabled'
        $NetworkDisableButton.IsEnabled=$false
        $NetworkDisableButton.Opacity=0.42
    }

    $NetworkToggleHint.Text=TF 'NetworkToggleHint' @($AdapterName)
}

function Refresh-NetworkToggleState {
    param([switch]$Force)
    if ($script:NetworkToggleStateCache) {
        $cached = $script:NetworkToggleStateCache
        if ($cached.Name) { Set-HuNetworkToggleVisualState -AdapterName ([string]$cached.Name) -IsEnabled ([bool]$cached.IsEnabled) }
        if (-not $Force -and $script:NetworkToggleStateUpdatedAt -and ((Get-Date)-$script:NetworkToggleStateUpdatedAt).TotalSeconds -lt 5) { return }
    }

    $completed = {
        param($output)
        $adapter = @($output | Where-Object { $_ -and $_.PSObject.Properties['Name'] } | Select-Object -Last 1)[0]
        if (-not $adapter) {
            $script:NetworkToggleStateCache = $null
            $NetworkEnableButton.Content=T 'Enable'; $NetworkDisableButton.Content=T 'Disable'
            $NetworkEnableButton.IsEnabled=$false; $NetworkDisableButton.IsEnabled=$false
            $NetworkEnableButton.Opacity=0.42; $NetworkDisableButton.Opacity=0.42
            $NetworkEnableButton.Tag=$null; $NetworkDisableButton.Tag=$null
            $NetworkToggleHint.Text=T 'NoActiveConnection'
            return
        }
        $script:NetworkToggleStateCache = $adapter
        $script:NetworkToggleStateUpdatedAt = Get-Date
        $script:NetworkToggleAdapterName = [string]$adapter.Name
        Set-HuNetworkToggleVisualState -AdapterName ([string]$adapter.Name) -IsEnabled ([bool]$adapter.IsEnabled)
    }

    $worker = {
        param($trackedName)
        $adapter = $null
        if (-not [string]::IsNullOrWhiteSpace([string]$trackedName)) {
            $adapter = Get-NetAdapter -Name $trackedName -ErrorAction SilentlyContinue | Select-Object -First 1
        }
        if (-not $adapter) {
            try {
                $route = Get-NetRoute -AddressFamily IPv4 -DestinationPrefix '0.0.0.0/0' -ErrorAction Stop |
                    Where-Object { $_.State -ne 'Invalid' } | Sort-Object RouteMetric,InterfaceMetric | Select-Object -First 1
                if ($route) { $adapter = Get-NetAdapter -InterfaceIndex ([uint32]$route.InterfaceIndex) -ErrorAction SilentlyContinue | Select-Object -First 1 }
            } catch { }
        }
        if (-not $adapter) { $adapter = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object Status -eq 'Up' | Sort-Object ifIndex | Select-Object -First 1 }
        if ($adapter) { [pscustomobject]@{ Name=[string]$adapter.Name; IsEnabled=([string]$adapter.Status -eq 'Up') } }
    }
    [void](Invoke-HuAsyncWork -Key 'Network.Toggle' -ScriptBlock $worker -ArgumentList @([string]$script:NetworkToggleAdapterName) -OnCompleted $completed -TimeoutSeconds 4 -Replace)
}

function Refresh-ConnectionsList {
    param([switch]$Force)
    if (-not $ConnectionsGrid) { return }
    if ($script:ConnectionsCache) {
        $ConnectionsGrid.ItemsSource = @($script:ConnectionsCache)
        if (-not $Force -and $script:ConnectionsCacheUpdatedAt -and ((Get-Date)-$script:ConnectionsCacheUpdatedAt).TotalSeconds -lt 10) { return }
    }
    $RefreshConnectionsButton.IsEnabled = $false

    $completed = {
        param($output)
        $rows = @($output | Where-Object { $_ -and $_.PSObject.Properties['RemoteEndpoint'] })
        $script:ConnectionsCache = $rows
        $script:ConnectionsCacheUpdatedAt = Get-Date
        $ConnectionsGrid.ItemsSource = $rows
        $RefreshConnectionsButton.IsEnabled = $true
    }
    $failed = { param($message) $RefreshConnectionsButton.IsEnabled = $true }
    $worker = {
        $identityCache = @{}
        foreach ($connection in @(Get-NetTCPConnection -ErrorAction Stop | Where-Object {
            $_.State -in @('Established','SynSent','SynReceived','CloseWait') -and
            $_.RemoteAddress -notin @('0.0.0.0','::','127.0.0.1','::1')
        } | Sort-Object OwningProcess,RemoteAddress,RemotePort)) {
            $pidValue = [uint32]$connection.OwningProcess
            if (-not $identityCache.ContainsKey($pidValue)) {
                $name=''; $path=''
                if ($pidValue -eq 0) { $name='System' }
                else {
                    try {
                        $process=Get-Process -Id $pidValue -ErrorAction Stop
                        $name=[string]$process.ProcessName
                        try { $path=[string]$process.Path } catch { }
                    } catch { }
                    if ([string]::IsNullOrWhiteSpace($path)) {
                        try { $path=[string](Get-CimInstance Win32_Process -Filter "ProcessId=$pidValue" -Property ExecutablePath -ErrorAction Stop).ExecutablePath } catch { }
                    }
                }
                $identityCache[$pidValue]=[pscustomobject]@{Name=$name;Path=$path}
            }
            $identity=$identityCache[$pidValue]
            $remoteAddress=[string]$connection.RemoteAddress
            $remotePort=[uint16]$connection.RemotePort
            $endpoint=if($remoteAddress.Contains(':')){'[{0}]:{1}' -f $remoteAddress,$remotePort}else{'{0}:{1}' -f $remoteAddress,$remotePort}
            [pscustomobject]@{
                ProcessName=[string]$identity.Name; PID=$pidValue; RemoteAddress=$remoteAddress; RemotePort=$remotePort
                RemoteEndpoint=$endpoint; Protocol='TCP'; State=[string]$connection.State; Path=[string]$identity.Path
            }
        }
    }
    [void](Invoke-HuAsyncWork -Key 'Page.Connections' -ScriptBlock $worker -OnCompleted $completed -OnError $failed -TimeoutSeconds 6 -Replace)
}

function Open-HuProgramLocation {
    param([AllowEmptyString()][string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { Show-AppError (T 'ProgramPathUnavailable'); return }
    try { Start-Process -FilePath (Join-Path $env:SystemRoot 'explorer.exe') -ArgumentList ('/select,"{0}"' -f $Path) }
    catch { Show-AppError $_.Exception.Message }
}

function Send-HuProgramToFirewall {
    param([AllowEmptyString()][string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf) -or [IO.Path]::GetExtension($Path) -ine '.exe') { Show-AppError (T 'ProgramPathUnavailable'); return }
    Add-PendingFirewallPrograms -Paths @($Path)
    Show-Page Firewall
    $FirewallPendingPanel.BringIntoView()
}

function Refresh-OpenPorts {
    param([switch]$Force)
    if (-not $OpenPortsGrid) { return }
    if ($script:OpenPortsCache) {
        $OpenPortsGrid.ItemsSource = @($script:OpenPortsCache)
        if (-not $Force -and $script:OpenPortsCacheUpdatedAt -and ((Get-Date)-$script:OpenPortsCacheUpdatedAt).TotalSeconds -lt 30) { return }
    }
    $RefreshOpenPortsButton.IsEnabled = $false

    $completed = {
        param($output)
        $rows = @($output | Where-Object { $_ -and $_.PSObject.Properties['LocalPort'] })
        $script:OpenPortsCache = $rows
        $script:OpenPortsCacheUpdatedAt = Get-Date
        $OpenPortsGrid.ItemsSource = $rows
        $RefreshOpenPortsButton.IsEnabled = $true
    }
    $failed = { param($message) $RefreshOpenPortsButton.IsEnabled = $true }
    $worker = {
        $identityCache=@{}
        $raw=New-Object System.Collections.Generic.List[object]
        foreach($item in @(Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue)){$raw.Add([pscustomobject]@{Protocol='TCP';LocalAddress=[string]$item.LocalAddress;LocalPort=[uint16]$item.LocalPort;PID=[uint32]$item.OwningProcess})}
        foreach($item in @(Get-NetUDPEndpoint -ErrorAction SilentlyContinue)){$raw.Add([pscustomobject]@{Protocol='UDP';LocalAddress=[string]$item.LocalAddress;LocalPort=[uint16]$item.LocalPort;PID=[uint32]$item.OwningProcess})}
        foreach($item in @($raw|Sort-Object LocalPort,Protocol -Unique)){
            if(-not $identityCache.ContainsKey($item.PID)){
                $name='';$path=''
                if([uint32]$item.PID -eq 0){$name='System'}else{
                    try{$process=Get-Process -Id ([uint32]$item.PID) -ErrorAction Stop;$name=[string]$process.ProcessName;try{$path=[string]$process.Path}catch{}}catch{}
                    if([string]::IsNullOrWhiteSpace($path)){try{$path=[string](Get-CimInstance Win32_Process -Filter ("ProcessId={0}" -f [uint32]$item.PID) -Property ExecutablePath -ErrorAction Stop).ExecutablePath}catch{}}
                }
                $identityCache[$item.PID]=[pscustomobject]@{Name=$name;Path=$path}
            }
            $identity=$identityCache[$item.PID]
            [pscustomobject]@{Protocol=$item.Protocol;LocalAddress=$item.LocalAddress;LocalPort=$item.LocalPort;ProcessName=[string]$identity.Name;PID=$item.PID;Path=[string]$identity.Path}
        }
    }
    [void](Invoke-HuAsyncWork -Key 'Page.OpenPorts' -ScriptBlock $worker -OnCompleted $completed -OnError $failed -TimeoutSeconds 6 -Replace)
}

function Refresh-ProxyStatus {
    if (-not $ProxyStatusText) { return }
    try {
        $settings=Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction Stop
        $enabled=[int]$settings.ProxyEnable -eq 1
        $server=[string]$settings.ProxyServer
        if ($enabled -and $server) {
            $ProxyStatusText.Text=TF 'ProxyEnabledStatus' @($server)
            $parts=$server -split ':',2
            if($parts.Count -eq 2 -and $parts[1] -match '^\d+$'){$ProxyHostBox.Text=$parts[0];$ProxyPortBox.Text=$parts[1]}
        }
        else { $ProxyStatusText.Text=T 'ProxyDisabledStatus' }
    }
    catch { $ProxyStatusText.Text=T 'ProxyDisabledStatus' }
}

function Notify-HuInternetSettingsChanged {
    try {
        if (-not ('WNST.WinInetNative' -as [type])) {
            Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; namespace WNST { public static class WinInetNative { [DllImport("wininet.dll", SetLastError=true)] public static extern bool InternetSetOption(IntPtr h, int o, IntPtr b, int l); } }' -ErrorAction Stop
        }
        [void][WNST.WinInetNative]::InternetSetOption([IntPtr]::Zero,39,[IntPtr]::Zero,0)
        [void][WNST.WinInetNative]::InternetSetOption([IntPtr]::Zero,37,[IntPtr]::Zero,0)
    } catch { }
}

function Set-HuProxyEnabled {
    param([bool]$Enabled,[bool]$Reset=$false)
    $key='HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
    if ($Enabled) {
        $hostValue=$ProxyHostBox.Text.Trim(); $portValue=$ProxyPortBox.Text.Trim(); $port=0
        if ($hostValue -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$' -or -not [int]::TryParse($portValue,[ref]$port) -or $port -lt 1 -or $port -gt 65535) { Show-AppError (T 'InvalidProxy'); return }
        if (-not (Show-AppConfirm (TF 'ConfirmEnableProxy' @($hostValue,$port)))) { return }
        try { Set-ItemProperty -LiteralPath $key -Name ProxyServer -Value ("$hostValue`:$port") -Type String -ErrorAction Stop; Set-ItemProperty -LiteralPath $key -Name ProxyEnable -Value 1 -Type DWord -ErrorAction Stop }
        catch { Show-AppError $_.Exception.Message; return }
    }
    elseif ($Reset) {
        if (-not (Show-AppConfirm (T 'ConfirmResetProxy'))) { return }
        try { Set-ItemProperty -LiteralPath $key -Name ProxyEnable -Value 0 -Type DWord -ErrorAction Stop; Remove-ItemProperty -LiteralPath $key -Name ProxyServer -ErrorAction SilentlyContinue; Remove-ItemProperty -LiteralPath $key -Name ProxyOverride -ErrorAction SilentlyContinue; $ProxyHostBox.Clear();$ProxyPortBox.Clear() }
        catch { Show-AppError $_.Exception.Message; return }
    }
    else {
        if (-not (Show-AppConfirm (T 'ConfirmDisableProxy'))) { return }
        try { Set-ItemProperty -LiteralPath $key -Name ProxyEnable -Value 0 -Type DWord -ErrorAction Stop }
        catch { Show-AppError $_.Exception.Message; return }
    }
    Notify-HuInternetSettingsChanged
    Refresh-ProxyStatus
}
