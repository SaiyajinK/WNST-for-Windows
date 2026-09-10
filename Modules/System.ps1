function Open-HuSystemTool {
    param([Parameter(Mandatory=$true)][string]$Path)
    try {
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw (TF 'SystemToolUnavailable' @([IO.Path]::GetFileName($Path))) }
        Start-Process -FilePath $Path
    }
    catch { Show-AppError $_.Exception.Message }
}

function Restart-HuExplorerShell {
    $explorerPath = Join-Path $env:SystemRoot 'explorer.exe'
    if (-not (Test-Path -LiteralPath $explorerPath -PathType Leaf)) {
        throw (Get-HuModuleText 'ExplorerExecutableMissing')
    }

    foreach ($process in @(Get-Process -Name explorer -ErrorAction SilentlyContinue)) {
        Stop-Process -Id $process.Id -Force -ErrorAction Stop
    }

    $deadline = [DateTime]::UtcNow.AddSeconds(4)
    do {
        Start-Sleep -Milliseconds 200
        $running = @(Get-Process -Name explorer -ErrorAction SilentlyContinue).Count -gt 0
    } while (-not $running -and [DateTime]::UtcNow -lt $deadline)

    if (-not $running) {
        Start-Process -FilePath $explorerPath | Out-Null
        Start-Sleep -Milliseconds 500
        $running = @(Get-Process -Name explorer -ErrorAction SilentlyContinue).Count -gt 0
    }

    if (-not $running) { throw (Get-HuModuleText 'ExplorerRestartFailed') }
    return [pscustomobject]@{ Restarted = $true }
}

function Clear-SafeTempFolders {
    $targets = @([IO.Path]::GetFullPath([IO.Path]::GetTempPath()), [IO.Path]::GetFullPath((Join-Path $env:SystemRoot 'Temp'))) | Select-Object -Unique
    $deleted = 0; $skipped = 0
    foreach ($target in $targets) {
        $root = [IO.Path]::GetPathRoot($target)
        if (-not $target -or $target.TrimEnd('\') -eq $root.TrimEnd('\') -or $target.TrimEnd('\') -eq ([IO.Path]::GetFullPath($env:SystemRoot)).TrimEnd('\')) { throw (TF 'UnsafeTempFolder' @($target)) }
        if (-not (Test-Path -LiteralPath $target -PathType Container)) { continue }
        foreach ($item in @(Get-ChildItem -LiteralPath $target -Force -ErrorAction SilentlyContinue)) {
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { $skipped++; continue }
            try { Remove-Item -LiteralPath $item.FullName -Recurse -Force -ErrorAction Stop; $deleted++ } catch { $skipped++ }
        }
    }
    return [pscustomobject]@{ Deleted=$deleted; Skipped=$skipped }
}

function Get-HuNativeSystemDirectory {
    $directory = if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
        Join-Path $env:SystemRoot 'Sysnative'
    } else {
        Join-Path $env:SystemRoot 'System32'
    }
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) { $directory = Join-Path $env:SystemRoot 'System32' }
    return $directory
}

function Get-HuSystemExecutablePath {
    param([Parameter(Mandatory=$true)][string]$Name)
    $path = Join-Path (Get-HuNativeSystemDirectory) $Name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw (TF 'SystemToolUnavailable' @($Name)) }
    return $path
}

