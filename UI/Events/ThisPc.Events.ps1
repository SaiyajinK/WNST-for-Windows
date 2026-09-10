$script:ThisPcCardClickReadyAt = (Get-Date).AddMilliseconds(2000)

function Update-HuThisPcResponsiveLayout {
    $isMaximized = ($window.WindowState -eq [Windows.WindowState]::Maximized)

    if ($DisplayLabelColumn) {
        $labelWidth = if ($isMaximized) { 200.0 } else { 95.0 }
        $DisplayLabelColumn.Width = [Windows.GridLength]::new($labelWidth)
    }

    foreach ($controls in @($DisplayResolutionControls,$DisplayRefreshControls,$DisplayScalingControls)) {
        if (-not $controls) { continue }
        if ($isMaximized) {
            $controls.Width = 430.0
            $controls.HorizontalAlignment = [Windows.HorizontalAlignment]::Right
        }
        else {
            $controls.Width = [double]::NaN
            $controls.HorizontalAlignment = [Windows.HorizontalAlignment]::Stretch
        }
    }

    if ($ThisPcHeaderActions) {
        $rightMargin = if ($isMaximized) { 10.0 } else { 22.0 }
        $ThisPcHeaderActions.Margin = [Windows.Thickness]::new(0.0,0.0,$rightMargin,0.0)
    }
}

$window.Add_StateChanged({ Update-HuThisPcResponsiveLayout })
$window.Add_Loaded({ Update-HuThisPcResponsiveLayout })

function Test-HuThisPcCardClickReady {
    return ((Get-Date) -ge $script:ThisPcCardClickReadyAt)
}

function Test-HuCardClickFromButton {
    param($OriginalSource)
    $source=$OriginalSource
    while($source){
        if($source -is [Windows.Controls.Button]){return $true}
        try{$source=[Windows.Media.VisualTreeHelper]::GetParent($source)}catch{$source=$null}
    }
    return $false
}

function Open-HuSystemAboutNoFocus {
    try {
        Start-Process 'ms-settings:about' | Out-Null
    }
    catch {
        Show-AppError $_.Exception.Message
    }
}

$PcOverviewCard.Add_MouseLeftButtonUp({
    param($sender,$eventArgs)
    if(-not (Test-HuThisPcCardClickReady)){return}
    if(Test-HuCardClickFromButton $eventArgs.OriginalSource){return}
    Open-HuSystemAboutNoFocus
})

