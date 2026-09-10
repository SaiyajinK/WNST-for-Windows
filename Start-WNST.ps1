#requires -Version 5.1

[CmdletBinding()]
param(
    [string]$DataRoot,
    [switch]$NoElevation,
    [switch]$HiddenHost,
    [switch]$ResumeAfterRestart
)

$ErrorActionPreference = 'Stop'

$modulePath = Join-Path $PSScriptRoot 'WNST.psd1'
Import-Module $modulePath -Force

if ($env:OS -ne 'Windows_NT') {
    throw (Get-HuModuleText 'StartupWindowsOnly')
}

if (-not $NoElevation -and -not $HiddenHost) {
    $hostExecutable = (Get-Process -Id $PID).Path
    $arguments = @('-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-STA', '-File', ('"{0}"' -f $PSCommandPath), '-HiddenHost')
    if ($DataRoot) { $arguments += @('-DataRoot', ('"{0}"' -f $DataRoot)) }
    if ($ResumeAfterRestart) { $arguments += '-ResumeAfterRestart' }
    try {
        $launch = @{ FilePath=$hostExecutable; ArgumentList=$arguments; WindowStyle='Hidden' }
        if (-not (Test-HuAdministrator)) { $launch.Verb = 'RunAs' }
        Start-Process @launch | Out-Null
    }
    catch {
        Add-Type -AssemblyName PresentationFramework
        [void][Windows.MessageBox]::Show((Get-HuModuleText 'StartupAdministratorRequired'), 'WNST', 'OK', 'Warning')
    }
    return
}

if (-not $NoElevation -and -not (Test-HuAdministrator)) { throw (Get-HuModuleText 'StartupAdministratorRequired') }

if ($ResumeAfterRestart) {
    # La tâche de reprise est strictement ponctuelle : la supprimer dès que son
    # lancement a réussi, puis laisser le bureau finir de charger avant WPF.
    try { Unregister-ScheduledTask -TaskName 'WNST Resume After Restart' -Confirm:$false -ErrorAction Stop }
    catch {
        try {
            $schtasksPath = Join-Path $env:SystemRoot 'System32\schtasks.exe'
            & $schtasksPath /Delete /TN 'WNST Resume After Restart' /F 2>$null | Out-Null
        }
        catch {}
    }
    Start-Sleep -Seconds 4
}

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

trap {
    try {
        $startupErrorText = ($_ | Out-String).Trim()
        $startupErrorPath = Join-Path $env:TEMP 'WNST-startup-error.log'
        [IO.File]::WriteAllText(
            $startupErrorPath,
            ((Get-Date).ToString('yyyy-MM-dd HH:mm:ss') + "`r`n" + $startupErrorText),
            (New-Object Text.UTF8Encoding($false))
        )
        [void][Windows.MessageBox]::Show(
            ("{0}`r`n`r`n{1}" -f $startupErrorText,$startupErrorPath),
            (Get-HuModuleText 'ErrorTitle'),
            'OK',
            'Error'
        )
    }
    catch {}
    break
}

if (-not ('WnstTaskbarIdentity' -as [type])) {
    Add-Type @'
using System;
using System.Runtime.InteropServices;

public static class WnstTaskbarIdentity
{
    [DllImport("shell32.dll", CharSet = CharSet.Unicode, PreserveSig = true)]
    public static extern int SetCurrentProcessExplicitAppUserModelID(string appID);
}
'@
}
[void][WnstTaskbarIdentity]::SetCurrentProcessExplicitAppUserModelID('SaiyajinK.WNST')

if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
    throw (Get-HuModuleText 'StartupStaRequired')
}


