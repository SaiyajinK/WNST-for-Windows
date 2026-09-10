function Format-HuByteSize {
    param([double]$Bytes)
    if ($Bytes -ge 1TB) { return ('{0:N2} TB' -f ($Bytes / 1TB)) }
    if ($Bytes -ge 1GB) { return ('{0:N1} GB' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:N0} MB' -f ($Bytes / 1MB)) }
    return ('{0:N0} KB' -f ($Bytes / 1KB))
}


function Format-HuThisPcMemorySize {
    param([double]$Bytes)
    $value = Format-HuByteSize $Bytes
    $value = $value -replace ' GB$',(' ' + (T 'ThisPcGigabyteUnit'))
    $value = $value -replace ' TB$',(' ' + (T 'ThisPcTerabyteUnit'))
    return $value
}

function Get-HuWindowsEditionDisplayName {
    param([AllowEmptyString()][string]$Source)

    $value = ([string]$Source).Trim()
    if ([string]::IsNullOrWhiteSpace($value)) { return '' }

    if ($value -match '(?i)Workstation|station de travail|Arbeitsstation|estaci[oó]n de trabajo|stazione di lavoro|esta[cç][aã]o de trabalho') {
        return T 'ThisPcWindowsEditionWorkstation'
    }
    if ($value -match '(?i)\\bPro(?:fessional|fessionnel)?\\b|Professionnel') {
        return T 'ThisPcWindowsEditionPro'
    }
    if ($value -match '(?i)Enterprise|Entreprise') {
        return T 'ThisPcWindowsEditionEnterprise'
    }
    if ($value -match '(?i)Education|Éducation') {
        return T 'ThisPcWindowsEditionEducation'
    }
    if ($value -match '(?i)\\bHome\\b|Famille') {
        return T 'ThisPcWindowsEditionHome'
    }

    return ($value -replace '^Microsoft\\s+Windows\\s+(?:10|11)\\s*','').Trim()
}

function Get-HuMemoryTypeLabel {
    param([object[]]$Modules)

    $types = @($Modules | ForEach-Object {
        $code = 0
        try { $code = [int]$_.SMBIOSMemoryType } catch { }
        if ($code -le 0) { try { $code = [int]$_.MemoryType } catch { } }
        switch ($code) {
            20 { 'DDR' }
            21 { 'DDR2' }
            24 { 'DDR3' }
            26 { 'DDR4' }
            34 { 'DDR5' }
            default { $null }
        }
    } | Where-Object { $_ } | Select-Object -Unique)
    if ($types.Count -eq 1) { return [string]$types[0] }
    if ($types.Count -gt 1) { return ($types -join ' / ') }
    return ''
}

function Get-HuMemoryDisplayName {
    param([object[]]$Modules)

    $modules = @($Modules)
    if ($modules.Count -eq 0) { return '' }

    $manufacturers = @($modules | ForEach-Object { ([string]$_.Manufacturer).Trim() } | Where-Object { $_ -and $_ -notmatch '^(?i)(unknown|undefined|n/a|not specified)$' } | Select-Object -Unique)
    $parts = @($modules | ForEach-Object {
        $part = ([string]$_.PartNumber).Trim()
        $part = [regex]::Replace($part,'^(?i)[0-9A-F]{4}\s+','')
        if ($part) { $part }
    } | Select-Object -Unique)
    $manufacturer = if ($manufacturers.Count -gt 0) { [string]$manufacturers[0] } else { '' }

    if ($manufacturer -match '^(?i)029E$') { $manufacturer = 'Corsair' }
    if ($manufacturer -match '(?i)Corsair' -or @($parts | Where-Object { $_ -match '^(?i)CM[RW]' }).Count -gt 0) {
        if (@($parts | Where-Object { $_ -match '^(?i)CM[RW]' }).Count -gt 0) { return 'CORSAIR VENGEANCE RGB PRO' }
        return 'CORSAIR'
    }

    if (-not [string]::IsNullOrWhiteSpace($manufacturer) -and $parts.Count -gt 0) { return ('{0} {1}' -f $manufacturer.ToUpperInvariant(),$parts[0]) }
    if (-not [string]::IsNullOrWhiteSpace($manufacturer)) { return $manufacturer.ToUpperInvariant() }
    if ($parts.Count -gt 0) { return [string]$parts[0] }
    return ''
}

function ConvertTo-HuDimmNumber {
    param([AllowEmptyString()][string]$DeviceLocator,[AllowEmptyString()][string]$BankLabel,[int]$FallbackIndex)

    $locator = ([string]$DeviceLocator).Trim()
    $bank = ([string]$BankLabel).Trim()

    if ($bank -match '(?i)BANK[_\- ]*([0-9]+)') { return ([int]$matches[1] + 1) }

    $combined = ($locator + ' ' + $bank).Trim()
    if ($combined -match '(?i)CHANNEL[_\- ]*([A-D]).*?DIMM[_\- ]*([0-9]+)') {
        $channel = [int][char]$matches[1].ToUpperInvariant() - [int][char]'A'
        $slot = [int]$matches[2]
        if ($channel -ge 0 -and $slot -ge 0) { return ($channel * 2) + $slot + 1 }
    }
    if ($combined -match '(?i)DIMM[_\- ]*([A-D])[_\- ]*([1-2])') {
        $channel = [int][char]$matches[1].ToUpperInvariant() - [int][char]'A'
        $slot = [int]$matches[2]
        if ($channel -ge 0) { return ($channel * 2) + $slot }
    }
    if ($combined -match '(?i)DIMM[_\- ]*([1-9][0-9]*)') { return [int]$matches[1] }
    return $FallbackIndex
}

function Get-HuOccupiedDimmLabels {
    param([object[]]$Modules)

    $labels = New-Object 'System.Collections.Generic.List[string]'
    $used = New-Object 'System.Collections.Generic.HashSet[int]'
    $fallback = 1
    foreach ($module in @($Modules | Sort-Object BankLabel,DeviceLocator)) {
        $number = ConvertTo-HuDimmNumber -DeviceLocator ([string]$module.DeviceLocator) -BankLabel ([string]$module.BankLabel) -FallbackIndex $fallback
        while ($used.Contains($number)) {
            $number++
        }
        [void]$used.Add($number)
        $labels.Add(('DIMM{0}' -f $number))
        $fallback++
    }
    return $labels.ToArray()
}

function Update-HuStorageDisksPanel {
    param([object[]]$DiskRecords)

    if (-not $StorageDisksPanel) { return }
    $StorageDisksPanel.Children.Clear()
    $StorageDisksPanel.RowDefinitions.Clear()
    $StorageDisksPanel.ColumnDefinitions.Clear()

    $records = @($DiskRecords)
    $useTwoColumns = $records.Count -ge 4

    $column1 = New-Object Windows.Controls.ColumnDefinition
    $column1.Width = New-Object Windows.GridLength(1,[Windows.GridUnitType]::Star)
    [void]$StorageDisksPanel.ColumnDefinitions.Add($column1)
    if ($useTwoColumns) {
        $column2 = New-Object Windows.Controls.ColumnDefinition
        $column2.Width = New-Object Windows.GridLength(1,[Windows.GridUnitType]::Star)
        [void]$StorageDisksPanel.ColumnDefinitions.Add($column2)
    }

    $rowCount = if ($useTwoColumns) { [math]::Ceiling($records.Count / 2.0) } else { $records.Count }
    for ($row = 0; $row -lt $rowCount; $row++) {
        $rowDefinition = New-Object Windows.Controls.RowDefinition
        $rowDefinition.Height = [Windows.GridLength]::Auto
        [void]$StorageDisksPanel.RowDefinitions.Add($rowDefinition)
    }

    for ($i = 0; $i -lt $records.Count; $i++) {
        $record = $records[$i]
        $card = New-Object Windows.Controls.Border
        $column = if ($useTwoColumns) { $i % 2 } else { 0 }
        $row = if ($useTwoColumns) { [math]::Floor($i / 2) } else { $i }
        $card.Margin = New-Object Windows.Thickness(0,0,$(if ($useTwoColumns -and $column -eq 0) { 8 } else { 0 }),8)
        $card.Style = $window.FindResource($(if ($null -ne $record.DiskNumber) { 'ClickableSubCardStyle' } else { 'SubCardStyle' }))
        [Windows.Controls.Grid]::SetColumn($card,$column)
        [Windows.Controls.Grid]::SetRow($card,$row)

        $stack = New-Object Windows.Controls.StackPanel
        $firstLine = New-Object Windows.Controls.StackPanel
        $firstLine.Orientation = [Windows.Controls.Orientation]::Horizontal
        $firstLine.VerticalAlignment = [Windows.VerticalAlignment]::Center

        $driveLabel = New-Object Windows.Controls.TextBlock
        $driveLabel.FontSize = 12
        $driveLabel.FontWeight = [Windows.FontWeights]::SemiBold
        $driveLabel.VerticalAlignment = [Windows.VerticalAlignment]::Center
        $driveLabel.Text = [string]$record.Root

        $capacity = New-Object Windows.Controls.TextBlock
        $capacity.FontSize = 12
        $capacity.FontWeight = [Windows.FontWeights]::SemiBold
        $capacity.Margin = New-Object Windows.Thickness(7,0,0,0)
        $capacity.VerticalAlignment = [Windows.VerticalAlignment]::Center
        $capacity.TextWrapping = [Windows.TextWrapping]::Wrap
        $capacity.Text = if ($useTwoColumns) { '{0} / {1}' -f (Format-HuByteSize $record.Available),(Format-HuByteSize $record.Total) } else { TF 'ThisPcDiskCapacityFormat' @((Format-HuByteSize $record.Available),(Format-HuByteSize $record.Total)) }

        $secondary = New-Object Windows.Controls.TextBlock
        $secondary.FontSize = 12
        $secondary.Margin = New-Object Windows.Thickness(0,5,0,0)
        $secondary.TextWrapping = [Windows.TextWrapping]::Wrap
        $secondary.Text = [string]$record.DeviceName
        $secondary.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty,'MutedBrush')

        [void]$firstLine.Children.Add($driveLabel)
        [void]$firstLine.Children.Add($capacity)
        [void]$stack.Children.Add($firstLine)
        [void]$stack.Children.Add($secondary)
        $card.Child = $stack

        if ($null -ne $record.DiskNumber) {
            $diskNumber = [int]$record.DiskNumber
            $card.Tag = $diskNumber
            $handler = {
                param($sender,$eventArgs)
                if (-not (Test-HuThisPcCardClickReady)) { return }
                Open-HuTaskManagerDiskTarget -DiskNumber ([int]$sender.Tag)
            }.GetNewClosure()
            $card.Add_MouseLeftButtonUp($handler)
        }

        [void]$StorageDisksPanel.Children.Add($card)
    }
}

