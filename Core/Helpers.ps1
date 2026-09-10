function Set-Busy {
    param([bool]$Value, [string]$Message)
    $script:Busy = $Value
    $BusyProgress.Visibility = if ($Value) { 'Visible' } else { 'Collapsed' }
    $StatusBarText.Text = if ($Value -and $Message) { $Message } else { '' }
    $StatusBarText.Visibility = if ($Value -and $Message) { 'Visible' } else { 'Collapsed' }
    foreach ($button in @($TestSourceButton,$ManualAddButton,$UpdateNowButton,$RestoreLatestButton,$RestoreSelectedButton,$RefreshHistoryButton,$DeleteSelectedBackupButton,$ClearHistoryButton,$CheckUpdatesButton)) {
        $button.IsEnabled = -not $Value
    }
    if (-not $Value) {
        $hasSelection = $null -ne $BackupGrid.SelectedItem
        $DeleteSelectedBackupButton.IsEnabled = $hasSelection
        $RestoreSelectedButton.IsEnabled = $hasSelection
        $ClearHistoryButton.IsEnabled = @(Get-AppBackups).Count -gt 0
        Update-SourceBanner; Update-StatusPanel
    }
    $window.Dispatcher.Invoke([Action]{}, [Windows.Threading.DispatcherPriority]::Background)
}

function Format-Size {
    param([int64]$Bytes)
    if ($Bytes -ge 1MB) { return ('{0:N1} MB' -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ('{0:N0} KB' -f ($Bytes / 1KB)) }
    return "$Bytes B"
}

function Get-PreferredTextEditor {
    $candidates = New-Object System.Collections.Generic.List[string]
    try { $candidates.Add((Get-Command 'notepad++.exe' -ErrorAction Stop).Source) } catch { }
    foreach ($registryPath in @('HKCU:\Software\Microsoft\Windows\CurrentVersion\App Paths\notepad++.exe','HKLM:\Software\Microsoft\Windows\CurrentVersion\App Paths\notepad++.exe','HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths\notepad++.exe')) { try { $candidates.Add([string](Get-ItemPropertyValue -LiteralPath $registryPath -Name '(default)' -ErrorAction Stop)) } catch { } }
    foreach ($candidate in @((Join-Path $script:AppRoot 'Notepad++\notepad++.exe'),(Join-Path (Split-Path -Parent $script:AppRoot) 'Notepad++\notepad++.exe'),(Join-Path $env:ProgramFiles 'Notepad++\notepad++.exe'),$(if (${env:ProgramFiles(x86)}) { Join-Path ${env:ProgramFiles(x86)} 'Notepad++\notepad++.exe' }),(Join-Path $env:LOCALAPPDATA 'Programs\Notepad++\notepad++.exe'))) { if ($candidate) { $candidates.Add([string]$candidate) } }
    foreach ($candidate in $candidates) { if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) { return $candidate } }
    return (Join-Path $env:SystemRoot 'System32\notepad.exe')
}

function Open-TextFile { param([Parameter(Mandatory = $true)][string]$Path) if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw (T 'TextFileMissing') }; $editor=Get-PreferredTextEditor; Start-Process -FilePath $editor -ArgumentList @(('"{0}"' -f ([IO.Path]::GetFullPath($Path)))) | Out-Null }

function Test-PingTarget {
    param([AllowEmptyString()][string]$Value)
    $target = $Value.Trim().TrimEnd('.')
    if (-not $target -or $target.Length -gt 253) { return $false }
    $ip = $null
    if ([Net.IPAddress]::TryParse($target, [ref]$ip)) { return $true }
    if ($target -match '^[0-9.]+$') { return $false }
    return $target -match '^(?=.{1,253}$)(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)*[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?$'
}

function Find-VisualDescendant {
    param([Parameter(Mandatory=$true)][Windows.DependencyObject]$Root, [Parameter(Mandatory=$true)][Type]$Type)
    $count = 0
    try { $count = [Windows.Media.VisualTreeHelper]::GetChildrenCount($Root) } catch { return $null }
    for ($index=0; $index -lt $count; $index++) {
        $child = [Windows.Media.VisualTreeHelper]::GetChild($Root,$index)
        if ($Type.IsInstanceOfType($child)) { return $child }
        $match = Find-VisualDescendant -Root $child -Type $Type
        if ($match) { return $match }
    }
    return $null
}

