# WNST - événements des pages Jeux et Applications

$script:GamesTweakControls=@{}
$script:SoftwareActionButtons=New-Object 'System.Collections.Generic.List[object]'
$script:SoftwarePrimaryButtons=@{}
$script:SteamDeveloperButton=$null
$script:UpdatingGamesTweaks=$false

function Get-HuActionGeometry {
    param([ValidateSet('PowerShell','Download','Installer','GitHub','Store','Web','FTP','Terminal')][string]$Kind)
    switch($Kind){
        PowerShell { 'M2,3 L7.5,8 L2,13 M8.5,13 L14,13' }
        Download { 'M8,1.5 L8,10.5 M4.5,7.5 L8,11 L11.5,7.5 M2,13.5 L14,13.5' }
        Installer { 'M2,2.5 L14,2.5 L14,13.5 L2,13.5 Z M2,5.5 L14,5.5 M5,9.5 L7,11.5 L11,7.5' }
        GitHub { 'M8,1.3 C4.3,1.3 1.4,4.2 1.4,7.9 C1.4,10.8 3.3,13.2 6,14 C6.3,14.1 6.4,13.9 6.4,13.7 L6.4,12.4 C4.4,12.8 4,11.5 4,11.5 C3.7,10.7 3.2,10.5 3.2,10.5 C2.6,10.1 3.2,10.1 3.2,10.1 C3.9,10.2 4.3,10.8 4.3,10.8 C4.9,11.9 5.9,11.6 6.4,11.4 C6.5,10.9 6.7,10.6 7,10.4 C5.4,10.2 3.7,9.6 3.7,6.8 C3.7,6 4,5.4 4.4,4.9 C4.3,4.7 4,3.9 4.5,2.9 C4.5,2.9 5.2,2.7 6.4,3.5 C7.4,3.2 8.5,3.2 9.6,3.5 C10.8,2.7 11.5,2.9 11.5,2.9 C12,3.9 11.7,4.7 11.6,4.9 C12,5.4 12.3,6 12.3,6.8 C12.3,9.6 10.6,10.2 9,10.4 C9.4,10.7 9.6,11.2 9.6,12 L9.6,13.7 C9.6,13.9 9.7,14.1 10,14 C12.7,13.1 14.6,10.8 14.6,7.9 C14.6,4.2 11.7,1.3 8,1.3 Z' }
        Store { 'M2,2.5 L7.2,1.8 L7.2,7.4 L2,7.4 Z M8.2,1.7 L14,1 L14,7.4 L8.2,7.4 Z M2,8.4 L7.2,8.4 L7.2,14 L2,13.3 Z M8.2,8.4 L14,8.4 L14,15 L8.2,14.2 Z' }
        Web { 'M8,1.5 A6.5,6.5 0 1 1 8,14.5 A6.5,6.5 0 1 1 8,1.5 M1.8,8 L14.2,8 M8,1.8 C10.6,4.1 10.6,11.9 8,14.2 M8,1.8 C5.4,4.1 5.4,11.9 8,14.2' }
        FTP { 'M2,2.5 L14,2.5 L14,6 L2,6 Z M2,9 L14,9 L14,13.5 L2,13.5 Z M4,4.25 L5.2,4.25 M4,11.25 L5.2,11.25 M7,7.5 L10.5,7.5 M9,6 L10.5,7.5 L9,9' }
        Terminal { 'M1.5,2.5 L14.5,2.5 L14.5,13.5 L1.5,13.5 Z M4,6 L6.5,8 L4,10 M8,10 L11.5,10' }
    }
}

function New-HuActionIcon {
    param([string]$Kind)
    $view=[Windows.Controls.Viewbox]::new();$view.Width=14;$view.Height=14;$view.HorizontalAlignment='Center';$view.VerticalAlignment='Center'
    $path=[Windows.Shapes.Path]::new();$path.Data=[Windows.Media.Geometry]::Parse((Get-HuActionGeometry $Kind));$path.Stretch='Uniform';$path.StrokeThickness=1.35;$path.StrokeStartLineCap='Round';$path.StrokeEndLineCap='Round';$path.StrokeLineJoin='Round';$path.HorizontalAlignment='Center';$path.VerticalAlignment='Center'
    $binding=[Windows.Data.Binding]::new('Foreground');$binding.RelativeSource=[Windows.Data.RelativeSource]::new([Windows.Data.RelativeSourceMode]::FindAncestor,[Windows.Controls.Button],1)
    if($Kind -eq 'GitHub'){[void]$path.SetBinding([Windows.Shapes.Shape]::FillProperty,$binding);$path.StrokeThickness=0}else{[void]$path.SetBinding([Windows.Shapes.Shape]::StrokeProperty,$binding)}
    $view.Child=$path;return $view
}

