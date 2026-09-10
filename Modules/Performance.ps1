$script:HuPowerSchemes = @{
    Eco         = 'a1841308-3541-4fab-bc81-f71556f20b4a'
    Normal      = '381b4222-f694-41f0-9685-ff5bb260df2e'
    High        = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
}

function Get-HuRegistryValue {
    param([string]$Path,[string]$Name,[object]$Default=$null)
    try { return Get-ItemPropertyValue -LiteralPath $Path -Name $Name -ErrorAction Stop } catch { return $Default }
}

function Set-HuRegistryValue {
    param([string]$Path,[string]$Name,[object]$Value,[ValidateSet('DWord','String')][string]$Type='DWord')
    if (-not (Test-Path -LiteralPath $Path)) { New-Item -Path $Path -Force | Out-Null }
    New-ItemProperty -LiteralPath $Path -Name $Name -PropertyType $Type -Value $Value -Force | Out-Null
}

function Remove-HuRegistryValue {
    param([string]$Path,[string]$Name)
    if (Test-Path -LiteralPath $Path) { Remove-ItemProperty -LiteralPath $Path -Name $Name -Force -ErrorAction SilentlyContinue }
}

function Get-HuPerformanceBackupPath { 'HKCU:\Software\WNST\ReversibleState\Performance' }

function Save-HuRegistryValueState {
    param([string]$Id,[string]$Path,[string]$Name)
    $backupPath = Get-HuPerformanceBackupPath
    if ($null -ne (Get-HuRegistryValue $backupPath ($Id + '_Exists') $null)) { return }
    $value = Get-HuRegistryValue $Path $Name $null
    Set-HuRegistryValue $backupPath ($Id + '_Exists') $(if ($null -eq $value) { 0 } else { 1 })
    if ($null -ne $value) {
        $type = if ($value -is [string]) { 'String' } else { 'DWord' }
        Set-HuRegistryValue $backupPath ($Id + '_Value') $value $type
        Set-HuRegistryValue $backupPath ($Id + '_Type') $type 'String'
    }
}

function Restore-HuRegistryValueState {
    param(
        [string]$Id,
        [string]$Path,
        [string]$Name,
        [object]$FallbackValue = $null,
        [ValidateSet('DWord','String')][string]$FallbackType = 'DWord'
    )
    $backupPath = Get-HuPerformanceBackupPath
    $exists = Get-HuRegistryValue $backupPath ($Id + '_Exists') $null
    if ($null -eq $exists) {
        if ($null -eq $FallbackValue) { Remove-HuRegistryValue $Path $Name }
        else { Set-HuRegistryValue $Path $Name $FallbackValue $FallbackType }
        return
    }

    if ([int]$exists -eq 1) {
        $value = Get-HuRegistryValue $backupPath ($Id + '_Value') $FallbackValue
        $type = [string](Get-HuRegistryValue $backupPath ($Id + '_Type') $FallbackType)
        if ($type -notin @('DWord','String')) { $type = $FallbackType }
        Set-HuRegistryValue $Path $Name $value $type
    }
    else {
        Remove-HuRegistryValue $Path $Name
    }

    foreach ($suffix in @('_Exists','_Value','_Type')) {
        Remove-HuRegistryValue $backupPath ($Id + $suffix)
    }
}

function Initialize-HuWindowsAnimationApi {
    if ('WnstAnimation.NativeMethods' -as [type]) { return }
    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;

namespace WnstAnimation {
    [StructLayout(LayoutKind.Sequential)]
    public struct AnimationInfo {
        public uint cbSize;
        public int iMinAnimate;
    }

    public static class NativeMethods {
        private const uint UpdateProfileAndBroadcast = 0x0001 | 0x0002;

        [DllImport("user32.dll", EntryPoint = "SystemParametersInfoW", SetLastError = true)]
        private static extern bool SystemParametersInfoBool(uint action, uint parameter, ref int value, uint flags);

        [DllImport("user32.dll", EntryPoint = "SystemParametersInfoW", SetLastError = true)]
        private static extern bool SystemParametersInfoSetBool(uint action, uint parameter, IntPtr value, uint flags);

        [DllImport("user32.dll", EntryPoint = "SystemParametersInfoW", SetLastError = true)]
        private static extern bool SystemParametersInfoAnimation(uint action, uint parameter, ref AnimationInfo value, uint flags);

        public static bool GetBoolean(uint action) {
            int value = 0;
            if (!SystemParametersInfoBool(action, 0, ref value, 0)) {
                throw new Win32Exception(Marshal.GetLastWin32Error());
            }
            return value != 0;
        }

        public static void SetBoolean(uint action, bool enabled) {
            IntPtr value = enabled ? new IntPtr(1) : IntPtr.Zero;
            if (!SystemParametersInfoSetBool(action, 0, value, UpdateProfileAndBroadcast)) {
                throw new Win32Exception(Marshal.GetLastWin32Error());
            }
        }

        public static bool GetMinimizeAnimation() {
            AnimationInfo value = new AnimationInfo();
            value.cbSize = (uint)Marshal.SizeOf(typeof(AnimationInfo));
            if (!SystemParametersInfoAnimation(0x0048, value.cbSize, ref value, 0)) {
                throw new Win32Exception(Marshal.GetLastWin32Error());
            }
            return value.iMinAnimate != 0;
        }

        public static void SetMinimizeAnimation(bool enabled) {
            AnimationInfo value = new AnimationInfo();
            value.cbSize = (uint)Marshal.SizeOf(typeof(AnimationInfo));
            value.iMinAnimate = enabled ? 1 : 0;
            if (!SystemParametersInfoAnimation(0x0049, value.cbSize, ref value, UpdateProfileAndBroadcast)) {
                throw new Win32Exception(Marshal.GetLastWin32Error());
            }
        }
    }
}
'@
}