$script:AppRoot = $PSScriptRoot
$script:EntryScriptPath = $PSCommandPath
$script:ResumeAfterRestart = [bool]$ResumeAfterRestart
. (Join-Path $script:AppRoot 'Core\Bootstrap.ps1')
$script:DataRootArgument = $DataRoot
$script:Settings = if ($DataRoot) { Get-HuSettings -DataRoot $DataRoot } else { Get-HuSettings }
[void](Set-HuModuleLanguage -Code ([string]$script:Settings.Language))
$script:Paths = if ($DataRoot) { Get-HuPaths -DataRoot $DataRoot } else { Get-HuPaths }
$script:Translations = @{}
$script:Initializing = $true
$script:Busy = $false
$script:SkipSaveOnClose = $false
$script:ResolvedTheme = 'Dark'
$script:UiFontFamily = Get-HuUiFontFamily
$script:GitHubProfileUrl = 'https://github.com/SaiyajinK'
$script:RepositoryUrl = 'https://github.com/SaiyajinK/WNST-for-Windows'
$script:KoFiUrl = 'https://ko-fi.com/saiyajink'
$script:PendingReleaseUrl = ''
$script:UpdateResultCloseBrush = $null
$script:ContextSelectedBackupRow = $null
$script:ContextSelectedFirewallRows = @()
$script:PendingFirewallPrograms = @()
$script:PendingFirewallFolders = @()
$script:FirewallRuleGroup = 'WNST'
$script:DnsPresets = @(
    [pscustomobject]@{ Code='Google'; Name='Google'; IPv4=@('8.8.8.8','8.8.4.4'); IPv6=@('2001:4860:4860::8888','2001:4860:4860::8844') },
    [pscustomobject]@{ Code='Cloudflare'; Name='Cloudflare'; IPv4=@('1.1.1.1','1.0.0.1'); IPv6=@('2606:4700:4700::1111','2606:4700:4700::1001') },
    [pscustomobject]@{ Code='AdGuard'; Name='AdGuard'; IPv4=@('94.140.14.14','94.140.15.15'); IPv6=@('2a10:50c0::ad1:ff','2a10:50c0::ad2:ff') },
    [pscustomobject]@{ Code='OpenDNS'; Name='Cisco OpenDNS'; IPv4=@('208.67.222.222','208.67.220.220'); IPv6=@('2620:119:35::35','2620:119:53::53') },
    [pscustomobject]@{ Code='NextDNS'; Name='NextDNS'; IPv4=@('45.90.28.0','45.90.30.0'); IPv6=@('2a07:a8c0::','2a07:a8c1::') },
    [pscustomobject]@{ Code='Quad9'; Name='Quad9'; IPv4=@('9.9.9.9','149.112.112.112'); IPv6=@('2620:fe::fe','2620:fe::9') }
)
$script:NetworkToggleAdapterName = ''
$script:SpecsLoaded = $false
$script:SpecsText = ''
$script:PrimaryGpuIsNvidia = $null


. (Join-Path $script:AppRoot 'Core\Localization.ps1')

$availableLanguages = @(Get-AvailableLanguages)
if ($availableLanguages.Count -eq 0) { throw (Get-HuModuleText 'StartupTranslationFilesMissing') }

if (-not [bool]$script:Settings.FirstRunCompleted -or [string]::IsNullOrWhiteSpace([string]$script:Settings.Language)) {
    $script:Settings.Language = Show-LanguageDialog -Languages $availableLanguages
    $script:Settings.FirstRunCompleted = $true
    $script:Settings = Save-AppSettingsObject -Settings $script:Settings
}
$script:Settings.Language = Import-AppLanguage -Code ([string]$script:Settings.Language)
[void](Set-HuModuleLanguage -Code ([string]$script:Settings.Language))

$xamlText = [IO.File]::ReadAllText((Join-Path $script:AppRoot 'UI\MainWindow.xaml'))
$xamlText = $xamlText.Replace('<!-- WNST_STYLES -->', [IO.File]::ReadAllText((Join-Path $script:AppRoot 'UI\Styles\AppStyles.xaml')))
foreach ($pageName in @('HomePage','HistoryPage','DiagnosticsPage','PerformancePage','GamesPage','ApplicationsPage','ConnectionsPage','NetworkPage','CommandsPage','DebloatPage','AdvancedPage','FirewallPage','DnsPage','ThisPcPage','SettingsPage','AboutPage')) {
    $pagePath = Join-Path $script:AppRoot ("UI\Pages\{0}.xaml" -f $pageName)
    $xamlText = $xamlText.Replace(('<!-- WNST_PAGE_{0} -->' -f $pageName), [IO.File]::ReadAllText($pagePath))
}
[xml]$xaml = $xamlText
$reader = New-Object Xml.XmlNodeReader($xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)
$window.FontFamily = $script:UiFontFamily

$windowIconPath = Join-Path $script:AppRoot 'WNST.ico'
if (Test-Path -LiteralPath $windowIconPath) {
    $windowIconStream = [IO.File]::OpenRead($windowIconPath)
    try {
        $window.Icon = [Windows.Media.Imaging.BitmapFrame]::Create(
            $windowIconStream,
            [Windows.Media.Imaging.BitmapCreateOptions]::PreservePixelFormat,
            [Windows.Media.Imaging.BitmapCacheOption]::OnLoad
        )
    }
    finally {
        $windowIconStream.Dispose()
    }
}

. (Join-Path $script:AppRoot 'UI\BindControls.ps1')