function Set-HuIconActionButtonKind {param([object]$Button,[string]$Kind)$Button.Content=(New-HuActionIcon -Kind $Kind)}

function New-HuIconActionButton {
    param([string]$Kind,[string]$ToolTip,[string]$ItemId,[scriptblock]$Click)
    $button=[Windows.Controls.Button]::new(); $button.Width=28; $button.Height=26; $button.Padding=[Windows.Thickness]::new(0); $button.Margin=[Windows.Thickness]::new(4,0,0,0); $button.HorizontalContentAlignment='Center'; $button.VerticalContentAlignment='Center'; $button.ToolTip=$ToolTip; $button.Tag=$ItemId; $button.Style=$window.FindResource('AccentHoverButtonStyle')
    $button.Content=(New-HuActionIcon -Kind $Kind)
    if($Click){ $button.Add_Click($Click) }
    return $button
}

function Add-HuSoftwareLog {
    param([ValidateSet('Games','Applications')][string]$Area,[string]$Text,[ValidateSet('Normal','Success','Error')][string]$Level='Normal')
    $control=if($Area -eq 'Games'){$GamesLogBox}else{$ApplicationsLogBox}
    Add-WnstLogText -Control $control -Text ('[{0}] {1}' -f (Get-Date -Format 'HH:mm:ss'),$Text) -Level $Level -LeadingNewLines 1
}

function Get-HuInstallerErrorText {
    param([string]$Code,[string]$Name)
    switch($Code){
        'LATEST_VERSION_UNAVAILABLE' { TF 'SoftwareLatestUnavailable' @($Name) }
        'INSTALLABLE_ASSET_UNAVAILABLE' { TF 'SoftwareAssetUnavailable' @($Name) }
        'UNSUPPORTED_INSTALLER_FORMAT' { T 'SoftwareUnsupportedFormat' }
        'INSECURE_DOWNLOAD_URL' { T 'SoftwareInsecureUrl' }
        'Timeout' { T 'Timeout' }
        default { TF 'SoftwareGenericError' @($Name,$Code) }
    }
}