function Get-HuWindowsAnimationDefinitions {
    @(
        [pscustomobject]@{ Name='ClientAreaAnimation';       GetAction=[uint32]0x1042; SetAction=[uint32]0x1043 },
        [pscustomobject]@{ Name='MenuAnimation';             GetAction=[uint32]0x1002; SetAction=[uint32]0x1003 },
        [pscustomobject]@{ Name='ComboBoxAnimation';         GetAction=[uint32]0x1004; SetAction=[uint32]0x1005 },
        [pscustomobject]@{ Name='ListBoxSmoothScrolling';    GetAction=[uint32]0x1006; SetAction=[uint32]0x1007 },
        [pscustomobject]@{ Name='MenuFade';                  GetAction=[uint32]0x1012; SetAction=[uint32]0x1013 },
        [pscustomobject]@{ Name='SelectionFade';             GetAction=[uint32]0x1014; SetAction=[uint32]0x1015 },
        [pscustomobject]@{ Name='ToolTipAnimation';          GetAction=[uint32]0x1016; SetAction=[uint32]0x1017 },
        [pscustomobject]@{ Name='ToolTipFade';               GetAction=[uint32]0x1018; SetAction=[uint32]0x1019 }
    )
}

function Get-HuWindowsAnimationEffectsState {
    Initialize-HuWindowsAnimationApi
    $state = [ordered]@{}
    foreach ($definition in @(Get-HuWindowsAnimationDefinitions)) {
        $state[$definition.Name] = [bool][WnstAnimation.NativeMethods]::GetBoolean($definition.GetAction)
    }
    $state.MinimizeAnimation = [bool][WnstAnimation.NativeMethods]::GetMinimizeAnimation()
    [pscustomobject]$state
}

function Set-HuWindowsAnimationEffectsState {
    param([Parameter(Mandatory=$true)][object]$State)
    Initialize-HuWindowsAnimationApi
    foreach ($definition in @(Get-HuWindowsAnimationDefinitions)) {
        [WnstAnimation.NativeMethods]::SetBoolean($definition.SetAction,[bool]$State.($definition.Name))
    }
    [WnstAnimation.NativeMethods]::SetMinimizeAnimation([bool]$State.MinimizeAnimation)
}

function Test-HuLegacyAnimationsBundleDisabled {
    $explorer = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
    return ([int](Get-HuRegistryValue $explorer 'TaskbarAnimations' 1) -eq 0) -and
        ([int](Get-HuRegistryValue $explorer 'ListviewAlphaSelect' 1) -eq 0) -and
        ([int](Get-HuRegistryValue $explorer 'ListviewShadow' 1) -eq 0) -and
        ([int](Get-HuRegistryValue 'HKCU:\Software\Microsoft\Windows\DWM' 'EnableAeroPeek' 1) -eq 0) -and
        ([string](Get-HuRegistryValue 'HKCU:\Control Panel\Desktop\WindowMetrics' 'MinAnimate' '1') -eq '0')
}

function Save-HuWindowsAnimationEffectsState {
    $backupPath = Get-HuPerformanceBackupPath
    if ($null -ne (Get-HuRegistryValue $backupPath 'Animations_SnapshotExists' $null)) { return }
    $state = Get-HuWindowsAnimationEffectsState
    foreach ($property in @($state.PSObject.Properties)) {
        Set-HuRegistryValue $backupPath ('Animations_' + $property.Name) $(if ([bool]$property.Value) { 1 } else { 0 })
    }
    Save-HuRegistryValueState -Id 'Animations_TaskbarAnimations' -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'TaskbarAnimations'
    $legacyBundle = Test-HuLegacyAnimationsBundleDisabled
    Set-HuRegistryValue $backupPath 'Animations_LegacyBundle' $(if ($legacyBundle) { 1 } else { 0 })
    if ($legacyBundle) { Set-HuRegistryValue $backupPath 'Animations_MinimizeAnimation' 1 }
    Set-HuRegistryValue $backupPath 'Animations_SnapshotExists' 1
}

function Repair-HuLegacyTaskbarAnimationOwnership {
    $backupPath = Get-HuPerformanceBackupPath
    if ($null -eq (Get-HuRegistryValue $backupPath 'TaskbarAnimations_Exists' $null)) { return $false }
    if ($null -eq (Get-HuRegistryValue $backupPath 'Animations_SnapshotExists' $null)) {
        Restore-HuRegistryValueState -Id 'TaskbarAnimations' -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'TaskbarAnimations' -FallbackValue 1
    }
    else {
        foreach ($suffix in @('_Exists','_Value','_Type')) { Remove-HuRegistryValue $backupPath ('TaskbarAnimations' + $suffix) }
    }
    return $true
}