. (Join-Path $script:AppRoot 'Core\Appearance.ps1')
. (Join-Path $script:AppRoot 'Core\Themes.ps1')
. (Join-Path $script:AppRoot 'UI\Dialogs\DialogService.ps1')
. (Join-Path $script:AppRoot 'Core\Helpers.ps1')
Register-WnstPersistentLogTarget -Control $NetworkOutputBox -Name 'Network'
Register-WnstPersistentLogTarget -Control $PingOutputBox -Name 'Ping'
Register-WnstPersistentLogTarget -Control $AppxLogBox -Name 'AppX'
Register-WnstPersistentLogTarget -Control $AdvancedLogBox -Name 'Advanced'
Register-WnstPersistentLogTarget -Control $IntegrityOutputBox -Name 'Integrity'
Register-WnstPersistentLogTarget -Control $PerformanceOutputBox -Name 'Performance'
Register-WnstPersistentLogTarget -Control $WindowsOutputBox -Name 'Windows'
Register-WnstPersistentLogTarget -Control $CleanupOutputBox -Name 'Cleanup'
Register-WnstPersistentLogTarget -Control $GamesLogBox -Name 'Games'
Register-WnstPersistentLogTarget -Control $ApplicationsLogBox -Name 'Applications'
. (Join-Path $script:AppRoot 'Core\Async.ps1')
. (Join-Path $script:AppRoot 'Modules\Updates.ps1')
. (Join-Path $script:AppRoot 'Modules\Hosts.ps1')
. (Join-Path $script:AppRoot 'Modules\Network.ps1')
. (Join-Path $script:AppRoot 'Modules\Firewall.ps1')
. (Join-Path $script:AppRoot 'Modules\Dns.ps1')
. (Join-Path $script:AppRoot 'Modules\System.ps1')
. (Join-Path $script:AppRoot 'Modules\Diagnostics.ps1')
. (Join-Path $script:AppRoot 'Modules\Performance.ps1')
. (Join-Path $script:AppRoot 'Modules\Installers.ps1')
. (Join-Path $script:AppRoot 'Modules\Games.ps1')
. (Join-Path $script:AppRoot 'Modules\ThisPc.ps1')
. (Join-Path $script:AppRoot 'Modules\Display.ps1')
. (Join-Path $script:AppRoot 'Core\Settings.ps1')

# Une exception dans un événement WPF ne doit pas fermer toute l'application.
$window.Dispatcher.add_UnhandledException({
    param($sender,$eventArgs)

    try {
        $exception = $eventArgs.Exception
        $message = if ($exception) { [string]$exception.Message } else { T 'ErrorTitle' }
        $details = if ($exception) { [string]$exception.ToString() } else { $message }
        $errorPath = Join-Path $env:TEMP 'WNST-runtime-error.log'

        [IO.File]::WriteAllText(
            $errorPath,
            ((Get-Date).ToString('yyyy-MM-dd HH:mm:ss') + "`r`n" + $details),
            (New-Object Text.UTF8Encoding($false))
        )

        if (Get-Command Show-AppError -ErrorAction SilentlyContinue) {
            Show-AppError ($message + [Environment]::NewLine + [Environment]::NewLine + $errorPath)
        }
        else {
            [void][Windows.MessageBox]::Show(
                ($message + [Environment]::NewLine + [Environment]::NewLine + $errorPath),
                (T 'ErrorTitle'),
                'OK',
                'Error'
            )
        }
    }
    catch { }
    finally {
        $eventArgs.Handled = $true
    }
})

. (Join-Path $script:AppRoot 'Core\Navigation.ps1')

. (Join-Path $script:AppRoot 'Core\InitializeUI.ps1')

. (Join-Path $script:AppRoot 'UI\Events\ShellNavigation.Events.ps1')
. (Join-Path $script:AppRoot 'UI\Events\Connections.Events.ps1')
. (Join-Path $script:AppRoot 'UI\Events\Commands.Events.ps1')
. (Join-Path $script:AppRoot 'UI\Events\Debloat.Events.ps1')
. (Join-Path $script:AppRoot 'UI\Events\Advanced.Events.ps1')
. (Join-Path $script:AppRoot 'UI\Events\Network.Events.ps1')
. (Join-Path $script:AppRoot 'UI\Events\Firewall.Events.ps1')
. (Join-Path $script:AppRoot 'UI\Events\Dns.Events.ps1')
. (Join-Path $script:AppRoot 'UI\Events\ThisPc.Events.ps1')
. (Join-Path $script:AppRoot 'UI\Events\Hosts.Events.ps1')
. (Join-Path $script:AppRoot 'UI\Events\Diagnostics.Events.ps1')
. (Join-Path $script:AppRoot 'UI\Events\Performance.Events.ps1')
. (Join-Path $script:AppRoot 'UI\Events\HistoryData.Events.ps1')
. (Join-Path $script:AppRoot 'UI\Events\About.Events.ps1')
. (Join-Path $script:AppRoot 'UI\Events\Settings.Events.ps1')
. (Join-Path $script:AppRoot 'UI\Events\LogActions.Events.ps1')
. (Join-Path $script:AppRoot 'UI\Events\SoftwareCatalog.Events.ps1')
. (Join-Path $script:AppRoot 'UI\Events\WindowLifecycle.Events.ps1')
. (Join-Path $script:AppRoot 'UI\Events\ResizableSurfaces.Events.ps1')

[void]$window.ShowDialog()