function Invoke-CapturedUtility {
    param([Parameter(Mandatory=$true)][string]$FilePath, [string[]]$Arguments=@())
    if (-not (Test-Path -LiteralPath $FilePath -PathType Leaf)) { throw (TF 'ExecutableMissing' @($FilePath)) }
    $startInfo = New-Object Diagnostics.ProcessStartInfo
    $startInfo.FileName = $FilePath
    $startInfo.Arguments = ($Arguments -join ' ')
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    try {
        $oem = [Text.Encoding]::GetEncoding([Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage)
        $startInfo.StandardOutputEncoding = $oem
        $startInfo.StandardErrorEncoding = $oem
    } catch { }
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $startInfo
    try {
        if (-not $process.Start()) { throw (T 'CommandStartFailed') }
        $stdout = $process.StandardOutput.ReadToEnd()
        $stderr = $process.StandardError.ReadToEnd()
        $process.WaitForExit()
        return [pscustomobject]@{ Output=$stdout; Error=$stderr; ExitCode=$process.ExitCode }
    }
    finally { $process.Dispose() }
}

function Get-WnstLogText {
    param([AllowNull()][object]$Control)

    if (-not $Control) { return '' }
    if ($Control -is [Windows.Controls.RichTextBox]) {
        $range = [Windows.Documents.TextRange]::new($Control.Document.ContentStart,$Control.Document.ContentEnd)
        return ([string]$range.Text).TrimEnd([char[]]@("`r","`n"))
    }
    if ($null -ne $Control.PSObject.Properties['Text']) { return [string]$Control.Text }
    return ''
}

function Get-WnstLogLineLevel {
    param(
        [AllowEmptyString()][string]$Text,
        [ValidateSet('Auto','Normal','Success','Error')][string]$Level = 'Auto'
    )

    if ($Level -ne 'Auto') { return $Level }
    $probe = ([string]$Text).TrimStart()
    $probe = [regex]::Replace($probe,'^\[\d{2}:\d{2}:\d{2}\]\s*','')
    if ($probe -match '^\[OK\](?:\s|$)') { return 'Success' }
    if ($probe -match '^\[(?:ERROR|ERR|FAIL|FAILED)\](?:\s|$)') { return 'Error' }
    return 'Normal'
}

$script:WnstPersistentLogTargets = New-Object 'System.Collections.Generic.List[object]'

function Register-WnstPersistentLogTarget {
    param(
        [AllowNull()][object]$Control,
        [Parameter(Mandatory=$true)][string]$Name
    )

    if (-not $Control -or [string]::IsNullOrWhiteSpace($Name)) { return }
    foreach ($target in $script:WnstPersistentLogTargets) {
        if ([object]::ReferenceEquals($target.Control,$Control)) {
            $target.Name = $Name
            return
        }
    }
    $script:WnstPersistentLogTargets.Add([pscustomobject]@{ Control=$Control; Name=$Name })
}

function Get-WnstPersistentLogName {
    param([AllowNull()][object]$Control)

    if (-not $Control) { return '' }
    foreach ($target in $script:WnstPersistentLogTargets) {
        if ([object]::ReferenceEquals($target.Control,$Control)) { return [string]$target.Name }
    }
    return ''
}

function Get-WnstPersistentLogPath {
    param([Parameter(Mandatory=$true)][string]$Name)

    $logRoot = [string]$script:Paths.LogRoot
    if ([string]::IsNullOrWhiteSpace($logRoot)) {
        $logRoot = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'WNST\Logs'
    }
    if (-not (Test-Path -LiteralPath $logRoot -PathType Container)) {
        [void](New-Item -ItemType Directory -Path $logRoot -Force -ErrorAction Stop)
    }
    return (Join-Path $logRoot ('WNST-{0}.log' -f $Name))
}

function Add-WnstPersistentLogText {
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [AllowEmptyString()][string]$Text
    )

    if ([string]::IsNullOrEmpty($Text)) { return }
    try {
        $path = Get-WnstPersistentLogPath -Name $Name
        $entry = [string]$Text + [Environment]::NewLine
        $encoding = New-Object Text.UTF8Encoding($true)
        if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or (Get-Item -LiteralPath $path).Length -eq 0) {
            [IO.File]::WriteAllText($path,$entry,$encoding)
        }
        else {
            [IO.File]::AppendAllText($path,$entry,$encoding)
        }
    }
    catch { }
}

function Resolve-WnstLogItemText {
    param([AllowNull()][object]$Item)

    if ($null -eq $Item) { return '' }
    if ($Item.PSObject.Properties['Key'] -and -not [string]::IsNullOrWhiteSpace([string]$Item.Key)) {
        $arguments = if ($Item.PSObject.Properties['Args']) { @($Item.Args) } else { @() }
        $resolved = $(if ($arguments.Count -gt 0) { TF ([string]$Item.Key) $arguments } else { T ([string]$Item.Key) })
        if ($Item.PSObject.Properties['Prefix'] -and -not [string]::IsNullOrWhiteSpace([string]$Item.Prefix)) {
            return ('{0} {1}' -f [string]$Item.Prefix,$resolved)
        }
        return $resolved
    }
    if ($Item.PSObject.Properties['Text']) { return [string]$Item.Text }
    return [string]$Item
}

