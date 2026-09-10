$DnsPresetCombo.Add_SelectionChanged({ Refresh-DnsPresetDetails })
$DnsAdapterCombo.Add_SelectionChanged({ Refresh-DnsCurrentStatus; Set-DnsPageStatus -Message '' })
$RefreshDnsAdaptersButton.Add_Click({ Refresh-DnsAdapters -Force; Set-DnsPageStatus -Message '' })
$ApplyDnsPresetButton.Add_Click({
    $preset=$DnsPresetCombo.SelectedItem
    if(-not $preset){Show-AppError (T 'DnsPresetRequired');return}
    Set-HuDnsConfiguration -IPv4 @($preset.IPv4) -IPv6 @($preset.IPv6) -Label ([string]$preset.Name)
})
$ApplyCustomDnsButton.Add_Click({
    $v4=@($DnsIpv4PrimaryBox.Text.Trim(),$DnsIpv4SecondaryBox.Text.Trim())|Where-Object{$_}
    $v6=@($DnsIpv6PrimaryBox.Text.Trim(),$DnsIpv6SecondaryBox.Text.Trim())|Where-Object{$_}
    foreach($address in $v4){if(-not(Test-HuDnsAddress -Address $address -Family IPv4)){Show-AppError (TF 'DnsInvalidAddress' @($address,'IPv4'));return}}
    foreach($address in $v6){if(-not(Test-HuDnsAddress -Address $address -Family IPv6)){Show-AppError (TF 'DnsInvalidAddress' @($address,'IPv6'));return}}
    Set-HuDnsConfiguration -IPv4 $v4 -IPv6 $v6 -Label (T 'CustomDnsTitle')
})
$ResetAutomaticDnsButton.Add_Click({
    $adapter=Get-SelectedDnsAdapter
    if(-not $adapter){Show-AppError (T 'DnsNoAdapter');return}
    if(-not(Show-AppConfirm (TF 'ConfirmResetDns' @($adapter.Name)))){return}
    try{if(-not(Test-HuAdministrator)){throw(T 'AdministratorRequired')};Set-HuDnsAddressFamily -InterfaceIndex ([uint32]$adapter.InterfaceIndex) -Family IPv4 -Servers @();Set-HuDnsAddressFamily -InterfaceIndex ([uint32]$adapter.InterfaceIndex) -Family IPv6 -Servers @();try{Clear-DnsClientCache -ErrorAction Stop}catch{};Refresh-DnsCurrentStatus;Set-DnsPageStatus -Message (TF 'DnsResetSuccess' @($adapter.Name))}catch{Set-DnsPageStatus -Message $_.Exception.Message -IsError $true;Show-AppError $_.Exception.Message}
})
$TestDnsButton.Add_Click({
    try{$answer=Resolve-DnsName -Name 'example.com' -DnsOnly -ErrorAction Stop|Where-Object IPAddress|Select-Object -First 1;if(-not $answer){throw(T 'DnsTestFailed')};Set-DnsPageStatus -Message (TF 'DnsTestSuccess' @($answer.IPAddress))}catch{Set-DnsPageStatus -Message (T 'DnsTestFailed') -IsError $true}
})
$FlushDnsPageButton.Add_Click({try{Clear-DnsClientCache -ErrorAction Stop;Set-DnsPageStatus -Message (T 'DnsCacheCleared')}catch{Set-DnsPageStatus -Message $_.Exception.Message -IsError $true;Show-AppError $_.Exception.Message}})
