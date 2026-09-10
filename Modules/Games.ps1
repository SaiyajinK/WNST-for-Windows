# WNST - réglages de jeu réversibles et mode développeur Steam

function Get-HuGamesBackupPath { 'HKCU:\Software\WNST\ReversibleState\Games' }

function Save-HuGameRegistryBackup {
    param([string]$Id,[string]$Path,[string]$Name)
    $root = Get-HuGamesBackupPath
    if (-not (Test-Path -LiteralPath $root)) { New-Item -Path $root -Force | Out-Null }
    $slot = 'Registry_' + $Id
    if ((Get-ItemProperty -LiteralPath $root -Name $slot -ErrorAction SilentlyContinue).PSObject.Properties.Name -contains $slot) { return }
    $entry = Get-HuGameRegistryEntry -Path $Path -Name $Name
    $exists = [bool]$entry.Exists; $value = $entry.Value; $kind = [string]$entry.Kind
    $data = [pscustomobject]@{ Exists=$exists; Path=$Path; Name=$Name; Kind=$kind; Value=$value } | ConvertTo-Json -Compress -Depth 4
    New-ItemProperty -LiteralPath $root -Name $slot -Value $data -PropertyType String -Force | Out-Null
}

function Restore-HuGameRegistryBackup {
    param([string]$Id)
    $root = Get-HuGamesBackupPath; $slot='Registry_' + $Id
    $raw = (Get-ItemProperty -LiteralPath $root -Name $slot -ErrorAction SilentlyContinue).$slot
    if ([string]::IsNullOrWhiteSpace([string]$raw)) { return $false }
    $data = $raw | ConvertFrom-Json
    if ([bool]$data.Exists) {
        $kind = [Enum]::Parse([Microsoft.Win32.RegistryValueKind],[string]$data.Kind)
        Set-HuGameRegistryValue -Path ([string]$data.Path) -Name ([string]$data.Name) -Value $data.Value -Kind $kind
    }
    else { Remove-HuGameRegistryValue -Path ([string]$data.Path) -Name ([string]$data.Name) }
    Remove-ItemProperty -LiteralPath $root -Name $slot -ErrorAction SilentlyContinue
    return $true
}