function Update-HuSoftwareProgress {
    param([ValidateSet('Games','Applications')][string]$Area,[object]$Event)
    $status=if($Area -eq 'Games'){$GamesProgressStatus}else{$ApplicationsProgressStatus}; $percentText=if($Area -eq 'Games'){$GamesProgressPercent}else{$ApplicationsProgressPercent}; $bar=if($Area -eq 'Games'){$GamesProgressBar}else{$ApplicationsProgressBar}; $details=if($Area -eq 'Games'){$GamesProgressDetails}else{$ApplicationsProgressDetails}; $clearButton=if($Area -eq 'Games'){$GamesClearProgressButton}else{$ApplicationsClearProgressButton}
    if($Event.Kind -eq 'Progress'){
        $clearButton.IsEnabled=([string]$Event.Stage -eq 'Complete')
        $percent=[double]$Event.Percent; $bar.IsIndeterminate=($Event.Stage -in @('Prepare','Search') -or ($Event.Stage -eq 'Download' -and [long]$Event.Total -le 0)); if(-not $bar.IsIndeterminate){$bar.Value=$percent}; $percentText.Text=if($bar.IsIndeterminate){'...'}else{('{0} %' -f [math]::Round($percent))}
        switch([string]$Event.Stage){
            Prepare {$status.Text=TF 'SoftwarePreparing' @($Event.Name);$details.Text=''}
            Search {$status.Text=TF 'SoftwareSearching' @($Event.Name);$details.Text=''}
            Download {$status.Text=TF 'SoftwareDownloading' @($Event.Name); if([long]$Event.Total -gt 0){$details.Text=TF 'SoftwareProgressDetails' @((Format-Size ([long]$Event.Bytes)),(Format-Size ([long]$Event.Total)),(Format-Size ([long]$Event.Speed)))}else{$details.Text=if([long]$Event.Bytes -gt 0){Format-Size ([long]$Event.Bytes)}else{''}}}
            Complete {$status.Text=TF 'SoftwareCompleted' @($Event.Name);$details.Text=[string]$Event.Path;$bar.IsIndeterminate=$false;$bar.Value=100;$percentText.Text='100 %'}
            Error {$status.Text=TF 'SoftwareFailed' @($Event.Name);$details.Text=Get-HuInstallerErrorText ([string]$Event.Code) ([string]$Event.Name);$bar.IsIndeterminate=$false;$bar.Value=0;$percentText.Text='0 %'}
        }
        return
    }
    $text=switch([string]$Event.Stage){
        Search {TF 'SoftwareLogSearch' @($Event.Name)}
        Source {TF 'SoftwareLogSource' @($Event.Source,$Event.Url)}
        Version {TF 'SoftwareLogVersion' @($Event.Name,$Event.Version)}
        Url {TF 'SoftwareLogUrl' @($Event.Url)}
        Download {TF 'SoftwareLogDownload' @($Event.Name,$Event.Path)}
        Progress {TF 'SoftwareLogProgress' @($Event.Name,$Event.Percent,(Format-Size ([long]$Event.Bytes)),(Format-Size ([long]$Event.Total)),(Format-Size ([long]$Event.Speed)))}
        Existing {TF 'SoftwareLogExisting' @($Event.Path)}
        Path {TF 'SoftwareLogPath' @($Event.Path)}
        Launch {TF 'SoftwareLogLaunch' @($Event.Name,$Event.Path)}
        Complete {TF 'SoftwareLogComplete' @($Event.Name,$Event.Version)}
        DownloadComplete {TF 'SoftwareLogDownloaded' @($Event.Name)}
        Error {Get-HuInstallerErrorText ([string]$Event.Code) ([string]$Event.Name)}
        default {[string]$Event.Stage}
    }
    Add-HuSoftwareLog $Area $text ([string]$Event.Level)
}

function Reset-HuSoftwareProgress {
    param([ValidateSet('Games','Applications')][string]$Area)
    $status=if($Area -eq 'Games'){$GamesProgressStatus}else{$ApplicationsProgressStatus};$percentText=if($Area -eq 'Games'){$GamesProgressPercent}else{$ApplicationsProgressPercent};$bar=if($Area -eq 'Games'){$GamesProgressBar}else{$ApplicationsProgressBar};$details=if($Area -eq 'Games'){$GamesProgressDetails}else{$ApplicationsProgressDetails};$clearButton=if($Area -eq 'Games'){$GamesClearProgressButton}else{$ApplicationsClearProgressButton}
    $status.Text=T 'Ready';$percentText.Text='0 %';$details.Text='';$bar.IsIndeterminate=$false;$bar.Value=0;$clearButton.IsEnabled=$false
}

function Set-HuSoftwareButtonsEnabled { param([bool]$Enabled) foreach($button in $script:SoftwareActionButtons){$button.IsEnabled=$Enabled}; if($script:SteamDeveloperButton){$script:SteamDeveloperButton.IsEnabled=$Enabled -and -not [string]::IsNullOrWhiteSpace((Get-HuSteamExecutable))} }

function Start-HuCatalogInstallFromUi {
    param([string]$Area,[string]$Id)
    $item=Get-HuCatalogItem $Id
    if(-not $item){return}
    if($item.Provider -eq 'Unavailable'){
        $message=TF 'SoftwareAutomaticUnavailable' @($item.Name); Add-HuSoftwareLog $Area $message Error; Show-AppInfo $message; return
    }
    Set-HuSoftwareButtonsEnabled $false
    $queue=[Collections.Concurrent.ConcurrentQueue[object]]::new(); $appRoot=[string]$script:AppRoot; $jobKey='SoftwareInstall.'+$Area;$language=[string]$script:Settings.Language
    [void](Invoke-HuAsyncWork -Key $jobKey -Replace -TimeoutSeconds 1800 -ProgressQueue $queue -ArgumentList @($appRoot,$Id,$queue,$language) -ScriptBlock {
        param($appRoot,$id,$queue,$language); . (Join-Path $appRoot 'Modules\Installers.ps1'); Invoke-HuCatalogInstall -Id $id -ProgressQueue $queue -Language $language
    } -OnProgress {param($event) Update-HuSoftwareProgress $Area $event}.GetNewClosure() -OnCompleted {param($result) Set-HuSoftwareButtonsEnabled $true; Refresh-HuDownloadsButtons}.GetNewClosure() -OnError {param($errorText) Set-HuSoftwareButtonsEnabled $true; Refresh-HuDownloadsButtons; if($errorText -and $errorText -notin @('LATEST_VERSION_UNAVAILABLE','INSTALLABLE_ASSET_UNAVAILABLE')){Show-AppError (Get-HuInstallerErrorText $errorText $item.Name)}}.GetNewClosure())
}

