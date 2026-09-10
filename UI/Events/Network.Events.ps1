$NetstatButton.Add_Click({ Invoke-UtilityToOutput -Button $NetstatButton -OutputBox $NetworkOutputBox -FilePath (Join-Path $env:SystemRoot 'System32\netstat.exe') -Arguments @('-an') })
$IpconfigButton.Add_Click({ Invoke-UtilityToOutput -Button $IpconfigButton -OutputBox $NetworkOutputBox -FilePath (Join-Path $env:SystemRoot 'System32\ipconfig.exe') })
$FlushDnsNowButton.Add_Click({ Invoke-UtilityToOutput -Button $FlushDnsNowButton -OutputBox $NetworkOutputBox -FilePath (Join-Path $env:SystemRoot 'System32\ipconfig.exe') -Arguments @('/flushdns') })
$ReleaseIpButton.Add_Click({ if (Show-AppConfirm (T 'ConfirmReleaseIp')) { Invoke-UtilityToOutput -Button $ReleaseIpButton -OutputBox $NetworkOutputBox -FilePath (Join-Path $env:SystemRoot 'System32\ipconfig.exe') -Arguments @('/release') } })
$RenewIpButton.Add_Click({ Invoke-UtilityToOutput -Button $RenewIpButton -OutputBox $NetworkOutputBox -FilePath (Join-Path $env:SystemRoot 'System32\ipconfig.exe') -Arguments @('/renew') })
$TraceRouteButton.Add_Click({$target=$NetworkTargetBox.Text.Trim().TrimEnd('.');if(-not(Test-PingTarget $target)){Show-AppError (T 'InvalidPingTarget');return};Invoke-UtilityToOutput -Button $TraceRouteButton -OutputBox $NetworkOutputBox -FilePath (Join-Path $env:SystemRoot 'System32\tracert.exe') -Arguments @('-d',$target)})
$NetworkDiagnosticButton.Add_Click({
    $target=$NetworkTargetBox.Text.Trim().TrimEnd('.');if(-not $target){$target='1.1.1.1'};if(-not(Test-PingTarget $target)){Show-AppError (T 'InvalidPingTarget');return}
    $NetworkDiagnosticButton.IsEnabled=$false;$window.Dispatcher.Invoke([Action]{},[Windows.Threading.DispatcherPriority]::Render)
    try{
        $config=Get-NetIPConfiguration -ErrorAction Stop|Where-Object{$_.NetAdapter.Status -eq 'Up'}|Select-Object -First 1
        $test=Test-NetConnection -ComputerName $target -Port 443 -InformationLevel Detailed -WarningAction SilentlyContinue
        $lines=@((TF 'DiagnosticAdapter' @($config.InterfaceAlias)),(TF 'DiagnosticIpv4' @((@($config.IPv4Address.IPAddress)-join ', '))),(TF 'DiagnosticGateway' @((@($config.IPv4DefaultGateway.NextHop)-join ', '))),(TF 'DiagnosticDns' @((@($config.DNSServer.ServerAddresses)-join ', '))),(TF 'DiagnosticTarget' @($target,[bool]$test.TcpTestSucceeded)))
        Add-WnstLogText -Control $NetworkOutputBox -Text ((@(('> ' + (T 'NetworkDiagnosticsTitle') + '    [' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ']'),$lines) | ForEach-Object { [string]$_ }) -join [Environment]::NewLine) -LeadingNewLines 2
    }catch{Add-WnstLogText -Control $NetworkOutputBox -Text ([string]$_.Exception.Message) -Level Error -LeadingNewLines 2}finally{$NetworkDiagnosticButton.IsEnabled=$true}
})
$NetworkDisableButton.Add_Click({
    $state=$NetworkDisableButton.Tag
    if(-not $state){Refresh-NetworkToggleState;return}
    if(-not(Show-AppConfirm (TF 'ConfirmDisableConnection' @($state.Name)))){return}
    try{
        if(-not(Test-HuAdministrator)){throw(T 'AdministratorRequired')}
        $script:NetworkToggleAdapterName=[string]$state.Name
        Disable-NetAdapter -Name $state.Name -Confirm:$false -ErrorAction Stop
        Set-HuNetworkToggleVisualState -AdapterName ([string]$state.Name) -IsEnabled $false
        Show-AppInfo (TF 'ConnectionDisabled' @($state.Name))
    }catch{Show-AppError $_.Exception.Message;Refresh-NetworkToggleState}
})

$NetworkEnableButton.Add_Click({
    $state=$NetworkEnableButton.Tag
    if(-not $state){Refresh-NetworkToggleState;return}
    if(-not(Show-AppConfirm (TF 'ConfirmEnableConnection' @($state.Name)))){return}
    try{
        if(-not(Test-HuAdministrator)){throw(T 'AdministratorRequired')}
        $script:NetworkToggleAdapterName=[string]$state.Name
        Enable-NetAdapter -Name $state.Name -Confirm:$false -ErrorAction Stop
        Set-HuNetworkToggleVisualState -AdapterName ([string]$state.Name) -IsEnabled $true
        Show-AppInfo (TF 'ConnectionEnabled' @($state.Name))
    }catch{Show-AppError $_.Exception.Message;Refresh-NetworkToggleState}
})
$PingButton.Add_Click({
    $target = $PingTargetBox.Text.Trim().TrimEnd('.')
    if (-not (Test-PingTarget $target)) { Show-AppError (T 'InvalidPingTarget'); return }
    $PingButton.IsEnabled = $false
    try{
        $window.Dispatcher.Invoke([Action]{},[Windows.Threading.DispatcherPriority]::Render)
        $resolved = Resolve-HuPingTarget -Target $target
        if(-not [bool]$resolved.Success){
            $detail = if([string]::IsNullOrWhiteSpace([string]$resolved.Error)){T 'DnsTestFailed'}else{('{0} {1}' -f (T 'DnsTestFailed'),[string]$resolved.Error)}
            Add-WnstLogText -Control $PingOutputBox -Text (('> DNS {0}    [{1}]' -f $target,(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')) + "`r`n`r`n" + $detail) -Level Error -LeadingNewLines 2
            return
        }
        if([string]$resolved.Address -ne $target){
            Add-WnstLogText -Control $PingOutputBox -Text ('> DNS {0} -> {1}    [{2}]' -f $target,[string]$resolved.Address,(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')) -LeadingNewLines 2
        }
        Invoke-UtilityToOutput -Button $PingButton -OutputBox $PingOutputBox -FilePath (Join-Path $env:SystemRoot 'System32\PING.EXE') -Arguments @('-n','4','-w','1500',[string]$resolved.Address)
    }
    finally{$PingButton.IsEnabled=$true}
})
$NetworkTargetBox.Add_TextChanged({ Update-NetworkTargetPlaceholders })
$PingTargetBox.Add_TextChanged({ Update-NetworkTargetPlaceholders })
$PingTargetBox.Add_KeyDown({ if ($_.Key -eq [Windows.Input.Key]::Enter) { $PingButton.RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Button]::ClickEvent))) } })
$ClearNetworkLogButton.Add_Click({ Clear-WnstLogContent -Control $NetworkOutputBox })
$ClearPingLogButton.Add_Click({ Clear-WnstLogContent -Control $PingOutputBox })