function Resolve-HuGameRegistryPath {
    param([Parameter(Mandatory=$true)][string]$Path)
    $normalized=$Path.Replace('/','\')
    if($normalized -match '^(?:HKCU:|HKEY_CURRENT_USER)\\(?<sub>.+)$'){return [pscustomobject]@{Hive=[Microsoft.Win32.Registry]::CurrentUser;SubKey=$matches.sub}}
    if($normalized -match '^(?:HKLM:|HKEY_LOCAL_MACHINE)\\(?<sub>.+)$'){return [pscustomobject]@{Hive=[Microsoft.Win32.Registry]::LocalMachine;SubKey=$matches.sub}}
    throw ('UNSUPPORTED_REGISTRY_PATH:{0}' -f $Path)
}

function Get-HuGameRegistryEntry {
    param([Parameter(Mandatory=$true)][string]$Path,[Parameter(Mandatory=$true)][string]$Name)
    try{
        $resolved=Resolve-HuGameRegistryPath -Path $Path
        $key=$resolved.Hive.OpenSubKey([string]$resolved.SubKey,$false)
        if(-not$key){return [pscustomobject]@{Exists=$false;Value=$null;Kind='String'}}
        try{
            if(@($key.GetValueNames()) -notcontains $Name){return [pscustomobject]@{Exists=$false;Value=$null;Kind='String'}}
            return [pscustomobject]@{Exists=$true;Value=$key.GetValue($Name,$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames);Kind=[string]$key.GetValueKind($Name)}
        }finally{$key.Dispose()}
    }catch{return [pscustomobject]@{Exists=$false;Value=$null;Kind='String'}}
}

function Set-HuGameRegistryValue {
    param([string]$Path,[string]$Name,[object]$Value,[Microsoft.Win32.RegistryValueKind]$Kind)
    $resolved=Resolve-HuGameRegistryPath -Path $Path
    $key=$resolved.Hive.OpenSubKey([string]$resolved.SubKey,$true)
    if(-not$key){$key=$resolved.Hive.CreateSubKey([string]$resolved.SubKey)}
    if(-not$key){throw ('REGISTRY_KEY_WRITE_FAILED:{0}' -f $Path)}
    try{$key.SetValue($Name,$Value,$Kind)}finally{$key.Dispose()}
}

function Remove-HuGameRegistryValue {
    param([Parameter(Mandatory=$true)][string]$Path,[Parameter(Mandatory=$true)][string]$Name)
    try{
        $resolved=Resolve-HuGameRegistryPath -Path $Path;$key=$resolved.Hive.OpenSubKey([string]$resolved.SubKey,$true)
        if($key){try{$key.DeleteValue($Name,$false)}finally{$key.Dispose()}}
    }catch{}
}

function Get-HuGameRegistryValueSafe {
    param([Parameter(Mandatory=$true)][string]$Path,[Parameter(Mandatory=$true)][string]$Name)
    $entry=Get-HuGameRegistryEntry -Path $Path -Name $Name
    if($entry.Exists){return $entry.Value}
    return $null
}

function Get-HuNetworkPowerTargets {
    try{
        $instances=@(Get-CimInstance -Namespace 'root\wmi' -ClassName 'MSPower_DeviceEnable' -ErrorAction Stop)
        $adapters=New-Object 'System.Collections.Generic.List[object]'
        try{foreach($adapter in @(Get-NetAdapter -ErrorAction Stop|Where-Object{-not[string]::IsNullOrWhiteSpace([string]$_.PnPDeviceID)})){$adapters.Add([pscustomobject]@{Name=[string]$adapter.Name;PnPDeviceID=[string]$adapter.PnPDeviceID})}}catch{}
        try{foreach($adapter in @(Get-CimInstance -ClassName Win32_NetworkAdapter -ErrorAction Stop|Where-Object{$_.PhysicalAdapter -and -not[string]::IsNullOrWhiteSpace([string]$_.PNPDeviceID)})){
            if(-not@($adapters|Where-Object{[string]$_.PnPDeviceID -eq [string]$adapter.PNPDeviceID}).Count){$adapters.Add([pscustomobject]@{Name=[string]$adapter.NetConnectionID;PnPDeviceID=[string]$adapter.PNPDeviceID})}
        }}catch{}
        $targets=New-Object 'System.Collections.Generic.List[object]'
        foreach($adapter in $adapters){
            $pnp=([string]$adapter.PnPDeviceID).Replace('\\','\').Trim().ToUpperInvariant()
            $instance=$instances|Where-Object{([string]$_.InstanceName).Replace('\\','\').Trim().ToUpperInvariant().IndexOf($pnp,[StringComparison]::OrdinalIgnoreCase) -ge 0}|Select-Object -First 1
            if($instance){$targets.Add([pscustomobject]@{Name=[string]$adapter.Name;InstanceName=[string]$instance.InstanceName;Enable=[bool]$instance.Enable;Instance=$instance})}
        }
        return @($targets)
    }catch{return @()}
}

function Get-HuSteamExecutable {
    $candidates = New-Object 'System.Collections.Generic.List[string]'
    foreach ($entry in @(
        @{ Path='HKCU:\Software\Valve\Steam'; Name='SteamExe' },
        @{ Path='HKCU:\Software\Valve\Steam'; Name='SteamPath' },
        @{ Path='HKLM:\SOFTWARE\WOW6432Node\Valve\Steam'; Name='InstallPath' },
        @{ Path='HKLM:\SOFTWARE\Valve\Steam'; Name='InstallPath' }
    )) {
        try {
            $value = [string](Get-ItemPropertyValue -LiteralPath $entry.Path -Name $entry.Name -ErrorAction Stop)
            if ($value) {
                $candidate = if ($value.EndsWith('.exe',[StringComparison]::OrdinalIgnoreCase)) { $value } else { Join-Path $value 'steam.exe' }
                $candidates.Add($candidate.Replace('/','\'))
            }
        } catch { }
    }
    try { foreach ($process in @(Get-Process steam -ErrorAction SilentlyContinue)) { if ($process.Path) { $candidates.Add([string]$process.Path) } } } catch { }
    foreach ($programRoot in @(${env:ProgramFiles(x86)},$env:ProgramFiles)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$programRoot)) { $candidates.Add((Join-Path $programRoot 'Steam\steam.exe')) }
    }
    foreach ($candidate in $candidates | Select-Object -Unique) { if (Test-Path -LiteralPath $candidate -PathType Leaf) { return [IO.Path]::GetFullPath($candidate) } }
    return ''
}

function Start-HuSteamDeveloperMode {
    $steamExe = Get-HuSteamExecutable
    if ([string]::IsNullOrWhiteSpace($steamExe)) { throw 'STEAM_NOT_INSTALLED' }
    $wasRunning = @(Get-Process steam -ErrorAction SilentlyContinue).Count -gt 0
    if ($wasRunning) {
        Get-Process steam -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction Stop
        $limit = [Diagnostics.Stopwatch]::StartNew()
        while (@(Get-Process steam -ErrorAction SilentlyContinue).Count -gt 0 -and $limit.Elapsed.TotalSeconds -lt 8) { Start-Sleep -Milliseconds 150 }
    }
    Start-Process -FilePath $steamExe -ArgumentList @('-dev') | Out-Null
    return [pscustomobject]@{ Path=$steamExe; Restarted=$wasRunning }
}

function Get-HuDirectXGlobalSettings {
    $path='HKCU:\Software\Microsoft\DirectX\UserGpuPreferences'
    try { return [string](Get-ItemPropertyValue -LiteralPath $path -Name 'DirectXUserGlobalSettings' -ErrorAction Stop) } catch { return '' }
}

function Set-HuDirectXGlobalSetting {
    param([string]$Name,[string]$Value)
    $path='HKCU:\Software\Microsoft\DirectX\UserGpuPreferences'; $current=Get-HuDirectXGlobalSettings
    $parts = New-Object 'System.Collections.Generic.List[string]'
    foreach ($part in @($current -split ';')) { if ($part -and -not $part.StartsWith($Name + '=',[StringComparison]::OrdinalIgnoreCase)) { $parts.Add($part) } }
    $parts.Add($Name + '=' + $Value)
    Set-HuGameRegistryValue $path 'DirectXUserGlobalSettings' (($parts -join ';') + ';') ([Microsoft.Win32.RegistryValueKind]::String)
}

function Get-HuGameTweakState {
    param([Parameter(Mandatory=$true)][ValidateSet('MouseAcceleration','BackgroundApps','GameMode','NetworkPowerSaving','WindowedOptimizations','Hags')][string]$Id)
    switch ($Id) {
        'MouseAcceleration' {
            $p='HKCU:\Control Panel\Mouse'; $a=Get-HuGameRegistryValueSafe $p MouseSpeed; $b=Get-HuGameRegistryValueSafe $p MouseThreshold1; $c=Get-HuGameRegistryValueSafe $p MouseThreshold2
            return [pscustomobject]@{ Checked=([string]$a -eq '0' -and [string]$b -eq '0' -and [string]$c -eq '0'); Known=($null -ne $a -and $null -ne $b -and $null -ne $c) }
        }
        'BackgroundApps' {
            $v=Get-HuGameRegistryValueSafe 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications' GlobalUserDisabled
            return [pscustomobject]@{ Checked=([int]$v -eq 1); Known=($null -ne $v) }
        }
        'GameMode' {
            $p='HKCU:\Software\Microsoft\GameBar'; $a=Get-HuGameRegistryValueSafe $p AllowAutoGameMode; $b=Get-HuGameRegistryValueSafe $p AutoGameModeEnabled
            $value=if($null -ne $b){$b}else{$a}
            return [pscustomobject]@{ Checked=($null -ne $value -and [int]$value -eq 1); Known=($null -ne $value) }
        }
        'NetworkPowerSaving' {
            $targets=@(Get-HuNetworkPowerTargets)
            return [pscustomobject]@{Checked=($targets.Count -gt 0 -and @($targets|Where-Object{$_.Enable}).Count -eq 0);Known=($targets.Count -gt 0)}
        }
        'WindowedOptimizations' {
            $match=[regex]::Match((Get-HuDirectXGlobalSettings),'(?:^|;)SwapEffectUpgradeEnable=([^;]+)')
            return [pscustomobject]@{ Checked=($match.Success -and $match.Groups[1].Value -eq '1'); Known=$match.Success }
        }
        'Hags' {
            $v=Get-HuGameRegistryValueSafe 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' HwSchMode
            return [pscustomobject]@{ Checked=([int]$v -eq 2); Known=($null -ne $v) }
        }
    }
}

function Wait-HuGameTweakState {
    param([Parameter(Mandatory=$true)][string]$Id,[Parameter(Mandatory=$true)][bool]$Checked,[int]$TimeoutMilliseconds=3000)
    $watch=[Diagnostics.Stopwatch]::StartNew();$state=$null
    do {
        $state=Get-HuGameTweakState -Id $Id
        if ($state.Known -and [bool]$state.Checked -eq $Checked) { return $state }
        Start-Sleep -Milliseconds 125
    } while ($watch.ElapsedMilliseconds -lt $TimeoutMilliseconds)
    return $state
}

function Apply-HuGameTweak {
    param([Parameter(Mandatory=$true)][ValidateSet('MouseAcceleration','BackgroundApps','GameMode','NetworkPowerSaving','WindowedOptimizations','Hags')][string]$Id,[Parameter(Mandatory=$true)][bool]$Checked)
    $before=Get-HuGameTweakState -Id $Id
    switch ($Id) {
        'MouseAcceleration' {
            $p='HKCU:\Control Panel\Mouse'
            if ($Checked) {
                Save-HuGameRegistryBackup MouseSpeed $p MouseSpeed; Save-HuGameRegistryBackup MouseThreshold1 $p MouseThreshold1; Save-HuGameRegistryBackup MouseThreshold2 $p MouseThreshold2
                Set-HuGameRegistryValue $p MouseSpeed '0' String; Set-HuGameRegistryValue $p MouseThreshold1 '0' String; Set-HuGameRegistryValue $p MouseThreshold2 '0' String
            } else {
                if(-not(Restore-HuGameRegistryBackup MouseSpeed)){Set-HuGameRegistryValue $p MouseSpeed '1' String}
                if(-not(Restore-HuGameRegistryBackup MouseThreshold1)){Set-HuGameRegistryValue $p MouseThreshold1 '6' String}
                if(-not(Restore-HuGameRegistryBackup MouseThreshold2)){Set-HuGameRegistryValue $p MouseThreshold2 '10' String}
            }
        }
        'BackgroundApps' {
            $p='HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications'; $s='HKCU:\Software\Microsoft\Windows\CurrentVersion\Search'
            if ($Checked) {
                Save-HuGameRegistryBackup BackgroundGlobal $p GlobalUserDisabled; Save-HuGameRegistryBackup BackgroundSearch $s BackgroundAppGlobalToggle
                Set-HuGameRegistryValue $p GlobalUserDisabled 1 DWord; Set-HuGameRegistryValue $s BackgroundAppGlobalToggle 0 DWord
            } else {
                if(-not(Restore-HuGameRegistryBackup BackgroundGlobal)){Set-HuGameRegistryValue $p GlobalUserDisabled 0 DWord}
                if(-not(Restore-HuGameRegistryBackup BackgroundSearch)){Set-HuGameRegistryValue $s BackgroundAppGlobalToggle 1 DWord}
            }
        }
        'GameMode' {
            $p='HKCU:\Software\Microsoft\GameBar'
            if ($Checked) {
                Save-HuGameRegistryBackup GameModeAllow $p AllowAutoGameMode; Save-HuGameRegistryBackup GameModeEnabled $p AutoGameModeEnabled
                Set-HuGameRegistryValue $p AllowAutoGameMode 1 DWord; Set-HuGameRegistryValue $p AutoGameModeEnabled 1 DWord
            } else {
                if(-not(Restore-HuGameRegistryBackup GameModeAllow)){Set-HuGameRegistryValue $p AllowAutoGameMode 0 DWord}
                if(-not(Restore-HuGameRegistryBackup GameModeEnabled)){Set-HuGameRegistryValue $p AutoGameModeEnabled 0 DWord}
            }
        }
        'WindowedOptimizations' {
            $p='HKCU:\Software\Microsoft\DirectX\UserGpuPreferences'
            if ($Checked) { Save-HuGameRegistryBackup WindowedGlobal $p DirectXUserGlobalSettings; Set-HuDirectXGlobalSetting SwapEffectUpgradeEnable 1 }
            else { if (-not (Restore-HuGameRegistryBackup WindowedGlobal)) { Set-HuDirectXGlobalSetting SwapEffectUpgradeEnable 0 } }
        }
        'Hags' {
            $p='HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers'
            if ($Checked) { Save-HuGameRegistryBackup Hags $p HwSchMode; Set-HuGameRegistryValue $p HwSchMode 2 DWord }
            else { if (-not (Restore-HuGameRegistryBackup Hags)) { Set-HuGameRegistryValue $p HwSchMode 1 DWord } }
        }
        'NetworkPowerSaving' {
            $root=Get-HuGamesBackupPath;if(-not(Test-Path -LiteralPath $root)){New-Item -Path $root -Force|Out-Null};$slot='NetworkPowerManagement'
            $targets=@(Get-HuNetworkPowerTargets)
            if($targets.Count -eq 0){throw 'TWEAK_UNSUPPORTED'}
            if ($Checked) {
                if (-not (Get-ItemProperty -LiteralPath $root -Name $slot -ErrorAction SilentlyContinue)) {
                    $snapshot=@($targets|Select-Object Name,InstanceName,Enable)|ConvertTo-Json -Compress -Depth 4
                    New-ItemProperty -LiteralPath $root -Name $slot -Value $snapshot -PropertyType String -Force | Out-Null
                }
                foreach($target in $targets){Set-CimInstance -InputObject $target.Instance -Property @{Enable=$false} -ErrorAction Stop|Out-Null}
            } else {
                $raw=(Get-ItemProperty -LiteralPath $root -Name $slot -ErrorAction SilentlyContinue).$slot
                if ($raw) {
                    foreach($saved in @($raw | ConvertFrom-Json)) {
                        $target=$targets|Where-Object{$_.InstanceName -eq [string]$saved.InstanceName}|Select-Object -First 1
                        if($target){Set-CimInstance -InputObject $target.Instance -Property @{Enable=[bool]$saved.Enable} -ErrorAction Stop|Out-Null}
                    }
                    Remove-ItemProperty -LiteralPath $root -Name $slot -ErrorAction SilentlyContinue
                }
                else {foreach($target in $targets){Set-CimInstance -InputObject $target.Instance -Property @{Enable=$true} -ErrorAction Stop|Out-Null}}
            }
        }
    }
    $after=Wait-HuGameTweakState -Id $Id -Checked $Checked
    if ($Checked -and -not $after.Known -and $Id -eq 'NetworkPowerSaving') { throw 'TWEAK_UNSUPPORTED' }
    if ($Checked -and (-not $after.Known -or -not [bool]$after.Checked)) {
        throw ('TWEAK_VERIFICATION_FAILED:{0}:expected=enabled:known={1}:actual={2}' -f $Id,[bool]$after.Known,[bool]$after.Checked)
    }
    if (-not $Checked -and $after.Known -and [bool]$after.Checked) {
        # Une restauration remet l'état exact sauvegardé. Cet état peut déjà correspondre
        # au tweak actif ; l'écriture a réussi et l'interface doit simplement refléter la réalité.
        $after=Get-HuGameTweakState -Id $Id
    }
    return [pscustomobject]@{ Id=$Id; Before=$before; After=$after; RestartRequired=($Id -eq 'Hags') }
}