function Start-HuCatalogDownloadFromUi {
    param([string]$Area,[string]$Id)
    $item=Get-HuCatalogItem $Id;if(-not $item -or $item.Provider -eq 'Unavailable'){return}
    Set-HuSoftwareButtonsEnabled $false
    $queue=[Collections.Concurrent.ConcurrentQueue[object]]::new();$appRoot=[string]$script:AppRoot;$jobKey='SoftwareDownload.'+$Area;$language=[string]$script:Settings.Language
    [void](Invoke-HuAsyncWork -Key $jobKey -Replace -TimeoutSeconds 1800 -ProgressQueue $queue -ArgumentList @($appRoot,$Id,$queue,$language) -ScriptBlock {
        param($appRoot,$id,$queue,$language);. (Join-Path $appRoot 'Modules\Installers.ps1');Invoke-HuCatalogDownload -Id $id -ProgressQueue $queue -Language $language
    } -OnProgress {param($event) Update-HuSoftwareProgress $Area $event}.GetNewClosure() -OnCompleted {param($result) Set-HuSoftwareButtonsEnabled $true;Refresh-HuDownloadsButtons}.GetNewClosure() -OnError {param($errorText) Set-HuSoftwareButtonsEnabled $true;Refresh-HuDownloadsButtons;if($errorText -and $errorText -notin @('LATEST_VERSION_UNAVAILABLE','INSTALLABLE_ASSET_UNAVAILABLE')){Show-AppError (Get-HuInstallerErrorText $errorText $item.Name)}}.GetNewClosure())
}

function Invoke-HuPrimarySoftwareActionFromUi {
    param([string]$Area,[string]$Id,[ValidateSet('Install','Download')][string]$DefaultAction)
    $downloaded=Get-HuDownloadedCatalogInstallerPath -Id $Id
    if(-not[string]::IsNullOrWhiteSpace($downloaded)){
        try{$path=Start-HuDownloadedCatalogInstaller -Id $Id;Add-HuSoftwareLog $Area (TF 'SoftwareLogLaunch' @((Get-HuCatalogItem $Id).Name,$path)) Success}
        catch{Add-HuSoftwareLog $Area (Get-HuInstallerErrorText ([string]$_.Exception.Message) ([string](Get-HuCatalogItem $Id).Name)) Error;Refresh-HuDownloadsButtons}
        return
    }
    if($DefaultAction -eq 'Install'){Start-HuCatalogInstallFromUi $Area $Id}else{Start-HuCatalogDownloadFromUi $Area $Id}
}

function Open-HuCatalogUrl {
    param([string]$Area,[string]$Url,[string]$Name,[string]$Source)
    if([string]::IsNullOrWhiteSpace($Url)){return}; Add-HuSoftwareLog $Area (TF 'SoftwareLogOpenLink' @($Source,$Name,$Url)); Start-Process -FilePath $Url | Out-Null
}

function Open-HuStoreDestination {
    param([string]$Area,[object]$Item)
    $choice=Show-HuStoreChoiceDialog; if($choice -eq 'Store'){Open-HuCatalogUrl $Area ('ms-windows-store://pdp/?ProductId='+$Item.StoreProductId) $Item.Name (T 'MicrosoftStore')}elseif($choice -eq 'Browser'){Open-HuCatalogUrl $Area $Item.StoreUrl $Item.Name (T 'ExternalBrowser')}
}