function Open-HuTaskManagerTarget {
    param([ValidateSet('CPU','Memory','GPU')][string]$Target)

    try {
        $performanceLabel=[string](T 'TaskManagerPerformancePage')
        $targetLabel=switch($Target){
            'CPU' { [string](T 'TaskManagerCpuLabel') }
            'Memory' { [string](T 'TaskManagerMemoryLabel') }
            'GPU' { [string](T 'TaskManagerGpuLabel') }
        }

        $performance64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($performanceLabel))
        $target64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($targetLabel))
        $nativeCode='using System;using System.Runtime.InteropServices;public static class HuNativeMouseChild{[StructLayout(LayoutKind.Sequential)]public struct RECT{public int Left;public int Top;public int Right;public int Bottom;}[DllImport("user32.dll")]public static extern bool SetCursorPos(int X,int Y);[DllImport("user32.dll")]public static extern void mouse_event(uint f,uint dx,uint dy,uint data,UIntPtr extra);[DllImport("user32.dll")]public static extern bool GetWindowRect(IntPtr hWnd,out RECT rect);[DllImport("user32.dll")]public static extern bool SetForegroundWindow(IntPtr hWnd);[DllImport("user32.dll")]public static extern IntPtr SendMessage(IntPtr hWnd,uint Msg,UIntPtr wParam,IntPtr lParam);public const uint LEFTDOWN=0x0002;public const uint LEFTUP=0x0004;public const uint WM_CHANGEUISTATE=0x0127;public const uint UIS_SET=1;public const uint UISF_HIDEFOCUS=1;public static UIntPtr MakeWParam(uint lo,uint hi){return (UIntPtr)((hi<<16)|(lo&0xFFFF));}}'
        $native64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($nativeCode))

        $childLines=@(
            '$ErrorActionPreference="SilentlyContinue"',
            'Add-Type -AssemblyName UIAutomationClient',
            'Add-Type -AssemblyName UIAutomationTypes',
            ('$NativeCode=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String("{0}"))' -f $native64),
            'Add-Type -TypeDefinition $NativeCode',
            ('$PerformanceLabel=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String("{0}"))' -f $performance64),
            ('$TargetLabel=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String("{0}"))' -f $target64),
            ('$Target="{0}"' -f $Target),
            '$PerformanceLabels=@($PerformanceLabel,"Performance","Performances")',
            '$TargetLabels=switch($Target){"CPU"{@($TargetLabel,"CPU","Processeur")}"Memory"{@($TargetLabel,"Memory","Mémoire")}"GPU"{@($TargetLabel,"GPU")}}',
            '$PerformanceIds=@("Performance","PerformancePage","PerformancePageNav","PerformanceNavigationViewItem")',
            '$TargetIds=switch($Target){"CPU"{@("CPU","Cpu","CpuItem","CpuView")}"Memory"{@("Memory","MemoryItem","MemoryView")}"GPU"{@("GPU","Gpu","GpuItem","GpuView")}}',
            'function Find-Element($Root,[string[]]$Labels,[string[]]$Ids){',
            '  try{$all=$Root.FindAll([Windows.Automation.TreeScope]::Descendants,[Windows.Automation.Condition]::TrueCondition)}catch{return $null}',
            '  foreach($e in $all){',
            '    $name="";$id=""',
            '    try{$name=[string]$e.Current.Name}catch{}',
            '    try{$id=[string]$e.Current.AutomationId}catch{}',
            '    foreach($label in $Labels){if([string]::IsNullOrWhiteSpace($label)){continue};if($name -eq $label -or $name.StartsWith($label,[StringComparison]::OrdinalIgnoreCase) -or $name.IndexOf($label,[StringComparison]::OrdinalIgnoreCase) -ge 0){return $e}}',
            '    foreach($candidate in $Ids){if([string]::IsNullOrWhiteSpace($candidate)){continue};if($id -eq $candidate -or $id.IndexOf($candidate,[StringComparison]::OrdinalIgnoreCase) -ge 0){return $e}}',
            '  }',
            '  return $null',
            '}',
            'function Invoke-Element($Element){',
            '  try{$p=$null;if($Element.TryGetCurrentPattern([Windows.Automation.SelectionItemPattern]::Pattern,[ref]$p)){$p.Select();return $true}}catch{}',
            '  try{$p=$null;if($Element.TryGetCurrentPattern([Windows.Automation.InvokePattern]::Pattern,[ref]$p)){$p.Invoke();return $true}}catch{}',
            '  try{$p=$null;if($Element.TryGetCurrentPattern([Windows.Automation.LegacyIAccessiblePattern]::Pattern,[ref]$p)){$p.DoDefaultAction();return $true}}catch{}',
            '  try{$pt=$null;if($Element.TryGetClickablePoint([ref]$pt)){[void][HuNativeMouseChild]::SetCursorPos([int]$pt.X,[int]$pt.Y);Start-Sleep -Milliseconds 20;[HuNativeMouseChild]::mouse_event([HuNativeMouseChild]::LEFTDOWN,0,0,0,[UIntPtr]::Zero);[HuNativeMouseChild]::mouse_event([HuNativeMouseChild]::LEFTUP,0,0,0,[UIntPtr]::Zero);return $true}}catch{}',
            '  return $false',
            '}',
            'Start-Process -FilePath (Join-Path $env:SystemRoot "System32\taskmgr.exe") | Out-Null',
            '$proc=$null',
            'for($i=0;$i -lt 80;$i++){$proc=Get-Process -Name Taskmgr -ErrorAction SilentlyContinue|Where-Object{$_.MainWindowHandle -ne 0}|Select-Object -First 1;if($proc){break};Start-Sleep -Milliseconds 100}',
            'if(-not $proc){exit}',
            '$root=[Windows.Automation.AutomationElement]::FromHandle($proc.MainWindowHandle)',
            'if(-not $root){exit}',
            '$performance=$null',
            'for($i=0;$i -lt 40;$i++){$performance=Find-Element $root $PerformanceLabels $PerformanceIds;if($performance){break};Start-Sleep -Milliseconds 100}',
            'if($performance){[void](Invoke-Element $performance)}',
            'Start-Sleep -Milliseconds 120',
            '$root=[Windows.Automation.AutomationElement]::FromHandle($proc.MainWindowHandle)',
            '$targetElement=$null',
            'for($i=0;$i -lt 40;$i++){$targetElement=Find-Element $root $TargetLabels $TargetIds;if($targetElement){break};Start-Sleep -Milliseconds 100}',
            'if($targetElement){[void](Invoke-Element $targetElement)}',
            'Start-Sleep -Milliseconds 80',
            '$rect=New-Object HuNativeMouseChild+RECT',
            'if([HuNativeMouseChild]::GetWindowRect([IntPtr]$proc.MainWindowHandle,[ref]$rect)){',
            '  [void][HuNativeMouseChild]::SetForegroundWindow([IntPtr]$proc.MainWindowHandle)',
            '  $width=$rect.Right-$rect.Left',
            '  $x=[int]($rect.Left+($width*0.55))',
            '  $y=[int]($rect.Top+72)',
            '  [void][HuNativeMouseChild]::SetCursorPos($x,$y)',
            '  Start-Sleep -Milliseconds 20',
            '  [HuNativeMouseChild]::mouse_event([HuNativeMouseChild]::LEFTDOWN,0,0,0,[UIntPtr]::Zero)',
            '  [HuNativeMouseChild]::mouse_event([HuNativeMouseChild]::LEFTUP,0,0,0,[UIntPtr]::Zero)',
            '  Start-Sleep -Milliseconds 30',
            '  [void][HuNativeMouseChild]::SendMessage([IntPtr]$proc.MainWindowHandle,[HuNativeMouseChild]::WM_CHANGEUISTATE,[HuNativeMouseChild]::MakeWParam([HuNativeMouseChild]::UIS_SET,[HuNativeMouseChild]::UISF_HIDEFOCUS),[IntPtr]::Zero)',
            '}'
        )

        $childScript=$childLines -join "`r`n"
        $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($childScript))
        $ps=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'

        Start-Process -FilePath $ps `
            -ArgumentList @('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-STA','-EncodedCommand',$encoded) `
            -WindowStyle Hidden | Out-Null
    }
    catch {
        try { Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\taskmgr.exe') | Out-Null } catch { }
    }
}

