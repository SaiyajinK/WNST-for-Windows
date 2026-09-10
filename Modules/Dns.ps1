function Set-DnsPageStatus {
    param([AllowEmptyString()][string]$Message,[bool]$IsError=$false)
    $DnsStatusText.Text = $Message
    if ([string]::IsNullOrWhiteSpace($Message)) { $DnsStatusText.Foreground = $window.Resources['MutedBrush']; return }
    $color = if($IsError){'#D13438'}else{'#4CC38A'}
    $DnsStatusText.Foreground = [Windows.Media.SolidColorBrush]::new([Windows.Media.ColorConverter]::ConvertFromString($color))
}

function Get-SelectedDnsAdapter {
    if (-not $DnsAdapterCombo.SelectedItem) { return $null }
    return $DnsAdapterCombo.SelectedItem
}

function Refresh-DnsPresetDetails {
    $preset = $DnsPresetCombo.SelectedItem
    if (-not $preset) { $DnsPresetIpv4Value.Text='—'; $DnsPresetIpv6Value.Text='—'; return }
    $DnsPresetIpv4Value.Text = @($preset.IPv4) -join '  ·  '
    $DnsPresetIpv6Value.Text = @($preset.IPv6) -join '  ·  '
}

function Refresh-DnsCurrentStatus {
    $adapter = Get-SelectedDnsAdapter
    if (-not $adapter) { $CurrentDnsValue.Text=T 'DnsNoAdapter'; return }
    $index=[uint32]$adapter.InterfaceIndex
    if ($script:DnsStatusCache -and [uint32]$script:DnsStatusCache.InterfaceIndex -eq $index) {
        $ipv4Text=if(@($script:DnsStatusCache.IPv4).Count){@($script:DnsStatusCache.IPv4)-join '  ·  '}else{T 'DnsAutomaticOrEmpty'}
        $ipv6Text=if(@($script:DnsStatusCache.IPv6).Count){@($script:DnsStatusCache.IPv6)-join '  ·  '}else{T 'DnsAutomaticOrEmpty'}
        $CurrentDnsValue.Text="IPv4  ·  $ipv4Text`r`nIPv6  ·  $ipv6Text"
    }
    $completed={
        param($output)
        $row=@($output|Where-Object{$_ -and $_.PSObject.Properties['InterfaceIndex']}|Select-Object -Last 1)[0]
        if(-not $row){return}
        if(-not $DnsAdapterCombo.SelectedItem -or [uint32]$DnsAdapterCombo.SelectedItem.InterfaceIndex -ne [uint32]$row.InterfaceIndex){return}
        $script:DnsStatusCache=$row
        $ipv4Text=if(@($row.IPv4).Count){@($row.IPv4)-join '  ·  '}else{T 'DnsAutomaticOrEmpty'}
        $ipv6Text=if(@($row.IPv6).Count){@($row.IPv6)-join '  ·  '}else{T 'DnsAutomaticOrEmpty'}
        $CurrentDnsValue.Text="IPv4  ·  $ipv4Text`r`nIPv6  ·  $ipv6Text"
    }
    $worker={
        param($interfaceIndex)
        $addresses=@(Get-DnsClientServerAddress -InterfaceIndex ([uint32]$interfaceIndex) -ErrorAction Stop)
        $ipv4=@($addresses|Where-Object{[string]$_.AddressFamily -match '^(2|IPv4)$'}|ForEach-Object ServerAddresses|Where-Object{$_})
        $ipv6=@($addresses|Where-Object{[string]$_.AddressFamily -match '^(23|IPv6)$'}|ForEach-Object ServerAddresses|Where-Object{$_})
        [pscustomobject]@{InterfaceIndex=[uint32]$interfaceIndex;IPv4=$ipv4;IPv6=$ipv6}
    }
    [void](Invoke-HuAsyncWork -Key 'Dns.Status' -ScriptBlock $worker -ArgumentList @($index) -OnCompleted $completed -TimeoutSeconds 4 -Replace)
}