function New-HuSoftwareCatalogRow {
    param([object]$Item,[ValidateSet('Games','Applications')][string]$Area)
    $border=[Windows.Controls.Border]::new(); $border.BorderBrush=$window.FindResource('SeparatorBrush'); $border.BorderThickness=[Windows.Thickness]::new(0,0,0,1); $border.Padding=[Windows.Thickness]::new(0,8,0,9)
    $grid=[Windows.Controls.Grid]::new(); [void]$grid.ColumnDefinitions.Add([Windows.Controls.ColumnDefinition]::new()); $auto=[Windows.Controls.ColumnDefinition]::new();$auto.Width='Auto';[void]$grid.ColumnDefinitions.Add($auto)
    $left=[Windows.Controls.StackPanel]::new(); $name=[Windows.Controls.TextBlock]::new();$name.Text=$Item.Name;$name.FontWeight='SemiBold';$name.TextWrapping='Wrap';$desc=[Windows.Controls.TextBlock]::new();$desc.Foreground=$window.FindResource('MutedBrush');$desc.Margin=[Windows.Thickness]::new(0,3,8,0);$desc.TextWrapping='Wrap';$desc.FontSize=11
    $desc.Text=if($Item.DescriptionKey -in @('CatalogLauncherDescription','ManufacturerDescription')){TF $Item.DescriptionKey @($Item.Name)}else{T $Item.DescriptionKey};if($Item.Id -eq 'steam'){$desc.Text+=[Environment]::NewLine+(T 'SteamDeveloperDescription')}; $left.Children.Add($name)|Out-Null;$left.Children.Add($desc)|Out-Null
    $actions=[Windows.Controls.StackPanel]::new();$actions.Orientation='Horizontal';$actions.VerticalAlignment='Center';[Windows.Controls.Grid]::SetColumn($actions,1)
    if($Item.Provider -ne 'Unavailable'){
        $id=[string]$Item.Id;$areaCopy=[string]$Area;$defaultAction=if([bool]$Item.DownloadOnlyButton){'Download'}else{'Install'};$kind=if($defaultAction -eq 'Install'){'PowerShell'}else{'Download'};$tip=if($defaultAction -eq 'Install'){T 'InstallWithPowerShell'}else{TF 'SoftwareDownloading' @($Item.Name)}
        $b=New-HuIconActionButton $kind $tip $id ({Invoke-HuPrimarySoftwareActionFromUi $areaCopy $id $defaultAction}.GetNewClosure());$actions.Children.Add($b)|Out-Null;$script:SoftwareActionButtons.Add($b);$script:SoftwarePrimaryButtons[$id]=[pscustomobject]@{Button=$b;DefaultKind=$kind;DefaultToolTip=$tip;Name=[string]$Item.Name}
    }
    if($Item.GitHubUrl){$u=[string]$Item.GitHubUrl;$n=[string]$Item.Name;$a=[string]$Area;$actions.Children.Add((New-HuIconActionButton GitHub 'GitHub' $Item.Id ({Open-HuCatalogUrl $a $u $n 'GitHub'}.GetNewClosure())))|Out-Null}
    if($Item.StoreUrl){$itemCopy=$Item;$a=[string]$Area;$actions.Children.Add((New-HuIconActionButton Store (T 'MicrosoftStore') $Item.Id ({Open-HuStoreDestination $a $itemCopy}.GetNewClosure())))|Out-Null}
    if($Item.OfficialUrl){$u=Get-HuLocalizedCatalogUrl ([string]$Item.OfficialUrl) ([string]$script:Settings.Language);$n=[string]$Item.Name;$a=[string]$Area;$actions.Children.Add((New-HuIconActionButton Web (T 'OfficialWebsite') $Item.Id ({Open-HuCatalogUrl $a $u $n (T 'OfficialWebsite')}.GetNewClosure())))|Out-Null}
    if($Item.FtpUrl){$u=[string]$Item.FtpUrl;$n=[string]$Item.Name;$a=[string]$Area;$actions.Children.Add((New-HuIconActionButton FTP 'FTP' $Item.Id ({Open-HuCatalogUrl $a $u $n 'FTP'}.GetNewClosure())))|Out-Null}
    if($Item.Id -eq 'steam'){$dev=New-HuIconActionButton Terminal (T 'SteamDeveloperMode') steam ({Start-HuSteamDeveloperFromUi});$actions.Children.Add($dev)|Out-Null;$script:SteamDeveloperButton=$dev}
    $grid.Children.Add($left)|Out-Null;$grid.Children.Add($actions)|Out-Null;$border.Child=$grid; return $border
}