function ConvertTo-WnstLocalizedLogText {
    param([AllowEmptyString()][string]$Text)

    if ([string]::IsNullOrEmpty($Text)) { return $Text }

    $categories = @((T 'LogTechnicalCategories') -split '\|')
    $terms = @((T 'LogTechnicalTerms') -split '\|')
    if ($categories.Count -ne 22 -or $terms.Count -ne 45) { return $Text }

    $localized = ([string]$Text).Replace('[TASKS] SCHEDULED_TASKS','[TASKS]')
    $categoryTokens = @(
        '[PROC]','[SCAN]','[FILE]','[CMD]','[EXIT]','[REG]','[SHORTCUT]',
        '[TASK]','[HIVE]','[PATH]','[USER]','[CHECK]','[SERVICE]','[TASKS]',
        '[HOSTS]','[WAIT]','[FEATURE]','[SYSTEM]','[VERIFY]','[START]',
        '[APPX-PROV]','[FAIL]'
    )
    for ($index = 0; $index -lt $categoryTokens.Count; $index++) {
        $localized = $localized.Replace($categoryTokens[$index],('[' + $categories[$index] + ']'))
    }

    # Remplacer d'abord les expressions longues afin de ne pas fragmenter les
    # états techniques composés comme AUTO-STARTED ou SCHEDULED_TASKS.
    $replacements = @(
        @('=True','=✓'),
        @('=False','=—'),
        @('package still installed after SYSTEM AppX removal',$terms[40]),
        @('SYSTEM worker did not complete',$terms[41]),
        @('SCHEDULED_TASKS',$terms[32]),
        @('AUTO-STARTED',$terms[11]),
        @('validation failed',$terms[39]),
        @('install/update',$terms[28]),
        @('exit code',$terms[29]),
        @('dnsFlush=',$terms[27] + '='),
        @('endpoints=',$terms[26] + '='),
        @('provisioned=',$terms[19] + '='),
        @('installed=',$terms[18] + '='),
        @('changed=',$terms[25] + '='),
        @('items=',$terms[17] + '='),
        @('files=',$terms[30] + '='),
        @('process=',$terms[31] + '='),
        @('UNTOUCHED',$terms[21]),
        @('UNINSTALL',$terms[36]),
        @('REMOVED',$terms[2]),
        @('PRESENT',$terms[3]),
        @('DELETE',$terms[4]),
        @('FAILED',$terms[5]),
        @('ABSENT',$terms[6]),
        @('STOPPED',$terms[8]),
        @('TIMEOUT',$terms[9]),
        @('STARTED',$terms[10]),
        @('LOADED',$terms[13]),
        @('UNLOADED',$terms[14]),
        @('DISABLED',$terms[20]),
        @('BLOCKED',$terms[23]),
        @('VERIFIED',$terms[1]),
        @('ENABLE',$terms[22]),
        @('REMOVE',$terms[24]),
        @('START',$terms[0]),
        @('STOP',$terms[7]),
        @('LOAD',$terms[12]),
        @('KEEP',$terms[15]),
        @('EMPTY',$terms[16]),
        @('protected',$terms[33]),
        @('worker',$terms[34]),
        @('token',$terms[35]),
        @('policy',$terms[37]),
        @('attempt',$terms[38]),
        @('marker',$terms[42]),
        @(' user ',(' ' + $terms[43] + ' ')),
        @(' removal',(' ' + $terms[44]))
    )
    foreach ($replacement in $replacements) {
        $localized = $localized.Replace([string]$replacement[0],[string]$replacement[1])
    }

    return $localized
}