function ConvertTo-HuNvidiaDriverVersion {
    param([AllowEmptyString()][string]$Version)
    if ([string]::IsNullOrWhiteSpace($Version)) { return '' }
    $parts = @($Version.Trim() -split '\.')
    if ($parts.Count -lt 4 -or $parts[-2] -notmatch '^\d+$' -or $parts[-1] -notmatch '^\d+$') { return $Version }
    $branchPart = [string]$parts[-2]
    $vendorDigits = $branchPart.Substring($branchPart.Length - 1,1) + ([int]$parts[-1]).ToString('0000')
    if ($vendorDigits.Length -lt 3) { return $Version }
    return $vendorDigits.Substring(0,$vendorDigits.Length - 2) + '.' + $vendorDigits.Substring($vendorDigits.Length - 2)
}

function Get-HuAmdSoftwareVersion {
    $paths = @('HKLM:\SOFTWARE\AMD\CN')
    try { $paths += @(Get-ChildItem -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Video' -ErrorAction Stop | ForEach-Object { Join-Path $_.PSPath '0000' }) } catch { }
    foreach ($path in $paths) {
        try {
            $properties = Get-ItemProperty -LiteralPath $path -ErrorAction Stop
            foreach ($name in @('RadeonSoftwareVersion','ReleaseVersion','Catalyst_Version')) {
                $value = [string]$properties.$name
                if ([string]::IsNullOrWhiteSpace($value)) { continue }
                $match = [regex]::Match($value,'(?<!\d)(\d{2}\.\d{1,2}\.\d+)(?!\d)')
                if ($match.Success) { return $match.Groups[1].Value }
                return $value.Trim()
            }
        }
        catch { }
    }
    return ''
}

function Get-HuGraphicsDriverDisplay {
    param([Parameter(Mandatory=$true)][object]$Gpu,[AllowEmptyString()][string]$AmdSoftwareVersion='')
    $name = [string]$Gpu.Name
    $deviceId = [string]$Gpu.PNPDeviceID
    $version = [string]$Gpu.DriverVersion
    if ($name -match 'NVIDIA' -or $deviceId -match 'VEN_10DE') {
        $vendorVersion = ConvertTo-HuNvidiaDriverVersion $version
        return ('NVIDIA {0}' -f $(if($vendorVersion){$vendorVersion}else{$version})).Trim()
    }
    if ($name -match 'AMD|Radeon' -or $deviceId -match 'VEN_1002') {
        return ('AMD {0}' -f $(if($AmdSoftwareVersion){$AmdSoftwareVersion}else{$version})).Trim()
    }
    if ($name -match 'Intel' -or $deviceId -match 'VEN_8086') {
        return ('Intel {0}' -f $version).Trim()
    }
    return $version
}

function Get-HuGraphicsMemoryBytes {
    param(
        [AllowNull()][object[]]$Gpus = @(),
        [AllowNull()][object[]]$RegistryRecords
    )
    if (-not $PSBoundParameters.ContainsKey('RegistryRecords')) {
        $records = New-Object 'System.Collections.Generic.List[object]'
        try {
            foreach ($videoKey in @(Get-ChildItem -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Video' -ErrorAction Stop)) {
                foreach ($adapterKey in @(Get-ChildItem -LiteralPath $videoKey.PSPath -ErrorAction SilentlyContinue | Where-Object PSChildName -match '^\d{4}$')) {
                    try {
                        $properties = Get-ItemProperty -LiteralPath $adapterKey.PSPath -ErrorAction Stop
                        $records.Add([pscustomobject]@{
                            DriverDesc      = [string]$properties.DriverDesc
                            MatchingDeviceId = [string]$properties.MatchingDeviceId
                            MemoryBytes     = $properties.'HardwareInformation.qwMemorySize'
                        })
                    }
                    catch { }
                }
            }
        }
        catch { }
        $RegistryRecords = $records.ToArray()
    }

    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $accurateValues = New-Object 'System.Collections.Generic.List[double]'
    foreach ($record in @($RegistryRecords)) {
        $memory = 0.0
        try { $memory = [double]$record.MemoryBytes } catch { continue }
        if ($memory -le 0) { continue }
        $description = ([string]$record.DriverDesc).Trim()
        $matchingId = ([string]$record.MatchingDeviceId).Trim()
        $isActive = @($Gpus).Count -eq 0
        foreach ($gpu in @($Gpus)) {
            $gpuName = ([string]$gpu.Name).Trim()
            $gpuId = ([string]$gpu.PNPDeviceID).Trim()
            if (($description -and $gpuName -and $description -ieq $gpuName) -or ($matchingId -and $gpuId -and $gpuId.StartsWith($matchingId,[StringComparison]::OrdinalIgnoreCase))) { $isActive=$true; break }
        }
        if (-not $isActive) { continue }
        $identity = '{0}|{1}|{2}' -f $description,$matchingId,[uint64]$memory
        if ($seen.Add($identity)) { $accurateValues.Add($memory) }
    }
    if ($accurateValues.Count -gt 0) { return [double](($accurateValues | Measure-Object -Maximum).Maximum) }

    $hasNvidia = @($Gpus).Count -eq 0 -or @($Gpus | Where-Object { [string]$_.Name -match 'NVIDIA' -or [string]$_.PNPDeviceID -match 'VEN_10DE' }).Count -gt 0
    if ($hasNvidia) {
        $nvidiaCandidates = @((Join-Path $env:SystemRoot 'System32\nvidia-smi.exe'))
        try { $nvidiaCandidates += [string](Get-Command 'nvidia-smi.exe' -ErrorAction Stop).Source } catch { }
        foreach ($nvidiaSmi in @($nvidiaCandidates | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) } | Select-Object -Unique)) {
            try {
                $memoryValues = @(& $nvidiaSmi '--query-gpu=memory.total' '--format=csv,noheader,nounits' 2>$null | ForEach-Object {
                    if ([string]$_ -match '^\s*(\d+(?:[\.,]\d+)?)') { [double]::Parse($matches[1].Replace(',','.'),[Globalization.CultureInfo]::InvariantCulture) * 1MB }
                } | Where-Object { $_ -gt 0 })
                if ($memoryValues.Count -gt 0) { return [double](($memoryValues | Measure-Object -Maximum).Maximum) }
            }
            catch { }
        }
    }

    $fallbackValues = @($Gpus | ForEach-Object { try { [double]$_.AdapterRAM } catch { 0 } } | Where-Object { $_ -gt 0 })
    if ($fallbackValues.Count -gt 0) { return [double](($fallbackValues | Measure-Object -Maximum).Maximum) }
    return 0.0
}

function Get-HuThisPcProcessorDisplayName {
    param([AllowEmptyString()][string]$Name)

    if ([string]::IsNullOrWhiteSpace($Name)) { return '' }
    return ([regex]::Replace($Name.Trim(),'\s*@\s*\d+(?:[\.,]\d+)?\s*(?:GHz|MHz)\b.*$','',[Text.RegularExpressions.RegexOptions]::IgnoreCase)).Trim()
}

function Get-HuGraphicsExactDisplayName {
    param([Parameter(Mandatory=$true)][object]$Gpu)

    $fallback = ([string]$Gpu.Name).Trim()
    $pnpId = ([string]$Gpu.PNPDeviceID).Trim()
    if ([string]::IsNullOrWhiteSpace($pnpId)) { return $fallback }

    # Le registre PCI est beaucoup plus rapide qu'une requête Win32_PnPEntity.
    # S'il expose un FriendlyName constructeur plus précis, on le conserve.
    try {
        $enumPath = 'Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Enum\' + $pnpId
        if (Test-Path -LiteralPath $enumPath) {
            $props = Get-ItemProperty -LiteralPath $enumPath -ErrorAction Stop
            foreach ($propertyName in @('FriendlyName','DeviceDesc')) {
                $value = [string]$props.$propertyName
                if ($value -match ';(.+)$') { $value = $matches[1] }
                $value = $value.Trim()
                if (-not [string]::IsNullOrWhiteSpace($value) -and $value.Length -gt $fallback.Length) {
                    return $value
                }
            }
        }
    }
    catch { }

    return $fallback
}

function Get-HuBiosDisplayVersion {
    param($BiosRegistry,$BiosCim,[string]$BoardModel,[string]$BoardManufacturer)

    $candidates = New-Object 'System.Collections.Generic.List[string]'
    foreach ($value in @(
        $(if ($BiosRegistry) { $BiosRegistry.BIOSVersion } else { $null }),
        $(if ($BiosRegistry) { $BiosRegistry.SystemBiosVersion } else { $null }),
        $(if ($BiosCim) { $BiosCim.SMBIOSBIOSVersion } else { $null }),
        $(if ($BiosCim) { $BiosCim.BIOSVersion } else { $null }),
        $(if ($BiosCim) { $BiosCim.Version } else { $null })
    )) {
        foreach ($item in @($value)) {
            $text = ([string]$item).Trim()
            if (-not [string]::IsNullOrWhiteSpace($text) -and -not $candidates.Contains($text)) { $candidates.Add($text) }
        }
    }

    $boardCode = ''
    if ($BoardModel -match '(?i)MS-([0-9A-Z]+)') { $boardCode = [string]$matches[1] }

    $raw = if ($candidates.Count -gt 0) { [string]$candidates[0] } else { '' }
    if ($BoardManufacturer -match '(?i)Micro-Star|MSI' -and -not [string]::IsNullOrWhiteSpace($boardCode)) {
        if ($raw -match '^([0-9]+)\.([0-9A-Z]+)0$') {
            return ('{0}v{1}{2}' -f $boardCode,$matches[1],$matches[2])
        }
        foreach ($candidate in $candidates) {
            if ($candidate -match ('(?i)(?:E)?{0}(?:IMS)?\.([0-9]+)([0-9A-Z]+)0$' -f [regex]::Escape($boardCode))) {
                return ('{0}v{1}{2}' -f $boardCode,$matches[1],$matches[2])
            }
            if ($candidate -match ('(?i)^{0}v[0-9A-Z]+$' -f [regex]::Escape($boardCode))) { return $candidate }
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($boardCode)) {
        foreach ($candidate in $candidates) {
            if ($candidate -match [regex]::Escape($boardCode)) { return $candidate }
        }
    }

    return $raw
}

function Get-HuMotherboardOfficialUrl {
    param([string]$Manufacturer,[string]$Model)

    if ([string]::IsNullOrWhiteSpace($Manufacturer) -or [string]::IsNullOrWhiteSpace($Model)) { return '' }

    $cleanModel = $Model.Trim()
    $cleanModel = [regex]::Replace($cleanModel,'\s*\(MS-[0-9A-Z]+\)\s*$','',[Text.RegularExpressions.RegexOptions]::IgnoreCase)

    if ($Manufacturer -match '(?i)Micro-Star|\bMSI\b') {
        $slug = [regex]::Replace($cleanModel.Trim(),'[^0-9A-Za-z]+','-').Trim('-')
        if (-not [string]::IsNullOrWhiteSpace($slug)) { return 'https://www.msi.com/Motherboard/' + $slug }
    }

    return ''
}

function Initialize-HuThisPcQuickInformation {
    if ($script:ThisPcQuickInitialized) { return }
    $script:ThisPcQuickInitialized = $true

    try {
        $windowsInfo = try { Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop } catch { $null }
        $cpuInfo = try { Get-ItemProperty -LiteralPath 'HKLM:\HARDWARE\DESCRIPTION\System\CentralProcessor\0' -ErrorAction Stop } catch { $null }
        $biosInfo = try { Get-ItemProperty -LiteralPath 'HKLM:\HARDWARE\DESCRIPTION\System\BIOS' -ErrorAction Stop } catch { $null }
        $drives = @([IO.DriveInfo]::GetDrives() | Where-Object { $_.DriveType -eq [IO.DriveType]::Fixed -and $_.IsReady })

        $ComputerNameValue.Text = [string]$env:COMPUTERNAME

        $buildNumber = if ($windowsInfo -and $windowsInfo.CurrentBuild) { [string]$windowsInfo.CurrentBuild } else { [Environment]::OSVersion.Version.Build.ToString() }
        $buildRevision = if ($windowsInfo -and $null -ne $windowsInfo.UBR) { [string]$windowsInfo.UBR } else { [Environment]::OSVersion.Version.Revision.ToString() }
        $productName = if ($windowsInfo -and $windowsInfo.ProductName) { [string]$windowsInfo.ProductName } else { 'Windows' }
        $windowsFamily = if ($productName -match 'Windows\s+11' -or ([int]$buildNumber -ge 22000)) { 'Windows 11' } elseif ($productName -match 'Windows\s+10') { 'Windows 10' } else { 'Windows' }
        $windowsEdition = Get-HuWindowsEditionDisplayName -Source $productName
        $OperatingSystemValue.Text = (@($windowsFamily,$windowsEdition) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique) -join ' '
        $BuildValue.Text = '{0}.{1}' -f $buildNumber,$buildRevision
        $SystemTypeValue.Text = if ([Environment]::Is64BitOperatingSystem) { 'x64' } else { 'x32' }
        $quickUptime = [TimeSpan]::FromMilliseconds([math]::Max(0,[Environment]::TickCount))
        $UptimeValue.Text = TF 'UptimeFormat' @([math]::Floor($quickUptime.TotalDays),$quickUptime.Hours,$quickUptime.Minutes)

        $cpuName = if ($cpuInfo -and $cpuInfo.ProcessorNameString) { ([string]$cpuInfo.ProcessorNameString).Trim() } else { [string]$env:PROCESSOR_IDENTIFIER }
        $ProcessorValue.Text = $(if ($cpuName) { Get-HuThisPcProcessorDisplayName $cpuName } else { '' })
        $ProcessorDetailsValue.Text = ''

        try {
            Add-Type -AssemblyName Microsoft.VisualBasic -ErrorAction Stop
            $computerInfo = New-Object Microsoft.VisualBasic.Devices.ComputerInfo
            $ramTotal = [double]$computerInfo.TotalPhysicalMemory
            $ramAvailable = [double]$computerInfo.AvailablePhysicalMemory
            $memoryTotalText = (Format-HuThisPcMemorySize $ramTotal)
            $memoryAvailableText = (Format-HuThisPcMemorySize $ramAvailable)
            $MemoryValue.Text = ''
            $MemoryDetailsValue.Text = TF 'ThisPcMemoryFormat' @($memoryTotalText,'',$memoryAvailableText)
        }
        catch {
            $MemoryValue.Text = ''
            $MemoryDetailsValue.Text = ''
        }

        $GraphicsValue.Text = ''
        $GraphicsDetailsValue.Text = ''

        $boardManufacturer = if ($biosInfo -and $biosInfo.BaseBoardManufacturer) { ([string]$biosInfo.BaseBoardManufacturer).Trim() } elseif ($biosInfo) { ([string]$biosInfo.SystemManufacturer).Trim() } else { '' }
        $boardModel = if ($biosInfo -and $biosInfo.BaseBoardProduct) { ([string]$biosInfo.BaseBoardProduct).Trim() } else { '' }
        $boardDisplayModel = [regex]::Replace(([string]$boardModel).Trim(),'\s*\([^)]*\)\s*$','').Trim()
        $MotherboardModelValue.Text = $(if ($boardDisplayModel) { $boardDisplayModel } else { '' })
        $MotherboardManufacturerValue.Text = TF 'ThisPcManufacturerFormat' @($(if ($boardManufacturer) { $boardManufacturer } else { '' }))
        $quickBiosVersion = Get-HuBiosDisplayVersion -BiosRegistry $biosInfo -BiosCim $null -BoardModel $boardModel -BoardManufacturer $boardManufacturer
        $MotherboardBiosValue.Text = TF 'ThisPcBiosFormat' @($quickBiosVersion)

        $quickDisks = @($drives | ForEach-Object {
            [pscustomobject]@{
                Root = [string]$_.Name
                Available = [double]$_.AvailableFreeSpace
                Total = [double]$_.TotalSize
                DiskNumber = $null
                DeviceName = ''
            }
        })
        if ($quickDisks.Count -gt 0) { Update-HuStorageDisksPanel -DiskRecords $quickDisks }

        $NetworkAdapterValue.Text = ''
        $NetworkDetailsValue.Text = ''
    }
    catch { }
}

function Get-HuThisPcCachePath {
    if (-not $script:Paths -or [string]::IsNullOrWhiteSpace([string]$script:Paths.DataRoot)) { return '' }
    return Join-Path ([string]$script:Paths.DataRoot) 'thispc-cache.json'
}

function Convert-HuThisPcCacheObject {
    param([object]$Value,[string[]]$Properties)
    if (-not $Value) { return $null }
    $result = [ordered]@{}
    foreach ($property in $Properties) {
        $result[$property] = $Value.$property
    }
    return [pscustomobject]$result
}

function Save-HuThisPcCache {
    param([Parameter(Mandatory=$true)][object]$Snapshot)

    try {
        $cachePath = Get-HuThisPcCachePath
        if ([string]::IsNullOrWhiteSpace($cachePath)) { return }
        New-Item -ItemType Directory -Path (Split-Path -Parent $cachePath) -Force -ErrorAction Stop | Out-Null

        $os = Convert-HuThisPcCacheObject -Value $Snapshot.Os -Properties @('Caption','BuildNumber','OSArchitecture','LastBootUpTime','FreePhysicalMemory','TotalVisibleMemorySize')
        if ($os -and $os.LastBootUpTime) {
            try { $os.LastBootUpTime = ([DateTime]$os.LastBootUpTime).ToString('o') } catch { }
        }

        $payload = [ordered]@{
            SchemaVersion = 2
            ComputerName = [string]$env:COMPUTERNAME
            SavedAtUtc = [DateTime]::UtcNow.ToString('o')
            Os = $os
            Cpu = Convert-HuThisPcCacheObject -Value $Snapshot.Cpu -Properties @('Name','NumberOfCores','NumberOfLogicalProcessors','MaxClockSpeed')
            MemoryModules = @($Snapshot.MemoryModules | ForEach-Object {
                Convert-HuThisPcCacheObject -Value $_ -Properties @('Speed','ConfiguredClockSpeed','Manufacturer','PartNumber','DeviceLocator','BankLabel','SMBIOSMemoryType','MemoryType','Capacity')
            })
            Gpus = @($Snapshot.Gpus | ForEach-Object {
                Convert-HuThisPcCacheObject -Value $_ -Properties @('Name','PNPDeviceID','AdapterRAM','DriverVersion')
            })
            BiosCim = Convert-HuThisPcCacheObject -Value $Snapshot.BiosCim -Properties @('SMBIOSBIOSVersion','BIOSVersion','Version')
            DiskRecords = @($Snapshot.DiskRecords | ForEach-Object {
                [ordered]@{
                    Root = [string]$_.Root
                    Available = [double]$_.Available
                    Total = [double]$_.Total
                    DiskNumber = if ($null -ne $_.DiskNumber) { [int]$_.DiskNumber } else { $null }
                    DeviceName = [string]$_.DeviceName
                }
            })
            NetworkInfo = [ordered]@{
                Adapter = [string]$Snapshot.NetworkInfo.Adapter
                InterfaceAlias = [string]$Snapshot.NetworkInfo.InterfaceAlias
                IPv4 = [string]$Snapshot.NetworkInfo.IPv4
                IPv6 = [string]$Snapshot.NetworkInfo.IPv6
                Gateway = [string]$Snapshot.NetworkInfo.Gateway
                Dns = [string]$Snapshot.NetworkInfo.Dns
                Speed = [string]$Snapshot.NetworkInfo.Speed
            }
        }

        $temporaryPath = $cachePath + '.' + [Guid]::NewGuid().ToString('N') + '.tmp'
        try {
            $json = $payload | ConvertTo-Json -Depth 8
            [IO.File]::WriteAllText($temporaryPath,$json,(New-Object Text.UTF8Encoding($false)))
            Move-Item -LiteralPath $temporaryPath -Destination $cachePath -Force -ErrorAction Stop
        }
        finally {
            if (Test-Path -LiteralPath $temporaryPath) { Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue }
        }
    }
    catch { }
}

function Import-HuThisPcCache {
    try {
        $cachePath = Get-HuThisPcCachePath
        if ([string]::IsNullOrWhiteSpace($cachePath) -or -not (Test-Path -LiteralPath $cachePath -PathType Leaf)) { return $false }
        $cache = Get-Content -LiteralPath $cachePath -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if (-not $cache -or [int]$cache.SchemaVersion -ne 2 -or [string]$cache.ComputerName -ne [string]$env:COMPUTERNAME) { return $false }

        $snapshot = [pscustomobject]@{
            Os = $cache.Os
            Cpu = $cache.Cpu
            MemoryModules = @($cache.MemoryModules)
            Gpus = @($cache.Gpus)
            BiosCim = $cache.BiosCim
            DiskRecords = @($cache.DiskRecords)
            NetworkInfo = $cache.NetworkInfo
        }
        Apply-HuThisPcSnapshot -Snapshot $snapshot -SkipCacheSave
        return $true
    }
    catch { return $false }
}

function Apply-HuThisPcSnapshot {
    param(
        [Parameter(Mandatory=$true)][object]$Snapshot,
        [switch]$SkipCacheSave
    )

    try {
        $script:ThisPcCurrentSnapshot = $Snapshot

        $os = $Snapshot.Os
        $cpu = $Snapshot.Cpu
        $memoryModules = @($Snapshot.MemoryModules)
        $gpus = @($Snapshot.Gpus)
        $biosCim = $Snapshot.BiosCim
        $diskRecords = @($Snapshot.DiskRecords)
        $networkInfo = $Snapshot.NetworkInfo

        $windowsInfo = try { Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop } catch { $null }
        $cpuInfo = try { Get-ItemProperty -LiteralPath 'HKLM:\HARDWARE\DESCRIPTION\System\CentralProcessor\0' -ErrorAction Stop } catch { $null }
        $biosInfo = try { Get-ItemProperty -LiteralPath 'HKLM:\HARDWARE\DESCRIPTION\System\BIOS' -ErrorAction Stop } catch { $null }

        $uptime = if ($os -and $os.LastBootUpTime) { (Get-Date) - [DateTime]$os.LastBootUpTime } else { [TimeSpan]::FromMilliseconds([math]::Max(0,[Environment]::TickCount)) }

        $ramInstalled = @($memoryModules | ForEach-Object { try { [double]$_.Capacity } catch { 0 } } | Measure-Object -Sum).Sum
        $ramTotal = if ($ramInstalled -gt 0) { [double]$ramInstalled } elseif ($os -and $os.TotalVisibleMemorySize) { [double]$os.TotalVisibleMemorySize * 1KB } else { 0 }
        $ramAvailable = if ($os -and $os.FreePhysicalMemory) { [double]$os.FreePhysicalMemory * 1KB } else { 0 }
        if ($ramTotal -le 0) {
            try {
                Add-Type -AssemblyName Microsoft.VisualBasic -ErrorAction Stop
                $computerInfo = New-Object Microsoft.VisualBasic.Devices.ComputerInfo
                $ramTotal = [double]$computerInfo.TotalPhysicalMemory
                $ramAvailable = [double]$computerInfo.AvailablePhysicalMemory
            }
            catch { }
        }

        $ramSpeed = @($memoryModules | ForEach-Object { if ($_.ConfiguredClockSpeed) { $_.ConfiguredClockSpeed } elseif ($_.Speed) { $_.Speed } } | Where-Object { $_ } | Select-Object -Unique) -join ' / '
        $ramType = Get-HuMemoryTypeLabel -Modules $memoryModules
        $ramDisplayName = Get-HuMemoryDisplayName -Modules $memoryModules
        $ramSlots = @(Get-HuOccupiedDimmLabels -Modules $memoryModules)
        $gpuNames = @($gpus | ForEach-Object { Get-HuGraphicsExactDisplayName -Gpu $_ } | Where-Object { $_ } | Select-Object -Unique) -join ' · '
        $gpuMemory = Get-HuGraphicsMemoryBytes -Gpus $gpus
        $script:PrimaryGpuIsNvidia = @($gpus | Where-Object { [string]$_.Name -match 'NVIDIA' -or [string]$_.PNPDeviceID -match 'VEN_10DE' }).Count -gt 0

        $amdSoftwareVersion = if ($gpus | Where-Object { [string]$_.Name -match 'AMD|Radeon' -or [string]$_.PNPDeviceID -match 'VEN_1002' }) { Get-HuAmdSoftwareVersion } else { '' }
        $gpuDrivers = @($gpus | Where-Object DriverVersion | ForEach-Object { Get-HuGraphicsDriverDisplay -Gpu $_ -AmdSoftwareVersion $amdSoftwareVersion } | Where-Object { $_ } | Select-Object -Unique) -join ' / '

        foreach ($record in $diskRecords) {
            if (-not $record.PSObject.Properties['DeviceName']) {
                $record | Add-Member -NotePropertyName DeviceName -NotePropertyValue (T 'Unavailable')
            }
            elseif ([string]::IsNullOrWhiteSpace([string]$record.DeviceName)) {
                $record.DeviceName = T 'Unavailable'
            }
        }
        $driveText = @($diskRecords | ForEach-Object { '{0}  {1} - {2}' -f $_.Root,(TF 'ThisPcDiskCapacityFormat' @((Format-HuByteSize $_.Available),(Format-HuByteSize $_.Total))),$_.DeviceName }) -join "`r`n"

        $osCaption = if ($os) { ([string]$os.Caption).Trim() } elseif ($windowsInfo) { [string]$windowsInfo.ProductName } else { 'Windows' }
        $buildNumber = if ($windowsInfo -and $windowsInfo.CurrentBuild) { [string]$windowsInfo.CurrentBuild } elseif ($os -and $os.BuildNumber) { [string]$os.BuildNumber } else { [Environment]::OSVersion.Version.Build.ToString() }
        $buildRevision = if ($windowsInfo -and $null -ne $windowsInfo.UBR) { [string]$windowsInfo.UBR } else { [Environment]::OSVersion.Version.Revision.ToString() }
        $windowsFamily = if ($osCaption -match 'Windows\s+11' -or ([int]$buildNumber -ge 22000)) { 'Windows 11' } elseif ($osCaption -match 'Windows\s+10') { 'Windows 10' } else { 'Windows' }
        $windowsEdition = Get-HuWindowsEditionDisplayName -Source $osCaption
        $osDisplay = (@($windowsFamily,$windowsEdition) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique) -join ' '
        $osArchitecture = if ($os) { [string]$os.OSArchitecture } elseif ([Environment]::Is64BitOperatingSystem) { '64-bit' } else { '32-bit' }
        $architectureLabel = if ($osArchitecture -match 'ARM64') { 'ARM64' } elseif ($osArchitecture -match '64') { 'x64' } else { 'x32' }
        $cpuName = if ($cpu) { ([string]$cpu.Name).Trim() } elseif ($cpuInfo) { ([string]$cpuInfo.ProcessorNameString).Trim() } else { [string]$env:PROCESSOR_IDENTIFIER }
        $cpuCores = if ($cpu) { [int]$cpu.NumberOfCores } else { [Environment]::ProcessorCount }
        $cpuThreads = if ($cpu) { [int]$cpu.NumberOfLogicalProcessors } else { [Environment]::ProcessorCount }
        $cpuMhz = if ($cpu) { [double]$cpu.MaxClockSpeed } elseif ($cpuInfo) { [double]$cpuInfo.'~MHz' } else { 0 }

        $ComputerNameValue.Text = [string]$env:COMPUTERNAME
        $OperatingSystemValue.Text = $osDisplay
        $BuildValue.Text = '{0}.{1}' -f $buildNumber,$buildRevision
        $SystemTypeValue.Text = $architectureLabel
        $UptimeValue.Text = TF 'UptimeFormat' @([math]::Floor($uptime.TotalDays),$uptime.Hours,$uptime.Minutes)
        $ProcessorValue.Text = $(if ($cpuName) { Get-HuThisPcProcessorDisplayName $cpuName } else { T 'Unavailable' })
        $ProcessorDetailsValue.Text = TF 'ProcessorDetails' @($cpuCores,$cpuThreads,$(if ($cpuMhz -gt 0) { '{0:N2}' -f ($cpuMhz / 1000) } else { '—' }))

        $memoryTotalText = $(if ($ramTotal -gt 0) { (Format-HuThisPcMemorySize $ramTotal) } else { T 'Unavailable' })
        $memoryAvailableText = $(if ($ramAvailable -gt 0) { (Format-HuThisPcMemorySize $ramAvailable) } else { T 'Unavailable' })
        $MemoryValue.Text = $(if (-not [string]::IsNullOrWhiteSpace($ramDisplayName)) { $ramDisplayName } else { T 'Unavailable' })
        $memoryTypeSuffix = $(if (-not [string]::IsNullOrWhiteSpace($ramType)) { ' ' + $ramType } else { '' })
        $memoryLine = TF 'ThisPcMemoryFormat' @($memoryTotalText,$memoryTypeSuffix,$memoryAvailableText)
        $slotsText = $(if ($ramSlots.Count -gt 0) { ' (' + ($ramSlots -join ' ') + ')' } else { '' })
        $cadenceLine = TF 'ThisPcMemorySpeedFormat' @($(if ($ramSpeed) { $ramSpeed + ' MHz' } else { T 'Unavailable' }))
        $modulesLine = TF 'ThisPcMemoryModulesFormat' @($memoryModules.Count,$slotsText)
        $MemoryDetailsValue.Text = $memoryLine + "`r`n" + $cadenceLine + "`r`n" + $modulesLine

        $GraphicsValue.Text = $(if ($gpuNames) { $gpuNames } else { T 'Unavailable' })
        $gpuDriverNumbers = @($gpuDrivers -split '\s*/\s*' | ForEach-Object { ([string]$_ -replace '^(NVIDIA|AMD|Intel)\s+','').Trim() } | Where-Object { $_ }) -join ' / '
        $GraphicsDetailsValue.Text = (TF 'GraphicsMemory' @($(if ($gpuMemory -gt 0) { Format-HuByteSize $gpuMemory } else { T 'Unavailable' }))) + "`r`n" + ('{0} : {1}' -f (T 'DriverVersion'),$(if ($gpuDriverNumbers) { $gpuDriverNumbers } else { T 'Unavailable' }))

        $StorageValue.Text = $(if ($driveText) { $driveText } else { T 'Unavailable' })
        Update-HuStorageDisksPanel -DiskRecords $diskRecords

        $boardManufacturer = if ($biosInfo -and $biosInfo.BaseBoardManufacturer) { ([string]$biosInfo.BaseBoardManufacturer).Trim() } elseif ($biosInfo) { ([string]$biosInfo.SystemManufacturer).Trim() } else { '' }
        $boardModel = if ($biosInfo -and $biosInfo.BaseBoardProduct) { ([string]$biosInfo.BaseBoardProduct).Trim() } else { '' }
        $biosVersion = Get-HuBiosDisplayVersion -BiosRegistry $biosInfo -BiosCim $biosCim -BoardModel $boardModel -BoardManufacturer $boardManufacturer
        $boardDisplayModel = [regex]::Replace(([string]$boardModel).Trim(),'\s*\([^)]*\)\s*$','').Trim()
        $MotherboardModelValue.Text = $(if (-not [string]::IsNullOrWhiteSpace($boardDisplayModel)) { $boardDisplayModel } else { T 'Unavailable' })
        $MotherboardManufacturerValue.Text = TF 'ThisPcManufacturerFormat' @($(if (-not [string]::IsNullOrWhiteSpace($boardManufacturer)) { $boardManufacturer } else { T 'Unavailable' }))
        $MotherboardBiosValue.Text = TF 'ThisPcBiosFormat' @($(if (-not [string]::IsNullOrWhiteSpace($biosVersion)) { $biosVersion } else { T 'Unavailable' }))
        $MotherboardValue.Text = (TF 'ThisPcModelFormat' @($MotherboardModelValue.Text)) + "`r`n" + $MotherboardManufacturerValue.Text + "`r`n" + $MotherboardBiosValue.Text
        $script:MotherboardOfficialUrl = Get-HuMotherboardOfficialUrl -Manufacturer $boardManufacturer -Model $boardModel

        $script:NetworkInterfaceAlias = [string]$networkInfo.InterfaceAlias
        $NetworkAdapterValue.Text = $(if (-not [string]::IsNullOrWhiteSpace([string]$networkInfo.Adapter)) { [string]$networkInfo.Adapter } else { T 'Unavailable' })
        $networkLines = New-Object 'System.Collections.Generic.List[string]'
        if (-not [string]::IsNullOrWhiteSpace([string]$networkInfo.IPv4)) { $networkLines.Add(('IPv4 : {0}' -f $networkInfo.IPv4)) }
        if (-not [string]::IsNullOrWhiteSpace([string]$networkInfo.IPv6)) { $networkLines.Add(('IPv6 : {0}' -f $networkInfo.IPv6)) }
        if (-not [string]::IsNullOrWhiteSpace([string]$networkInfo.Gateway)) { $networkLines.Add((TF 'DiagnosticGateway' @($networkInfo.Gateway))) }
        if (-not [string]::IsNullOrWhiteSpace([string]$networkInfo.Dns)) { $networkLines.Add(('DNS : {0}' -f $networkInfo.Dns)) }
        if (-not [string]::IsNullOrWhiteSpace([string]$networkInfo.Speed)) { $networkLines.Add((TF 'ThisPcSpeedFormat' @($networkInfo.Speed))) }
        $NetworkDetailsValue.Text = $(if ($networkLines.Count -gt 0) { $networkLines -join "`r`n" } else { T 'Unavailable' })

        $script:SpecsText = @(
            "$(T 'ComputerName'): $($ComputerNameValue.Text)",
            "OS: $($OperatingSystemValue.Text)",
            "Build: $($BuildValue.Text)",
            "$(T 'SystemType'): $($SystemTypeValue.Text)",
            "$(T 'Uptime'): $($UptimeValue.Text)",
            "$(T 'Processor'): $($ProcessorValue.Text) — $($ProcessorDetailsValue.Text)",
            "$(T 'Memory'): $($MemoryValue.Text) — $($MemoryDetailsValue.Text)",
            "$(T 'Graphics'): $($GraphicsValue.Text) — $($GraphicsDetailsValue.Text)",
            "$(T 'ThisPcStorage'): $($StorageValue.Text)",
            "$(T 'ThisPcMotherboard'): $($MotherboardValue.Text)",
            "$(T 'NetworkTitle'): $($NetworkAdapterValue.Text) - $($NetworkDetailsValue.Text)"
        ) -join "`r`n"
        $script:SpecsLoaded = $true
        if (-not $SkipCacheSave) { Save-HuThisPcCache -Snapshot $Snapshot }
    }
    catch { Show-AppError $_.Exception.Message }
}

function Clear-HuThisPcRefreshWorker {
    foreach($task in @($script:ThisPcRefreshTasks)) {
        if(-not $task){continue}
        try{if($task.Async -and -not $task.Async.IsCompleted){$task.PowerShell.Stop()}}catch{}
        try{$task.PowerShell.Dispose()}catch{}
    }
    $script:ThisPcRefreshTasks=@()
    $script:ThisPcRefreshStartedAt=$null
}

function Start-HuThisPcRefreshJob {
    param([switch]$DynamicOnly)
    if(@($script:ThisPcRefreshTasks).Count -gt 0){return}
    Clear-HuThisPcRefreshWorker

    $pool=Get-HuSharedRunspacePool
    $tasks=New-Object 'System.Collections.Generic.List[object]'
    $definitions=New-Object 'System.Collections.Generic.List[object]'

    $definitions.Add([pscustomobject]@{Kind='Os';Script=@'
$value=try{Get-CimInstance Win32_OperatingSystem -Property Caption,BuildNumber,OSArchitecture,LastBootUpTime,FreePhysicalMemory,TotalVisibleMemorySize -ErrorAction Stop}catch{$null}
[pscustomobject]@{Kind='Os';Value=$value}
'@})

    if(-not $DynamicOnly){
        $definitions.Add([pscustomobject]@{Kind='Cpu';Script=@'
$value=try{Get-CimInstance Win32_Processor -Property Name,NumberOfCores,NumberOfLogicalProcessors,MaxClockSpeed -ErrorAction Stop|Select-Object -First 1}catch{$null}
[pscustomobject]@{Kind='Cpu';Value=$value}
'@})
        $definitions.Add([pscustomobject]@{Kind='MemoryModules';Script=@'
$value=@(try{Get-CimInstance Win32_PhysicalMemory -Property Speed,ConfiguredClockSpeed,Manufacturer,PartNumber,DeviceLocator,BankLabel,SMBIOSMemoryType,MemoryType,Capacity -ErrorAction Stop}catch{@()})
[pscustomobject]@{Kind='MemoryModules';Value=$value}
'@})
        $definitions.Add([pscustomobject]@{Kind='Gpus';Script=@'
$value=@(try{Get-CimInstance Win32_VideoController -Property Name,PNPDeviceID,AdapterRAM,DriverVersion -ErrorAction Stop|Where-Object{$_.Name}}catch{@()})
[pscustomobject]@{Kind='Gpus';Value=$value}
'@})
        $definitions.Add([pscustomobject]@{Kind='BiosCim';Script=@'
$value=try{Get-CimInstance Win32_BIOS -Property SMBIOSBIOSVersion,BIOSVersion,Version -ErrorAction Stop|Select-Object -First 1}catch{$null}
[pscustomobject]@{Kind='BiosCim';Value=$value}
'@})
    }

    if($DynamicOnly){
        $definitions.Add([pscustomobject]@{Kind='DiskRecords';Script=@'
foreach($drive in @([IO.DriveInfo]::GetDrives()|Where-Object{$_.DriveType -eq [IO.DriveType]::Fixed -and $_.IsReady})){
 [pscustomobject]@{Root=[string]$drive.Name;Available=[double]$drive.AvailableFreeSpace;Total=[double]$drive.TotalSize;DiskNumber=$null;DeviceName=''}
}
'@})
    }else{
        $definitions.Add([pscustomobject]@{Kind='DiskRecords';Script=@'
$drives=@([IO.DriveInfo]::GetDrives()|Where-Object{$_.DriveType -eq [IO.DriveType]::Fixed -and $_.IsReady})
$partitionMap=@{};$diskMap=@{}
try{foreach($p in @(Get-Partition -ErrorAction Stop)){if($p.DriveLetter){$partitionMap[([string]$p.DriveLetter).ToUpperInvariant()]=$p}};foreach($d in @(Get-Disk -ErrorAction Stop)){$diskMap[[int]$d.Number]=$d}}catch{}
foreach($drive in $drives){
 $root=[string]$drive.Name;$letter=$root.TrimEnd('\').TrimEnd(':').ToUpperInvariant();$number=$null;$manufacturer='';$model=''
 if($partitionMap.ContainsKey($letter)){$p=$partitionMap[$letter];try{$number=[int]$p.DiskNumber}catch{};if($null -ne $number -and $diskMap.ContainsKey([int]$number)){$d=$diskMap[[int]$number];$manufacturer=([string]$d.Manufacturer).Trim();$model=([string]$d.Model).Trim()}}
 $deviceName=(@($manufacturer,$model)|Where-Object{$_}) -join ' '
 [pscustomobject]@{Root=$root;Available=[double]$drive.AvailableFreeSpace;Total=[double]$drive.TotalSize;DiskNumber=$number;DeviceName=$deviceName}
}
'@})
    }

    $definitions.Add([pscustomobject]@{Kind='NetworkInfo';Script=@'
$network=[ordered]@{Adapter='';InterfaceAlias='';IPv4='';IPv6='';Gateway='';Dns='';Speed=''}
try{
 $configs=@(Get-NetIPConfiguration -ErrorAction Stop|Where-Object{$_.NetAdapter -and $_.NetAdapter.Status -eq 'Up'})
 $config=$configs|Sort-Object @{Expression={if($_.IPv4DefaultGateway -or $_.IPv6DefaultGateway){0}else{1}}},InterfaceIndex|Select-Object -First 1
 if($config){
  $network.InterfaceAlias=([string]$config.InterfaceAlias).Trim();$network.Adapter=$network.InterfaceAlias
  try{$adapter=Get-NetAdapter -InterfaceIndex $config.InterfaceIndex -ErrorAction Stop;if($adapter){$description=([string]$adapter.InterfaceDescription).Trim();if($description){$network.Adapter=$description};$network.Speed=([string]$adapter.LinkSpeed).Trim()}}catch{}
  $v4=@($config.IPv4Address|ForEach-Object{([string]$_.IPAddress).Trim()}|Where-Object{$_});if($v4.Count){$network.IPv4=$v4 -join ' / '}
  $v6=@($config.IPv6Address|ForEach-Object{([string]$_.IPAddress).Trim()}|Where-Object{$_ -and $_ -notmatch '^(?i)fe80:' -and $_ -ne '::1'});if($v6.Count){$network.IPv6=$v6 -join ' / '}
  $gw=@(@($config.IPv4DefaultGateway)+@($config.IPv6DefaultGateway)|Where-Object{$_}|ForEach-Object{([string]$_.NextHop).Trim()}|Where-Object{$_});if($gw.Count){$network.Gateway=$gw -join ' / '}
  try{$dns=@(Get-DnsClientServerAddress -InterfaceIndex $config.InterfaceIndex -ErrorAction Stop|ForEach-Object{$_.ServerAddresses}|Where-Object{$_}|Select-Object -Unique);if($dns.Count){$network.Dns=$dns -join ' / '}}catch{}
 }
}catch{}
[pscustomobject]@{Kind='NetworkInfo';Value=[pscustomobject]$network}
'@})

    foreach($definition in $definitions){
        $worker=[System.Management.Automation.PowerShell]::Create()
        $worker.RunspacePool=$pool
        [void]$worker.AddScript([string]$definition.Script)
        $tasks.Add([pscustomobject]@{Kind=[string]$definition.Kind;PowerShell=$worker;Async=$worker.BeginInvoke()})
    }
    $script:ThisPcRefreshTasks=$tasks.ToArray()
    $script:ThisPcRefreshStartedAt=Get-Date
}

function Complete-HuThisPcRefreshWorker {
    param([switch]$AllowPartial)
    $tasks=@($script:ThisPcRefreshTasks)
    if($tasks.Count -eq 0){return $false}
    if(-not $AllowPartial -and @($tasks|Where-Object{-not $_.Async.IsCompleted}).Count -gt 0){return $false}

    $values=@{}
    foreach($task in $tasks){
        if(-not $task.Async.IsCompleted){continue}
        try{
            $output=@($task.PowerShell.EndInvoke($task.Async))
            if([string]$task.Kind -eq 'DiskRecords'){$values['DiskRecords']=@($output|Where-Object{$_ -and $_.PSObject.Properties['Root']});continue}
            $record=$output|Where-Object{$_ -and $_.PSObject.Properties['Kind']}|Select-Object -Last 1
            if($record){$values[[string]$record.Kind]=$record.Value}
        }catch{}
    }

    $previous=$script:ThisPcCurrentSnapshot
    $oldDisks=if($previous){@($previous.DiskRecords)}else{@()}
    $newDisks=@($values['DiskRecords'])
    if($newDisks.Count -gt 0 -and $oldDisks.Count -gt 0){
        foreach($disk in $newDisks){
            $old=$oldDisks|Where-Object{[string]$_.Root -eq [string]$disk.Root}|Select-Object -First 1
            if(-not $disk.PSObject.Properties['DiskNumber']){$disk|Add-Member -NotePropertyName DiskNumber -NotePropertyValue $null}
            if(-not $disk.PSObject.Properties['DeviceName']){$disk|Add-Member -NotePropertyName DeviceName -NotePropertyValue ''}
            if($old){if($null -eq $disk.DiskNumber){$disk.DiskNumber=$old.DiskNumber};if([string]::IsNullOrWhiteSpace([string]$disk.DeviceName)){$disk.DeviceName=[string]$old.DeviceName}}
        }
    }

    $snapshot=[pscustomobject]@{
        Os=$(if($values.ContainsKey('Os') -and $values['Os']){$values['Os']}elseif($previous){$previous.Os}else{$null})
        Cpu=$(if($values.ContainsKey('Cpu') -and $values['Cpu']){$values['Cpu']}elseif($previous){$previous.Cpu}else{$null})
        MemoryModules=$(if($values.ContainsKey('MemoryModules') -and @($values['MemoryModules']).Count){@($values['MemoryModules'])}elseif($previous){@($previous.MemoryModules)}else{@()})
        Gpus=$(if($values.ContainsKey('Gpus') -and @($values['Gpus']).Count){@($values['Gpus'])}elseif($previous){@($previous.Gpus)}else{@()})
        BiosCim=$(if($values.ContainsKey('BiosCim') -and $values['BiosCim']){$values['BiosCim']}elseif($previous){$previous.BiosCim}else{$null})
        DiskRecords=$(if($newDisks.Count){$newDisks}elseif($previous){@($previous.DiskRecords)}else{@()})
        NetworkInfo=$(if($values.ContainsKey('NetworkInfo') -and $values['NetworkInfo']){$values['NetworkInfo']}elseif($previous){$previous.NetworkInfo}else{$null})
    }
    try{Apply-HuThisPcSnapshot -Snapshot $snapshot;return $true}catch{return $false}finally{Clear-HuThisPcRefreshWorker}
}

function Refresh-ThisPcInformation {
    param([switch]$DynamicOnly)
    if (Get-Command Update-HuDisplayInventory -ErrorAction SilentlyContinue) { Update-HuDisplayInventory }
    $RefreshSpecsButton.IsEnabled=$false
    Clear-HuThisPcRefreshWorker
    Start-HuThisPcRefreshJob -DynamicOnly:$DynamicOnly

    if(-not $script:ThisPcRefreshTimer){
        $script:ThisPcRefreshTimer=New-Object Windows.Threading.DispatcherTimer
        $script:ThisPcRefreshTimer.Interval=[TimeSpan]::FromMilliseconds(100)
        $script:ThisPcRefreshTimer.Add_Tick({
            $tasks=@($script:ThisPcRefreshTasks)
            if($tasks.Count -eq 0){$script:ThisPcRefreshTimer.Stop();$RefreshSpecsButton.IsEnabled=$true;return}
            $pending=@($tasks|Where-Object{-not $_.Async.IsCompleted})
            if($pending.Count -gt 0){
                if($script:ThisPcRefreshStartedAt -and ((Get-Date)-$script:ThisPcRefreshStartedAt).TotalSeconds -ge 6){
                    foreach($task in $pending){try{$task.PowerShell.Stop()}catch{}}
                    $script:ThisPcRefreshTimer.Stop();[void](Complete-HuThisPcRefreshWorker -AllowPartial);$RefreshSpecsButton.IsEnabled=$true
                }
                return
            }
            $script:ThisPcRefreshTimer.Stop();[void](Complete-HuThisPcRefreshWorker);$RefreshSpecsButton.IsEnabled=$true
        })
    }
    $script:ThisPcRefreshTimer.Stop();$script:ThisPcRefreshTimer.Start()
}
