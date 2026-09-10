# WNST - Actions Windows avancées intégrées
# Backend uniquement. Les confirmations et messages sont gérés par l'interface WNST.


function Test-WnstAdvancedAdministrator {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = [Security.Principal.WindowsPrincipal]::new($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch { return $false }
}


function Invoke-WnstProtectedAiPackageRemoval {
    param(
        [Parameter(Mandatory=$true)][object[]]$Packages,
        [Parameter(Mandatory=$true)][AllowEmptyCollection()][Collections.Generic.List[string]]$Actions,
        [Parameter(Mandatory=$true)][AllowEmptyCollection()][Collections.Generic.List[string]]$Errors
    )

    if ($Packages.Count -eq 0) { return 0 }

    $workRoot = Join-Path $env:WINDIR 'Temp\WNST'
    $token = [Guid]::NewGuid().ToString('N')
    $taskName = "WNST-CoreAI-SYSTEM-$token"
    $inputPath = Join-Path $workRoot ("coreai-input-$token.json")
    $workerPath = Join-Path $workRoot ("coreai-system-$token.ps1")
    $preflightPath = Join-Path $workRoot ("coreai-preflight-$token.json")
    $progressPath = Join-Path $workRoot ("coreai-progress-$token.log")
    $resultPath = Join-Path $workRoot ("coreai-result-$token.json")
    $registered = $false
    $removed = 0

    $workerScript = @'
param(
    [Parameter(Mandatory=$true)][string]$InputPath,
    [Parameter(Mandatory=$true)][string]$PreflightPath,
    [Parameter(Mandatory=$true)][string]$ProgressPath,
    [Parameter(Mandatory=$true)][string]$ResultPath
)

$ErrorActionPreference = 'Stop'
$result = [ordered]@{ IsSystem = $false; Identity = ''; Error = ''; Packages = @() }
$createdMarkers = [Collections.Generic.List[string]]::new()

try {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $result.Identity = [string]$identity.Name
    $result.IsSystem = [bool]$identity.IsSystem
    if (-not $result.IsSystem) {
        throw ('SYSTEM token validation failed: {0}' -f $result.Identity)
    }

    [ordered]@{ IsSystem = $true; Identity = $result.Identity } |
        ConvertTo-Json -Compress |
        Set-Content -LiteralPath $PreflightPath -Encoding UTF8 -Force

    $targets = @(Get-Content -LiteralPath $InputPath -Raw -ErrorAction Stop | ConvertFrom-Json)
    $storePath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore'
    $knownSids = @('S-1-5-18')
    if (Test-Path -LiteralPath $storePath) {
        $knownSids += @(Get-ChildItem -LiteralPath $storePath -ErrorAction Ignore |
            Where-Object { $_.PSChildName -like 'S-1-5-21*' } |
            Select-Object -ExpandProperty PSChildName)
    }

    foreach ($target in $targets) {
        $fullName = [string]$target.PackageFullName
        $familyName = [string]$target.PackageFamilyName
        $removedThisPackage = $false
        $lastDetail = ''

        for ($attempt = 1; $attempt -le 10 -and -not $removedThisPackage; $attempt++) {
            $current = Get-AppxPackage -AllUsers -ErrorAction Ignore |
                Where-Object { [string]$_.PackageFullName -eq $fullName } |
                Select-Object -First 1
            if (-not $current) {
                $removedThisPackage = $true
                break
            }
            Add-Content -LiteralPath $ProgressPath -Value ('[SYSTEM] protected AppX removal -> attempt {0}/10' -f $attempt) -Encoding UTF8

            $attemptDetails = [Collections.Generic.List[string]]::new()

            if (-not [string]::IsNullOrWhiteSpace($familyName)) {
                try {
                    Set-NonRemovableAppsPolicy -Online -PackageFamilyName $familyName -NonRemovable 0 -ErrorAction Stop | Out-Null
                }
                catch {
                    $attemptDetails.Add(('Set-NonRemovableAppsPolicy: {0}' -f [string]$_.Exception.Message))
                }

                $deprovisionedPath = Join-Path $storePath ("Deprovisioned\$familyName")
                if (-not (Test-Path -LiteralPath $deprovisionedPath)) {
                    try {
                        New-Item -Path $deprovisionedPath -Force -ErrorAction Stop | Out-Null
                        $createdMarkers.Add($deprovisionedPath)
                    }
                    catch {
                        $attemptDetails.Add(('Deprovisioned marker: {0}' -f [string]$_.Exception.Message))
                    }
                }
            }

            $inboxPath = Join-Path $storePath ("InboxApplications\$fullName")
            if (Test-Path -LiteralPath $inboxPath) {
                try {
                    Remove-Item -LiteralPath $inboxPath -Recurse -Force -ErrorAction Stop
                }
                catch {
                    $attemptDetails.Add(('InboxApplications: {0}' -f [string]$_.Exception.Message))
                }
            }

            $targetSids = [Collections.Generic.List[string]]::new()
            foreach ($sid in $knownSids) {
                if (-not [string]::IsNullOrWhiteSpace($sid) -and -not $targetSids.Contains($sid)) {
                    $targetSids.Add($sid)
                }
            }
            foreach ($userInfo in @($current.PackageUserInformation)) {
                $sid = ''
                try { $sid = [string]$userInfo.UserSecurityID.SID } catch {}
                if ([string]::IsNullOrWhiteSpace($sid)) {
                    try { $sid = [string]$userInfo.UserSecurityID } catch {}
                }
                if (-not [string]::IsNullOrWhiteSpace($sid) -and -not $targetSids.Contains($sid)) {
                    $targetSids.Add($sid)
                }
            }

            foreach ($sid in $targetSids) {
                $endOfLifePath = Join-Path $storePath ("EndOfLife\$sid\$fullName")
                if (-not (Test-Path -LiteralPath $endOfLifePath)) {
                    try {
                        New-Item -Path $endOfLifePath -Force -ErrorAction Stop | Out-Null
                        $createdMarkers.Add($endOfLifePath)
                    }
                    catch {
                        $attemptDetails.Add(('EndOfLife {0}: {1}' -f $sid,[string]$_.Exception.Message))
                    }
                }

                try {
                    Remove-AppxPackage -Package $fullName -User $sid -ErrorAction Stop
                }
                catch {
                    $attemptDetails.Add(('Remove-AppxPackage user {0}: {1}' -f $sid,[string]$_.Exception.Message))
                }
            }

            try {
                Remove-AppxPackage -Package $fullName -AllUsers -ErrorAction Stop
            }
            catch {
                $attemptDetails.Add(('Remove-AppxPackage AllUsers: {0}' -f [string]$_.Exception.Message))
            }

            Start-Sleep -Milliseconds 900
            $stillPresent = @(Get-AppxPackage -AllUsers -ErrorAction Ignore |
                Where-Object { [string]$_.PackageFullName -eq $fullName }).Count -gt 0

            if (-not $stillPresent) {
                $removedThisPackage = $true
            }
            elseif ($attemptDetails.Count -gt 0) {
                $lastDetail = [string]$attemptDetails[$attemptDetails.Count - 1]
            }
        }

        if (-not $removedThisPackage -and [string]::IsNullOrWhiteSpace($lastDetail)) {
            $lastDetail = 'package still installed after SYSTEM AppX removal'
        }

        $result.Packages += [pscustomobject]@{
            PackageFullName = $fullName
            Removed = $removedThisPackage
            Detail = $lastDetail
        }
    }
}
catch {
    $result.Error = [string]$_.Exception.Message
}
finally {
    foreach ($marker in $createdMarkers) {
        Remove-Item -LiteralPath $marker -Recurse -Force -ErrorAction Ignore
    }
    $result | ConvertTo-Json -Depth 5 |
        Set-Content -LiteralPath $ResultPath -Encoding UTF8 -Force
}
'@

    try {
        New-Item -Path $workRoot -ItemType Directory -Force -ErrorAction Stop | Out-Null

        @($Packages | ForEach-Object {
            [pscustomobject]@{
                PackageFullName = [string]$_.PackageFullName
                PackageFamilyName = [string]$_.PackageFamilyName
            }
        }) | ConvertTo-Json -Depth 4 |
            Set-Content -LiteralPath $inputPath -Encoding UTF8 -Force -ErrorAction Stop

        Set-Content -LiteralPath $workerPath -Value $workerScript -Encoding UTF8 -Force -ErrorAction Stop

        $powershellExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $arguments = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" -InputPath "{1}" -PreflightPath "{2}" -ProgressPath "{3}" -ResultPath "{4}"' -f $workerPath,$inputPath,$preflightPath,$progressPath,$resultPath
        $action = New-ScheduledTaskAction -Execute $powershellExe -Argument $arguments -WorkingDirectory $workRoot
        $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
        $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 3)

        Register-ScheduledTask -TaskName $taskName -Action $action -Principal $principal -Settings $settings -Force -ErrorAction Stop | Out-Null
        $registered = $true
        Add-WnstAdvancedAction $Actions '[SYSTEM] protected AppX worker -> START'
        Start-ScheduledTask -TaskName $taskName -ErrorAction Stop

        $preflightLogged = $false
        $progressOffset = 0
        $deadline = [DateTime]::UtcNow.AddMinutes(3)
        while (-not (Test-Path -LiteralPath $resultPath) -and [DateTime]::UtcNow -lt $deadline) {
            if (-not $preflightLogged -and (Test-Path -LiteralPath $preflightPath)) {
                $preflight = Get-Content -LiteralPath $preflightPath -Raw -ErrorAction Stop | ConvertFrom-Json
                if (-not [bool]$preflight.IsSystem) {
                    throw ('SYSTEM token validation failed: {0}' -f [string]$preflight.Identity)
                }
                Add-WnstAdvancedAction $Actions ('[SYSTEM] token -> VERIFIED ({0})' -f [string]$preflight.Identity)
                $preflightLogged = $true
            }
            if (Test-Path -LiteralPath $progressPath) {
                $progressLines = @(Get-Content -LiteralPath $progressPath -ErrorAction Ignore)
                while ($progressOffset -lt $progressLines.Count) {
                    Add-WnstAdvancedAction $Actions ([string]$progressLines[$progressOffset])
                    $progressOffset++
                }
            }
            Start-Sleep -Milliseconds 200
        }

        if (Test-Path -LiteralPath $progressPath) {
            $progressLines = @(Get-Content -LiteralPath $progressPath -ErrorAction Ignore)
            while ($progressOffset -lt $progressLines.Count) {
                Add-WnstAdvancedAction $Actions ([string]$progressLines[$progressOffset])
                $progressOffset++
            }
        }

        if (-not (Test-Path -LiteralPath $resultPath)) {
            $taskDetail = ''
            try {
                $taskInfo = Get-ScheduledTaskInfo -TaskName $taskName -ErrorAction Stop
                $taskDetail = '0x{0:X8}' -f [uint32]$taskInfo.LastTaskResult
            }
            catch {}
            throw ('SYSTEM worker did not complete ({0})' -f $taskDetail)
        }

        if (-not $preflightLogged -and (Test-Path -LiteralPath $preflightPath)) {
            $preflight = Get-Content -LiteralPath $preflightPath -Raw -ErrorAction Stop | ConvertFrom-Json
            if (-not [bool]$preflight.IsSystem) {
                throw ('SYSTEM token validation failed: {0}' -f [string]$preflight.Identity)
            }
            Add-WnstAdvancedAction $Actions ('[SYSTEM] token -> VERIFIED ({0})' -f [string]$preflight.Identity)
        }

        $result = Get-Content -LiteralPath $resultPath -Raw -ErrorAction Stop | ConvertFrom-Json
        if (-not [bool]$result.IsSystem) {
            throw ('SYSTEM token validation failed: {0}' -f [string]$result.Identity)
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$result.Error)) {
            throw [string]$result.Error
        }

        foreach ($packageResult in @($result.Packages)) {
            $fullName = [string]$packageResult.PackageFullName
            if ([bool]$packageResult.Removed) {
                $removed++
                Add-WnstAdvancedAction $Actions ('[OK] {0} -> REMOVED (SYSTEM)' -f $fullName)
            }
            else {
                $detail = [string]$packageResult.Detail
                $Errors.Add(('{0}: {1}' -f $fullName,$detail))
                Add-WnstAdvancedAction $Actions ('[FAIL] {0} -> PRESENT ({1})' -f $fullName,$detail)
            }
        }
    }
    catch {
        $Errors.Add([string]$_.Exception.Message)
        Add-WnstAdvancedAction $Actions ('[FAIL] SYSTEM AppX worker -> {0}' -f [string]$_.Exception.Message)
    }
    finally {
        if ($registered) {
            try { Stop-ScheduledTask -TaskName $taskName -ErrorAction Ignore } catch {}
            try { Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction Ignore } catch {}
        }
        Remove-Item -LiteralPath $inputPath,$workerPath,$preflightPath,$progressPath,$resultPath -Force -ErrorAction Ignore
    }

    return $removed
}