function Open-HuTaskManagerDiskTarget {
    param([Parameter(Mandatory=$true)][int]$DiskNumber)

    try {
        $performanceLabel=[string](T 'TaskManagerPerformancePage')
        $diskEnglish='Disk {0}' -f $DiskNumber
        $diskFrench='Disque {0}' -f $DiskNumber
        $performance64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($performanceLabel))
        $diskEnglish64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($diskEnglish))
        $diskFrench64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($diskFrench))
        $nativeCode='using System;using System.Runtime.InteropServices;public static class HuNativeMouseChild{[StructLayout(LayoutKind.Sequential)]public struct RECT{public int Left;public int Top;public int Right;public int Bottom;}[DllImport("user32.dll")]public static extern bool SetCursorPos(int X,int Y);[DllImport("user32.dll")]public static extern void mouse_event(uint f,uint dx,uint dy,uint data,UIntPtr extra);[DllImport("user32.dll")]public static extern bool GetWindowRect(IntPtr hWnd,out RECT rect);[DllImport("user32.dll")]public static extern bool SetForegroundWindow(IntPtr hWnd);[DllImport("user32.dll")]public static extern IntPtr SendMessage(IntPtr hWnd,uint Msg,UIntPtr wParam,IntPtr lParam);public const uint LEFTDOWN=0x0002;public const uint LEFTUP=0x0004;public const uint WM_CHANGEUISTATE=0x0127;public const uint UIS_SET=1;public const uint UISF_HIDEFOCUS=1;public static UIntPtr MakeWParam(uint lo,uint hi){return (UIntPtr)((hi<<16)|(lo&0xFFFF));}}'
        $native64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($nativeCode))

        $childLines=@(
            '$ErrorActionPreference="SilentlyContinue"',
            'Add-Type -AssemblyName UIAutomationClient',
            'Add-Type -AssemblyName UIAutomationTypes',
            ('$NativeCode=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String("{0}"))' -f $native64),
            'Add-Type -TypeDefinition $NativeCode',
            ('$PerformanceLabel=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String("{0}"))' -f $performance64),
            ('$DiskEnglish=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String("{0}"))' -f $diskEnglish64),
            ('$DiskFrench=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String("{0}"))' -f $diskFrench64),
            ('$DiskNumber={0}' -f $DiskNumber),
            '$PerformanceLabels=@($PerformanceLabel,"Performance","Performances")',
            '$TargetLabels=@($DiskEnglish,$DiskFrench)',
            '$PerformanceIds=@("Performance","PerformancePage","PerformancePageNav","PerformanceNavigationViewItem")',
            '$TargetIds=@(("Disk{0}" -f $DiskNumber),("Disk {0}" -f $DiskNumber),("Disk_{0}" -f $DiskNumber))',
            'function Find-Element($Root,[string[]]$Labels,[string[]]$Ids){',
            '  try{$all=$Root.FindAll([Windows.Automation.TreeScope]::Descendants,[Windows.Automation.Condition]::TrueCondition)}catch{return $null}',
            '  foreach($e in $all){',
            '    $name="";$id=""',
            '    try{$name=[string]$e.Current.Name}catch{}',
            '    try{$id=[string]$e.Current.AutomationId}catch{}',
            '    foreach($label in $Labels){if([string]::IsNullOrWhiteSpace($label)){continue};if($name -eq $label -or $name.StartsWith($label,[StringComparison]::OrdinalIgnoreCase)){return $e}}',
            '    foreach($candidate in $Ids){if([string]::IsNullOrWhiteSpace($candidate)){continue};if($id -eq $candidate -or $id.IndexOf($candidate,[StringComparison]::OrdinalIgnoreCase) -ge 0){return $e}}',
            '  }',
            '  return $null',
            '}',
            'function Invoke-Element($Element){',
            '  try{$p=$null;if($Element.TryGetCurrentPattern([Windows.Automation.SelectionItemPattern]::Pattern,[ref]$p)){$p.Select();return $true}}catch{}',
            '  try{$p=$null;if($Element.TryGetCurrentPattern([Windows.Automation.InvokePattern]::Pattern,[ref]$p)){$p.Invoke();return $true}}catch{}',
            '  try{$p=$null;if($Element.TryGetCurrentPattern([Windows.Automation.LegacyIAccessiblePattern]::Pattern,[ref]$p)){$p.DoDefaultAction();return $true}}catch{}',
            '  try{$pt=$null;if($Element.TryGetClickablePoint([ref]$pt)){[void][HuNativeMouseChild]::SetCursorPos([int]$pt.X,[int]$pt.Y);Start-Sleep -Milliseconds 20;[HuNativeMouseChild]::mouse_event([HuNativeMouseChild]::LEFTDOWN,0,0,0,[UIntPtr]::Zero);[HuNativeMouseChild]::mouse_event([HuNativeMouseChild]::LEFTUP,0,0,0,[UIntPtr]::Zero);return $true}}catch{}',
            '  return $false',
            '}',
            'Start-Process -FilePath (Join-Path $env:SystemRoot "System32\taskmgr.exe") | Out-Null',
            '$proc=$null',
            'for($i=0;$i -lt 80;$i++){$proc=Get-Process -Name Taskmgr -ErrorAction SilentlyContinue|Where-Object{$_.MainWindowHandle -ne 0}|Select-Object -First 1;if($proc){break};Start-Sleep -Milliseconds 100}',
            'if(-not $proc){exit}',
            '$root=[Windows.Automation.AutomationElement]::FromHandle($proc.MainWindowHandle)',
            'if(-not $root){exit}',
            '$performance=$null',
            'for($i=0;$i -lt 40;$i++){$performance=Find-Element $root $PerformanceLabels $PerformanceIds;if($performance){break};Start-Sleep -Milliseconds 100}',
            'if($performance){[void](Invoke-Element $performance)}',
            'Start-Sleep -Milliseconds 120',
            '$root=[Windows.Automation.AutomationElement]::FromHandle($proc.MainWindowHandle)',
            '$targetElement=$null',
            'for($i=0;$i -lt 40;$i++){$targetElement=Find-Element $root $TargetLabels $TargetIds;if($targetElement){break};Start-Sleep -Milliseconds 100}',
            'if($targetElement){[void](Invoke-Element $targetElement)}',
            'Start-Sleep -Milliseconds 80',
            '$rect=New-Object HuNativeMouseChild+RECT',
            'if([HuNativeMouseChild]::GetWindowRect([IntPtr]$proc.MainWindowHandle,[ref]$rect)){',
            '  [void][HuNativeMouseChild]::SetForegroundWindow([IntPtr]$proc.MainWindowHandle)',
            '  $width=$rect.Right-$rect.Left',
            '  $x=[int]($rect.Left+($width*0.55))',
            '  $y=[int]($rect.Top+72)',
            '  [void][HuNativeMouseChild]::SetCursorPos($x,$y)',
            '  Start-Sleep -Milliseconds 20',
            '  [HuNativeMouseChild]::mouse_event([HuNativeMouseChild]::LEFTDOWN,0,0,0,[UIntPtr]::Zero)',
            '  [HuNativeMouseChild]::mouse_event([HuNativeMouseChild]::LEFTUP,0,0,0,[UIntPtr]::Zero)',
            '  Start-Sleep -Milliseconds 30',
            '  [void][HuNativeMouseChild]::SendMessage([IntPtr]$proc.MainWindowHandle,[HuNativeMouseChild]::WM_CHANGEUISTATE,[HuNativeMouseChild]::MakeWParam([HuNativeMouseChild]::UIS_SET,[HuNativeMouseChild]::UISF_HIDEFOCUS),[IntPtr]::Zero)',
            '}'
        )

        $childScript=$childLines -join "`r`n"
        $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($childScript))
        $ps=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        Start-Process -FilePath $ps -ArgumentList @('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-STA','-EncodedCommand',$encoded) -WindowStyle Hidden | Out-Null
    }
    catch {
        try { Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\taskmgr.exe') | Out-Null } catch { }
    }
}