function Restore-HuWindowsAnimationEffectsState {
    $backupPath = Get-HuPerformanceBackupPath
    $hasSnapshot = $null -ne (Get-HuRegistryValue $backupPath 'Animations_SnapshotExists' $null)
    $state = [ordered]@{}
    foreach ($definition in @(Get-HuWindowsAnimationDefinitions)) {
        $state[$definition.Name] = if ($hasSnapshot) { [int](Get-HuRegistryValue $backupPath ('Animations_' + $definition.Name) 1) -ne 0 } else { $true }
    }
    $state.MinimizeAnimation = if ($hasSnapshot) { [int](Get-HuRegistryValue $backupPath 'Animations_MinimizeAnimation' 1) -ne 0 } else { $true }
    Set-HuWindowsAnimationEffectsState -State ([pscustomobject]$state)

    $legacyBundle = [int](Get-HuRegistryValue $backupPath 'Animations_LegacyBundle' 0) -eq 1
    Restore-HuRegistryValueState -Id 'Animations_TaskbarAnimations' -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'TaskbarAnimations' -FallbackValue 1
    if ($legacyBundle) {
        $explorer = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
        Set-HuRegistryValue $explorer 'TaskbarAnimations' 1
        Set-HuRegistryValue $explorer 'ListviewAlphaSelect' 1
        Set-HuRegistryValue $explorer 'ListviewShadow' 1
        Set-HuRegistryValue 'HKCU:\Software\Microsoft\Windows\DWM' 'EnableAeroPeek' 1
    }

    foreach ($definition in @(Get-HuWindowsAnimationDefinitions)) {
        Remove-HuRegistryValue $backupPath ('Animations_' + $definition.Name)
    }
    foreach ($name in @('Animations_MinimizeAnimation','Animations_LegacyBundle','Animations_SnapshotExists')) {
        Remove-HuRegistryValue $backupPath $name
    }
}

function Test-HuWindowsAnimationEffectsDisabled {
    try {
        $state = Get-HuWindowsAnimationEffectsState
        foreach ($property in @($state.PSObject.Properties)) {
            if ([bool]$property.Value) { return $false }
        }
        return [int](Get-HuRegistryValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'TaskbarAnimations' 1) -eq 0
    }
    catch { return $false }
}

function Assert-HuMachineChange {
    if (-not (Test-HuAdministrator)) { throw 'AdministratorRequired' }
}