function Start-HuSteamDeveloperFromUi {
    try{$before=Get-HuSteamExecutable;if(-not $before){throw 'STEAM_NOT_INSTALLED'};Add-HuSoftwareLog Games (TF 'SteamDeveloperStarting' @($before));$result=Start-HuSteamDeveloperMode;Add-HuSoftwareLog Games (TF $(if($result.Restarted){'SteamDeveloperRestarted'}else{'SteamDeveloperStarted'}) @($result.Path)) Success}catch{Add-HuSoftwareLog Games (TF 'SteamDeveloperFailed' @($_.Exception.Message)) Error;Show-AppError (TF 'SteamDeveloperFailed' @($_.Exception.Message))}finally{Refresh-GamesState}
}

function New-HuGameTweakRow {
    param([string]$Id,[string]$TitleKey,[string]$DescriptionKey)
    $border=[Windows.Controls.Border]::new();$border.BorderBrush=$window.FindResource('SeparatorBrush');$border.BorderThickness=[Windows.Thickness]::new(0,0,0,1);$border.Padding=[Windows.Thickness]::new(0,8,0,9)
    $grid=[Windows.Controls.Grid]::new();[void]$grid.ColumnDefinitions.Add([Windows.Controls.ColumnDefinition]::new());$auto=[Windows.Controls.ColumnDefinition]::new();$auto.Width='Auto';[void]$grid.ColumnDefinitions.Add($auto)
    $left=[Windows.Controls.StackPanel]::new();$title=[Windows.Controls.TextBlock]::new();$title.Text=T $TitleKey;$title.FontWeight='SemiBold';$title.TextWrapping='Wrap';$desc=[Windows.Controls.TextBlock]::new();$desc.Text=T $DescriptionKey;$desc.Foreground=$window.FindResource('MutedBrush');$desc.FontSize=11;$desc.TextWrapping='Wrap';$desc.Margin=[Windows.Thickness]::new(0,3,8,0);$state=[Windows.Controls.TextBlock]::new();$state.Foreground=$window.FindResource('MutedBrush');$state.FontSize=10;$state.Margin=[Windows.Thickness]::new(0,4,8,0);$left.Children.Add($title)|Out-Null;$left.Children.Add($desc)|Out-Null;$left.Children.Add($state)|Out-Null
    $toggle=[Windows.Controls.Primitives.ToggleButton]::new();$toggle.Style=$window.FindResource('SwitchToggleStyle');$toggle.VerticalAlignment='Center';$toggle.Tag=$Id;[Windows.Controls.Grid]::SetColumn($toggle,1);$idCopy=$Id;$toggle.Add_Click({if(-not $script:UpdatingGamesTweaks){Start-HuGameTweakFromUi $idCopy ([bool]$this.IsChecked)}}.GetNewClosure());$grid.Children.Add($left)|Out-Null;$grid.Children.Add($toggle)|Out-Null;$border.Child=$grid;$script:GamesTweakControls[$Id]=[pscustomobject]@{Toggle=$toggle;State=$state;Title=$title};return $border
}

