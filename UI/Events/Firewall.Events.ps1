$BrowseFirewallProgramsButton.Add_Click({
    try {
        $dialog = New-Object Microsoft.Win32.OpenFileDialog
        $dialog.Title = T 'BrowseApplications'
        $dialog.Filter = T 'ExecutableFilter'
        $dialog.Multiselect = $true
        $dialog.CheckFileExists = $true
        if ($dialog.ShowDialog($window) -eq $true) {
            Add-PendingFirewallPrograms -Paths $dialog.FileNames
        }
    }
    catch { Show-AppError $_.Exception.Message }
})
$BrowseFirewallFolderButton.Add_Click({
    try {
        $shell = New-Object -ComObject Shell.Application
        $selection = $shell.BrowseForFolder(0,(T 'BrowseFolder'),0,0)
        if ($selection -and $selection.Self -and $selection.Self.Path) {
            $folder = [IO.Path]::GetFullPath([string]$selection.Self.Path)
            $executables = @(Get-ChildItem -LiteralPath $folder -Filter '*.exe' -File -ErrorAction SilentlyContinue)
            if ($executables.Count -eq 0) { Show-AppError (T 'NoExecutablesInFolder'); return }
            $script:PendingFirewallFolders = @($script:PendingFirewallFolders + $folder | Select-Object -Unique)
            Refresh-PendingFirewallSelection
        }
    }
    catch { Show-AppError $_.Exception.Message }
})
$FirewallPendingGrid.Add_SelectionChanged({ $RemovePendingFirewallButton.IsEnabled = @($FirewallPendingGrid.SelectedItems).Count -gt 0 })
$RemovePendingFirewallButton.Add_Click({ Remove-SelectedPendingFirewallItems })
$ClearPendingFirewallButton.Add_Click({ $script:PendingFirewallPrograms=@(); $script:PendingFirewallFolders=@(); Refresh-PendingFirewallSelection })
$AddFirewallRulesButton.Add_Click({
    $programs = @(Get-PendingFirewallExecutables)
    $directions = @(); if ($FirewallInboundCheck.IsChecked) { $directions += 'Inbound' }; if ($FirewallOutboundCheck.IsChecked) { $directions += 'Outbound' }
    if ($programs.Count -eq 0) { Show-AppError (T 'NoApplicationsSelected'); return }
    if ($directions.Count -eq 0) { Show-AppError (T 'FirewallDirectionRequired'); return }
    if (-not (Show-AppConfirm (TF 'ConfirmAddFirewallRules' @(($programs.Count * $directions.Count))))) { return }
    try {
        if (-not (Test-HuAdministrator)) { throw (T 'AdministratorRequired') }
        $action = [string]$FirewallActionCombo.SelectedItem.Code
        $profile = [string]$FirewallProfileCombo.SelectedItem.Code
        $existing = @(Get-NetFirewallRule -Group $script:FirewallRuleGroup -ErrorAction SilentlyContinue)
        $existingRows = foreach ($rule in $existing) { $filter=$rule|Get-NetFirewallApplicationFilter -ErrorAction SilentlyContinue|Select-Object -First 1; [pscustomobject]@{Program=[string]$filter.Program;Direction=[string]$rule.Direction;Action=[string]$rule.Action;Profile=[string]$rule.Profile} }
        $created = 0; $skipped = 0
        foreach ($program in $programs) {
            $fullProgram = [IO.Path]::GetFullPath($program)
            foreach ($direction in $directions) {
                $duplicate = $existingRows | Where-Object { $_.Program -ieq $fullProgram -and $_.Direction -eq $direction -and $_.Action -eq $action -and ($_.Profile -eq $profile -or ($profile -eq 'Any' -and $_.Profile -match 'Any|Domain, Private, Public')) } | Select-Object -First 1
                if ($duplicate) { $skipped++; continue }
                $displayDirection = T $(if($direction -eq 'Inbound'){'FirewallInbound'}else{'FirewallOutbound'})
                $displayName = 'WNST · {0} · {1}' -f ([IO.Path]::GetFileNameWithoutExtension($fullProgram)),$displayDirection
                New-NetFirewallRule -Name ('WNST-' + [Guid]::NewGuid().ToString('N')) -DisplayName $displayName -Group $script:FirewallRuleGroup -Description (T 'FirewallRuleDescription') -Program $fullProgram -Direction $direction -Action $action -Profile $profile -Enabled True -ErrorAction Stop | Out-Null
                $created++
            }
        }
        $script:PendingFirewallPrograms=@(); $script:PendingFirewallFolders=@(); Refresh-PendingFirewallSelection; Refresh-FirewallRules -Force
        Show-AppInfo (TF 'FirewallRulesAdded' @($created,$skipped))
    }
    catch { Show-AppError $_.Exception.Message }
})
$FirewallGrid.Add_SelectionChanged({ $has=@($FirewallGrid.SelectedItems).Count -gt 0; $DeleteFirewallRulesButton.IsEnabled=$has; $EnableFirewallRulesButton.IsEnabled=$has; $DisableFirewallRulesButton.IsEnabled=$has })
$FirewallGrid.Add_PreviewMouseRightButtonDown({
    Clear-FirewallContextSelection
    $element=$FirewallGrid.InputHitTest($_.GetPosition($FirewallGrid))
    while($element -and -not ($element -is [Windows.Controls.DataGridRow])){try{$element=[Windows.Media.VisualTreeHelper]::GetParent($element)}catch{$element=[Windows.LogicalTreeHelper]::GetParent($element)}}
    if($element -is [Windows.Controls.DataGridRow]){
        if(-not $element.IsSelected){$FirewallGrid.SelectedItems.Clear();$element.IsSelected=$true}
        $rows=foreach($item in @($FirewallGrid.SelectedItems)){ $row=$FirewallGrid.ItemContainerGenerator.ContainerFromItem($item); if($row){$row.Tag='ContextSelected';$row} }
        $script:ContextSelectedFirewallRows=@($rows)
    }
})
$FirewallGrid.Add_PreviewMouseLeftButtonDown({ Clear-FirewallContextSelection })
$FirewallContextMenu.Add_Opened({ $DeleteFirewallMenuItem.IsEnabled=@($FirewallGrid.SelectedItems).Count -gt 0 })
$FirewallContextMenu.Add_Closed({ Clear-FirewallContextSelection })
$DeleteFirewallMenuItem.Add_Click({ Remove-SelectedFirewallRules })
$DeleteFirewallRulesButton.Add_Click({ Remove-SelectedFirewallRules })
$EnableFirewallRulesButton.Add_Click({ Set-SelectedFirewallRulesEnabled -Enabled $true })
$DisableFirewallRulesButton.Add_Click({ Set-SelectedFirewallRulesEnabled -Enabled $false })
$OpenAdvancedFirewallButton.Add_Click({ Open-HuSystemTool (Join-Path $env:SystemRoot 'System32\wf.msc') })
$RefreshFirewallButton.Add_Click({ Refresh-FirewallRules -Force })