function Add-WnstAdvancedAction {
    param(
        [Parameter(Mandatory=$true)][AllowEmptyCollection()][Collections.Generic.List[string]]$Log,
        [Parameter(Mandatory=$true)][string]$Text
    )
    # The UI timestamps every displayed line. Keeping the backend payload free
    # of presentation metadata avoids duplicated timestamps in the live log.
    $line = [string]$Text
    $Log.Add($line)
    if ($null -ne $script:WnstAdvancedProgressQueue) {
        try { $script:WnstAdvancedProgressQueue.Enqueue($line) } catch {}
    }
}

function Set-WnstRegistryDwordSafe {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][int]$Value,
        [Collections.Generic.List[string]]$Errors
    )
    try {
        Set-WnstRegistryDword -Path $Path -Name $Name -Value $Value
        return $true
    }
    catch {
        if ($null -ne $Errors) { $Errors.Add([string]$_.Exception.Message) }
        return $false
    }
}

function Set-WnstRegistryDword {
    param([Parameter(Mandatory=$true)][string]$Path,[Parameter(Mandatory=$true)][string]$Name,[Parameter(Mandatory=$true)][int]$Value)
    if (-not (Test-Path -LiteralPath $Path)) { New-Item -Path $Path -Force -ErrorAction Stop | Out-Null }
    New-ItemProperty -Path $Path -Name $Name -PropertyType DWord -Value $Value -Force -ErrorAction Stop | Out-Null
}

function Remove-WnstPathSafe {
    param([AllowEmptyString()][string]$Path,[Collections.Generic.List[string]]$Errors)
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) { return $false }
    try { Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop; return $true }
    catch { if ($null -ne $Errors) { $Errors.Add(('{0}: {1}' -f $Path,$_.Exception.Message)) }; return $false }
}