function Repair-HuWindowsPath {
    if (-not (Test-HuAdministrator)) { throw 'AdministratorRequired' }
    $requiredEntries = @(
        '%SystemRoot%\system32',
        '%SystemRoot%',
        '%SystemRoot%\System32\Wbem',
        '%SystemRoot%\System32\WindowsPowerShell\v1.0\',
        '%SystemRoot%\System32\OpenSSH\'
    )
    $machinePath = [string][Environment]::GetEnvironmentVariable('Path','Machine')
    $entries = @($machinePath -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $normalized = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in $entries) {
        $expanded = [Environment]::ExpandEnvironmentVariables($entry).Trim().TrimEnd('\')
        if ($expanded) { [void]$normalized.Add($expanded) }
    }
    $missing = New-Object 'System.Collections.Generic.List[string]'
    foreach ($entry in $requiredEntries) {
        $expanded = [Environment]::ExpandEnvironmentVariables($entry).Trim().TrimEnd('\')
        if (-not $normalized.Contains($expanded)) { $missing.Add($entry); [void]$normalized.Add($expanded) }
    }
    if ($missing.Count -gt 0) {
        $newMachinePath = @($entries + @($missing)) -join ';'
        [Environment]::SetEnvironmentVariable('Path',$newMachinePath,'Machine')
        $userPath = [string][Environment]::GetEnvironmentVariable('Path','User')
        $env:Path = @($newMachinePath,$userPath | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join ';'
    }
    return [pscustomobject]@{ Added = $missing.Count; Entries = @($missing) }
}

function Start-HuVisibleCommand {
    param(
        [Parameter(Mandatory=$true)][string]$Title,
        [Parameter(Mandatory=$true)][string]$Command
    )

    try {
        if (-not (Test-HuAdministrator)) { throw (T 'AdministratorRequired') }
        $cmdPath = Join-Path $env:SystemRoot 'System32\cmd.exe'
        $commandLine = 'title WNST - {0} & {1}' -f $Title,$Command
        Start-Process -FilePath $cmdPath -ArgumentList @('/k',$commandLine) | Out-Null
    }
    catch {
        Show-AppError $_.Exception.Message
    }
}

function Assert-HuLocalAccountsAvailable {
    foreach ($commandName in @('Get-LocalUser','New-LocalUser','Remove-LocalUser','Get-LocalGroup','Get-LocalGroupMember','Add-LocalGroupMember')) {
        if (-not (Get-Command $commandName -ErrorAction SilentlyContinue)) { throw 'LocalAccountsUnavailable' }
    }
}

function Assert-HuLocalUserName {
    param([Parameter(Mandatory=$true)][string]$Name)

    if ([string]::IsNullOrWhiteSpace($Name)) { throw 'LocalUserNameRequired' }
    if ($Name -ne $Name.Trim() -or $Name.Length -gt 20 -or $Name.EndsWith('.') -or
        $Name -match '[\x00-\x1F"/\\\[\]:;|=,+*?<>@]' -or $Name -match '^\.+$') {
        throw 'LocalUserInvalidName'
    }
}

function Get-HuLocalUserState {
    param([Parameter(Mandatory=$true)][string]$Name)

    Assert-HuLocalAccountsAvailable
    Assert-HuLocalUserName -Name $Name
    $user = Get-LocalUser -Name $Name -ErrorAction SilentlyContinue
    if (-not $user) {
        return [pscustomobject]@{ Exists=$false; Name=$Name; Sid=''; Enabled=$false; IsAdministrator=$false; CanDelete=$false }
    }

    $sid = [string]$user.SID.Value
    $administratorGroup = Get-LocalGroup -SID ([Security.Principal.SecurityIdentifier]::new('S-1-5-32-544')) -ErrorAction Stop
    $administratorSids = @(Get-LocalGroupMember -Group $administratorGroup -ErrorAction SilentlyContinue | ForEach-Object { [string]$_.SID.Value })
    $currentSid = [string][Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $isProtected = $sid -eq $currentSid -or $sid -match '-(500|501|503|504)$'

    [pscustomobject]@{
        Exists=$true
        Name=[string]$user.Name
        Sid=$sid
        Enabled=[bool]$user.Enabled
        IsAdministrator=$administratorSids -contains $sid
        CanDelete=-not $isProtected
    }
}

function New-HuLocalUser {
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [AllowEmptyString()][string]$Password = '',
        [bool]$Administrator = $false
    )

    if (-not (Test-HuAdministrator)) { throw 'AdministratorRequired' }
    Assert-HuLocalAccountsAvailable
    Assert-HuLocalUserName -Name $Name
    if ((Get-HuLocalUserState -Name $Name).Exists) { throw 'LocalUserAlreadyExists' }

    $createdUser = $null
    try {
        if ([string]::IsNullOrEmpty($Password)) {
            $createdUser = New-LocalUser -Name $Name -NoPassword -ErrorAction Stop
        }
        else {
            $securePassword = ConvertTo-SecureString -String $Password -AsPlainText -Force
            $createdUser = New-LocalUser -Name $Name -Password $securePassword -ErrorAction Stop
        }

        $usersGroup = Get-LocalGroup -SID ([Security.Principal.SecurityIdentifier]::new('S-1-5-32-545')) -ErrorAction Stop
        $usersMemberSids = @(Get-LocalGroupMember -Group $usersGroup -ErrorAction SilentlyContinue | ForEach-Object { [string]$_.SID.Value })
        if ($usersMemberSids -notcontains [string]$createdUser.SID.Value) {
            Add-LocalGroupMember -Group $usersGroup -Member $createdUser -ErrorAction Stop
        }

        if ($Administrator) {
            $administratorGroup = Get-LocalGroup -SID ([Security.Principal.SecurityIdentifier]::new('S-1-5-32-544')) -ErrorAction Stop
            Add-LocalGroupMember -Group $administratorGroup -Member $createdUser -ErrorAction Stop
        }
    }
    catch {
        $creationError = $_
        if ($createdUser) { Remove-LocalUser -InputObject $createdUser -ErrorAction SilentlyContinue }
        throw $creationError
    }

    Get-HuLocalUserState -Name $Name
}

function Remove-HuLocalUser {
    param([Parameter(Mandatory=$true)][string]$Name)

    if (-not (Test-HuAdministrator)) { throw 'AdministratorRequired' }
    Assert-HuLocalAccountsAvailable
    Assert-HuLocalUserName -Name $Name
    $state = Get-HuLocalUserState -Name $Name
    if (-not $state.Exists) { throw 'LocalUserNotFound' }
    if (-not $state.CanDelete) { throw 'LocalUserProtected' }

    $user = Get-LocalUser -Name $Name -ErrorAction Stop
    Remove-LocalUser -InputObject $user -ErrorAction Stop
    if ((Get-HuLocalUserState -Name $Name).Exists) { throw 'LocalUserDeleteNotVerified' }
    [pscustomobject]@{ Removed=$true; Name=$Name; Sid=$state.Sid }
}

function Invoke-HuBcdEditProcess {
    param([Parameter(Mandatory=$true)][string[]]$Arguments)

    $bcdEditPath = Get-HuSystemExecutablePath 'bcdedit.exe'
    $encodedArguments = foreach ($argument in $Arguments) {
        if ($argument -match '[\s"]') { '"{0}"' -f $argument.Replace('"','\"') }
        else { $argument }
    }

    $startInfo = New-Object Diagnostics.ProcessStartInfo
    $startInfo.FileName = $bcdEditPath
    $startInfo.Arguments = $encodedArguments -join ' '
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true

    $process = New-Object Diagnostics.Process
    $process.StartInfo = $startInfo
    if (-not $process.Start()) { throw 'BcdEditStartFailed' }
    $standardOutput = $process.StandardOutput.ReadToEnd()
    $standardError = $process.StandardError.ReadToEnd()
    $process.WaitForExit()

    [pscustomobject]@{
        ExitCode=$process.ExitCode
        Output=[string]$standardOutput
        Error=[string]$standardError
        Arguments=@($Arguments)
    }
}

function Get-HuSafeModeBootStatePath {
    return 'HKLM:\SOFTWARE\WNST\ReversibleState\Boot'
}

function Get-HuStoredSafeModeBootGuid {
    try { return [string](Get-ItemPropertyValue -LiteralPath (Get-HuSafeModeBootStatePath) -Name 'SafeModeEntryGuid' -ErrorAction Stop) }
    catch { return '' }
}

function Set-HuStoredSafeModeBootGuid {
    param([Parameter(Mandatory=$true)][string]$Guid)
    $path = Get-HuSafeModeBootStatePath
    if (-not (Test-Path -LiteralPath $path)) { New-Item -Path $path -Force | Out-Null }
    New-ItemProperty -LiteralPath $path -Name 'SafeModeEntryGuid' -PropertyType String -Value $Guid -Force | Out-Null
}

function Remove-HuStoredSafeModeBootGuid {
    $path = Get-HuSafeModeBootStatePath
    if (Test-Path -LiteralPath $path) { Remove-ItemProperty -LiteralPath $path -Name 'SafeModeEntryGuid' -Force -ErrorAction SilentlyContinue }
}

function Get-HuSafeModeBootEntryState {
    param([string[]]$Descriptions = @())

    if (-not (Test-HuAdministrator)) { throw 'AdministratorRequired' }
    $guidPattern = '\{[0-9A-Fa-f]{8}-(?:[0-9A-Fa-f]{4}-){3}[0-9A-Fa-f]{12}\}'
    $storedGuid = Get-HuStoredSafeModeBootGuid
    if ($storedGuid -match ('^' + $guidPattern + '$')) {
        $storedResult = Invoke-HuBcdEditProcess -Arguments @('/enum',$storedGuid,'/v')
        if ($storedResult.ExitCode -eq 0) {
            return [pscustomobject]@{ Exists=$true; Guid=$storedGuid; Detected=$false }
        }
        Remove-HuStoredSafeModeBootGuid
    }

    $knownDescriptions = @($Descriptions | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique)
    if ($knownDescriptions.Count -gt 0) {
        $enumResult = Invoke-HuBcdEditProcess -Arguments @('/enum','osloader','/v')
        if ($enumResult.ExitCode -eq 0) {
            foreach ($block in @([regex]::Split([string]$enumResult.Output,'(?:\r?\n){2,}'))) {
                $descriptionFound = @($knownDescriptions | Where-Object { $block.IndexOf([string]$_,[StringComparison]::OrdinalIgnoreCase) -ge 0 }).Count -gt 0
                if (-not $descriptionFound) { continue }
                $guidMatch = [regex]::Match($block,$guidPattern)
                if ($guidMatch.Success) {
                    $detectedGuid = [string]$guidMatch.Value
                    Set-HuStoredSafeModeBootGuid -Guid $detectedGuid
                    return [pscustomobject]@{ Exists=$true; Guid=$detectedGuid; Detected=$true }
                }
            }
        }
    }

    [pscustomobject]@{ Exists=$false; Guid=''; Detected=$false }
}

function Add-HuSafeModeBootEntry {
    param([Parameter(Mandatory=$true)][string]$Description)

    if (-not (Test-HuAdministrator)) { throw 'AdministratorRequired' }
    if ([string]::IsNullOrWhiteSpace($Description)) { throw 'SafeModeBootDescriptionMissing' }

    $copyResult = Invoke-HuBcdEditProcess -Arguments @('/copy','{current}','/d',$Description)
    if ($copyResult.ExitCode -ne 0) {
        $detail = @($copyResult.Error,$copyResult.Output | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }) -join [Environment]::NewLine
        if ([string]::IsNullOrWhiteSpace($detail)) { $detail = 'bcdedit.exe exit code ' + $copyResult.ExitCode }
        throw $detail.Trim()
    }

    $guidMatch = [regex]::Match([string]$copyResult.Output,'\{[0-9A-Fa-f]{8}-(?:[0-9A-Fa-f]{4}-){3}[0-9A-Fa-f]{12}\}')
    if (-not $guidMatch.Success) { throw 'SafeModeBootGuidMissing' }
    $newGuid = [string]$guidMatch.Value

    $safeBootResult = Invoke-HuBcdEditProcess -Arguments @('/set',$newGuid,'safeboot','minimal')
    if ($safeBootResult.ExitCode -ne 0) {
        $detail = @($safeBootResult.Error,$safeBootResult.Output | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }) -join [Environment]::NewLine
        if ([string]::IsNullOrWhiteSpace($detail)) { $detail = 'bcdedit.exe exit code ' + $safeBootResult.ExitCode }
        throw $detail.Trim()
    }

    Set-HuStoredSafeModeBootGuid -Guid $newGuid
    [pscustomobject]@{ Created=$true; Guid=$newGuid; Description=$Description }
}

function Remove-HuSafeModeBootEntry {
    param([string]$Guid = '')

    if (-not (Test-HuAdministrator)) { throw 'AdministratorRequired' }
    if ([string]::IsNullOrWhiteSpace($Guid)) { $Guid = Get-HuStoredSafeModeBootGuid }
    if ($Guid -notmatch '^\{[0-9A-Fa-f]{8}-(?:[0-9A-Fa-f]{4}-){3}[0-9A-Fa-f]{12}\}$') { throw 'SafeModeBootEntryNotFound' }

    $deleteResult = Invoke-HuBcdEditProcess -Arguments @('/delete',$Guid)
    if ($deleteResult.ExitCode -ne 0) {
        $detail = @($deleteResult.Error,$deleteResult.Output | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }) -join [Environment]::NewLine
        if ([string]::IsNullOrWhiteSpace($detail)) { $detail = 'bcdedit.exe exit code ' + $deleteResult.ExitCode }
        throw $detail.Trim()
    }

    Remove-HuStoredSafeModeBootGuid
    [pscustomobject]@{ Removed=$true; Guid=$Guid }
}
