function Clear-FirewallContextSelection {
    foreach ($row in @($script:ContextSelectedFirewallRows)) { if ($row) { $row.Tag = $null } }
    $script:ContextSelectedFirewallRows = @()
}

function Get-PendingFirewallExecutables {
    $programs = @()
    foreach ($path in @($script:PendingFirewallPrograms)) {
        if (Test-Path -LiteralPath $path -PathType Leaf) { $programs += [IO.Path]::GetFullPath($path) }
    }
    foreach ($folder in @($script:PendingFirewallFolders)) {
        if (-not (Test-Path -LiteralPath $folder -PathType Container)) { continue }
        foreach ($file in @(Get-ChildItem -LiteralPath $folder -Filter '*.exe' -File -ErrorAction SilentlyContinue)) { $programs += $file.FullName }
    }
    return @($programs | Select-Object -Unique)
}

function Refresh-PendingFirewallSelection {
    $rows = @()
    foreach ($path in @($script:PendingFirewallPrograms)) {
        $rows += [pscustomobject]@{ Kind='Application'; Name=[IO.Path]::GetFileName($path); Path=$path }
    }
    foreach ($path in @($script:PendingFirewallFolders)) {
        $rows += [pscustomobject]@{ Kind='Folder'; Name=(TF 'SelectedFolderName' @([IO.Path]::GetFileName($path.TrimEnd('\')))); Path=$path }
    }
    $FirewallPendingGrid.ItemsSource = @($rows)
    $count = $rows.Count
    $FirewallPendingPanel.Visibility = if ($count -gt 0) { 'Visible' } else { 'Collapsed' }
    $FirewallProgramBox.Text = if ($count -gt 0) { TF 'FirewallItemsSelected' @($count) } else { T 'NoApplicationsSelected' }
    $RemovePendingFirewallButton.IsEnabled = $false
    $ClearPendingFirewallButton.IsEnabled = $count -gt 0
}

function Add-PendingFirewallPrograms {
    param([string[]]$Paths)
    $valid = @($Paths | Where-Object { $_ -and [IO.Path]::GetExtension($_) -ieq '.exe' -and (Test-Path -LiteralPath $_ -PathType Leaf) } | ForEach-Object { [IO.Path]::GetFullPath($_) })
    $script:PendingFirewallPrograms = @($script:PendingFirewallPrograms + $valid | Select-Object -Unique)
    Refresh-PendingFirewallSelection
}

function Remove-SelectedPendingFirewallItems {
    $selected = @($FirewallPendingGrid.SelectedItems)
    if ($selected.Count -eq 0) { return }
    $applicationPaths = @($selected | Where-Object Kind -eq 'Application' | ForEach-Object Path)
    $folderPaths = @($selected | Where-Object Kind -eq 'Folder' | ForEach-Object Path)
    $script:PendingFirewallPrograms = @($script:PendingFirewallPrograms | Where-Object { $_ -notin $applicationPaths })
    $script:PendingFirewallFolders = @($script:PendingFirewallFolders | Where-Object { $_ -notin $folderPaths })
    Refresh-PendingFirewallSelection
}

function Refresh-FirewallRules {
    param([switch]$Force)
    if ($script:FirewallRulesCache) {
        $FirewallGrid.ItemsSource = @($script:FirewallRulesCache)
        if (-not $Force -and $script:FirewallRulesCacheUpdatedAt -and ((Get-Date)-$script:FirewallRulesCacheUpdatedAt).TotalSeconds -lt 30) { return }
    }
    $completed = {
        param($output)
        $rawRows = @($output | Where-Object { $_ -and $_.PSObject.Properties['Name'] })
        $rows = foreach ($rule in $rawRows) {
            $profileCode=[string]$rule.Profile
            $directionCode=[string]$rule.Direction
            $actionCode=[string]$rule.Action
            $enabledCode=[string]$rule.Enabled
            [pscustomobject]@{
                Name=[string]$rule.Name
                DisplayName=[string]$rule.DisplayName
                Program=[string]$rule.Program
                Direction=$directionCode
                Action=$actionCode
                Profile=$profileCode
                Enabled=$enabledCode
                DisplayDirection=T $(if($directionCode -eq 'Inbound'){'FirewallInbound'}else{'FirewallOutbound'})
                DisplayAction=T $(if($actionCode -eq 'Block'){'Block'}else{'Allow'})
                DisplayProfile=T $(switch -Regex($profileCode){'^Private$'{'PrivateProfile';break};'^Public$'{'PublicProfile';break};'^Domain$'{'DomainProfile';break};default{'AllProfiles'}})
                DisplayEnabled=T $(if($enabledCode -eq 'True'){'Enabled'}else{'Disabled'})
            }
        }
        $script:FirewallRulesCache=@($rows|Sort-Object DisplayName,Direction)
        $script:FirewallRulesCacheUpdatedAt=Get-Date
        $FirewallGrid.ItemsSource=$script:FirewallRulesCache
    }
    $worker = {
        $rules=@(Get-NetFirewallRule -Group 'WNST' -ErrorAction SilentlyContinue)
        foreach($rule in $rules){
            $application=$rule|Get-NetFirewallApplicationFilter -ErrorAction SilentlyContinue|Select-Object -First 1
            [pscustomobject]@{
                Name=[string]$rule.Name;DisplayName=[string]$rule.DisplayName;Program=[string]$application.Program
                Direction=[string]$rule.Direction;Action=[string]$rule.Action;Profile=[string]$rule.Profile;Enabled=[string]$rule.Enabled
            }
        }
    }
    [void](Invoke-HuAsyncWork -Key 'Page.Firewall' -ScriptBlock $worker -OnCompleted $completed -TimeoutSeconds 6 -Replace)
}

function Remove-SelectedFirewallRules {
    $selected = @($FirewallGrid.SelectedItems)
    if ($selected.Count -eq 0) { Show-AppError (T 'FirewallSelectionRequired'); return }
    if (-not (Show-AppConfirm (TF 'ConfirmDeleteFirewallRules' @($selected.Count)))) { return }
    try {
        foreach ($row in $selected) { Remove-NetFirewallRule -Name ([string]$row.Name) -Confirm:$false -ErrorAction Stop }
        Clear-FirewallContextSelection
        Refresh-FirewallRules -Force
        Show-AppInfo (TF 'FirewallRulesDeleted' @($selected.Count))
    }
    catch { Show-AppError $_.Exception.Message }
}

function Set-SelectedFirewallRulesEnabled {
    param([Parameter(Mandatory=$true)][bool]$Enabled)
    $selected = @($FirewallGrid.SelectedItems)
    if ($selected.Count -eq 0) { Show-AppError (T 'FirewallSelectionRequired'); return }
    try {
        foreach ($row in $selected) { Set-NetFirewallRule -Name ([string]$row.Name) -Enabled $(if($Enabled){'True'}else{'False'}) -ErrorAction Stop | Out-Null }
        Refresh-FirewallRules -Force
    }
    catch { Show-AppError $_.Exception.Message }
}