function Start-HuGameTweakFromUi {
    param([string]$Id,[bool]$Checked)
    $entry=$script:GamesTweakControls[$Id];$entry.Toggle.IsEnabled=$false;$before=Get-HuGameTweakState $Id;Add-HuSoftwareLog Games (TF 'TweakLogBefore' @($entry.Title.Text,$(if($before.Known){if($before.Checked){T 'Enabled'}else{T 'Disabled'}}else{T 'Unavailable'})));Add-HuSoftwareLog Games (TF 'TweakLogApply' @($entry.Title.Text,$(if($Checked){T 'Enabled'}else{T 'Disabled'})))
    $appRoot=[string]$script:AppRoot;$idCopy=$Id;$desired=$Checked
    [void](Invoke-HuAsyncWork -Key ('GameTweak.'+$Id) -Replace -TimeoutSeconds 45 -ArgumentList @($appRoot,$Id,$Checked) -ScriptBlock {param($appRoot,$id,$checked);. (Join-Path $appRoot 'Modules\Games.ps1');Apply-HuGameTweak -Id $id -Checked ([bool]$checked)} -OnCompleted {param($output);$entry.Toggle.IsEnabled=$true;Refresh-GamesState;$after=Get-HuGameTweakState $idCopy;Add-HuSoftwareLog Games (TF 'TweakLogAfter' @($entry.Title.Text,$(if($after.Checked){T 'Enabled'}else{T 'Disabled'}))) Success;if($idCopy -eq 'Hags'){Show-AppInfo (T 'HagsRestartRequired')}}.GetNewClosure() -OnError {param($errorText);$entry.Toggle.IsEnabled=$true;Refresh-GamesState;Add-HuSoftwareLog Games (TF 'TweakLogError' @($entry.Title.Text,$errorText)) Error;Show-AppError (TF 'TweakLogError' @($entry.Title.Text,$errorText))}.GetNewClosure())
}

function Refresh-GamesState {
    $script:UpdatingGamesTweaks=$true
    try{foreach($id in $script:GamesTweakControls.Keys){$state=Get-HuGameTweakState $id;$entry=$script:GamesTweakControls[$id];$entry.Toggle.IsChecked=[bool]$state.Checked;if($id -eq 'NetworkPowerSaving'){$entry.Toggle.IsEnabled=[bool]$state.Known};$entry.State.Text=(T 'CurrentState')+': '+$(if(-not $state.Known){T 'Unavailable'}elseif($state.Checked){T 'Enabled'}else{T 'Disabled'});if($id -eq 'Hags'){$entry.State.Text+=' · '+(T 'RestartRequired')}};if($script:SteamDeveloperButton){$script:SteamDeveloperButton.IsEnabled=-not [string]::IsNullOrWhiteSpace((Get-HuSteamExecutable))}}
    finally{$script:UpdatingGamesTweaks=$false}
    Refresh-HuDownloadsButtons
}

function Refresh-HuDownloadsButtons {
    $path=Get-HuDownloadsPath;$visible=if(@(Get-ChildItem -LiteralPath $path -File -ErrorAction SilentlyContinue).Count -gt 0){'Visible'}else{'Collapsed'};$GamesOpenDownloadsButton.Visibility=$visible;$ApplicationsOpenDownloadsButton.Visibility=$visible
    foreach($id in @($script:SoftwarePrimaryButtons.Keys)){$entry=$script:SoftwarePrimaryButtons[$id];$downloaded=Get-HuDownloadedCatalogInstallerPath -Id $id;if([string]::IsNullOrWhiteSpace($downloaded)){Set-HuIconActionButtonKind $entry.Button $entry.DefaultKind;$entry.Button.ToolTip=$entry.DefaultToolTip}else{Set-HuIconActionButtonKind $entry.Button Installer;$entry.Button.ToolTip=(T 'Execute')}}
}