function Open-HuNvidiaControlPanel {
    try {
        $paths=@((Join-Path $env:ProgramFiles 'NVIDIA Corporation\Control Panel Client\nvcplui.exe'))
        if(${env:ProgramFiles(x86)}){
            $paths += Join-Path ${env:ProgramFiles(x86)} 'NVIDIA Corporation\Control Panel Client\nvcplui.exe'
        }

        foreach($path in $paths){
            if($path -and (Test-Path -LiteralPath $path -PathType Leaf)){
                Start-Process -FilePath $path | Out-Null
                return
            }
        }

        $app=Get-StartApps | Where-Object {$_.Name -match 'NVIDIA.*Control Panel'} | Select-Object -First 1
        if($app){
            Start-Process -FilePath 'explorer.exe' -ArgumentList ('shell:AppsFolder\' + [string]$app.AppID) | Out-Null
            return
        }

        throw (TF 'SystemToolUnavailable' @('NVIDIA Control Panel'))
    }
    catch { Show-AppError $_.Exception.Message }
}

function Open-HuNetworkAdapterProperties {
    param([AllowEmptyString()][string]$InterfaceAlias)

    $alias = ([string]$InterfaceAlias).Trim()
    if ([string]::IsNullOrWhiteSpace($alias)) {
        Start-Process 'control.exe' -ArgumentList 'ncpa.cpl' | Out-Null
        return
    }

    try {
        $shell = New-Object -ComObject Shell.Application
        $folder = $shell.Namespace('shell:::{7007ACC7-3202-11D1-AAD2-00805FC1270E}')
        if ($folder) {
            $item = @($folder.Items() | Where-Object { ([string]$_.Name).Trim() -ieq $alias } | Select-Object -First 1)
            if ($item.Count -gt 0 -and $item[0]) {
                $propertyVerb = @($item[0].Verbs() | Where-Object {
                    $verbName = (([string]$_.Name) -replace '&','').Trim()
                    $verbName -match '^(?i)(properties|propriétés)$'
                } | Select-Object -First 1)
                if ($propertyVerb.Count -gt 0 -and $propertyVerb[0]) {
                    $propertyVerb[0].DoIt()
                    return
                }
                $item[0].InvokeVerb('properties')
                return
            }
        }
    }
    catch { }

    Start-Process 'control.exe' -ArgumentList 'ncpa.cpl' | Out-Null
}

$ProcessorCard.Add_MouseLeftButtonUp({
    if(-not (Test-HuThisPcCardClickReady)){return}
    Open-HuTaskManagerTarget -Target 'CPU'
})

$MemoryCard.Add_MouseLeftButtonUp({
    if(-not (Test-HuThisPcCardClickReady)){return}
    Open-HuTaskManagerTarget -Target 'Memory'
})

$GraphicsCard.Add_MouseLeftButtonUp({
    if(-not (Test-HuThisPcCardClickReady)){return}
    try {
        $isNvidia = if ($null -ne $script:PrimaryGpuIsNvidia) {
            [bool]$script:PrimaryGpuIsNvidia
        } else {
            [string]$GraphicsValue.Text -match 'NVIDIA'
        }

        if ($isNvidia) {
            Open-HuNvidiaControlPanel
            return
        }

        Open-HuTaskManagerTarget -Target 'GPU'
    }
    catch { Show-AppError $_.Exception.Message }
})


$MotherboardCard.Add_MouseLeftButtonUp({
    if(-not (Test-HuThisPcCardClickReady)){return}
    try {
        $url = [string]$script:MotherboardOfficialUrl
        if (-not [string]::IsNullOrWhiteSpace($url)) { Start-Process $url | Out-Null }
    }
    catch { Show-AppError $_.Exception.Message }
})

$NetworkInfoCard.Add_MouseLeftButtonUp({
    if(-not (Test-HuThisPcCardClickReady)){return}
    try { Open-HuNetworkAdapterProperties -InterfaceAlias ([string]$script:NetworkInterfaceAlias) }
    catch { Show-AppError $_.Exception.Message }
})

$DisplayPreviousButton.Add_Click({
    if (@($script:DisplayMonitors).Count -le 1) { return }
    $script:DisplayCarouselIndex--
    Update-HuDisplayCarousel
})
$DisplayNextButton.Add_Click({
    if (@($script:DisplayMonitors).Count -le 1) { return }
    $script:DisplayCarouselIndex++
    Update-HuDisplayCarousel
})
$DisplayResolutionCombo.Add_SelectionChanged({
    if (-not $script:DisplayUiUpdating) { Update-HuDisplayRefreshOptions }
})
$DisplayApplyResolutionButton.Add_Click({ Invoke-HuDisplayModeChange })
$DisplayApplyRefreshButton.Add_Click({ Invoke-HuDisplayModeChange })
$DisplayApplyScalingButton.Add_Click({ Invoke-HuDisplayScaleChange })

$RefreshSpecsButton.Add_Click({ Refresh-ThisPcInformation })
$CopySpecsButton.Add_Click({ try { if(-not $script:SpecsLoaded){Refresh-ThisPcInformation}; if($script:SpecsText){[Windows.Clipboard]::SetText([string]$script:SpecsText); Show-AppInfo (T 'SpecsCopied')} } catch { Show-AppError $_.Exception.Message } })
$RenameComputerButton.Add_Click({
    $newName = Show-AppTextPrompt -Title (T 'RenameComputerTitle') -Hint (T 'RenameComputerHint') -InitialValue ([string]$env:COMPUTERNAME) -MaxLength 15
    if ($null -eq $newName) { return }
    if ($newName -notmatch '^(?=.{1,15}$)(?![0-9]+$)[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?$') { Show-AppError (T 'InvalidComputerName'); return }
    if ($newName -ieq [string]$env:COMPUTERNAME) { return }
    try {
        if (-not (Test-HuAdministrator)) { throw (T 'AdministratorRequired') }
        Rename-Computer -NewName $newName -Force -ErrorAction Stop
        $ComputerNameValue.Text = TF 'PendingComputerName' @($newName)
        Show-AppInfo (T 'RenameComputerSuccess')
    }
    catch { Show-AppError $_.Exception.Message }
})
$GodModeButton.Add_Click({ try { Start-Process -FilePath (Join-Path $env:SystemRoot 'explorer.exe') -ArgumentList 'shell:::{ED7BA470-8E54-465E-825C-99712043E01C}' } catch { Show-AppError $_.Exception.Message } })

$SourceUrlBox.Add_TextChanged({
    Update-SourceBanner
    if (-not $script:Initializing) { $saveTimer.Stop(); $saveTimer.Start() }
})