function Add-WnstLogText {
    param(
        [Parameter(Mandatory=$true)][object]$Control,
        [AllowEmptyString()][string]$Text,
        [ValidateSet('Auto','Normal','Success','Error')][string]$Level = 'Auto',
        [ValidateRange(0,4)][int]$LeadingNewLines = 0
    )

    $persistentName = Get-WnstPersistentLogName -Control $Control
    $persistentText = [string]$Text
    if ($LeadingNewLines -gt 1 -and -not [string]::IsNullOrWhiteSpace($persistentName)) {
        try {
            $persistentPath = Get-WnstPersistentLogPath -Name $persistentName
            if (Test-Path -LiteralPath $persistentPath -PathType Leaf) {
                if ((Get-Item -LiteralPath $persistentPath).Length -gt 0) {
                    $persistentText = ([Environment]::NewLine * ($LeadingNewLines - 1)) + $persistentText
                }
            }
        }
        catch { }
    }

    if ($Control -is [Windows.Controls.RichTextBox]) {
        $paragraph = $Control.Document.Blocks.LastBlock -as [Windows.Documents.Paragraph]
        if (-not $paragraph) {
            $paragraph = [Windows.Documents.Paragraph]::new()
            $paragraph.Margin = [Windows.Thickness]::new(0)
            [void]$Control.Document.Blocks.Add($paragraph)
        }

        if (-not [string]::IsNullOrEmpty((Get-WnstLogText -Control $Control))) {
            for ($index = 0; $index -lt $LeadingNewLines; $index++) {
                [void]$paragraph.Inlines.Add([Windows.Documents.LineBreak]::new())
            }
        }

        $lines = [regex]::Split([string]$Text,"`r`n|`n|`r")
        for ($index = 0; $index -lt $lines.Count; $index++) {
            $run = [Windows.Documents.Run]::new([string]$lines[$index])
            switch (Get-WnstLogLineLevel -Text ([string]$lines[$index]) -Level $Level) {
                'Success' { $run.Foreground = $Control.TryFindResource('LogSuccessBrush') }
                'Error'   { $run.Foreground = $Control.TryFindResource('LogErrorBrush') }
            }
            [void]$paragraph.Inlines.Add($run)
            if ($index -lt ($lines.Count - 1)) {
                [void]$paragraph.Inlines.Add([Windows.Documents.LineBreak]::new())
            }
        }
        try { $Control.ScrollToEnd() } catch { }
        if (-not [string]::IsNullOrWhiteSpace($persistentName)) {
            Add-WnstPersistentLogText -Name $persistentName -Text $persistentText
        }
        return
    }

    $prefix = ''
    if (-not [string]::IsNullOrEmpty((Get-WnstLogText -Control $Control))) {
        for ($index = 0; $index -lt $LeadingNewLines; $index++) { $prefix += [Environment]::NewLine }
    }
    if ($null -ne $Control.PSObject.Methods['AppendText']) { $Control.AppendText($prefix + [string]$Text) }
    elseif ($null -ne $Control.PSObject.Properties['Text']) { $Control.Text = (Get-WnstLogText -Control $Control) + $prefix + [string]$Text }
    try { $Control.ScrollToEnd() } catch { }
    if (-not [string]::IsNullOrWhiteSpace($persistentName)) {
        Add-WnstPersistentLogText -Name $persistentName -Text $persistentText
    }
}

function Clear-WnstLogContent {
    param([AllowNull()][object]$Control)

    if (-not $Control) { return }
    if ($Control -is [Windows.Controls.RichTextBox]) {
        $Control.Document.Blocks.Clear()
        $paragraph = [Windows.Documents.Paragraph]::new()
        $paragraph.Margin = [Windows.Thickness]::new(0)
        [void]$Control.Document.Blocks.Add($paragraph)
    }
    elseif ($null -ne $Control.PSObject.Methods['Clear']) { $Control.Clear() }
    elseif ($null -ne $Control.PSObject.Properties['Text']) { $Control.Text = '' }
    try { $Control.ScrollToHome() } catch { }
}

function Invoke-UtilityToOutput {
    param([Parameter(Mandatory=$true)][Windows.Controls.Button]$Button, [Parameter(Mandatory=$true)][object]$OutputBox, [Parameter(Mandatory=$true)][string]$FilePath, [string[]]$Arguments=@())
    $Button.IsEnabled = $false
    try {
        $window.Dispatcher.Invoke([Action]{}, [Windows.Threading.DispatcherPriority]::Render)
        $result = Invoke-CapturedUtility -FilePath $FilePath -Arguments $Arguments

        $parts = New-Object System.Collections.Generic.List[string]
        $parts.Add(('> {0} {1}    [{2}]' -f ([IO.Path]::GetFileName($FilePath)),($Arguments -join ' '),(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')).TrimEnd())
        $parts.Add('')
        if (-not [string]::IsNullOrWhiteSpace($result.Output)) { $parts.Add($result.Output.TrimEnd()) }
        if (-not [string]::IsNullOrWhiteSpace($result.Error)) { $parts.Add($result.Error.TrimEnd()) }
        $parts.Add('')
        $parts.Add((TF 'CommandExitCode' @($result.ExitCode)))

        $level = if ([int]$result.ExitCode -eq 0) { 'Auto' } else { 'Error' }
        Add-WnstLogText -Control $OutputBox -Text ($parts -join "`r`n") -Level $level -LeadingNewLines 2
    }
    catch {
        Add-WnstLogText -Control $OutputBox -Text ([string]$_.Exception.Message) -Level Error -LeadingNewLines 2
        Show-AppError $_.Exception.Message
    }
    finally { $Button.IsEnabled = $true }
}
