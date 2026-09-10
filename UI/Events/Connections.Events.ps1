$ConnectionsGrid.Add_SelectionChanged({
    $row=$ConnectionsGrid.SelectedItem; $has=[bool]$row
    $OpenConnectionLocationButton.IsEnabled=$has -and -not [string]::IsNullOrWhiteSpace([string]$row.Path)
    $StopConnectionProcessButton.IsEnabled=$has -and [uint32]$row.PID -notin @(0,4,[uint32]$PID)
    $ConnectionToFirewallButton.IsEnabled=$has -and -not [string]::IsNullOrWhiteSpace([string]$row.Path)
})
$ConnectionsGrid.Add_PreviewMouseRightButtonDown({
    $element=$ConnectionsGrid.InputHitTest($_.GetPosition($ConnectionsGrid))
    while($element -and -not($element -is [Windows.Controls.DataGridRow])){try{$element=[Windows.Media.VisualTreeHelper]::GetParent($element)}catch{$element=$null}}
    if($element -is [Windows.Controls.DataGridRow]){$ConnectionsGrid.SelectedItem=$element.Item}
})
$ConnectionsContextMenu.Add_Opened({
    $row=$ConnectionsGrid.SelectedItem; $has=[bool]$row
    $ConnectionOpenLocationMenuItem.IsEnabled=$has -and -not [string]::IsNullOrWhiteSpace([string]$row.Path)
    $ConnectionStopMenuItem.IsEnabled=$has -and [uint32]$row.PID -notin @(0,4,[uint32]$PID)
    $ConnectionFirewallMenuItem.IsEnabled=$has -and -not [string]::IsNullOrWhiteSpace([string]$row.Path)
    $ConnectionPingMenuItem.IsEnabled=$has -and -not [string]::IsNullOrWhiteSpace([string]$row.RemoteAddress)
})
$openConnectionLocation={if($ConnectionsGrid.SelectedItem){Open-HuProgramLocation -Path ([string]$ConnectionsGrid.SelectedItem.Path)}}
$stopConnectionProcess={
    $row=$ConnectionsGrid.SelectedItem;if(-not $row){return};$targetPid=[uint32]$row.PID
    if($targetPid -in @(0,4,[uint32]$PID)){Show-AppError (T 'ProtectedProcess');return}
    if(-not(Show-AppConfirm (TF 'ConfirmStopProcess' @($row.ProcessName,$targetPid)))){return}
    try{Stop-Process -Id $targetPid -Force -ErrorAction Stop;Show-AppInfo (TF 'ProcessStopped' @($row.ProcessName));Refresh-ConnectionsList -Force}catch{Show-AppError $_.Exception.Message}
}
$sendConnectionFirewall={if($ConnectionsGrid.SelectedItem){Send-HuProgramToFirewall -Path ([string]$ConnectionsGrid.SelectedItem.Path)}}
$pingConnection={if($ConnectionsGrid.SelectedItem){$PingTargetBox.Text=[string]$ConnectionsGrid.SelectedItem.RemoteAddress;$NetworkTargetBox.Text=$PingTargetBox.Text;Show-Page Network;$PingButton.RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Button]::ClickEvent)))}}
$OpenConnectionLocationButton.Add_Click($openConnectionLocation);$ConnectionOpenLocationMenuItem.Add_Click($openConnectionLocation)
$StopConnectionProcessButton.Add_Click($stopConnectionProcess);$ConnectionStopMenuItem.Add_Click($stopConnectionProcess)
$ConnectionToFirewallButton.Add_Click($sendConnectionFirewall);$ConnectionFirewallMenuItem.Add_Click($sendConnectionFirewall)
$ConnectionPingMenuItem.Add_Click($pingConnection);$RefreshConnectionsButton.Add_Click({Refresh-ConnectionsList -Force})

$OpenPortsGrid.Add_SelectionChanged({$OpenPortToFirewallButton.IsEnabled=$OpenPortsGrid.SelectedItem -and -not [string]::IsNullOrWhiteSpace([string]$OpenPortsGrid.SelectedItem.Path)})
$OpenPortsGrid.Add_PreviewMouseRightButtonDown({$element=$OpenPortsGrid.InputHitTest($_.GetPosition($OpenPortsGrid));while($element -and -not($element -is [Windows.Controls.DataGridRow])){try{$element=[Windows.Media.VisualTreeHelper]::GetParent($element)}catch{$element=$null}};if($element -is [Windows.Controls.DataGridRow]){$OpenPortsGrid.SelectedItem=$element.Item}})
$OpenPortsContextMenu.Add_Opened({$OpenPortFirewallMenuItem.IsEnabled=$OpenPortsGrid.SelectedItem -and -not [string]::IsNullOrWhiteSpace([string]$OpenPortsGrid.SelectedItem.Path)})
$sendPortFirewall={if($OpenPortsGrid.SelectedItem){Send-HuProgramToFirewall -Path ([string]$OpenPortsGrid.SelectedItem.Path)}}
$OpenPortToFirewallButton.Add_Click($sendPortFirewall);$OpenPortFirewallMenuItem.Add_Click($sendPortFirewall);$RefreshOpenPortsButton.Add_Click({Refresh-OpenPorts -Force})
$EnableProxyButton.Add_Click({Set-HuProxyEnabled -Enabled $true});$DisableProxyButton.Add_Click({Set-HuProxyEnabled -Enabled $false});$ResetProxyButton.Add_Click({Set-HuProxyEnabled -Enabled $false -Reset $true})