function Repair-HuHomeGalleryFolderDescriptions {
    param(
        [string]$FolderDescriptionsRoot = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FolderDescriptions'
    )

    Assert-HuMachineChange
    $removed = New-Object 'System.Collections.Generic.List[string]'
    foreach ($id in @('{f874310e-b6b7-47dc-bc84-b9e6b38f5903}','{e88865ea-0e1c-4e20-9aa6-edcd0212c87c}')) {
        $descriptionPath = Join-Path $FolderDescriptionsRoot $id
        $propertyBagPath = Join-Path $descriptionPath 'PropertyBag'
        if (-not (Test-Path -LiteralPath $descriptionPath) -or -not (Test-Path -LiteralPath $propertyBagPath)) { continue }

        $policy = Get-HuRegistryValue $propertyBagPath 'ThisPCPolicy' $null
        if ([string]$policy -notin @('Hide','Show')) { continue }

        $rootItem = Get-ItemProperty -LiteralPath $descriptionPath -ErrorAction SilentlyContinue
        $rootProperties = @($rootItem.PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' })
        $children = @(Get-ChildItem -LiteralPath $descriptionPath -ErrorAction SilentlyContinue)
        $bagItem = Get-ItemProperty -LiteralPath $propertyBagPath -ErrorAction SilentlyContinue
        $bagProperties = @($bagItem.PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' })

        $isWnstPartialDescription = @($rootProperties).Count -eq 0 -and
            $children.Count -eq 1 -and [string]$children[0].PSChildName -eq 'PropertyBag' -and
            @($bagProperties).Count -eq 1 -and [string]$bagProperties[0].Name -eq 'ThisPCPolicy'

        if ($isWnstPartialDescription) {
            Remove-Item -LiteralPath $descriptionPath -Recurse -Force -ErrorAction Stop
            $removed.Add($id)
        }
    }

    [pscustomobject]@{ RemovedCount=$removed.Count; RemovedIds=@($removed) }
}

function Get-HuPerformanceState {
    $explorer = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
    $content = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
    $cloud = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent'
    $notificationPolicy = 'HKCU:\Software\Policies\Microsoft\Windows\CurrentVersion\PushNotifications'
    $notificationSettings = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings'
    $legacyMenu = 'HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32'
    $legacyExplorer = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Shell Extensions\Blocked'
    $legacyExplorerSupported = [Environment]::OSVersion.Version.Build -lt 22621
    $homeGalleryIds = @('{f874310e-b6b7-47dc-bc84-b9e6b38f5903}','{e88865ea-0e1c-4e20-9aa6-edcd0212c87c}')
    $homeGalleryHidden = @($homeGalleryIds | Where-Object {
        [int](Get-HuRegistryValue "HKCU:\Software\Classes\CLSID\$_" 'System.IsPinnedToNameSpaceTree' 1) -eq 0
    }).Count -eq $homeGalleryIds.Count
    $suggestionNames = @('SilentInstalledAppsEnabled','SystemPaneSuggestionsEnabled','SubscribedContent-338388Enabled','SubscribedContent-338389Enabled','SubscribedContent-353694Enabled','SubscribedContent-353696Enabled')
    $suggestionsBlocked = @($suggestionNames | Where-Object { [int](Get-HuRegistryValue $content $_ 1) -eq 0 }).Count -eq $suggestionNames.Count
    $animationValuesDisabled = Test-HuWindowsAnimationEffectsDisabled
    $cloudNotificationsDisabled = ([int](Get-HuRegistryValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CurrentVersion\PushNotifications' 'DisallowCloudNotification' 0) -eq 1) -or
        ([int](Get-HuRegistryValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CurrentVersion\PushNotifications' 'NoCloudApplicationNotification' 0) -eq 1)
    $notificationsDisabled = ([int](Get-HuRegistryValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\PushNotifications' 'ToastEnabled' 1) -eq 0) -and
        ([int](Get-HuRegistryValue $notificationPolicy 'NoToastApplicationNotification' 0) -eq 1) -and
        ([int](Get-HuRegistryValue $notificationPolicy 'NoToastApplicationNotificationOnLockScreen' 0) -eq 1) -and
        ([int](Get-HuRegistryValue $notificationSettings 'NOC_GLOBAL_SETTING_TOASTS_ENABLED' 1) -eq 0) -and
        $cloudNotificationsDisabled -and
        ([int](Get-HuRegistryValue 'HKCU:\Software\Policies\Microsoft\Windows\Explorer' 'DisableNotificationCenter' 0) -eq 1) -and
        ([int](Get-HuRegistryValue $explorer 'ShowNotificationIcon' 1) -eq 0)

    $defenderCpu = 50
    $defenderPolicy = Get-HuRegistryValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Scan' 'AvgCPULoadFactor' $null
    if ($null -ne $defenderPolicy) { $defenderCpu = [int]$defenderPolicy }
    else { try { $defenderCpu = [int](Get-MpPreference -ErrorAction Stop).ScanAvgCPULoadFactor } catch { } }

    [pscustomobject]@{
        DefenderCpu        = $defenderCpu
        BingDisabled       = [int](Get-HuRegistryValue 'HKCU:\Software\Policies\Microsoft\Windows\Explorer' 'DisableSearchBoxSuggestions' 0) -eq 1
        SponsoredBlocked   = [int](Get-HuRegistryValue $cloud 'DisableWindowsConsumerFeatures' 0) -eq 1
        SuggestionsBlocked = $suggestionsBlocked
        Transparency       = [int](Get-HuRegistryValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'EnableTransparency' 1) -ne 0
        AnimationsDisabled = $animationValuesDisabled
        ShutdownAnimationDisabled = [int](Get-HuRegistryValue 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' 'DisableStatusMessages' 0) -eq 1
        HomeGalleryHidden  = $homeGalleryHidden
        ClockSeconds       = [int](Get-HuRegistryValue $explorer 'ShowSecondsInSystemClock' 0) -eq 1
        NotificationsDisabled = $notificationsDisabled
        EndTask            = [int](Get-HuRegistryValue (Join-Path $explorer 'TaskbarDeveloperSettings') 'TaskbarEndTask' 0) -eq 1
        LegacyContextMenu  = Test-Path -LiteralPath $legacyMenu
        LegacyExplorer     = $legacyExplorerSupported -and ($null -ne (Get-HuRegistryValue $legacyExplorer '{e2bf9676-5f8f-435c-97eb-11607a5bedf7}' $null))
        LegacyExplorerSupported = $legacyExplorerSupported
        GameFeaturesDisabled = ([int](Get-HuRegistryValue 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled' 1) -eq 0) -and
            ([int](Get-HuRegistryValue 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR' 'AppCaptureEnabled' 1) -eq 0) -and
            ([int](Get-HuRegistryValue 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR' 'HistoricalCaptureEnabled' 1) -eq 0) -and
            ([int](Get-HuRegistryValue 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR' 'VKMToggleGameBar' 1) -eq 0) -and
            ([int](Get-HuRegistryValue 'HKCU:\SOFTWARE\Microsoft\GameBar' 'UseNexusForGameBarEnabled' 1) -eq 0) -and
            ([int](Get-HuRegistryValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR' 'AllowGameDVR' 1) -eq 0)
        BackgroundThrottleDisabled = [int](Get-HuRegistryValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling' 'PowerThrottlingOff' 0) -eq 1
        LatencyOptimized   = [uint32](Get-HuRegistryValue 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' 'NetworkThrottlingIndex' 10) -eq [uint32]::MaxValue
        TasksDisabled      = Test-HuGamingTasksDisabled
        ServicesDisabled   = Test-HuBackgroundServicesDisabled
        TaskbarOptimized   = [int](Get-HuRegistryValue $explorer 'TaskbarBadges' 1) -eq 0
        StartupOptimized   = [int](Get-HuRegistryValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize' 'StartupDelayInMSec' -1) -eq 0
        ActivePowerMode    = Get-HuActivePowerMode
    }
}

function Set-HuDefenderCpuLimit {
    param([ValidateRange(5,100)][int]$Percent)
    Assert-HuMachineChange
    $policyPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Scan'
    Set-HuRegistryValue $policyPath 'AvgCPULoadFactor' $Percent
    # Defender ignores ScanAvgCPULoadFactor when idle scans explicitly disable
    # CPU throttling. Keep throttling enabled so the selected percentage is
    # effective for scheduled scans as well.
    Set-HuRegistryValue $policyPath 'DisableCpuThrottleOnIdleScans' 0
    $preferenceError = ''
    try { Set-MpPreference -ScanAvgCPULoadFactor $Percent -DisableCpuThrottleOnIdleScans $false -ErrorAction Stop }
    catch { $preferenceError = [string]$_.Exception.Message }

    $policyActual = -1
    $defenderActual = -1
    $defenderReadable = $false
    $idleThrottleDisabled = $false
    for ($attempt = 0; $attempt -lt 6; $attempt++) {
        $policyActual = [int](Get-HuRegistryValue $policyPath 'AvgCPULoadFactor' -1)
        try {
            $preference = Get-MpPreference -ErrorAction Stop
            $defenderActual = [int]$preference.ScanAvgCPULoadFactor
            $idleThrottleDisabled = [bool]$preference.DisableCpuThrottleOnIdleScans
            $defenderReadable = $true
        }
        catch { $defenderReadable = $false }
        if ($policyActual -eq $Percent -and (-not $defenderReadable -or ($defenderActual -eq $Percent -and -not $idleThrottleDisabled))) { break }
        Start-Sleep -Milliseconds 350
    }
    $actual = if ($defenderReadable) { $defenderActual } else { $policyActual }
    $verified = $policyActual -eq $Percent -and (-not $defenderReadable -or ($defenderActual -eq $Percent -and -not $idleThrottleDisabled))
    [pscustomobject]@{
        Requested=$Percent
        Actual=$actual
        PolicyActual=$policyActual
        DefenderActual=$defenderActual
        DefenderReadable=$defenderReadable
        IdleThrottleDisabled=$idleThrottleDisabled
        Verified=$verified
        PolicyApplied=$policyActual -eq $Percent
        PreferenceError=$preferenceError
    }
}

function Set-HuBingSearchDisabled { param([bool]$Disabled)
    $path='HKCU:\Software\Policies\Microsoft\Windows\Explorer'; if($Disabled){Set-HuRegistryValue $path 'DisableSearchBoxSuggestions' 1}else{Remove-HuRegistryValue $path 'DisableSearchBoxSuggestions'}
}
function Set-HuSponsoredAppsBlocked { param([bool]$Blocked)
    Assert-HuMachineChange; $value=if($Blocked){1}else{0}; Set-HuRegistryValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableWindowsConsumerFeatures' $value
}
function Set-HuSuggestionsBlocked { param([bool]$Blocked)
    $path='HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; $value=if($Blocked){0}else{1}
    foreach($name in @('SilentInstalledAppsEnabled','SystemPaneSuggestionsEnabled','SubscribedContent-338388Enabled','SubscribedContent-338389Enabled','SubscribedContent-353694Enabled','SubscribedContent-353696Enabled')){Set-HuRegistryValue $path $name $value}
}
function Set-HuTransparency { param([bool]$Enabled) Set-HuRegistryValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'EnableTransparency' $(if($Enabled){1}else{0}) }
function Set-HuAnimationsDisabled { param([bool]$Disabled)
    $explorer = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
    Repair-HuLegacyTaskbarAnimationOwnership | Out-Null
    if ($Disabled) {
        Save-HuWindowsAnimationEffectsState
        $disabledState = [ordered]@{}
        foreach ($definition in @(Get-HuWindowsAnimationDefinitions)) { $disabledState[$definition.Name] = $false }
        $disabledState.MinimizeAnimation = $false
        Set-HuWindowsAnimationEffectsState -State ([pscustomobject]$disabledState)
        Set-HuRegistryValue $explorer 'TaskbarAnimations' 0

        $backupPath = Get-HuPerformanceBackupPath
        if ([int](Get-HuRegistryValue $backupPath 'Animations_LegacyBundle' 0) -eq 1) {
            Set-HuRegistryValue $explorer 'ListviewAlphaSelect' 1
            Set-HuRegistryValue $explorer 'ListviewShadow' 1
            Set-HuRegistryValue 'HKCU:\Software\Microsoft\Windows\DWM' 'EnableAeroPeek' 1
        }
    }
    else {
        Restore-HuWindowsAnimationEffectsState
    }
    Restart-HuExplorerShell | Out-Null
}
function Set-HuShutdownAnimationDisabled { param([bool]$Disabled)
    Assert-HuMachineChange; Set-HuRegistryValue 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' 'DisableStatusMessages' $(if($Disabled){1}else{0})
}
function Set-HuHomeGalleryHidden { param([bool]$Hidden)
    Assert-HuMachineChange
    Repair-HuHomeGalleryFolderDescriptions | Out-Null
    $pinValue = if($Hidden){0}else{1}
    foreach($id in @('{f874310e-b6b7-47dc-bc84-b9e6b38f5903}','{e88865ea-0e1c-4e20-9aa6-edcd0212c87c}')){
        Set-HuRegistryValue ("HKCU:\Software\Classes\CLSID\$id") 'System.IsPinnedToNameSpaceTree' $pinValue
    }
    Restart-HuExplorerShell | Out-Null
}
function Set-HuClockSeconds { param([bool]$Enabled) Set-HuRegistryValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'ShowSecondsInSystemClock' $(if($Enabled){1}else{0}) }

function Save-HuNotificationRegistryValue {
    param([string]$Path,[string]$Name,[string]$BackupName,[string]$BackupPath)
    if ($null -ne (Get-HuRegistryValue $BackupPath ($BackupName + '_Exists') $null)) { return }
    $current = Get-HuRegistryValue $Path $Name $null
    Set-HuRegistryValue $BackupPath ($BackupName + '_Exists') $(if($null -eq $current){0}else{1})
    if ($null -ne $current) { Set-HuRegistryValue $BackupPath ($BackupName + '_Value') ([int]$current) }
}

function Restore-HuNotificationRegistryValue {
    param([string]$Path,[string]$Name,[string]$BackupName,[string]$BackupPath,[AllowNull()][object]$FallbackValue)
    $existed = Get-HuRegistryValue $BackupPath ($BackupName + '_Exists') $null
    if ($null -ne $existed) {
        if ([int]$existed -eq 1) {
            $saved = Get-HuRegistryValue $BackupPath ($BackupName + '_Value') $FallbackValue
            if ($null -ne $saved) { Set-HuRegistryValue $Path $Name ([int]$saved) }
        }
        else { Remove-HuRegistryValue $Path $Name }
        Remove-HuRegistryValue $BackupPath ($BackupName + '_Exists')
        Remove-HuRegistryValue $BackupPath ($BackupName + '_Value')
    }
    elseif ($null -eq $FallbackValue) { Remove-HuRegistryValue $Path $Name }
    else { Set-HuRegistryValue $Path $Name ([int]$FallbackValue) }
}

function Restore-HuNotificationServiceInfrastructure {
    $backupPath = 'HKCU:\Software\WNST\ReversibleState'
    $serviceRoot = 'HKLM:\SYSTEM\CurrentControlSet\Services'
    $serviceNames = [Collections.Generic.List[string]]::new()
    foreach ($serviceName in @('WpnService','WpnUserService')) {
        if (Test-Path -LiteralPath (Join-Path $serviceRoot $serviceName)) { $serviceNames.Add($serviceName) }
    }
    foreach ($key in @(Get-ChildItem -LiteralPath $serviceRoot -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -like 'WpnUserService_*' })) {
        if (-not $serviceNames.Contains([string]$key.PSChildName)) { $serviceNames.Add([string]$key.PSChildName) }
    }

    $failures = [Collections.Generic.List[string]]::new()
    $repaired = $false
    foreach ($serviceName in $serviceNames) {
        $servicePath = Join-Path $serviceRoot $serviceName
        $backupName = 'NotificationServiceStart_' + $serviceName
        $savedStart = Get-HuRegistryValue $backupPath $backupName $null
        $currentStart = Get-HuRegistryValue $servicePath 'Start' $null

        # Older WNST builds disabled both the template and the current
        # per-user instance. Prefer their saved values. If an interrupted old
        # build already discarded its backup but left Start=4, enabling the
        # Notification Center explicitly authorizes restoring the required
        # Windows default so that the next sign-in can recreate the instance.
        if ($null -ne $savedStart -or ($null -ne $currentStart -and [int]$currentStart -eq 4)) {
            $restoredStart = if ($null -ne $savedStart -and [int]$savedStart -in @(2,3)) { [int]$savedStart } else { 2 }
            try {
                if ($null -eq $currentStart -or [int]$currentStart -ne $restoredStart) {
                    Set-HuRegistryValue $servicePath 'Start' $restoredStart
                    $repaired = $true
                }
                if ([int](Get-HuRegistryValue $servicePath 'Start' -1) -ne $restoredStart) { throw 'ServiceStartNotRestored' }
                Remove-HuRegistryValue $backupPath $backupName
            }
            catch { $failures.Add(('[SERVICE] {0} -> FAILED' -f $serviceName)) }
        }
    }

    # Remove backup entries left by an older per-user instance. Its LUID suffix
    # changes when Windows recreates the service at the next sign-in.
    if (Test-Path -LiteralPath $backupPath) {
        $backupItem = Get-ItemProperty -LiteralPath $backupPath -ErrorAction SilentlyContinue
        if ($backupItem) {
            foreach ($property in @($backupItem.PSObject.Properties | Where-Object { $_.Name -like 'NotificationServiceStart_WpnUserService_*' })) {
                $instanceName = [string]$property.Name -replace '^NotificationServiceStart_',''
                if (-not (Test-Path -LiteralPath (Join-Path $serviceRoot $instanceName))) {
                    Remove-HuRegistryValue $backupPath ([string]$property.Name)
                }
            }
        }
    }

    $wpnService = Get-Service -Name 'WpnService' -ErrorAction SilentlyContinue
    $userServices = @(Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.Name -like 'WpnUserService_*' })
    $masterHealthy = $wpnService -and [string]$wpnService.Status -eq 'Running'
    $userHealthy = $userServices.Count -gt 0 -and @($userServices | Where-Object { [string]$_.Status -eq 'Running' }).Count -gt 0

    return [pscustomobject]@{
        ConfigurationVerified = ($failures.Count -eq 0)
        Failures = @($failures | Select-Object -Unique)
        RestartRequired = [bool]($repaired -or -not ($masterHealthy -and $userHealthy))
        UserServiceCount = $userServices.Count
    }
}

function Set-HuNotificationsDisabled { param([bool]$Disabled)
    Assert-HuMachineChange
    $toast='HKCU:\Software\Microsoft\Windows\CurrentVersion\PushNotifications'
    $policy='HKCU:\Software\Policies\Microsoft\Windows\CurrentVersion\PushNotifications'
    $machinePolicy='HKLM:\SOFTWARE\Policies\Microsoft\Windows\CurrentVersion\PushNotifications'
    $settings='HKCU:\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings'
    $explorerPolicy='HKCU:\Software\Policies\Microsoft\Windows\Explorer'
    $explorerAdvanced='HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
    $backupPath = 'HKCU:\Software\WNST\ReversibleState'
    $entries = @(
        [pscustomobject]@{Path=$toast;Name='ToastEnabled';Backup='Notification_ToastEnabled';Disabled=0;Fallback=1},
        [pscustomobject]@{Path=$settings;Name='NOC_GLOBAL_SETTING_TOASTS_ENABLED';Backup='Notification_GlobalToasts';Disabled=0;Fallback=1},
        [pscustomobject]@{Path=$policy;Name='NoToastApplicationNotification';Backup='Notification_NoToast';Disabled=1;Fallback=$null},
        [pscustomobject]@{Path=$policy;Name='NoToastApplicationNotificationOnLockScreen';Backup='Notification_NoToastLock';Disabled=1;Fallback=$null},
        [pscustomobject]@{Path=$machinePolicy;Name='DisallowCloudNotification';Backup='Notification_DisallowCloud';Disabled=1;Fallback=$null},
        [pscustomobject]@{Path=$explorerPolicy;Name='DisableNotificationCenter';Backup='Notification_DisableCenter';Disabled=1;Fallback=$null},
        [pscustomobject]@{Path=$explorerAdvanced;Name='ShowNotificationIcon';Backup='Notification_ShowIcon';Disabled=0;Fallback=1}
    )
    if($Disabled){
        foreach($entry in $entries){
            Save-HuNotificationRegistryValue -Path $entry.Path -Name $entry.Name -BackupName $entry.Backup -BackupPath $backupPath
            Set-HuRegistryValue $entry.Path $entry.Name ([int]$entry.Disabled)
        }
        # Remove the non-policy value written by the previous WNST test build.
        Remove-HuRegistryValue $machinePolicy 'NoCloudApplicationNotification'
    }else{
        foreach($entry in $entries){
            Restore-HuNotificationRegistryValue -Path $entry.Path -Name $entry.Name -BackupName $entry.Backup -BackupPath $backupPath -FallbackValue $entry.Fallback
        }
        Remove-HuRegistryValue $machinePolicy 'NoCloudApplicationNotification'
    }

    # These two values only backed up the non-policy name used by the previous
    # test build. They must not be restored onto the real Microsoft policy.
    Remove-HuRegistryValue $backupPath 'Notification_NoCloud_Exists'
    Remove-HuRegistryValue $backupPath 'Notification_NoCloud_Value'

    $soundPath = 'HKCU:\AppEvents\Schemes\Apps\.Default\Notification.Default\.Current'
    if(Test-Path -LiteralPath $soundPath){
        if($Disabled){
            if($null -eq (Get-HuRegistryValue $backupPath 'NotificationSound' $null)){Set-HuRegistryValue $backupPath 'NotificationSound' ([string](Get-Item -LiteralPath $soundPath).GetValue('')) 'String'}
            Set-Item -LiteralPath $soundPath -Value '' -Force -ErrorAction Stop
        }else{
            $savedSound = Get-HuRegistryValue $backupPath 'NotificationSound' $null
            if([string]::IsNullOrWhiteSpace([string]$savedSound)){
                $defaultSoundPath = 'HKCU:\AppEvents\Schemes\Apps\.Default\Notification.Default\.Default'
                if(Test-Path -LiteralPath $defaultSoundPath){$savedSound=[string](Get-Item -LiteralPath $defaultSoundPath).GetValue('')}
            }
            if(-not [string]::IsNullOrWhiteSpace([string]$savedSound)){Set-Item -LiteralPath $soundPath -Value ([string]$savedSound) -Force -ErrorAction Stop}
            Remove-HuRegistryValue $backupPath 'NotificationSound'
        }
    }
    # Notification Center is controlled through reversible policies, user
    # settings and its separate taskbar icon value. Never stop or reconfigure
    # the live per-user service: Windows owns that session-specific instance.
    # On reactivation, only repair service Start values backed up by an older
    # WNST build; Windows will recreate/restart the instance at the next sign-in.
    $serviceRepair = if($Disabled){
        [pscustomobject]@{ConfigurationVerified=$true;Failures=@();RestartRequired=$true}
    }else{
        Restore-HuNotificationServiceInfrastructure
    }

    if(-not $Disabled){
        foreach($processName in @('ShellExperienceHost','StartMenuExperienceHost')){
            try{Get-Process -Name $processName -ErrorAction SilentlyContinue|Stop-Process -Force -ErrorAction SilentlyContinue}catch{}
        }
    }
    Restart-HuExplorerShell | Out-Null
    [pscustomobject]@{
        Disabled=$Disabled
        Verified=(Get-HuPerformanceState).NotificationsDisabled
        InfrastructureVerified=[bool]$serviceRepair.ConfigurationVerified
        InfrastructureErrors=@($serviceRepair.Failures)
        # Windows applies the complete Notification Center state at sign-in.
        # Require a restart in both directions so the visible shell state and
        # the verified registry state cannot diverge.
        RestartRequired=$true
    }
}

function Set-HuEndTask { param([bool]$Enabled) Set-HuRegistryValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarDeveloperSettings' 'TaskbarEndTask' $(if($Enabled){1}else{0}) }
function Set-HuLegacyContextMenu { param([bool]$Enabled)
    $root='HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}'
    if($Enabled){$path=Join-Path $root 'InprocServer32';if(-not(Test-Path -LiteralPath $path)){New-Item -Path $path -Force|Out-Null};Set-Item -LiteralPath $path -Value '' -Force}
    elseif(Test-Path -LiteralPath $root){Remove-Item -LiteralPath $root -Recurse -Force}
    Restart-HuExplorerShell | Out-Null
}
function Set-HuLegacyExplorer { param([bool]$Enabled)
    if([Environment]::OSVersion.Version.Build -ge 22621){throw 'LegacyExplorerUnsupported'}
    Assert-HuMachineChange; $path='HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Shell Extensions\Blocked';$name='{e2bf9676-5f8f-435c-97eb-11607a5bedf7}'
    if($Enabled){Set-HuRegistryValue $path $name '' 'String'}else{Remove-HuRegistryValue $path $name}
    Restart-HuExplorerShell | Out-Null
}

function Get-HuActivePowerMode {
    try{
        $powercfg=Get-HuSystemExecutablePath 'powercfg.exe';$text=& $powercfg /getactivescheme 2>$null|Out-String
        foreach($key in $script:HuPowerSchemes.Keys){if($text -match [regex]::Escape($script:HuPowerSchemes[$key])){return $key}}
    }catch{}
    return 'Unknown'
}
function Set-HuPowerMode { param([ValidateSet('Eco','Normal','High')][string]$Mode)
    $powercfg=Get-HuSystemExecutablePath 'powercfg.exe';$guid=$script:HuPowerSchemes[$Mode]
    & $powercfg /setactive $guid|Out-Null;if($LASTEXITCODE -ne 0){throw 'PowerModeUnavailable'}
    [pscustomobject]@{Mode=$Mode;Verified=(Get-HuActivePowerMode)-eq $Mode}
}

function Set-HuGameFeaturesDisabled { param([bool]$Disabled)
    Assert-HuMachineChange
    $entries = @(
        [pscustomobject]@{Id='GameDvrEnabled';Path='HKCU:\System\GameConfigStore';Name='GameDVR_Enabled';Default=1},
        [pscustomobject]@{Id='GameDvrCapture';Path='HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR';Name='AppCaptureEnabled';Default=1},
        [pscustomobject]@{Id='GameDvrHistory';Path='HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR';Name='HistoricalCaptureEnabled';Default=1},
        [pscustomobject]@{Id='GameDvrBar';Path='HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR';Name='VKMToggleGameBar';Default=1},
        [pscustomobject]@{Id='GameDvrRecord';Path='HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR';Name='VKMToggleRecording';Default=1},
        [pscustomobject]@{Id='GameDvrHistoricalVideo';Path='HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR';Name='VKMSaveHistoricalVideo';Default=1},
        [pscustomobject]@{Id='GameBarNexus';Path='HKCU:\SOFTWARE\Microsoft\GameBar';Name='UseNexusForGameBarEnabled';Default=1},
        [pscustomobject]@{Id='GameDvrPolicy';Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR';Name='AllowGameDVR';Default=$null}
    )
    foreach($entry in $entries){
        if($Disabled){
            Save-HuRegistryValueState $entry.Id $entry.Path $entry.Name
            Set-HuRegistryValue $entry.Path $entry.Name 0
        }else{
            Restore-HuRegistryValueState $entry.Id $entry.Path $entry.Name $entry.Default
        }
    }
    if($Disabled){
        foreach($name in @('GameBar','GameBarFTServer','GameBarPresenceWriter')){
            Get-Process -Name $name -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        }
    }
}
function Set-HuBackgroundThrottleDisabled { param([bool]$Disabled)
    Assert-HuMachineChange;Set-HuRegistryValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling' 'PowerThrottlingOff' $(if($Disabled){1}else{0})
}
function Set-HuLatencyOptimized { param([bool]$Optimized)
    Assert-HuMachineChange;$path='HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'
    Set-HuRegistryValue $path 'NetworkThrottlingIndex' $(if($Optimized){[uint32]::MaxValue}else{[uint32]10})
    Set-HuRegistryValue $path 'SystemResponsiveness' $(if($Optimized){0}else{20})
    $games=Join-Path $path 'Tasks\Games';Set-HuRegistryValue $games 'GPU Priority' $(if($Optimized){8}else{8});Set-HuRegistryValue $games 'Priority' $(if($Optimized){6}else{2})
}

function Get-HuGamingTaskPaths { @('\Microsoft\Windows\Maps\MapsToastTask','\Microsoft\Windows\Maps\MapsUpdateTask','\Microsoft\XblGameSave\XblGameSaveTask') }
function Test-HuGamingTasksDisabled {
    $found=0;$disabled=0
    foreach($full in Get-HuGamingTaskPaths){$name=Split-Path $full -Leaf;$path=$full.Substring(0,$full.Length-$name.Length);try{$task=Get-ScheduledTask -TaskPath $path -TaskName $name -ErrorAction Stop;$found++;if($task.State -eq 'Disabled'){$disabled++}}catch{}}
    return $found -eq 0 -or $found -eq $disabled
}
function Set-HuGamingTasksDisabled { param([bool]$Disabled)
    Assert-HuMachineChange;$changed=0
    foreach($full in Get-HuGamingTaskPaths){$name=Split-Path $full -Leaf;$path=$full.Substring(0,$full.Length-$name.Length);try{if($Disabled){Disable-ScheduledTask -TaskPath $path -TaskName $name -ErrorAction Stop|Out-Null}else{Enable-ScheduledTask -TaskPath $path -TaskName $name -ErrorAction Stop|Out-Null};$changed++}catch{}}
    return $changed
}
function Get-HuBackgroundServiceDefaults { @{MapsBroker=2;Fax=3;WMPNetworkSvc=3;RetailDemo=3} }
function Test-HuBackgroundServicesDisabled {
    $found=0;$disabled=0;foreach($name in (Get-HuBackgroundServiceDefaults).Keys){$path="HKLM:\SYSTEM\CurrentControlSet\Services\$name";if(Test-Path -LiteralPath $path){$found++;if([int](Get-HuRegistryValue $path 'Start' 3)-eq 4){$disabled++}}};return $found -eq 0 -or $found -eq $disabled
}
function Set-HuBackgroundServicesDisabled { param([bool]$Disabled)
    Assert-HuMachineChange;$changed=0;$defaults=Get-HuBackgroundServiceDefaults
    foreach($name in $defaults.Keys){$path="HKLM:\SYSTEM\CurrentControlSet\Services\$name";if(Test-Path -LiteralPath $path){Set-HuRegistryValue $path 'Start' $(if($Disabled){4}else{[int]$defaults[$name]});if($Disabled){try{Stop-Service -Name $name -Force -ErrorAction Stop}catch{}};$changed++}}
    return $changed
}
function Set-HuTaskbarOptimized { param([bool]$Optimized)
    $path='HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
    Repair-HuLegacyTaskbarAnimationOwnership | Out-Null
    if($Optimized){Save-HuRegistryValueState 'TaskbarBadges' $path 'TaskbarBadges';Set-HuRegistryValue $path 'TaskbarBadges' 0}
    else{Restore-HuRegistryValueState 'TaskbarBadges' $path 'TaskbarBadges' 1}
    Restart-HuExplorerShell | Out-Null
}
function Set-HuStartupOptimized { param([bool]$Optimized)
    $path='HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize';if($Optimized){Set-HuRegistryValue $path 'StartupDelayInMSec' 0}else{Remove-HuRegistryValue $path 'StartupDelayInMSec'}
    Set-HuRegistryValue 'HKCU:\Control Panel\Desktop' 'MenuShowDelay' $(if($Optimized){'100'}else{'400'}) 'String'
}