function Initialize-HuSoftwareCatalogUi {
    foreach($panel in @($GamesLaunchersPanel,$GamesTweaksPanel,$ApplicationsAppsLeftPanel,$ApplicationsAppsRightPanel,$ApplicationsManufacturersLeftPanel,$ApplicationsManufacturersRightPanel,$ApplicationsMiscPanel)){$panel.Children.Clear()}
    $script:SoftwareActionButtons.Clear();$script:SoftwarePrimaryButtons=@{};$script:GamesTweakControls=@{};$script:SteamDeveloperButton=$null
    $catalog=@(Get-HuSoftwareCatalog)
    foreach($item in @($catalog|Where-Object {$_.Area -eq 'Games'})){$GamesLaunchersPanel.Children.Add((New-HuSoftwareCatalogRow $item Games))|Out-Null}
    foreach($spec in @(@('MouseAcceleration','GameTweakMouseTitle','GameTweakMouseDescription'),@('BackgroundApps','GameTweakBackgroundTitle','GameTweakBackgroundDescription'),@('GameMode','GameTweakGameModeTitle','GameTweakGameModeDescription'),@('NetworkPowerSaving','GameTweakNetworkPowerTitle','GameTweakNetworkPowerDescription'),@('WindowedOptimizations','GameTweakWindowedTitle','GameTweakWindowedDescription'),@('Hags','GameTweakHagsTitle','GameTweakHagsDescription'))){$GamesTweaksPanel.Children.Add((New-HuGameTweakRow $spec[0] $spec[1] $spec[2]))|Out-Null}
    $apps=@($catalog|Where-Object {$_.Area -eq 'Applications' -and $_.Group -eq 'App'});for($i=0;$i -lt $apps.Count;$i++){$panel=if($i -lt [math]::Ceiling($apps.Count/2)){$ApplicationsAppsLeftPanel}else{$ApplicationsAppsRightPanel};$panel.Children.Add((New-HuSoftwareCatalogRow $apps[$i] Applications))|Out-Null}
    $makers=@($catalog|Where-Object {$_.Area -eq 'Applications' -and $_.Group -eq 'Manufacturer'});for($i=0;$i -lt $makers.Count;$i++){$panel=if($i -lt [math]::Ceiling($makers.Count/2)){$ApplicationsManufacturersLeftPanel}else{$ApplicationsManufacturersRightPanel};$panel.Children.Add((New-HuSoftwareCatalogRow $makers[$i] Applications))|Out-Null}
    foreach($item in @($catalog|Where-Object {$_.Area -eq 'Applications' -and $_.Group -eq 'Misc'})){$ApplicationsMiscPanel.Children.Add((New-HuSoftwareCatalogRow $item Applications))|Out-Null}
    Refresh-GamesState;Refresh-HuDownloadsButtons
}

function Import-HuPersistentLogView {
    param([object]$Control,[string]$Name)
    $path=Get-WnstPersistentLogPath $Name;if(-not(Test-Path -LiteralPath $path -PathType Leaf)){return};$Control.Document.Blocks.Clear();$paragraph=[Windows.Documents.Paragraph]::new();$paragraph.Margin=[Windows.Thickness]::new(0);$Control.Document.Blocks.Add($paragraph)|Out-Null;$lines=[IO.File]::ReadAllLines($path,[Text.Encoding]::UTF8);for($i=0;$i -lt $lines.Count;$i++){$run=[Windows.Documents.Run]::new($lines[$i]);switch(Get-WnstLogLineLevel $lines[$i]){Success{$run.Foreground=$Control.TryFindResource('LogSuccessBrush')}Error{$run.Foreground=$Control.TryFindResource('LogErrorBrush')}};$paragraph.Inlines.Add($run)|Out-Null;if($i -lt $lines.Count-1){$paragraph.Inlines.Add([Windows.Documents.LineBreak]::new())|Out-Null}};$Control.ScrollToEnd()
}

function Clear-HuPersistentLog {param([object]$Control,[string]$Name) Clear-WnstLogContent $Control;$path=Get-WnstPersistentLogPath $Name;if(Test-Path -LiteralPath $path -PathType Leaf){Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue}}

$GamesOpenDownloadsButton.Add_Click({Start-Process explorer.exe -ArgumentList @((Get-HuDownloadsPath))|Out-Null});$ApplicationsOpenDownloadsButton.Add_Click({Start-Process explorer.exe -ArgumentList @((Get-HuDownloadsPath))|Out-Null})
$GamesClearProgressButton.Add_Click({Reset-HuSoftwareProgress Games});$ApplicationsClearProgressButton.Add_Click({Reset-HuSoftwareProgress Applications})
$GamesExportLogButton.Add_Click({Export-WnstLogSnapshot $GamesLogBox Games});$GamesOpenLogButton.Add_Click({Open-WnstLogSnapshot $GamesLogBox Games});$GamesClearLogButton.Add_Click({Clear-HuPersistentLog $GamesLogBox Games})
$ApplicationsExportLogButton.Add_Click({Export-WnstLogSnapshot $ApplicationsLogBox Applications});$ApplicationsOpenLogButton.Add_Click({Open-WnstLogSnapshot $ApplicationsLogBox Applications});$ApplicationsClearLogButton.Add_Click({Clear-HuPersistentLog $ApplicationsLogBox Applications})
Import-HuPersistentLogView $GamesLogBox Games;Import-HuPersistentLogView $ApplicationsLogBox Applications;Initialize-HuSoftwareCatalogUi