function Refresh-DnsAdapters {
    param([switch]$Force)
    $previousIndex=if($DnsAdapterCombo.SelectedItem){[uint32]$DnsAdapterCombo.SelectedItem.InterfaceIndex}else{0}
    if($script:DnsAdaptersCache){
        $rows=@($script:DnsAdaptersCache)
        $DnsAdapterCombo.ItemsSource=$rows
        $selected=$rows|Where-Object InterfaceIndex -eq $previousIndex|Select-Object -First 1
        if(-not $selected){$selected=$rows|Select-Object -First 1}
        $DnsAdapterCombo.SelectedItem=$selected
        if(-not $Force -and $script:DnsAdaptersCacheUpdatedAt -and ((Get-Date)-$script:DnsAdaptersCacheUpdatedAt).TotalSeconds -lt 30){return}
    }
    $completed={
        param($output)
        $rows=@($output|Where-Object{$_ -and $_.PSObject.Properties['InterfaceIndex']})
        $script:DnsAdaptersCache=$rows
        $script:DnsAdaptersCacheUpdatedAt=Get-Date
        $currentIndex=if($DnsAdapterCombo.SelectedItem){[uint32]$DnsAdapterCombo.SelectedItem.InterfaceIndex}else{$previousIndex}
        $DnsAdapterCombo.ItemsSource=$rows
        $selected=$rows|Where-Object InterfaceIndex -eq $currentIndex|Select-Object -First 1
        if(-not $selected){$selected=$rows|Select-Object -First 1}
        $DnsAdapterCombo.SelectedItem=$selected
        if(-not $selected){$CurrentDnsValue.Text=T 'DnsNoAdapter'}
    }.GetNewClosure()
    $failed={param($message) if(-not $script:DnsAdaptersCache){$DnsAdapterCombo.ItemsSource=@();$CurrentDnsValue.Text=T 'DnsNoAdapter'}}
    $worker={
        $rows=@(Get-NetAdapter -ErrorAction Stop|Where-Object{$_.Name -and [string]$_.Status -ne 'Disabled'}|ForEach-Object{[pscustomobject]@{InterfaceIndex=[uint32]$_.ifIndex;Name=[string]$_.Name;Status=[string]$_.Status;DisplayName=('{0}  ·  {1}' -f $_.Name,$_.InterfaceDescription)}}|Sort-Object @{Expression={if($_.Status -eq 'Up'){0}else{1}}},DisplayName)
        if($rows.Count -eq 0){$rows=@(Get-DnsClient -ErrorAction Stop|Where-Object InterfaceAlias|ForEach-Object{[pscustomobject]@{InterfaceIndex=[uint32]$_.InterfaceIndex;Name=[string]$_.InterfaceAlias;Status='';DisplayName=[string]$_.InterfaceAlias}}|Sort-Object DisplayName -Unique)}
        $rows
    }
    [void](Invoke-HuAsyncWork -Key 'Dns.Adapters' -ScriptBlock $worker -OnCompleted $completed -OnError $failed -TimeoutSeconds 5 -Replace)
}

function Test-HuDnsAddress {
    param([AllowEmptyString()][string]$Address,[ValidateSet('IPv4','IPv6')][string]$Family)
    if ([string]::IsNullOrWhiteSpace($Address)) { return $true }
    $parsed = $null
    if (-not [Net.IPAddress]::TryParse($Address.Trim(),[ref]$parsed)) { return $false }
    if ($Family -eq 'IPv4') { return $parsed.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetwork }
    return $parsed.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetworkV6
}

function Set-HuDnsAddressFamily {
    param(
        [Parameter(Mandatory=$true)][uint32]$InterfaceIndex,
        [Parameter(Mandatory=$true)][ValidateSet('IPv4','IPv6')][string]$Family,
        [Parameter(Mandatory=$true)][AllowEmptyCollection()][string[]]$Servers
    )
    $client = Get-DnsClientServerAddress -InterfaceIndex $InterfaceIndex -AddressFamily $Family -ErrorAction Stop
    if (-not $client) { return }
    if (@($Servers).Count -gt 0) {
        $client | Set-DnsClientServerAddress -ServerAddresses @($Servers) -ErrorAction Stop
    }
    else {
        $client | Set-DnsClientServerAddress -ResetServerAddresses -ErrorAction Stop
    }
}

function Set-HuDnsConfiguration {
    param([Parameter(Mandatory=$true)][AllowEmptyCollection()][string[]]$IPv4,[Parameter(Mandatory=$true)][AllowEmptyCollection()][string[]]$IPv6,[Parameter(Mandatory=$true)][string]$Label)
    $adapter = Get-SelectedDnsAdapter
    if (-not $adapter) { Show-AppError (T 'DnsNoAdapter'); return }
    $servers = @($IPv4 + $IPv6 | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.Trim() } | Select-Object -Unique)
    if ($servers.Count -eq 0) { Show-AppError (T 'DnsCustomRequired'); return }
    if (-not (Show-AppConfirm (TF 'ConfirmApplyDns' @($Label,$adapter.Name)))) { return }
    try {
        if (-not (Test-HuAdministrator)) { throw (T 'AdministratorRequired') }
        Set-HuDnsAddressFamily -InterfaceIndex ([uint32]$adapter.InterfaceIndex) -Family IPv4 -Servers @($IPv4)
        Set-HuDnsAddressFamily -InterfaceIndex ([uint32]$adapter.InterfaceIndex) -Family IPv6 -Servers @($IPv6)
        try { Clear-DnsClientCache -ErrorAction Stop } catch { & (Join-Path $env:SystemRoot 'System32\ipconfig.exe') /flushdns | Out-Null }
        Refresh-DnsCurrentStatus
        Set-DnsPageStatus -Message (TF 'DnsApplied' @($adapter.Name))
    }
    catch { Set-DnsPageStatus -Message $_.Exception.Message -IsError $true; Show-AppError $_.Exception.Message }
}