function Get-WnstOneDriveInstallRoots {
    $roots = @(
        (Join-Path $env:LOCALAPPDATA 'Microsoft\OneDrive'),
        (Join-Path $env:ProgramData 'Microsoft OneDrive'),
        (Join-Path $env:SystemDrive 'OneDriveTemp'),
        (Join-Path $env:ProgramFiles 'Microsoft OneDrive'),
        $(if (${env:ProgramFiles(x86)}) { Join-Path ${env:ProgramFiles(x86)} 'Microsoft OneDrive' })
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }

    return @($roots | ForEach-Object {
        try { [IO.Path]::GetFullPath([string]$_).TrimEnd('\') } catch { [string]$_ }
    } | Select-Object -Unique)
}

function Test-WnstPathInsideRoot {
    param([AllowEmptyString()][string]$Path,[AllowEmptyString()][string]$Root)
    if ([string]::IsNullOrWhiteSpace($Path) -or [string]::IsNullOrWhiteSpace($Root)) { return $false }
    try {
        $fullPath = [IO.Path]::GetFullPath($Path).TrimEnd('\')
        $fullRoot = [IO.Path]::GetFullPath($Root).TrimEnd('\')
        return $fullPath.Equals($fullRoot,[StringComparison]::OrdinalIgnoreCase) -or
            $fullPath.StartsWith(($fullRoot + '\'),[StringComparison]::OrdinalIgnoreCase)
    }
    catch { return $false }
}

function Stop-WnstOneDriveOwnedProcesses {
    param([Collections.Generic.List[string]]$Actions)

    $roots = @(Get-WnstOneDriveInstallRoots)
    $knownNames = @('OneDrive.exe','OneDrive.App.exe','OneDriveSetup.exe','OneDriveStandaloneUpdater.exe','OneDriveFileCoAuth.exe','FileCoAuth.exe','Microsoft.SharePoint.exe','Microsoft.OneDrive.Update.Service.exe','Microsoft.OneDrive.Sync.Service.exe')
    $matches = @()
    try {
        $matches = @(Get-CimInstance Win32_Process -ErrorAction Stop | Where-Object {
            $path = [string]$_.ExecutablePath
            $name = [string]$_.Name
            ($name -in $knownNames) -or @($roots | Where-Object { Test-WnstPathInsideRoot -Path $path -Root $_ }).Count -gt 0
        } | Sort-Object ProcessId -Unique)
    }
    catch {
        $matches = @(
            @('OneDrive','OneDrive.App','OneDriveSetup','OneDriveStandaloneUpdater','OneDriveFileCoAuth','FileCoAuth','Microsoft.SharePoint','Microsoft.OneDrive.Update.Service','Microsoft.OneDrive.Sync.Service') |
                ForEach-Object { Get-Process -Name $_ -ErrorAction Ignore } |
                Sort-Object Id -Unique |
                ForEach-Object { [pscustomobject]@{ ProcessId=$_.Id; Name=$_.ProcessName } }
        )
    }

    foreach ($process in $matches) {
        try { Stop-Process -Id ([int]$process.ProcessId) -Force -ErrorAction Stop } catch {}
    }
    if ($matches.Count -gt 0 -and $null -ne $Actions) {
        Add-WnstAdvancedAction $Actions ('[PROC] OneDrive -> STOP (count={0})' -f $matches.Count)
    }
    return $matches.Count
}

function Stop-WnstOneDriveOwnedServices {
    param([Collections.Generic.List[string]]$Errors,[Collections.Generic.List[string]]$Actions)

    $roots = @(Get-WnstOneDriveInstallRoots)
    $services = @()
    try {
        $services = @(Get-CimInstance Win32_Service -ErrorAction Stop | Where-Object {
            $binary = ([string]$_.PathName).Trim().Trim('"')
            @($roots | Where-Object { Test-WnstPathInsideRoot -Path $binary -Root $_ }).Count -gt 0 -or
                [string]$_.PathName -match '(?i)\\Microsoft OneDrive\\'
        })
    }
    catch {
        if ($null -ne $Errors) { $Errors.Add([string]$_.Exception.Message) }
        return 0
    }

    $removed = 0
    $scExe = Join-Path $env:SystemRoot 'System32\sc.exe'
    foreach ($service in $services) {
        $serviceName = [string]$service.Name
        try {
            try { Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue } catch {}
            if ([int]$service.ProcessId -gt 0) {
                try { Stop-Process -Id ([int]$service.ProcessId) -Force -ErrorAction SilentlyContinue } catch {}
            }
            & $scExe delete $serviceName 2>$null | Out-Null
            if ($LASTEXITCODE -notin @(0,1060)) { throw ('sc.exe delete {0}: exit code {1}' -f $serviceName,$LASTEXITCODE) }
            $removed++
            if ($null -ne $Actions) { Add-WnstAdvancedAction $Actions ('[SERVICE] {0} -> DELETE' -f $serviceName) }
        }
        catch {
            if ($null -ne $Errors) { $Errors.Add([string]$_.Exception.Message) }
            if ($null -ne $Actions) { Add-WnstAdvancedAction $Actions ('[SERVICE] {0} -> FAILED' -f $serviceName) }
        }
    }
    return $removed
}

function Grant-WnstOneDriveInstallRootRemovalAccess {
    param([Parameter(Mandatory=$true)][string]$Path)

    $allowedRoots = @(Get-WnstOneDriveInstallRoots | Where-Object {
        $_ -like (([IO.Path]::GetFullPath($env:ProgramFiles).TrimEnd('\')) + '\*') -or
        (${env:ProgramFiles(x86)} -and $_ -like (([IO.Path]::GetFullPath(${env:ProgramFiles(x86)}).TrimEnd('\')) + '\*'))
    })
    if (@($allowedRoots | Where-Object { ([IO.Path]::GetFullPath($Path).TrimEnd('\')).Equals($_,[StringComparison]::OrdinalIgnoreCase) }).Count -eq 0) {
        return $false
    }

    $takeOwn = Join-Path $env:SystemRoot 'System32\takeown.exe'
    $icacls = Join-Path $env:SystemRoot 'System32\icacls.exe'
    if (Test-Path -LiteralPath $takeOwn -PathType Leaf) {
        & $takeOwn /F $Path /A /R 2>$null | Out-Null
    }
    if (Test-Path -LiteralPath $icacls -PathType Leaf) {
        # SID form is language-neutral and always identifies Builtin Administrators.
        & $icacls $Path /grant '*S-1-5-32-544:(OI)(CI)F' /T /C /Q 2>$null | Out-Null
    }
    try {
        Get-ChildItem -LiteralPath $Path -Force -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
            try { $_.Attributes = $_.Attributes -band (-bnot ([IO.FileAttributes]::ReadOnly -bor [IO.FileAttributes]::System)) } catch {}
        }
        $rootItem = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
        if ($rootItem) { $rootItem.Attributes = $rootItem.Attributes -band (-bnot ([IO.FileAttributes]::ReadOnly -bor [IO.FileAttributes]::System)) }
    }
    catch {}
    return $true
}

function Register-WnstPathDeleteAtRestart {
    param([Parameter(Mandatory=$true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $true }

    if (-not ('WNST.PendingFileDelete' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
namespace WNST {
    public static class PendingFileDelete {
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern bool MoveFileEx(string existingName, string newName, int flags);
        public static void Register(string path) {
            if (!MoveFileEx(path, null, 0x4)) throw new Win32Exception(Marshal.GetLastWin32Error());
        }
    }
}
'@ -ErrorAction Stop
    }

    # Session Manager processes entries in order. Files therefore come first,
    # followed by directories from deepest to shallowest, then the root itself.
    $items = [Collections.Generic.List[string]]::new()
    foreach ($file in @(Get-ChildItem -LiteralPath $Path -Force -Recurse -File -ErrorAction Stop | Sort-Object { $_.FullName.Length } -Descending)) {
        $items.Add([string]$file.FullName)
    }
    foreach ($directory in @(Get-ChildItem -LiteralPath $Path -Force -Recurse -Directory -ErrorAction Stop | Sort-Object { $_.FullName.Length } -Descending)) {
        $items.Add([string]$directory.FullName)
    }
    $items.Add([IO.Path]::GetFullPath($Path).TrimEnd('\'))
    foreach ($item in $items) { [WNST.PendingFileDelete]::Register($item) }
    return $true
}

function Get-WnstFileLockProcessIds {
    param([Parameter(Mandatory=$true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return @() }

    if (-not ('WNST.RestartManagerLockInspector' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;

namespace WNST {
    public static class RestartManagerLockInspector {
        private const int ErrorSuccess = 0;
        private const int ErrorMoreData = 234;
        private const int MaxAppName = 255;
        private const int MaxServiceName = 63;

        [StructLayout(LayoutKind.Sequential)]
        private struct RM_UNIQUE_PROCESS {
            public int ProcessId;
            public System.Runtime.InteropServices.ComTypes.FILETIME ProcessStartTime;
        }

        private enum RM_APP_TYPE {
            UnknownApp = 0,
            MainWindow = 1,
            OtherWindow = 2,
            Service = 3,
            Explorer = 4,
            Console = 5,
            Critical = 1000
        }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct RM_PROCESS_INFO {
            public RM_UNIQUE_PROCESS Process;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = MaxAppName + 1)]
            public string AppName;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = MaxServiceName + 1)]
            public string ServiceShortName;
            public RM_APP_TYPE ApplicationType;
            public uint AppStatus;
            public uint TSSessionId;
            [MarshalAs(UnmanagedType.Bool)]
            public bool Restartable;
        }

        [DllImport("rstrtmgr.dll", CharSet = CharSet.Unicode)]
        private static extern int RmStartSession(out uint sessionHandle, int sessionFlags, string sessionKey);

        [DllImport("rstrtmgr.dll")]
        private static extern int RmEndSession(uint sessionHandle);

        [DllImport("rstrtmgr.dll", CharSet = CharSet.Unicode)]
        private static extern int RmRegisterResources(
            uint sessionHandle,
            uint fileCount,
            string[] fileNames,
            uint applicationCount,
            [In] RM_UNIQUE_PROCESS[] applications,
            uint serviceCount,
            string[] serviceNames);

        [DllImport("rstrtmgr.dll", CharSet = CharSet.Unicode)]
        private static extern int RmGetList(
            uint sessionHandle,
            out uint processInfoNeeded,
            ref uint processInfoCount,
            [In, Out] RM_PROCESS_INFO[] affectedApps,
            ref uint rebootReasons);

        public static int[] GetLockingProcessIds(string[] fileNames) {
            if (fileNames == null || fileNames.Length == 0) return new int[0];

            uint sessionHandle;
            int result = RmStartSession(out sessionHandle, 0, Guid.NewGuid().ToString("N"));
            if (result != ErrorSuccess) throw new Win32Exception(result);

            try {
                result = RmRegisterResources(sessionHandle, (uint)fileNames.Length, fileNames, 0, null, 0, null);
                if (result != ErrorSuccess) throw new Win32Exception(result);

                uint needed;
                uint count = 0;
                uint rebootReasons = 0;
                result = RmGetList(sessionHandle, out needed, ref count, null, ref rebootReasons);
                if (result == ErrorSuccess) return new int[0];
                if (result != ErrorMoreData) throw new Win32Exception(result);

                RM_PROCESS_INFO[] processes = new RM_PROCESS_INFO[needed];
                count = needed;
                result = RmGetList(sessionHandle, out needed, ref count, processes, ref rebootReasons);
                if (result != ErrorSuccess) throw new Win32Exception(result);

                HashSet<int> processIds = new HashSet<int>();
                for (int index = 0; index < count; index++) {
                    if (processes[index].Process.ProcessId > 0) processIds.Add(processes[index].Process.ProcessId);
                }
                int[] output = new int[processIds.Count];
                processIds.CopyTo(output);
                return output;
            }
            finally {
                RmEndSession(sessionHandle);
            }
        }
    }
}
'@ -ErrorAction Stop
    }

    $files = @(
        Get-ChildItem -LiteralPath $Path -Force -Recurse -File -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty FullName -Unique
    )
    if ($files.Count -eq 0) { return @() }
    return @([WNST.RestartManagerLockInspector]::GetLockingProcessIds([string[]]$files))
}

function Stop-WnstOneDriveFileLockOwners {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Collections.Generic.List[string]]$Actions
    )

    $knownNames = @('OneDrive','OneDrive.App','OneDriveSetup','OneDriveStandaloneUpdater','OneDriveFileCoAuth','FileCoAuth','Microsoft.SharePoint','Microsoft.OneDrive.Update.Service','Microsoft.OneDrive.Sync.Service')
    $stopped = 0
    $lockingProcessIds = @()
    try { $lockingProcessIds = @(Get-WnstFileLockProcessIds -Path $Path) } catch { $lockingProcessIds = @() }
    foreach ($processId in $lockingProcessIds) {
        if ([int]$processId -le 4 -or [int]$processId -eq $PID) { continue }

        $process = Get-CimInstance Win32_Process -Filter ('ProcessId = {0}' -f [int]$processId) -ErrorAction SilentlyContinue
        if (-not $process) { continue }

        $name = [IO.Path]::GetFileNameWithoutExtension([string]$process.Name)
        $executablePath = [string]$process.ExecutablePath
        $ownedByOneDrive = ($name -in $knownNames) -or (Test-WnstPathInsideRoot -Path $executablePath -Root $Path)
        if (-not $ownedByOneDrive) {
            if ($null -ne $Actions) {
                Add-WnstAdvancedAction $Actions ('[CHECK] {0} -> PRESENT (process={1}, PID={2})' -f $Path,$name,[int]$processId)
            }
            continue
        }

        try {
            Stop-Process -Id ([int]$processId) -Force -ErrorAction Stop
            $stopped++
            if ($null -ne $Actions) {
                Add-WnstAdvancedAction $Actions ('[PROC] {0} (PID={1}) -> STOP' -f $name,[int]$processId)
            }
        }
        catch {}
    }
    return $stopped
}

function Remove-WnstOneDriveInstallRootImmediately {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Collections.Generic.List[string]]$Actions
    )

    $lastError = $null
    for ($attempt = 1; $attempt -le 5; $attempt++) {
        # Explorer can be relaunched automatically by Winlogon while the long
        # OneDrive cleanup is still running and reload a OneDrive shell DLL.
        # Stop the current instance again immediately before every delete try.
        foreach ($explorerProcess in @(Get-Process explorer -ErrorAction SilentlyContinue)) {
            try { Stop-Process -Id $explorerProcess.Id -Force -ErrorAction Stop } catch {}
        }

        [void](Stop-WnstOneDriveOwnedServices -Errors $null -Actions $null)
        [void](Stop-WnstOneDriveOwnedProcesses -Actions $null)
        [void](Stop-WnstOneDriveFileLockOwners -Path $Path -Actions $Actions)
        [void](Grant-WnstOneDriveInstallRootRemovalAccess -Path $Path)

        try {
            Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
        }
        catch {
            $lastError = [string]$_.Exception.Message
            try { [IO.Directory]::Delete([IO.Path]::GetFullPath($Path),$true) }
            catch { $lastError = [string]$_.Exception.Message }
        }

        if (-not (Test-Path -LiteralPath $Path)) {
            return [pscustomobject]@{ Removed=$true; Error=$null; Attempts=$attempt }
        }

        [gc]::Collect()
        [gc]::WaitForPendingFinalizers()
        Start-Sleep -Milliseconds (250 * $attempt)
    }

    return [pscustomobject]@{ Removed=$false; Error=$lastError; Attempts=5 }
}

function Disable-WnstServiceSafe {
    param([Parameter(Mandatory=$true)][string]$Name,[Collections.Generic.List[string]]$Errors)
    $service = Get-Service -Name $Name -ErrorAction Ignore
    if (-not $service) { return $false }
    try { Stop-Service -Name $Name -Force -ErrorAction Ignore; Set-Service -Name $Name -StartupType Disabled -ErrorAction Stop; return $true }
    catch { if ($null -ne $Errors) { $Errors.Add(('{0}: {1}' -f $Name,$_.Exception.Message)) }; return $false }
}

function Invoke-WnstOneDriveRemoval {
    [CmdletBinding()] param([object]$ProgressQueue)
    if (-not (Test-WnstAdvancedAdministrator)) { throw 'AdministratorRequired' }

    $script:WnstAdvancedProgressQueue = $ProgressQueue

    $errors = [Collections.Generic.List[string]]::new()
    $installerErrors = [Collections.Generic.List[string]]::new()
    $actions = [Collections.Generic.List[string]]::new()
    $removedFolders = 0
    $uninstallAttempts = 0
    $uninstallSuccess = 0
    $personalPreserved = $false
    $appxInstalledRemoved = 0
    $appxProvisionedRemoved = 0
    $pendingDeleteFolders = [Collections.Generic.List[string]]::new()

    $regExe = Join-Path $env:SystemRoot 'System32\reg.exe'
    if (-not (Test-Path -LiteralPath $regExe -PathType Leaf)) {
        $regExe = Join-Path $env:WINDIR 'System32\reg.exe'
    }

    $oneDriveProcessNames = @('OneDrive','OneDrive.App','OneDriveSetup','OneDriveStandaloneUpdater','OneDriveFileCoAuth','FileCoAuth','Microsoft.SharePoint','Microsoft.OneDrive.Update.Service','Microsoft.OneDrive.Sync.Service')
    if ((Stop-WnstOneDriveOwnedProcesses -Actions $actions) -eq 0) {
        Add-WnstAdvancedAction $actions '[PROC] OneDrive.exe -> ABSENT'
    }

    $explorerWasRunning = @(Get-Process explorer -ErrorAction Ignore).Count -gt 0
    $explorerExe = Join-Path $env:WINDIR 'explorer.exe'

    try {
        if ($explorerWasRunning) {
            Add-WnstAdvancedAction $actions '[PROC] explorer.exe -> STOP'
            $oldExplorerIds = @(Get-Process explorer -ErrorAction Ignore | Select-Object -ExpandProperty Id)
            Get-Process explorer -ErrorAction Ignore | Stop-Process -Force -ErrorAction Ignore

            # Attendre que l'ancien shell soit réellement terminé avant de toucher
            # aux fichiers/CLSID OneDrive. Cela évite aussi de relancer Explorer
            # alors que l'ancienne instance est encore en train de se fermer.
            $stopDeadline = [DateTime]::UtcNow.AddSeconds(5)
            while (@(Get-Process explorer -ErrorAction Ignore | Where-Object { $_.Id -in $oldExplorerIds }).Count -gt 0 -and [DateTime]::UtcNow -lt $stopDeadline) {
                Start-Sleep -Milliseconds 150
            }

            if (@(Get-Process explorer -ErrorAction Ignore | Where-Object { $_.Id -in $oldExplorerIds }).Count -gt 0) {
                Add-WnstAdvancedAction $actions '[PROC] explorer.exe -> STOP'
            }
            else {
                Add-WnstAdvancedAction $actions '[PROC] explorer.exe -> STOPPED'
            }
        }
        else {
            Add-WnstAdvancedAction $actions '[PROC] explorer.exe -> ABSENT'
        }

        Add-WnstAdvancedAction $actions '[SCAN] OneDriveSetup.exe'

        $uninstallers = [Collections.Generic.List[string]]::new()
        foreach ($candidate in @(
            (Join-Path $env:SystemRoot 'System32\OneDriveSetup.exe'),
            (Join-Path $env:SystemRoot 'SysWOW64\OneDriveSetup.exe'),
            (Join-Path $env:ProgramFiles 'Microsoft OneDrive\OneDriveSetup.exe'),
            $(if (${env:ProgramFiles(x86)}) { Join-Path ${env:ProgramFiles(x86)} 'Microsoft OneDrive\OneDriveSetup.exe' }),
            (Join-Path $env:LOCALAPPDATA 'Microsoft\OneDrive\OneDriveSetup.exe')
        )) {
            if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf) -and -not $uninstallers.Contains($candidate)) {
                $uninstallers.Add($candidate)
            }
        }

        foreach ($searchRoot in @(
            (Join-Path $env:LOCALAPPDATA 'Microsoft\OneDrive'),
            (Join-Path $env:ProgramFiles 'Microsoft OneDrive'),
            $(if (${env:ProgramFiles(x86)}) { Join-Path ${env:ProgramFiles(x86)} 'Microsoft OneDrive' })
        )) {
            if (-not $searchRoot -or -not (Test-Path -LiteralPath $searchRoot -PathType Container)) { continue }
            foreach ($file in @(Get-ChildItem -LiteralPath $searchRoot -Filter OneDriveSetup.exe -Recurse -File -ErrorAction Ignore)) {
                if (-not $uninstallers.Contains($file.FullName)) {
                    $uninstallers.Add($file.FullName)
                }
            }
        }

        Add-WnstAdvancedAction $actions ('[SCAN] OneDriveSetup.exe -> {0}' -f $uninstallers.Count)

        foreach ($setup in $uninstallers) {
            # An earlier official uninstaller may remove the other setup files.
            # Re-check each candidate instead of reporting a stale path as a failure.
            if (-not (Test-Path -LiteralPath $setup -PathType Leaf)) {
                Add-WnstAdvancedAction $actions ('[FILE] {0} -> ABSENT' -f $setup)
                continue
            }
            $uninstallAttempts++
            Add-WnstAdvancedAction $actions ('[FILE] {0}' -f $setup)

            $ok = $false
            $attemptErrors = [Collections.Generic.List[string]]::new()

            foreach ($arguments in @('/allusers /uninstall','/uninstall')) {
                if (-not (Test-Path -LiteralPath $setup -PathType Leaf)) { break }
                Add-WnstAdvancedAction $actions ('[CMD] "{0}" {1}' -f $setup,$arguments)
                try {
                    $process = Start-Process -FilePath $setup -ArgumentList $arguments -WindowStyle Hidden -Wait -PassThru -ErrorAction Stop
                    Add-WnstAdvancedAction $actions ('[EXIT] {0}' -f $process.ExitCode)

                    if ($process.ExitCode -eq 0) {
                        $ok = $true
                        break
                    }

                    $attemptErrors.Add(('{0} {1}: exit code {2}' -f $setup,$arguments,$process.ExitCode))
                }
                catch {
                    $attemptErrors.Add(('{0} {1}: {2}' -f $setup,$arguments,$_.Exception.Message))
                }
            }

            if ($ok) {
                $uninstallSuccess++
                Add-WnstAdvancedAction $actions ('[OK] UNINSTALL -> {0}' -f $setup)
            }
            else {
                Add-WnstAdvancedAction $actions ('[FAIL] UNINSTALL -> {0}' -f $setup)
                foreach ($attemptError in $attemptErrors) { $installerErrors.Add($attemptError) }
            }
        }

        Start-Sleep -Milliseconds 3000

        # The uninstaller can leave an updater service or relaunch a helper.
        # Stop both again before touching the installation directories.
        [void](Stop-WnstOneDriveOwnedServices -Errors $errors -Actions $actions)
        [void](Stop-WnstOneDriveOwnedProcesses -Actions $actions)

        # OneDrive existe aussi sous forme AppX sur certaines versions de Windows 11.
        # L'option dédiée OneDrive doit donc nettoyer cette variante elle-même afin
        # qu'elle n'ait pas à apparaître dans le gestionnaire Debloat.
        foreach ($package in @(Get-AppxPackage -AllUsers -Name '*OneDrive*' -ErrorAction Ignore)) {
            if (-not $package.PackageFullName) { continue }
            try {
                Remove-AppxPackage -Package $package.PackageFullName -AllUsers -ErrorAction Stop
                $appxInstalledRemoved++
                Add-WnstAdvancedAction $actions ('[APPX] {0} -> DELETE' -f [string]$package.Name)
            }
            catch {
                $errors.Add(('{0}: {1}' -f [string]$package.Name,$_.Exception.Message))
                Add-WnstAdvancedAction $actions ('[APPX] {0} -> FAILED' -f [string]$package.Name)
            }
        }

        foreach ($package in @(Get-AppxProvisionedPackage -Online -ErrorAction Ignore)) {
            $displayName = [string]$package.DisplayName
            if ($displayName -notlike '*OneDrive*' -or -not $package.PackageName) { continue }
            try {
                Remove-AppxProvisionedPackage -Online -PackageName $package.PackageName -AllUsers -ErrorAction Stop | Out-Null
                $appxProvisionedRemoved++
                Add-WnstAdvancedAction $actions ('[APPX-PROV] {0} -> DELETE' -f $displayName)
            }
            catch {
                $errors.Add(('{0}: {1}' -f $displayName,$_.Exception.Message))
                Add-WnstAdvancedAction $actions ('[APPX-PROV] {0} -> FAILED' -f $displayName)
            }
        }

        foreach ($policyPath in @(
            'HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive',
            'HKLM:\SOFTWARE\Wow6432Node\Policies\Microsoft\Windows\OneDrive'
        )) {
            try {
                Set-WnstRegistryDword $policyPath 'DisableFileSyncNGSC' 1
                Add-WnstAdvancedAction $actions ('[REG] {0}\DisableFileSyncNGSC = 1' -f $policyPath)
            }
            catch {
                $errors.Add([string]$_.Exception.Message)
            }
        }

        $clsid = '{018D5C66-4533-4307-9B53-224DE2ED1FE6}'
        foreach ($key in @(
            "HKLM:\SOFTWARE\Classes\CLSID\$clsid",
            "HKLM:\SOFTWARE\Classes\Wow6432Node\CLSID\$clsid"
        )) {
            if (Test-Path -LiteralPath $key) {
                try {
                    Set-WnstRegistryDword $key 'System.IsPinnedToNameSpaceTree' 0
                    Add-WnstAdvancedAction $actions ('[REG] {0}\System.IsPinnedToNameSpaceTree = 0' -f $key)
                }
                catch {
                    $errors.Add([string]$_.Exception.Message)
                }
            }
            else {
                Add-WnstAdvancedAction $actions ('[REG] {0} -> ABSENT' -f $key)
            }
        }

        foreach ($runPath in @(
            'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run',
            'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run',
            'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'
        )) {
            $hadOneDrive = $false
            try {
                $props = Get-ItemProperty -LiteralPath $runPath -Name OneDrive -ErrorAction Stop
                if ($null -ne $props) { $hadOneDrive = $true }
            }
            catch {}

            Remove-ItemProperty -LiteralPath $runPath -Name OneDrive -Force -ErrorAction Ignore
            Add-WnstAdvancedAction $actions (
                '[RUN] {0}\OneDrive -> {1}' -f $runPath, $(if ($hadOneDrive) { 'DELETE' } else { 'ABSENT' })
            )
        }

        # Nettoyage du raccourci OneDrive du menu Démarrer, présent dans le script d'origine.
        $oneDriveShortcut = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\OneDrive.lnk'
        if (Test-Path -LiteralPath $oneDriveShortcut) {
            try {
                Remove-Item -LiteralPath $oneDriveShortcut -Force -ErrorAction Stop
                Add-WnstAdvancedAction $actions ('[SHORTCUT] {0} -> DELETE' -f $oneDriveShortcut)
            }
            catch {
                $errors.Add(('{0}: {1}' -f $oneDriveShortcut,$_.Exception.Message))
                Add-WnstAdvancedAction $actions ('[SHORTCUT] {0} -> FAILED' -f $oneDriveShortcut)
            }
        }
        else {
            Add-WnstAdvancedAction $actions ('[SHORTCUT] {0} -> ABSENT' -f $oneDriveShortcut)
        }

        # Nettoyage des tâches planifiées OneDrive*, également présent dans le script d'origine.
        # Le filtre est volontairement limité au nom OneDrive* : aucune tâche WNST n'est touchée.
        try {
            $oneDriveTasks = @(Get-ScheduledTask -TaskPath '\' -TaskName 'OneDrive*' -ErrorAction SilentlyContinue)
            if ($oneDriveTasks.Count -gt 0) {
                foreach ($task in $oneDriveTasks) {
                    try {
                        Unregister-ScheduledTask -InputObject $task -Confirm:$false -ErrorAction Stop
                        Add-WnstAdvancedAction $actions ('[TASK] {0}{1} -> DELETE' -f [string]$task.TaskPath,[string]$task.TaskName)
                    }
                    catch {
                        $errors.Add(('{0}{1}: {2}' -f [string]$task.TaskPath,[string]$task.TaskName,$_.Exception.Message))
                        Add-WnstAdvancedAction $actions ('[TASK] {0}{1} -> FAILED' -f [string]$task.TaskPath,[string]$task.TaskName)
                    }
                }
            }
            else {
                Add-WnstAdvancedAction $actions '[TASK] OneDrive* -> ABSENT'
            }
        }
        catch {
            $errors.Add(('OneDrive scheduled tasks: {0}' -f $_.Exception.Message))
            Add-WnstAdvancedAction $actions '[TASK] OneDrive* -> FAILED'
        }

        $defaultHive = Join-Path $env:SystemDrive 'Users\Default\NTUSER.DAT'
        if (Test-Path -LiteralPath $defaultHive -PathType Leaf) {
            Add-WnstAdvancedAction $actions ('[HIVE] {0} -> LOAD' -f $defaultHive)
            $loaded = $false

            try {
                & $regExe load 'HKU\WNST_Default' $defaultHive 2>$null | Out-Null
                if ($LASTEXITCODE -ne 0) {
                    throw ('reg.exe load HKU\WNST_Default: exit code {0}' -f $LASTEXITCODE)
                }

                $loaded = $true
                Add-WnstAdvancedAction $actions '[HIVE] HKU\WNST_Default -> LOADED'

                foreach ($name in @('OneDriveSetup','OneDrive')) {
                    $defaultRun = 'Registry::HKEY_USERS\WNST_Default\Software\Microsoft\Windows\CurrentVersion\Run'
                    $exists = $false
                    try {
                        $props = Get-ItemProperty -LiteralPath $defaultRun -Name $name -ErrorAction Stop
                        if ($null -ne $props) { $exists = $true }
                    }
                    catch {}

                    Remove-ItemProperty -LiteralPath $defaultRun -Name $name -Force -ErrorAction Ignore
                    Add-WnstAdvancedAction $actions (
                        '[RUN] Default\{0} -> {1}' -f $name, $(if ($exists) { 'DELETE' } else { 'ABSENT' })
                    )
                }
            }
            catch {
                $errors.Add([string]$_.Exception.Message)
            }
            finally {
                if ($loaded) {
                    [gc]::Collect()
                    [gc]::WaitForPendingFinalizers()

                    & $regExe unload 'HKU\WNST_Default' 2>$null | Out-Null
                    if ($LASTEXITCODE -ne 0) {
                        $errors.Add(('reg.exe unload HKU\WNST_Default: exit code {0}' -f $LASTEXITCODE))
                    }
                    else {
                        Add-WnstAdvancedAction $actions '[HIVE] HKU\WNST_Default -> UNLOADED'
                    }
                }
            }
        }
        else {
            Add-WnstAdvancedAction $actions ('[HIVE] {0} -> ABSENT' -f $defaultHive)
        }

        foreach ($folder in @(Get-WnstOneDriveInstallRoots)) {
            if (-not $folder) { continue }

            if (-not (Test-Path -LiteralPath $folder)) {
                Add-WnstAdvancedAction $actions ('[PATH] {0} -> ABSENT' -f $folder)
                continue
            }

            $deleteResult = Remove-WnstOneDriveInstallRootImmediately -Path $folder -Actions $actions
            if ([bool]$deleteResult.Removed) {
                $removedFolders++
                Add-WnstAdvancedAction $actions ('[PATH] {0} -> DELETE' -f $folder)
            }
            else {
                try {
                    if (Register-WnstPathDeleteAtRestart -Path $folder) {
                        $pendingDeleteFolders.Add([IO.Path]::GetFullPath($folder).TrimEnd('\'))
                        Add-WnstAdvancedAction $actions ('[PATH] {0} -> PRESENT' -f $folder)
                    }
                }
                catch {
                    $detail = if ([string]::IsNullOrWhiteSpace([string]$deleteResult.Error)) { $_.Exception.Message } else { [string]$deleteResult.Error }
                    $errors.Add(('{0}: {1}' -f $folder,$detail))
                    Add-WnstAdvancedAction $actions ('[PATH] {0} -> FAILED' -f $folder)
                }
            }
        }

        $personal = Join-Path $env:USERPROFILE 'OneDrive'
        if (Test-Path -LiteralPath $personal -PathType Container) {
            $content = @(Get-ChildItem -LiteralPath $personal -Force -ErrorAction Ignore)

            if ($content.Count -eq 0) {
                try {
                    Remove-Item -LiteralPath $personal -Force -ErrorAction Stop
                    Add-WnstAdvancedAction $actions ('[USER] {0} -> DELETE (EMPTY)' -f $personal)
                }
                catch {
                    $errors.Add([string]$_.Exception.Message)
                    Add-WnstAdvancedAction $actions ('[USER] {0} -> FAILED' -f $personal)
                }
            }
            else {
                $personalPreserved = $true
                Add-WnstAdvancedAction $actions ('[USER] {0} -> KEEP (items={1})' -f $personal,$content.Count)
            }
        }
        else {
            Add-WnstAdvancedAction $actions ('[USER] {0} -> ABSENT' -f $personal)
        }
    }
    finally {
        if ($explorerWasRunning) {
            # Windows peut relancer Explorer automatiquement après sa fermeture.
            # On attend d'abord ce redémarrage natif pour éviter une double instance
            # ou une course avec Winlogon. WNST ne lance Explorer lui-même que si
            # aucune instance n'est revenue après quelques secondes.
            $restartDeadline = [DateTime]::UtcNow.AddSeconds(5)
            while (-not (Get-Process explorer -ErrorAction Ignore) -and [DateTime]::UtcNow -lt $restartDeadline) {
                Start-Sleep -Milliseconds 200
            }

            if (Get-Process explorer -ErrorAction Ignore) {
                Add-WnstAdvancedAction $actions '[PROC] explorer.exe -> AUTO-STARTED'
            }
            else {
                try {
                    Start-Process -FilePath $explorerExe -ErrorAction Stop | Out-Null

                    $readyDeadline = [DateTime]::UtcNow.AddSeconds(5)
                    while (-not (Get-Process explorer -ErrorAction Ignore) -and [DateTime]::UtcNow -lt $readyDeadline) {
                        Start-Sleep -Milliseconds 200
                    }

                    if (Get-Process explorer -ErrorAction Ignore) {
                        Add-WnstAdvancedAction $actions '[PROC] explorer.exe -> STARTED'
                    }
                    else {
                        $errors.Add('ExplorerRestartFailed')
                        Add-WnstAdvancedAction $actions '[PROC] explorer.exe -> START FAILED'
                    }
                }
                catch {
                    $errors.Add(('explorer.exe: {0}' -f $_.Exception.Message))
                    Add-WnstAdvancedAction $actions '[PROC] explorer.exe -> START FAILED'
                }
            }
        }
    }

    $processRemaining = @($oneDriveProcessNames | ForEach-Object { Get-Process -Name $_ -ErrorAction Ignore }).Count -gt 0
    $appxRemaining = @(Get-AppxPackage -AllUsers -Name '*OneDrive*' -ErrorAction Ignore).Count
    $provisionedAppxRemaining = @(
        Get-AppxProvisionedPackage -Online -ErrorAction Ignore |
            Where-Object { [string]$_.DisplayName -like '*OneDrive*' }
    ).Count
    $remainingInstallFolders = @(Get-WnstOneDriveInstallRoots | Where-Object { Test-Path -LiteralPath $_ })
    $remaining = $processRemaining -or ($appxRemaining -gt 0) -or ($provisionedAppxRemaining -gt 0) -or ($remainingInstallFolders.Count -gt 0)

    # Installer return codes are advisory: the final state is authoritative.
    # Surface them only when OneDrive is actually still installed.
    if ($remaining) {
        foreach ($item in $installerErrors) { $errors.Add($item) }
    }
    elseif ($uninstallAttempts -gt 0 -and $uninstallSuccess -eq 0) {
        $uninstallSuccess = $uninstallAttempts
    }

    Add-WnstAdvancedAction $actions ('[CHECK] OneDrive.exe -> {0}' -f $(if ($processRemaining) { 'PRESENT' } else { 'ABSENT' }))
    Add-WnstAdvancedAction $actions ('[CHECK] OneDrive AppX -> installed={0} provisioned={1}' -f $appxRemaining,$provisionedAppxRemaining)
    Add-WnstAdvancedAction $actions ('[PATH] Microsoft OneDrive -> {0} (count={1})' -f $(if($remainingInstallFolders.Count -gt 0){'PRESENT'}else{'ABSENT'}),$remainingInstallFolders.Count)

    $success = (-not $remaining -and $errors.Count -eq 0)

    return [pscustomobject]@{
        Operation = 'OneDrive'
        Success = $success
        Partial = (-not $success)
        Errors = @($errors)
        Actions = @($actions)
        ActionsStreamed = ($null -ne $ProgressQueue)
        UninstallAttempts = $uninstallAttempts
        UninstallSuccess = $uninstallSuccess
        RemovedFolders = $removedFolders
        AppxInstalledRemoved = $appxInstalledRemoved
        AppxProvisionedRemoved = $appxProvisionedRemoved
        PendingDeleteFolders = $pendingDeleteFolders.Count
        PersonalFolderPreserved = $personalPreserved
        RestartRecommended = $true
    }
}

function Invoke-WnstTelemetryDisable {
    [CmdletBinding()] param(
        [ValidateSet('Pushed','Aggressive')][string]$Mode='Pushed',
        [string]$DataRoot,
        [object]$ProgressQueue
    )
    if (-not (Test-WnstAdvancedAdministrator)) { throw 'AdministratorRequired' }

    $script:WnstAdvancedProgressQueue = $ProgressQueue

    $errors = [Collections.Generic.List[string]]::new()
    $actions = [Collections.Generic.List[string]]::new()
    $services = 0
    $policies = 0

    foreach ($entry in @(
        @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection','AllowTelemetry',0),
        @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection','DoNotShowFeedbackNotifications',1),
        @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection','DisableOneSettingsDownloads',1),
        @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection','AllowDeviceNameInTelemetry',0),
        @('HKCU:\SOFTWARE\Policies\Microsoft\Windows\CloudContent','DisableTailoredExperiencesWithDiagnosticData',1),
        @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent','DisableWindowsConsumerFeatures',1),
        @('HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo','Enabled',0),
        @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\System','EnableActivityFeed',0),
        @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\System','PublishUserActivities',0),
        @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\System','UploadUserActivities',0)
    )) {
        if (Set-WnstRegistryDwordSafe -Path $entry[0] -Name $entry[1] -Value ([int]$entry[2]) -Errors $errors) {
            $policies++
            Add-WnstAdvancedAction $actions ('[REG] {0}\{1} = {2}' -f $entry[0],$entry[1],$entry[2])
        }
        else {
            Add-WnstAdvancedAction $actions ('[FAIL] {0}\{1}' -f $entry[0],$entry[1])
        }
    }

    foreach ($name in @(
        'SubscribedContent-338388Enabled',
        'SubscribedContent-338389Enabled',
        'SubscribedContent-353694Enabled',
        'SubscribedContent-353696Enabled',
        'SystemPaneSuggestionsEnabled'
    )) {
        $path = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
        if (Set-WnstRegistryDwordSafe -Path $path -Name $name -Value 0 -Errors $errors) {
            $policies++
            Add-WnstAdvancedAction $actions ('[REG] {0}\{1} = 0' -f $path,$name)
        }
        else {
            Add-WnstAdvancedAction $actions ('[FAIL] {0}\{1}' -f $path,$name)
        }
    }

    foreach ($name in @('DiagTrack','dmwappushservice')) {
        $errorCountBefore = $errors.Count
        if (Disable-WnstServiceSafe -Name $name -Errors $errors) {
            $services++
            Add-WnstAdvancedAction $actions ('[SERVICE] {0} -> DISABLED' -f $name)
        }
        elseif ($errors.Count -gt $errorCountBefore) {
            Add-WnstAdvancedAction $actions ('[SERVICE] {0} -> FAILED' -f $name)
        }
    }

    # Aucune tâche planifiée n'est modifiée ici. Le planificateur utilisé par
    # l'onglet Host reste complètement indépendant de la télémétrie.
    Add-WnstAdvancedAction $actions '[TASKS] SCHEDULED_TASKS -> UNTOUCHED'

    $hostsBlocked = $false
    $telemetryState = $null

    if ($Mode -eq 'Aggressive') {
        foreach ($entry in @(
            @('HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting','Disabled',1),
            @('HKCU:\SOFTWARE\Microsoft\Windows\Windows Error Reporting','Disabled',1)
        )) {
            if (Set-WnstRegistryDwordSafe -Path $entry[0] -Name $entry[1] -Value ([int]$entry[2]) -Errors $errors) {
                $policies++
                Add-WnstAdvancedAction $actions ('[REG] {0}\{1} = {2}' -f $entry[0],$entry[1],$entry[2])
            }
            else {
                Add-WnstAdvancedAction $actions ('[FAIL] {0}\{1}' -f $entry[0],$entry[1])
            }
        }

        foreach ($name in @('WerSvc','diagnosticshub.standardcollector.service')) {
            $errorCountBefore = $errors.Count
            if (Disable-WnstServiceSafe -Name $name -Errors $errors) {
                $services++
                Add-WnstAdvancedAction $actions ('[SERVICE] {0} -> DISABLED' -f $name)
            }
            elseif ($errors.Count -gt $errorCountBefore) {
                Add-WnstAdvancedAction $actions ('[SERVICE] {0} -> FAILED' -f $name)
            }
        }

        Add-WnstAdvancedAction $actions '[HOSTS] WNST_TELEMETRY_BLOCK -> ENABLE'
        try {
            $telemetryBlockResult = Set-HuTelemetryHostsBlock -Enabled $true -DataRoot $DataRoot
            $hostsBlocked = [bool]$telemetryBlockResult.Enabled
            $telemetryState = [bool]$telemetryBlockResult.Enabled
            Add-WnstAdvancedAction $actions ('[HOSTS] endpoints={0} changed={1} dnsFlush={2}' -f [int]$telemetryBlockResult.EndpointCount,[bool]$telemetryBlockResult.Changed,[bool]$telemetryBlockResult.DnsFlushed)
        }
        catch {
            $errors.Add([string]$_.Exception.Message)
            Add-WnstAdvancedAction $actions ('[HOSTS] FAILED -> {0}' -f [string]$_.Exception.Message)
            $hostsBlocked = $false
            $telemetryState = $null
        }
    }

    return [pscustomobject]@{
        Operation = 'Telemetry'
        Mode = $Mode
        Success = ($errors.Count -eq 0)
        Partial = ($errors.Count -gt 0)
        Errors = @($errors)
        Actions = @($actions)
        ActionsStreamed = ($null -ne $ProgressQueue)
        Policies = $policies
        Services = $services
        HostsBlocked = $hostsBlocked
        TelemetryHostsBlockEnabled = $telemetryState
        ScheduledTasksModified = 0
        RestartRecommended = $true
    }
}

function Remove-WnstEdgeTaskbarShortcuts {
    param([Collections.Generic.List[string]]$Errors,[Collections.Generic.List[string]]$Actions)
    $pinnedRoot = Join-Path $env:APPDATA 'Microsoft\Internet Explorer\Quick Launch\User Pinned'

    if (-not ('WNST.TaskbarPin' -as [type])) {
        try {
            Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Threading;
namespace WNST {
    [ComImport, Guid("4CD19ADA-25A5-4A32-B3B7-347BEE5BE36B"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IStartMenuPinnedList {
        [PreserveSig] int RemoveFromList(IntPtr item);
    }
    public static class TaskbarPin {
        [DllImport("shell32.dll", CharSet = CharSet.Unicode, PreserveSig = true)]
        private static extern int SHCreateItemFromParsingName(string path, IntPtr bindContext, ref Guid iid, out IntPtr item);
        private static int UnpinCore(string path) {
            Guid shellItemIid = new Guid("43826D1E-E718-42EE-BC55-A1E261C37BFE");
            IntPtr item = IntPtr.Zero;
            object pinnedList = null;
            int hr = SHCreateItemFromParsingName(path, IntPtr.Zero, ref shellItemIid, out item);
            if (hr < 0) return hr;
            try {
                Type type = Type.GetTypeFromCLSID(new Guid("A2A9545D-A0C2-42B4-9708-A0B2BADD77C8"), true);
                pinnedList = Activator.CreateInstance(type);
                return ((IStartMenuPinnedList)pinnedList).RemoveFromList(item);
            }
            finally {
                if (pinnedList != null && Marshal.IsComObject(pinnedList)) Marshal.FinalReleaseComObject(pinnedList);
                if (item != IntPtr.Zero) Marshal.Release(item);
            }
        }
        public static int Unpin(string path) {
            int result = unchecked((int)0x80004005);
            Exception failure = null;
            Thread thread = new Thread(() => {
                try { result = UnpinCore(path); }
                catch (Exception ex) { failure = ex; }
            });
            thread.SetApartmentState(ApartmentState.STA);
            thread.Start();
            thread.Join();
            if (failure != null) throw failure;
            return result;
        }
    }
}
'@ -ErrorAction Stop
        }
        catch {
            # Shortcut deletion below remains a safe fallback if this legacy
            # Shell interface is unavailable on a future Windows build.
        }
    }

    $removed = 0
    $shell = $null
    try {
        $shell = New-Object -ComObject WScript.Shell
        $shortcutCandidates = [Collections.Generic.List[object]]::new()
        foreach ($knownPath in @(
            (Join-Path $env:PUBLIC 'Desktop\Microsoft Edge.lnk'),
            (Join-Path $env:USERPROFILE 'Desktop\Microsoft Edge.lnk'),
            (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Microsoft Edge.lnk'),
            (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\Microsoft Edge.lnk')
        )) {
            if (Test-Path -LiteralPath $knownPath -PathType Leaf) {
                $shortcutCandidates.Add((Get-Item -LiteralPath $knownPath -Force))
            }
        }
        if (Test-Path -LiteralPath $pinnedRoot -PathType Container) {
            foreach ($item in @(Get-ChildItem -LiteralPath $pinnedRoot -Filter '*.lnk' -File -Recurse -ErrorAction SilentlyContinue)) {
                if (@($shortcutCandidates | Where-Object FullName -EQ $item.FullName).Count -eq 0) { $shortcutCandidates.Add($item) }
            }
        }

        foreach ($shortcut in $shortcutCandidates) {
            $shortcutPath = [string]$shortcut.FullName
            if (-not (Test-Path -LiteralPath $shortcutPath -PathType Leaf)) { continue }
            try {
                $shortcutData = $shell.CreateShortcut($shortcutPath)
                $target = [string]$shortcutData.TargetPath
                $iconLocation = [string]$shortcutData.IconLocation
                $baseName = [IO.Path]::GetFileNameWithoutExtension([string]$shortcut.Name)
                $isEdge = ([IO.Path]::GetFileName($target) -ieq 'msedge.exe') -or
                    ($target -match '(?i)\\Microsoft\\Edge\\') -or
                    ($iconLocation -match '(?i)(?:\\Microsoft\\Edge\\|msedge\.exe)') -or
                    ($baseName -imatch '^(?:Microsoft\s+)?Edge$')
                if (-not $isEdge) { continue }

                $changed = $false
                if ('WNST.TaskbarPin' -as [type]) {
                    try {
                        if ([WNST.TaskbarPin]::Unpin($shortcutPath) -ge 0) { $changed = $true }
                    }
                    catch {}
                }

                if ((Test-WnstPathInsideRoot -Path $shortcutPath -Root $pinnedRoot) -and (Test-Path -LiteralPath $shortcutPath -PathType Leaf)) {
                    Remove-Item -LiteralPath $shortcutPath -Force -ErrorAction Stop
                    $changed = $true
                }
                if ($changed) {
                    $removed++
                    Add-WnstAdvancedAction $Actions ('[SHORTCUT] {0} -> DELETE' -f $shortcutPath)
                }
            }
            catch {
                # Unpinning can remove the backing .lnk before the explicit
                # fallback delete reaches it. That race is success, not an error.
                if (-not (Test-Path -LiteralPath $shortcutPath -PathType Leaf)) {
                    $removed++
                    Add-WnstAdvancedAction $Actions ('[SHORTCUT] {0} -> DELETE' -f $shortcutPath)
                    continue
                }
                $message = '{0}: {1}' -f $shortcutPath,$_.Exception.Message
                $Errors.Add($message)
                Add-WnstAdvancedAction $Actions ('[FAIL] {0}' -f $message)
            }
        }
    }
    finally {
        if ($shell) { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell) }
    }
    return $removed
}

function Invoke-WnstEdgeRemoval {
    [CmdletBinding()] param([object]$ProgressQueue)
    if (-not (Test-WnstAdvancedAdministrator)) { throw 'AdministratorRequired' }

    $script:WnstAdvancedProgressQueue = $ProgressQueue
    $errors = [Collections.Generic.List[string]]::new()
    $installerErrors = [Collections.Generic.List[string]]::new()
    $actions = [Collections.Generic.List[string]]::new()
    $attempts = 0
    $successfulUninstallers = 0
    $removedFolders = 0

    foreach ($name in @('msedge','msedge_proxy','identity_helper')) {
        $processes = @(Get-Process -Name $name -ErrorAction Ignore)
        if ($processes.Count -gt 0) {
            $processes | Stop-Process -Force -ErrorAction Ignore
            Add-WnstAdvancedAction $actions ('[PROC] {0} -> STOP' -f $name)
        }
    }

    # Unpin while the original Edge shortcuts and executable still exist.
    # Windows explicitly recommends doing this before deleting an application's
    # shortcuts during uninstallation.
    $removedTaskbarShortcuts = Remove-WnstEdgeTaskbarShortcuts -Errors $errors -Actions $actions

    $browserRoots = @(
        $(if (${env:ProgramFiles(x86)}) { Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application' }),
        (Join-Path $env:ProgramFiles 'Microsoft\Edge\Application')
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }

    $installers = [Collections.Generic.List[string]]::new()
    Add-WnstAdvancedAction $actions '[SCAN] Edge setup.exe'
    foreach ($root in $browserRoots) {
        if (-not (Test-Path -LiteralPath $root -PathType Container)) { continue }
        foreach ($file in @(Get-ChildItem -LiteralPath $root -Filter setup.exe -Recurse -File -ErrorAction Ignore | Where-Object { $_.FullName -match '\\Installer\\setup\.exe$' })) {
            if (-not $installers.Contains($file.FullName)) { $installers.Add($file.FullName) }
        }
    }
    Add-WnstAdvancedAction $actions ('[SCAN] Edge setup.exe -> {0}' -f $installers.Count)

    foreach ($setup in $installers) {
        $attempts++
        Add-WnstAdvancedAction $actions ('[CMD] "{0}" --uninstall --system-level --force-uninstall --delete-profile --verbose-logging' -f $setup)
        try {
            $process = Start-Process -FilePath $setup -ArgumentList '--uninstall --system-level --force-uninstall --delete-profile --verbose-logging' -Wait -WindowStyle Hidden -PassThru -ErrorAction Stop
            if ($process.ExitCode -eq 0) {
                $successfulUninstallers++
                Add-WnstAdvancedAction $actions '[EXIT] 0'
            }
            else {
                $installerErrors.Add(('{0}: exit code {1}' -f $setup,$process.ExitCode))
            }
        }
        catch {
            $installerErrors.Add(('{0}: {1}' -f $setup,$_.Exception.Message))
        }
    }

    Add-WnstAdvancedAction $actions '[WAIT] 900 ms'
    Start-Sleep -Milliseconds 900

    foreach ($shortcut in @(
        (Join-Path $env:PUBLIC 'Desktop\Microsoft Edge.lnk'),
        (Join-Path $env:USERPROFILE 'Desktop\Microsoft Edge.lnk'),
        (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Microsoft Edge.lnk'),
        (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\Microsoft Edge.lnk')
    )) {
        if (-not (Test-Path -LiteralPath $shortcut)) { continue }
        try {
            Remove-Item -LiteralPath $shortcut -Force -ErrorAction Stop
            Add-WnstAdvancedAction $actions ('[SHORTCUT] {0} -> DELETE' -f $shortcut)
        }
        catch {
            $message = '{0}: {1}' -f $shortcut,$_.Exception.Message
            $errors.Add($message)
            Add-WnstAdvancedAction $actions ('[FAIL] {0}' -f $message)
        }
    }

    $removedTaskbarShortcuts += Remove-WnstEdgeTaskbarShortcuts -Errors $errors -Actions $actions

    $cleanupFolders = @($browserRoots) + @(
        (Join-Path $env:LOCALAPPDATA 'Microsoft\Edge'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\EdgeCore'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\EdgeBrowser')
    )
    foreach ($folder in $cleanupFolders) {
        if (-not (Test-Path -LiteralPath $folder)) { continue }
        $folderErrors = [Collections.Generic.List[string]]::new()
        if (Remove-WnstPathSafe -Path $folder -Errors $folderErrors) {
            $removedFolders++
            Add-WnstAdvancedAction $actions ('[PATH] {0} -> DELETE' -f $folder)
        }
        else {
            foreach ($item in $folderErrors) {
                $errors.Add($item)
                Add-WnstAdvancedAction $actions ('[FAIL] {0}' -f $item)
            }
        }
    }

    try {
        $guid = '{56EB18F8-B008-4CBD-B6D2-8C97FE7E9062}'
        Set-WnstRegistryDword 'HKLM:\SOFTWARE\Policies\Microsoft\EdgeUpdate' ("Install$guid") 0
        Set-WnstRegistryDword 'HKLM:\SOFTWARE\Policies\Microsoft\EdgeUpdate' ("Update$guid") 0
        Add-WnstAdvancedAction $actions '[REG] Edge Stable install/update -> BLOCKED'
    }
    catch {
        $errors.Add([string]$_.Exception.Message)
        Add-WnstAdvancedAction $actions ('[FAIL] Edge policy -> {0}' -f [string]$_.Exception.Message)
    }

    $remainingExecutables = @()
    foreach ($root in $browserRoots) {
        if (Test-Path -LiteralPath $root -PathType Container) {
            $remainingExecutables += @(Get-ChildItem -LiteralPath $root -Filter msedge.exe -Recurse -File -ErrorAction Ignore)
        }
    }
    $processRemaining = @(Get-Process -Name msedge -ErrorAction Ignore).Count -gt 0
    $remaining = ($remainingExecutables.Count -gt 0) -or $processRemaining

    if ($remaining) {
        foreach ($item in $installerErrors) {
            $errors.Add($item)
            Add-WnstAdvancedAction $actions ('[FAIL] {0}' -f $item)
        }
        Add-WnstAdvancedAction $actions ('[FAIL] Edge -> PRESENT (files={0}, process={1})' -f $remainingExecutables.Count,$processRemaining)
    }
    else {
        # Certains setup.exe (notamment exit 532) annoncent un échec après avoir
        # pourtant supprimé Edge. La vérification finale fait foi.
        $successfulUninstallers = $attempts
        Add-WnstAdvancedAction $actions '[OK] Microsoft Edge -> ABSENT'
    }

    # Refresh the taskbar once, after all uninstall and cleanup work is done.
    # Clearing the global icon cache made Explorer unresponsive for 15-20 s and
    # is unnecessary once the pinned shortcut has been removed through Shell.
    if ($removedTaskbarShortcuts -gt 0) {
        $explorerExe = Join-Path $env:SystemRoot 'explorer.exe'
        try {
            $oldExplorerIds = @(Get-Process -Name explorer -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id)
            Get-Process -Name explorer -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
            $stopDeadline = [DateTime]::UtcNow.AddSeconds(2)
            while (@(Get-Process -Name explorer -ErrorAction SilentlyContinue | Where-Object { $_.Id -in $oldExplorerIds }).Count -gt 0 -and [DateTime]::UtcNow -lt $stopDeadline) {
                Start-Sleep -Milliseconds 100
            }

            $restartDeadline = [DateTime]::UtcNow.AddSeconds(3)
            while (-not (Get-Process -Name explorer -ErrorAction SilentlyContinue) -and [DateTime]::UtcNow -lt $restartDeadline) {
                Start-Sleep -Milliseconds 100
            }
            if (-not (Get-Process -Name explorer -ErrorAction SilentlyContinue)) {
                Start-Process -FilePath $explorerExe -ErrorAction Stop | Out-Null
            }
            Add-WnstAdvancedAction $actions '[PROC] explorer.exe -> STARTED'
        }
        catch {
            $message = 'explorer.exe: {0}' -f $_.Exception.Message
            $errors.Add($message)
            Add-WnstAdvancedAction $actions ('[FAIL] {0}' -f $message)
        }
    }

    $success = (-not $remaining -and $errors.Count -eq 0)
    return [pscustomobject]@{
        Operation = 'Edge'
        Mode = 'Aggressive'
        Success = $success
        Partial = (-not $success)
        Errors = @($errors)
        Actions = @($actions)
        ActionsStreamed = ($null -ne $ProgressQueue)
        UninstallAttempts = $attempts
        UninstallSuccess = $successfulUninstallers
        RemovedFolders = $removedFolders
        WebView2Preserved = $true
        RestartRecommended = $true
    }
}

function Invoke-WnstWindowsAiRemoval {
    [CmdletBinding()] param([object]$ProgressQueue)
    if (-not (Test-WnstAdvancedAdministrator)) { throw 'AdministratorRequired' }

    $script:WnstAdvancedProgressQueue = $ProgressQueue
    $errors = [Collections.Generic.List[string]]::new()
    $actions = [Collections.Generic.List[string]]::new()
    $installedRemoved = 0
    $provisionedRemoved = 0
    $recallRemoved = $false
    $policies = 0

    foreach ($name in @('*Copilot*')) {
        $processes = @(Get-Process -Name $name -ErrorAction Ignore)
        if ($processes.Count -gt 0) {
            $processes | Stop-Process -Force -ErrorAction Ignore
            Add-WnstAdvancedAction $actions ('[PROC] {0} -> STOP' -f $name)
        }
    }

    foreach ($entry in @(
        @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI','AllowRecallEnablement',0),
        @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI','DisableAIDataAnalysis',1),
        @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI','DisableClickToDo',1),
        @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI','DisableCocreator',1),
        @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI','DisableGenerativeFill',1),
        @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI','DisableImageCreator',1),
        @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI','DisableSettingsAgent',1),
        @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI','DisableAgentConnectors',1),
        @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI','DisableAgentWorkspaces',1),
        @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI','ConfigureAgentConnectors',2),
        @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI','RemoveMicrosoftCopilotApp',1),
        @('HKCU:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot','TurnOffWindowsCopilot',1),
        @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced','ShowCopilotButton',0)
    )) {
        if (Set-WnstRegistryDwordSafe -Path $entry[0] -Name $entry[1] -Value ([int]$entry[2]) -Errors $errors) {
            $policies++
            Add-WnstAdvancedAction $actions ('[REG] {0}\{1} = {2}' -f $entry[0],$entry[1],$entry[2])
        }
        else {
            Add-WnstAdvancedAction $actions ('[FAIL] {0}\{1}' -f $entry[0],$entry[1])
        }
    }

    try {
        $feature = Get-WindowsOptionalFeature -Online -FeatureName Recall -ErrorAction Ignore
        if ($feature -and $feature.State -notin @('Disabled','DisabledWithPayloadRemoved')) {
            Add-WnstAdvancedAction $actions '[FEATURE] Recall -> REMOVE'
            Disable-WindowsOptionalFeature -Online -FeatureName Recall -Remove -NoRestart -ErrorAction Stop | Out-Null
            $recallRemoved = $true
            Add-WnstAdvancedAction $actions '[OK] Recall -> DISABLED'
        }
        elseif ($feature) {
            Add-WnstAdvancedAction $actions '[CHECK] Recall -> DISABLED'
        }
    }
    catch {
        $errors.Add([string]$_.Exception.Message)
        Add-WnstAdvancedAction $actions ('[FAIL] Recall -> {0}' -f [string]$_.Exception.Message)
    }

    $patterns = @(
        '*Microsoft.Copilot*',
        '*Microsoft.Windows.Ai.Copilot.Provider*',
        '*Microsoft.WindowsAiFoundation*',
        '*Microsoft.Windows.Recall*',
        '*Microsoft.Windows.AIHub*',
        '*MicrosoftWindows.Client.CoreAI*',
        '*MicrosoftWindows.Client.AIX*'
    )
    $protectedNames = @(
        'MicrosoftWindows.Client.CoreAI',
        'MicrosoftWindows.Client.AIX'
    )
    $installed = [Collections.Generic.List[object]]::new()
    foreach ($pattern in $patterns) {
        foreach ($package in @(Get-AppxPackage -AllUsers -Name $pattern -ErrorAction Ignore)) {
            $alreadyAdded = @($installed | Where-Object { $_.PackageFullName -eq $package.PackageFullName }).Count -gt 0
            if ($package.PackageFullName -and -not $alreadyAdded) {
                $installed.Add($package)
            }
        }
    }
    Add-WnstAdvancedAction $actions ('[SCAN] Windows AI AppX -> {0}' -f $installed.Count)

    $protectedPackages = @($installed | Where-Object { $protectedNames -contains [string]$_.Name })
    foreach ($package in $installed) {
        if ($protectedNames -contains [string]$package.Name) { continue }
        $fullName = [string]$package.PackageFullName

        try {
            Add-WnstAdvancedAction $actions ('[APPX] {0} -> DELETE' -f $fullName)
            Remove-AppxPackage -Package $fullName -AllUsers -ErrorAction Stop
            $stillPresent = @(Get-AppxPackage -AllUsers -ErrorAction Ignore | Where-Object { [string]$_.PackageFullName -eq $fullName }).Count -gt 0
            if ($stillPresent) { throw ('Package still installed: {0}' -f $fullName) }
            $installedRemoved++
            Add-WnstAdvancedAction $actions ('[OK] {0} -> REMOVED' -f $fullName)
        }
        catch {
            $message = [string]$_.Exception.Message
            $errors.Add(('{0}: {1}' -f $fullName,$message))
            Add-WnstAdvancedAction $actions ('[FAIL] {0} -> {1}' -f $fullName,$message)
        }
    }

    if ($protectedPackages.Count -gt 0) {
        $installedRemoved += Invoke-WnstProtectedAiPackageRemoval -Packages $protectedPackages -Actions $actions -Errors $errors
    }

    $provisioned = @(Get-AppxProvisionedPackage -Online -ErrorAction Ignore)
    foreach ($package in $provisioned) {
        $match = $false
        foreach ($pattern in $patterns) {
            if ([string]$package.DisplayName -like $pattern) { $match = $true; break }
        }
        if (-not $match -or -not $package.PackageName) { continue }
        try {
            Add-WnstAdvancedAction $actions ('[APPX-PROV] {0} -> DELETE' -f [string]$package.PackageName)
            Remove-AppxProvisionedPackage -Online -PackageName $package.PackageName -AllUsers -ErrorAction Stop | Out-Null
            $provisionedRemoved++
            Add-WnstAdvancedAction $actions ('[OK] {0} -> REMOVED' -f [string]$package.PackageName)
        }
        catch {
            $errors.Add([string]$_.Exception.Message)
            Add-WnstAdvancedAction $actions ('[FAIL] {0} -> {1}' -f [string]$package.PackageName,[string]$_.Exception.Message)
        }
    }

    $remaining = 0
    foreach ($pattern in $patterns) {
        $remaining += @(Get-AppxPackage -AllUsers -Name $pattern -ErrorAction Ignore).Count
    }
    $remainingProvisioned = 0
    foreach ($package in @(Get-AppxProvisionedPackage -Online -ErrorAction Ignore)) {
        foreach ($pattern in $patterns) {
            if ([string]$package.DisplayName -like $pattern) { $remainingProvisioned++; break }
        }
    }
    $recallRemaining = 0
    $recallState = Get-WindowsOptionalFeature -Online -FeatureName Recall -ErrorAction Ignore
    if ($recallState -and $recallState.State -notin @('Disabled','DisabledWithPayloadRemoved')) { $recallRemaining = 1 }
    $remainingTotal = $remaining + $remainingProvisioned + $recallRemaining
    Add-WnstAdvancedAction $actions ('[CHECK] Windows AI -> installed={0} provisioned={1} recall={2}' -f $remaining,$remainingProvisioned,$recallRemaining)
    if ($remainingTotal -eq 0) { Add-WnstAdvancedAction $actions '[OK] Windows AI -> REMOVED' }

    $success = ($remainingTotal -eq 0 -and $errors.Count -eq 0)
    return [pscustomobject]@{
        Operation = 'WindowsAI'
        Mode = 'Aggressive'
        Success = $success
        Partial = (-not $success)
        Errors = @($errors)
        Actions = @($actions)
        ActionsStreamed = ($null -ne $ProgressQueue)
        Policies = $policies
        InstalledRemoved = $installedRemoved
        ProvisionedRemoved = $provisionedRemoved
        RecallRemoved = $recallRemoved
        Remaining = $remainingTotal
        RestartRecommended = $true
    }
}
