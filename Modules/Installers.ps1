# WNST - catalogue logiciel et téléchargements vérifiés au moment du clic

Add-Type -AssemblyName System.Net.Http -ErrorAction SilentlyContinue
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }

function Get-HuDownloadsPath {
    $local = [string]$env:LOCALAPPDATA
    if ([string]::IsNullOrWhiteSpace($local)) { $local = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData) }
    $path = Join-Path $local 'WNST\Downloads'
    if (-not (Test-Path -LiteralPath $path -PathType Container)) {
        [void](New-Item -ItemType Directory -Path $path -Force -ErrorAction Stop)
    }
    return $path
}

function Get-HuDownloadedInstallersManifestPath {
    $downloads=Get-HuDownloadsPath
    return Join-Path (Split-Path -Parent $downloads) 'downloaded-installers.json'
}

function Get-HuDownloadedInstallerEntries {
    $manifest=Get-HuDownloadedInstallersManifestPath
    if(-not(Test-Path -LiteralPath $manifest -PathType Leaf)){return @()}
    try{return @((Get-Content -LiteralPath $manifest -Raw -Encoding UTF8|ConvertFrom-Json))}
    catch{return @()}
}

function Save-HuDownloadedInstallerEntry {
    param([Parameter(Mandatory=$true)][string]$Id,[Parameter(Mandatory=$true)][string]$Path,[string]$Version='')
    $extension=[IO.Path]::GetExtension($Path).ToLowerInvariant()
    if($extension -notin @('.exe','.msi','.msix','.msixbundle','.appx','.appxbundle','.appinstaller')){return}
    $fullPath=[IO.Path]::GetFullPath($Path);$root=[IO.Path]::GetFullPath((Get-HuDownloadsPath)).TrimEnd('\')+'\'
    if(-not$fullPath.StartsWith($root,[StringComparison]::OrdinalIgnoreCase)){throw 'INVALID_INSTALLER_PATH'}
    $entries=@(Get-HuDownloadedInstallerEntries|Where-Object{[string]$_.Id -ne $Id -and (Test-Path -LiteralPath ([string]$_.Path) -PathType Leaf)})
    $entries+=([pscustomobject]@{Id=$Id;Path=$fullPath;Version=$Version;SavedAt=[DateTime]::UtcNow.ToString('o')})
    $manifest=Get-HuDownloadedInstallersManifestPath;$temporary=$manifest+'.partial'
    [IO.File]::WriteAllText($temporary,(ConvertTo-Json -InputObject @($entries) -Compress -Depth 4),(New-Object Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $temporary -Destination $manifest -Force
}

function Test-HuInstallableArtifact {
    param([Parameter(Mandatory=$true)][string]$Path)
    return [IO.Path]::GetExtension($Path).ToLowerInvariant() -in @('.exe','.msi','.msix','.msixbundle','.appx','.appxbundle','.appinstaller')
}

function Expand-HuDownloadedInstallerArchive {
    param([Parameter(Mandatory=$true)][string]$Path,[Parameter(Mandatory=$true)][object]$Item)
    if(-not[IO.Path]::GetExtension($Path).Equals('.zip',[StringComparison]::OrdinalIgnoreCase)){return ''}
    Add-Type -AssemblyName System.IO.Compression -ErrorAction Stop
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop
    $parent=Split-Path -Parent $Path;$baseName=[IO.Path]::GetFileNameWithoutExtension($Path)
    $target=Join-Path $parent $baseName
    if(Test-Path -LiteralPath $target -PathType Container){
        $existing=@(Get-ChildItem -LiteralPath $target -Recurse -File -ErrorAction SilentlyContinue|Where-Object{Test-HuInstallableArtifact $_.FullName})
        if($existing.Count -eq 1){return $existing[0].FullName}
        $target=Join-Path $parent ('{0}_{1}' -f $baseName,(Get-Date -Format 'yyyyMMdd-HHmmss'))
    }
    [void](New-Item -ItemType Directory -Path $target -ErrorAction Stop)
    $targetRoot=[IO.Path]::GetFullPath($target).TrimEnd('\')+'\';$archive=$null
    try{
        $archive=[IO.Compression.ZipFile]::OpenRead($Path);$count=0;$expanded=[long]0
        foreach($entry in $archive.Entries){
            $count++;$expanded+=[long]$entry.Length
            if($count -gt 10000 -or $expanded -gt 8589934592){throw 'UNSAFE_ARCHIVE_CONTENT'}
            $relative=([string]$entry.FullName).Replace('/','\').TrimStart('\')
            if([string]::IsNullOrWhiteSpace($relative)){continue}
            $destination=[IO.Path]::GetFullPath((Join-Path $target $relative))
            if(-not$destination.StartsWith($targetRoot,[StringComparison]::OrdinalIgnoreCase)){throw 'UNSAFE_ARCHIVE_CONTENT'}
            if([string]::IsNullOrWhiteSpace([string]$entry.Name)){[void](New-Item -ItemType Directory -Path $destination -Force -ErrorAction Stop);continue}
            $directory=Split-Path -Parent $destination;if(-not(Test-Path -LiteralPath $directory -PathType Container)){[void](New-Item -ItemType Directory -Path $directory -Force -ErrorAction Stop)}
            $input=$entry.Open();$output=[IO.File]::Open($destination,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
            try{$input.CopyTo($output)}finally{$output.Dispose();$input.Dispose()}
        }
    }catch{if(Test-Path -LiteralPath $target -PathType Container){Remove-Item -LiteralPath $target -Recurse -Force -ErrorAction SilentlyContinue};throw}
    finally{if($archive){$archive.Dispose()}}
    $candidates=@(Get-ChildItem -LiteralPath $target -Recurse -File -ErrorAction Stop|Where-Object{Test-HuInstallableArtifact $_.FullName})
    if($candidates.Count -gt 1){
        $preferred=@($candidates|Where-Object{$_.Name -match '(?i)(setup|installer|install)' -and $_.Name -notmatch '(?i)(uninstall|unins|remove)'})
        if($preferred.Count -eq 1){$candidates=$preferred}
    }
    if($candidates.Count -ne 1){return ''}
    Assert-HuInstallerPublisher -Path $candidates[0].FullName -Item $Item
    return $candidates[0].FullName
}

function Register-HuDownloadedCatalogArtifact {
    param([Parameter(Mandatory=$true)][object]$Item,[Parameter(Mandatory=$true)][string]$Path,[string]$Version='')
    $installer=''
    if(Test-HuInstallableArtifact $Path){$installer=$Path}
    elseif([IO.Path]::GetExtension($Path).Equals('.zip',[StringComparison]::OrdinalIgnoreCase)){$installer=Expand-HuDownloadedInstallerArchive -Path $Path -Item $Item}
    if(-not[string]::IsNullOrWhiteSpace($installer)){Save-HuDownloadedInstallerEntry -Id ([string]$Item.Id) -Path $installer -Version $Version}
    return $installer
}

function Get-HuDownloadedCatalogInstallerPath {
    param([Parameter(Mandatory=$true)][string]$Id)
    $root=[IO.Path]::GetFullPath((Get-HuDownloadsPath)).TrimEnd('\')+'\'
    foreach($entry in @(Get-HuDownloadedInstallerEntries|Where-Object{[string]$_.Id -eq $Id}|Sort-Object SavedAt -Descending)){
        try{
            $path=[IO.Path]::GetFullPath([string]$entry.Path);$extension=[IO.Path]::GetExtension($path).ToLowerInvariant()
            if($path.StartsWith($root,[StringComparison]::OrdinalIgnoreCase) -and $extension -in @('.exe','.msi','.msix','.msixbundle','.appx','.appxbundle','.appinstaller') -and (Test-Path -LiteralPath $path -PathType Leaf)){return $path}
        }catch{}
    }
    return ''
}

function Start-HuDownloadedCatalogInstaller {
    param([Parameter(Mandatory=$true)][string]$Id)
    $path=Get-HuDownloadedCatalogInstallerPath -Id $Id
    if([string]::IsNullOrWhiteSpace($path)){throw 'DOWNLOADED_INSTALLER_UNAVAILABLE'}
    if([IO.Path]::GetExtension($path).Equals('.msi',[StringComparison]::OrdinalIgnoreCase)){
        Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\msiexec.exe') -ArgumentList @('/i',('"{0}"' -f $path))|Out-Null
    }else{Start-Process -FilePath $path|Out-Null}
    return $path
}

function New-HuCatalogItem {
    param(
        [string]$Id,[string]$Area,[string]$Group,[string]$Name,[string]$DescriptionKey,
        [string]$Provider='Unavailable',[string]$Repository='',[string]$AssetPattern='',
        [string]$DirectUrl='',[string]$OfficialUrl='',[string]$GitHubUrl='',
        [string]$StoreUrl='',[string]$StoreProductId='',[string]$FtpUrl='',
        [string]$MetadataUrl='',[string]$LinkPattern='',[bool]$DownloadOnlyButton=$false,
        [string]$ExpectedPublisher='',[string]$FallbackPattern='',[string]$PackageId=''
    )
    [pscustomobject]@{
        Id=$Id; Area=$Area; Group=$Group; Name=$Name; DescriptionKey=$DescriptionKey
        Provider=$Provider; Repository=$Repository; AssetPattern=$AssetPattern
        DirectUrl=$DirectUrl; OfficialUrl=$OfficialUrl; GitHubUrl=$GitHubUrl
        StoreUrl=$StoreUrl; StoreProductId=$StoreProductId; FtpUrl=$FtpUrl
        MetadataUrl=$MetadataUrl; LinkPattern=$LinkPattern; DownloadOnlyButton=$DownloadOnlyButton
        ExpectedPublisher=$ExpectedPublisher; FallbackPattern=$FallbackPattern; PackageId=$PackageId
    }
}

function Get-HuSoftwareCatalog {
    @(
        New-HuCatalogItem -Id steam -Area Games -Group Launcher -Name 'Steam' -DescriptionKey CatalogLauncherDescription -Provider OfficialCurrent -DirectUrl 'https://cdn.akamai.steamstatic.com/client/installer/SteamSetup.exe' -OfficialUrl 'https://store.steampowered.com/about/' -ExpectedPublisher 'Valve'
        New-HuCatalogItem -Id gog -Area Games -Group Launcher -Name 'GOG Galaxy' -DescriptionKey CatalogLauncherDescription -Provider OfficialCurrent -DirectUrl 'https://webinstallers.gog-statics.com/download/GOG_Galaxy_2.0.exe' -OfficialUrl 'https://www.gog.com/galaxy' -ExpectedPublisher 'GOG'
        New-HuCatalogItem epic Games Launcher 'Epic Games Launcher' CatalogLauncherDescription OfficialRedirect '' '' 'https://launcher-public-service-prod06.ol.epicgames.com/launcher/api/installer/download/EpicGamesLauncherInstaller.msi' 'https://store.epicgames.com/download/'
        New-HuCatalogItem -Id ea -Area Games -Group Launcher -Name 'EA App' -DescriptionKey CatalogLauncherDescription -Provider OfficialCurrent -DirectUrl 'https://origin-a.akamaihd.net/EA-Desktop-Client-Download/installer-releases/EAappInstaller.exe' -OfficialUrl 'https://www.ea.com/ea-app' -ExpectedPublisher 'Electronic Arts'
        New-HuCatalogItem -Id battlenet -Area Games -Group Launcher -Name 'Battle.net' -DescriptionKey CatalogLauncherDescription -Provider OfficialCurrent -DirectUrl 'https://downloader.battle.net/download/getInstallerForGame?os=win&gameProgram=BATTLENET_APP&version=Live' -OfficialUrl 'https://download.battle.net/en-us/desktop' -ExpectedPublisher 'Blizzard Entertainment'
        New-HuCatalogItem playnite Games Launcher 'Playnite' CatalogLauncherDescription GitHubRelease 'JosefNemec/Playnite' '(?i)Playnite.*\.exe$' '' 'https://playnite.link/' 'https://github.com/JosefNemec/Playnite'
        New-HuCatalogItem -Id amazon -Area Games -Group Launcher -Name 'Amazon Games' -DescriptionKey CatalogLauncherDescription -Provider OfficialCurrent -DirectUrl 'https://download.amazongames.com/AmazonGamesSetup.exe' -OfficialUrl 'https://www.amazongames.com/' -ExpectedPublisher 'Amazon'
        New-HuCatalogItem discord Games Launcher 'Discord' CatalogLauncherDescription DiscordLatest '' '' 'https://discord.com/api/downloads/distributions/app/installers/latest?channel=stable&platform=win&arch=x64' 'https://discord.com/download'
        New-HuCatalogItem -Id afterburner -Area Games -Group Launcher -Name 'MSI Afterburner' -DescriptionKey CatalogLauncherDescription -Provider RenderedPageResolver -OfficialUrl 'https://www.msi.com/Landing/afterburner/graphics-cards' -MetadataUrl 'https://www.msi.com/Landing/afterburner/graphics-cards' -LinkPattern '(?i)(?<url>(?:(?:https?:)?//|/)[^"''<> ]*MSIAfterburner[^"''<> ]*\.zip(?:\?[^"''<> ]*)?)' -DownloadOnlyButton $true -ExpectedPublisher 'MICRO-STAR|MSI'
        New-HuCatalogItem -Id xbox -Area Games -Group Launcher -Name 'Xbox App' -DescriptionKey CatalogLauncherDescription -Provider OfficialCurrent -DirectUrl 'https://aka.ms/XboxInstaller' -OfficialUrl 'https://www.xbox.com/apps/xbox-app-for-pc' -StoreUrl 'https://apps.microsoft.com/detail/9mv0b5hzvk9z' -StoreProductId '9MV0B5HZVK9Z' -ExpectedPublisher 'Microsoft'

        New-HuCatalogItem notepadpp Applications App 'Notepad++' AppDescriptionNotepad GitHubRelease 'notepad-plus-plus/notepad-plus-plus' '(?i)npp\..*\.Installer\.x64\.exe$' '' 'https://notepad-plus-plus.org/downloads/' 'https://github.com/notepad-plus-plus/notepad-plus-plus'
        New-HuCatalogItem sharex Applications App 'ShareX' AppDescriptionShareX GitHubRelease 'ShareX/ShareX' '(?i)ShareX-.*-setup(?:-x64)?\.exe$' '' 'https://getsharex.com/' 'https://github.com/ShareX/ShareX'
        New-HuCatalogItem -Id jdownloader -Area Applications -Group App -Name 'JDownloader' -DescriptionKey AppDescriptionJDownloader -Provider MegaResolver -DirectUrl 'https://mega.nz/file/WUlnQbQY#cAmkTc5V83obAZj28TA61VlmiwuukicBrupXgczkgMs' -OfficialUrl 'https://jdownloader.org/download/index' -MetadataUrl 'https://jdownloader.org/jdownloader2#selection=windows' -LinkPattern '(?i)https://mega\.nz/file/[A-Za-z0-9_-]+#[A-Za-z0-9_-]+' -DownloadOnlyButton $false -ExpectedPublisher 'Appwork GmbH'
        New-HuCatalogItem -Id mpcbe -Area Applications -Group App -Name 'MPC-BE x64' -DescriptionKey AppDescriptionMpcBe -Provider GitHubRelease -Repository 'Aleksoid1978/MPC-BE' -AssetPattern '(?i)^MPC-BE\..*\.x64-installer\.zip$' -GitHubUrl 'https://github.com/Aleksoid1978/MPC-BE' -StoreUrl 'https://apps.microsoft.com/detail/9pd88qb3bgkn' -StoreProductId '9PD88QB3BGKN' -DownloadOnlyButton $false
        New-HuCatalogItem -Id eartrumpet -Area Applications -Group App -Name 'EarTrumpet' -DescriptionKey AppDescriptionEarTrumpet -Provider WingetManifest -OfficialUrl 'https://eartrumpet.app/' -GitHubUrl 'https://github.com/file-new-project/eartrumpet' -StoreUrl 'https://apps.microsoft.com/detail/9nblggh516xp' -StoreProductId '9NBLGGH516XP' -MetadataUrl 'https://api.github.com/repos/microsoft/winget-pkgs/contents/manifests/f/File-New-Project/EarTrumpet' -PackageId 'File-New-Project.EarTrumpet'
        New-HuCatalogItem appgroup Applications App 'AppGroup' AppDescriptionAppGroup GitHubRelease 'iandiv/AppGroup' '(?i)^AppGroup_.*\.win-x64-Bundled-Setup\.exe$' '' '' 'https://github.com/iandiv/AppGroup'
        New-HuCatalogItem nvcpl Applications App 'NVIDIA Control Panel' AppDescriptionNvidia Unavailable '' '' '' '' '' 'https://apps.microsoft.com/detail/9nf8h0h7wmlt' '9NF8H0H7WMLT'
        New-HuCatalogItem dolby Applications App 'Dolby Access' AppDescriptionDolby Unavailable '' '' '' '' '' 'https://apps.microsoft.com/detail/9n0866fs04w8' '9N0866FS04W8'
        New-HuCatalogItem mica Applications App 'Mica For Everyone' AppDescriptionMica GitHubRelease 'MicaForEveryone/MicaForEveryone' '(?i)^MicaForEveryone\.appinstaller$' '' '' 'https://github.com/MicaForEveryone/MicaForEveryone' 'https://apps.microsoft.com/detail/9p8v68p4z78p' '9P8V68P4Z78P'
        New-HuCatalogItem -Id firefox -Area Applications -Group App -Name 'Firefox' -DescriptionKey AppDescriptionFirefox -Provider MozillaFirefox -DirectUrl 'https://download.mozilla.org/?product=firefox-latest-ssl&os=win64&lang={locale}' -OfficialUrl 'https://www.firefox.com/{locale}/download/windows/' -GitHubUrl 'https://github.com/mozilla-firefox/firefox' -StoreUrl 'https://apps.microsoft.com/detail/9nzvdkpmr9rd' -StoreProductId '9NZVDKPMR9RD' -FtpUrl 'https://ftp.mozilla.org/pub/firefox/releases/' -MetadataUrl 'https://product-details.mozilla.org/1.0/firefox_versions.json'

        New-HuCatalogItem -Id icue -Area Applications -Group Manufacturer -Name 'Corsair iCUE' -DescriptionKey ManufacturerDescription -Provider OfficialCurrent -DirectUrl 'https://www3.corsair.com/software/CUE_V5/public/modules/windows/installer/Install%20iCUE.exe' -OfficialUrl 'https://www.corsair.com/us/en/s/downloads' -DownloadOnlyButton $true -ExpectedPublisher 'Corsair'
        New-HuCatalogItem -Id armoury -Area Applications -Group Manufacturer -Name 'ASUS Armoury Crate' -DescriptionKey ManufacturerDescription -Provider AsusSupportApi -OfficialUrl 'https://www.asus.com/supportonly/armoury%20crate/helpdesk_download/' -MetadataUrl 'https://www.asus.com/support/webapi/ProductV2/GetPDDrivers?website=global&model=armoury%20crate&pdhashedid=&pdid=99999&cpu=&osid=52&siteID=www&sitelang=' -LinkPattern '(?i)(?<url>(?:https://dlcdnets\.asus\.com)?/pub/ASUS/[^"''<> ]*ArmouryCrateInstallTool\.zip(?:\?[^"''<> ]*)?)' -DownloadOnlyButton $true
        New-HuCatalogItem -Id msicenter -Area Applications -Group Manufacturer -Name 'MSI Center' -DescriptionKey ManufacturerDescription -Provider OfficialCurrent -DirectUrl 'https://download.msi.com/uti_exe/desktop/MSI-Center.zip' -OfficialUrl 'https://www.msi.com/Landing/MSI-Center' -DownloadOnlyButton $true
        New-HuCatalogItem -Id gigabyte -Area Applications -Group Manufacturer -Name 'Gigabyte Control Center' -DescriptionKey ManufacturerDescription -Provider GigabyteApi -OfficialUrl 'https://www.gigabyte.com/Support/Utility?kw=GIGABYTE+Control+Center&p=1' -MetadataUrl 'https://www.gigabyte.com/Ajax/SupportFunction/GetUtilityAjax' -LinkPattern '(?i)(?<url>(?:(?:https?:)?//|/)[^"''<> ]*(?:GCC|Gigabyte.Control.Center)[^"''<> ]*\.zip(?:\?[^"''<> ]*)?)' -DownloadOnlyButton $true
        New-HuCatalogItem -Id razer -Area Applications -Group Manufacturer -Name 'Razer Synapse' -DescriptionKey ManufacturerDescription -Provider OfficialCurrent -DirectUrl 'https://rzr.to/synapse-4-pc-download' -OfficialUrl 'https://www.razer.com/synapse-4' -DownloadOnlyButton $true -ExpectedPublisher 'Razer'
        New-HuCatalogItem -Id lghub -Area Applications -Group Manufacturer -Name 'Logitech G HUB' -DescriptionKey ManufacturerDescription -Provider OfficialCurrent -DirectUrl 'https://download01.logi.com/web/ftp/pub/techsupport/gaming/lghub_installer.exe' -OfficialUrl 'https://www.logitechg.com/en-us/software/ghub' -DownloadOnlyButton $true -ExpectedPublisher 'Logitech'
        New-HuCatalogItem -Id nzxt -Area Applications -Group Manufacturer -Name 'NZXT CAM' -DescriptionKey ManufacturerDescription -Provider OfficialCurrent -DirectUrl 'https://nzxt-app.nzxt.com/NZXT-CAM-Setup.exe' -OfficialUrl 'https://nzxt.com/pages/cam' -DownloadOnlyButton $true -ExpectedPublisher 'NZXT'
        New-HuCatalogItem -Id masterctrl -Area Applications -Group Manufacturer -Name 'Cooler Master MasterCTRL' -DescriptionKey ManufacturerDescription -Provider OfficialPageResolver -OfficialUrl 'https://www.coolermaster.com/en-global/masterctrl.html' -MetadataUrl 'https://www.coolermaster.com/en-global/masterctrl.html' -LinkPattern '(?i)(?<url>https://linkto\.cm/masterctrl-[0-9]+)' -DownloadOnlyButton $true
        New-HuCatalogItem -Id ttrgb -Area Applications -Group Manufacturer -Name 'Thermaltake TT RGB Plus' -DescriptionKey ManufacturerDescription -Provider RenderedPageResolver -OfficialUrl 'https://www.thermaltake.com/downloads' -MetadataUrl 'https://www.thermaltake.com/downloads' -LinkPattern '(?i)(?<url>https://bit\.ly/TTRGBPlusV[0-9]+)' -DownloadOnlyButton $true
        New-HuCatalogItem -Id lconnect -Area Applications -Group Manufacturer -Name 'Lian Li L-Connect 3' -DescriptionKey ManufacturerDescription -Provider RenderedPageResolver -OfficialUrl 'https://lian-li.com/l-connect3/' -MetadataUrl 'https://lian-li.com/l-connect3/' -LinkPattern '(?i)(?<url>https://lianli-update-20[0-9]{2}\.lianli-cn\.com/[^"''<> ]+L-Connect[^"''<> ]+\.exe)' -FallbackPattern '(?i)(?<url>https://cdn-update-20[0-9]{2}\.lianhaomaoyi\.cn/[^"''<> ]+L-Connect[^"''<> ]+\.exe)' -DownloadOnlyButton $true
        New-HuCatalogItem -Id steelseries -Area Applications -Group Manufacturer -Name 'SteelSeries GG' -DescriptionKey ManufacturerDescription -Provider OfficialRedirect -DirectUrl 'https://steelseries.com/gg/downloads/gg/latest/windows' -OfficialUrl 'https://steelseries.com/gg' -DownloadOnlyButton $true
        New-HuCatalogItem -Id hyperx -Area Applications -Group Manufacturer -Name 'HyperX NGENUITY' -DescriptionKey ManufacturerDescription -Provider OfficialPageResolver -OfficialUrl 'https://hyperx.com/pages/ngenuity' -MetadataUrl 'https://hyperx.com/pages/ngenuity' -LinkPattern '(?i)(?<url>https://files\.hyperx\.com/software-installers/ngenuity/stable/[^/"''<> ]+/HyperX_NGENUITY_Installer\.exe)' -DownloadOnlyButton $true -ExpectedPublisher 'HP|HyperX'
        New-HuCatalogItem -Id alienware -Area Applications -Group Manufacturer -Name 'Alienware Command Center' -DescriptionKey ManufacturerDescription -Provider Unavailable -OfficialUrl 'https://www.dell.com/support/kbdoc/000179513/alienware-command-center-quick-guide'

        New-HuCatalogItem -Id mpvci -Area Applications -Group Misc -Name 'MultiPack Visual C++ Installer' -DescriptionKey RedistributableVcppDescription -Provider OfficialPageAsset -OfficialUrl 'https://mpvci.co.uk/' -MetadataUrl 'https://mpvci.co.uk/' -LinkPattern '(?i)https://mpvci\.b-cdn\.net/MPVCI_[0-9.]+_setup\.exe' -DownloadOnlyButton $true
        New-HuCatalogItem -Id mpdni -Area Applications -Group Misc -Name 'MultiPack .NET Windows Desktop Installer' -DescriptionKey RedistributableDotNetDescription -Provider OfficialPageAsset -OfficialUrl 'https://mpdni.co.uk/' -MetadataUrl 'https://mpdni.co.uk/' -LinkPattern '(?i)https://mpdni\.b-cdn\.net/MPDNI_[0-9.]+_setup\.exe' -DownloadOnlyButton $true
    )
}

function Get-HuCatalogItem {
    param([Parameter(Mandatory=$true)][string]$Id)
    return Get-HuSoftwareCatalog | Where-Object Id -EQ $Id | Select-Object -First 1
}

function Send-HuInstallerEvent {
    param([object]$ProgressQueue,[string]$Kind,[string]$Stage,[string]$Level='Normal',[hashtable]$Data=@{})
    if (-not $ProgressQueue) { return }
    $payload = [ordered]@{ Kind=$Kind; Stage=$Stage; Level=$Level; Timestamp=(Get-Date).ToString('HH:mm:ss') }
    foreach ($key in $Data.Keys) { $payload[$key] = $Data[$key] }
    $ProgressQueue.Enqueue([pscustomobject]$payload)
}

function New-HuInstallerHttpClient {
    param([switch]$RawContent)
    $handler = [Net.Http.HttpClientHandler]::new()
    $handler.AllowAutoRedirect = $true
    $handler.MaxAutomaticRedirections = 10
    $handler.AutomaticDecompression = if($RawContent){[Net.DecompressionMethods]::None}else{[Net.DecompressionMethods]::GZip -bor [Net.DecompressionMethods]::Deflate}
    $client = [Net.Http.HttpClient]::new($handler)
    $client.Timeout = [TimeSpan]::FromMinutes(15)
    $client.DefaultRequestHeaders.UserAgent.ParseAdd('Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36 WNST/1.0')
    $client.DefaultRequestHeaders.Accept.ParseAdd('*/*')
    $client.DefaultRequestHeaders.AcceptLanguage.ParseAdd('en-US,en;q=0.9')
    $client.DefaultRequestHeaders.TryAddWithoutValidation('Sec-Fetch-Dest','document')|Out-Null
    $client.DefaultRequestHeaders.TryAddWithoutValidation('Sec-Fetch-Mode','navigate')|Out-Null
    $client.DefaultRequestHeaders.TryAddWithoutValidation('Sec-Fetch-Site','none')|Out-Null
    return $client
}

function Get-HuMozillaLocale {
    param([string]$Language)
    $map=@{
        'ar-SA'='ar';'bg-BG'='bg';'cs-CZ'='cs';'da-DK'='da';'de-DE'='de';'el-GR'='el';'en-US'='en-US';
        'es-419'='es-MX';'es-ES'='es-ES';'fi-FI'='fi';'fr-FR'='fr';'hu-HU'='hu';'id-ID'='id';'it-IT'='it';
        'ja-JP'='ja';'ko-KR'='ko';'ms-MY'='ms';'nb-NO'='nb-NO';'nl-NL'='nl';'pl-PL'='pl';'pt-BR'='pt-BR';
        'pt-PT'='pt-PT';'ro-RO'='ro';'ru-RU'='ru';'sv-SE'='sv-SE';'th-TH'='th';'tr-TR'='tr';'uk-UA'='uk';
        'vi-VN'='vi';'zh-CN'='zh-CN';'zh-TW'='zh-TW'
    }
    if ([string]::IsNullOrWhiteSpace($Language)) { $Language=[Globalization.CultureInfo]::CurrentUICulture.Name }
    if ($map.ContainsKey($Language)) { return [string]$map[$Language] }
    return 'en-US'
}

function Get-HuLocalizedCatalogUrl {
    param([string]$Url,[string]$Language)
    if ([string]::IsNullOrWhiteSpace($Url)) { return '' }
    return $Url.Replace('{locale}',(Get-HuMozillaLocale -Language $Language))
}

function Get-HuInstallerRemoteText {
    param([Parameter(Mandatory=$true)][string]$Url)
    $client=New-HuInstallerHttpClient
    try { return $client.GetStringAsync($Url).GetAwaiter().GetResult() }
    finally { $client.Dispose() }
}

function Get-HuInstallerRemoteFormText {
    param([Parameter(Mandatory=$true)][string]$Url,[Parameter(Mandatory=$true)][Collections.Generic.Dictionary[string,string]]$Fields,[string]$Referrer='')
    $client=New-HuInstallerHttpClient
    try{
        $request=[Net.Http.HttpRequestMessage]::new([Net.Http.HttpMethod]::Post,$Url)
        try{
            if(-not[string]::IsNullOrWhiteSpace($Referrer)){$request.Headers.Referrer=[Uri]$Referrer}
            $request.Headers.TryAddWithoutValidation('X-Requested-With','XMLHttpRequest')|Out-Null
            $request.Content=[Net.Http.FormUrlEncodedContent]::new($Fields)
            $response=$client.SendAsync($request).GetAwaiter().GetResult()
            try{$response.EnsureSuccessStatusCode()|Out-Null;return $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()}
            finally{$response.Dispose()}
        }finally{$request.Dispose()}
    }finally{$client.Dispose()}
}

function Get-HuEdgeExecutable {
    $candidates=New-Object 'System.Collections.Generic.List[string]'
    foreach($root in @(${env:ProgramFiles(x86)},$env:ProgramFiles,$env:LOCALAPPDATA)){
        if(-not[string]::IsNullOrWhiteSpace([string]$root)){$candidates.Add((Join-Path $root 'Microsoft\Edge\Application\msedge.exe'))}
    }
    try{$command=Get-Command msedge.exe -ErrorAction Stop;if($command.Source){$candidates.Add([string]$command.Source)}}catch{}
    foreach($candidate in $candidates|Select-Object -Unique){if(Test-Path -LiteralPath $candidate -PathType Leaf){return $candidate}}
    return ''
}

function Get-HuInstallerRenderedText {
    param([Parameter(Mandatory=$true)][string]$Url)
    $edge=Get-HuEdgeExecutable
    if([string]::IsNullOrWhiteSpace($edge)){throw 'RENDERED_PAGE_UNAVAILABLE'}
    $temporaryRoot=Join-Path ([IO.Path]::GetTempPath()) ('WNST-Resolver-'+[Guid]::NewGuid().ToString('N'))
    $outputPath=Join-Path $temporaryRoot 'page.html';$errorPath=Join-Path $temporaryRoot 'edge.log';New-Item -ItemType Directory -Path $temporaryRoot -Force|Out-Null
    try{
        $arguments=@('--headless=new','--disable-gpu','--disable-extensions','--no-first-run','--disable-background-networking',('--user-data-dir="{0}"' -f $temporaryRoot),'--dump-dom',('"{0}"' -f $Url.Replace('"','')))
        $process=Start-Process -FilePath $edge -ArgumentList $arguments -WindowStyle Hidden -PassThru -RedirectStandardOutput $outputPath -RedirectStandardError $errorPath
        if(-not$process.WaitForExit(45000)){try{$process.Kill()}catch{};throw 'RENDERED_PAGE_TIMEOUT'}
        if($process.ExitCode -ne 0 -or -not(Test-Path -LiteralPath $outputPath -PathType Leaf)){throw 'RENDERED_PAGE_UNAVAILABLE'}
        $html=[IO.File]::ReadAllText($outputPath)
        if([string]::IsNullOrWhiteSpace($html)){throw 'RENDERED_PAGE_UNAVAILABLE'}
        return $html
    }finally{if(Test-Path -LiteralPath $temporaryRoot){Remove-Item -LiteralPath $temporaryRoot -Recurse -Force -ErrorAction SilentlyContinue}}
}

function ConvertFrom-HuBase64Url {
    param([Parameter(Mandatory=$true)][string]$Value)
    $text=$Value.Replace('-','+').Replace('_','/')
    while(($text.Length % 4) -ne 0){$text+='='}
    return [Convert]::FromBase64String($text)
}

function Get-HuRemoteFileMetadata {
    param([Parameter(Mandatory=$true)][string]$Url,[string]$Source='Official download page',[string]$VersionHint='',[string]$DefaultFileName='')
    $client=New-HuInstallerHttpClient
    try {
        $request=[Net.Http.HttpRequestMessage]::new([Net.Http.HttpMethod]::Get,$Url)
        $response=$client.SendAsync($request,[Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
        try {
            $response.EnsureSuccessStatusCode()|Out-Null
            $finalUrl=[string]$response.RequestMessage.RequestUri.AbsoluteUri
            if(-not([Uri]$finalUrl).Scheme.Equals('https',[StringComparison]::OrdinalIgnoreCase)){throw 'INSECURE_DOWNLOAD_URL'}
            $fileName=''
            if($response.Content.Headers.ContentDisposition){
                if($response.Content.Headers.ContentDisposition.FileNameStar){$fileName=[Uri]::UnescapeDataString(([string]$response.Content.Headers.ContentDisposition.FileNameStar).Trim('"'))}
                elseif($response.Content.Headers.ContentDisposition.FileName){$fileName=([string]$response.Content.Headers.ContentDisposition.FileName).Trim('"')}
            }
            if([string]::IsNullOrWhiteSpace($fileName)){$fileName=[Uri]::UnescapeDataString([IO.Path]::GetFileName(([Uri]$finalUrl).LocalPath))}
            if([string]::IsNullOrWhiteSpace([IO.Path]::GetExtension($fileName))){
                if(-not[string]::IsNullOrWhiteSpace($DefaultFileName)){$fileName=$DefaultFileName}
                else{
                    $mediaType=if($response.Content.Headers.ContentType){[string]$response.Content.Headers.ContentType.MediaType}else{''}
                    if($mediaType -match '(?i)(zip|compressed)'){$fileName='Official_Installer.zip'}
                    elseif($mediaType -match '(?i)(msdownload|octet-stream)'){$fileName='Official_Installer.exe'}
                }
            }
            if([string]::IsNullOrWhiteSpace($fileName)){throw 'INVALID_INSTALLER_NAME'}
            $version=[string]$VersionHint
            if([string]::IsNullOrWhiteSpace($version)){
                $match=[regex]::Match(($finalUrl+' '+$fileName),'(?<!\d)(\d+\.\d+(?:\.\d+){0,3})(?!\d)')
                $version=if($match.Success){$match.Groups[1].Value}else{'current'}
            }
            $expectedSize=if($response.Content.Headers.ContentLength){[long]$response.Content.Headers.ContentLength}else{[long]0}
            return [pscustomobject]@{Version=$version;Url=$finalUrl;FileName=$fileName;Source=$Source;ExpectedSize=$expectedSize}
        } finally {$response.Dispose();$request.Dispose()}
    } finally {$client.Dispose()}
}

function Get-HuOfficialPageLinks {
    param([Parameter(Mandatory=$true)][string]$Html,[Parameter(Mandatory=$true)][string]$Pattern,[Parameter(Mandatory=$true)][string]$BaseUrl)
    $decoded=[Net.WebUtility]::HtmlDecode([string]$Html).Replace('\/','/').Replace('\u002F','/').Replace('\u002f','/').Replace('\u003A',':').Replace('\u003a',':').Replace('\u0026','&').Replace('\u003D','=').Replace('\u003d','=')
    $result=New-Object 'System.Collections.Generic.List[string]'
    foreach($match in [regex]::Matches($decoded,$Pattern)){
        $candidate=if($match.Groups['url'] -and $match.Groups['url'].Success){$match.Groups['url'].Value}else{$match.Value}
        $candidate=[Net.WebUtility]::HtmlDecode([string]$candidate).Trim('"','''',' ')
        if($candidate.StartsWith('//')){$candidate='https:'+$candidate}
        elseif(-not[Uri]::IsWellFormedUriString($candidate,[UriKind]::Absolute)){$candidate=[Uri]::new([Uri]$BaseUrl,$candidate).AbsoluteUri}
        if(([Uri]$candidate).Scheme -eq 'https' -and -not $result.Contains($candidate)){$result.Add($candidate)}
    }
    return @($result)
}

function Resolve-HuMegaPublicFile {
    param([Parameter(Mandatory=$true)][string]$Url)
    $match=[regex]::Match($Url,'(?i)mega\.nz/file/(?<handle>[A-Za-z0-9_-]+)#(?<key>[A-Za-z0-9_-]+)')
    if(-not $match.Success){throw 'LATEST_VERSION_UNAVAILABLE'}
    $keyMaterial=ConvertFrom-HuBase64Url $match.Groups['key'].Value
    if($keyMaterial.Length -ne 32){throw 'LATEST_VERSION_UNAVAILABLE'}
    $aesKey=New-Object byte[] 16
    for($i=0;$i -lt 16;$i++){$aesKey[$i]=$keyMaterial[$i] -bxor $keyMaterial[$i+16]}
    $iv=New-Object byte[] 16;[Array]::Copy($keyMaterial,16,$iv,0,8)
    $payload=ConvertTo-Json -InputObject @([ordered]@{a='g';g=1;p=$match.Groups['handle'].Value}) -Compress
    $client=New-HuInstallerHttpClient
    try {
        $content=[Net.Http.StringContent]::new($payload,[Text.Encoding]::UTF8,'application/json')
        try{$response=$client.PostAsync(('https://g.api.mega.co.nz/cs?id='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()),$content).GetAwaiter().GetResult()}
        finally{$content.Dispose()}
        try{$response.EnsureSuccessStatusCode()|Out-Null;$json=$response.Content.ReadAsStringAsync().GetAwaiter().GetResult()|ConvertFrom-Json}
        finally{$response.Dispose()}
    } finally {$client.Dispose()}
    $entry=@($json)[0]
    if(-not $entry -or [string]::IsNullOrWhiteSpace([string]$entry.g)){throw 'LATEST_VERSION_UNAVAILABLE'}
    $attributes=ConvertFrom-HuBase64Url ([string]$entry.at)
    $aes=[Security.Cryptography.Aes]::Create();$aes.Mode=[Security.Cryptography.CipherMode]::CBC;$aes.Padding=[Security.Cryptography.PaddingMode]::Zeros;$aes.Key=$aesKey;$aes.IV=(New-Object byte[] 16)
    try{$decryptor=$aes.CreateDecryptor();try{$plain=$decryptor.TransformFinalBlock($attributes,0,$attributes.Length)}finally{$decryptor.Dispose()}}
    finally{$aes.Dispose()}
    $attributeText=[Text.Encoding]::UTF8.GetString($plain).Trim([char]0)
    if(-not $attributeText.StartsWith('MEGA')){throw 'LATEST_VERSION_UNAVAILABLE'}
    $metadata=$attributeText.Substring(4)|ConvertFrom-Json
    $fileName=[string]$metadata.n
    if([string]::IsNullOrWhiteSpace($fileName)){throw 'INVALID_INSTALLER_NAME'}
    $downloadUri=[Uri][string]$entry.g
    if($downloadUri.Scheme.Equals('http',[StringComparison]::OrdinalIgnoreCase) -and $downloadUri.Host -match '(?i)(^|\.)mega\.(?:co\.)?nz$'){
        $builder=[UriBuilder]$downloadUri;$builder.Scheme='https';$builder.Port=-1;$downloadUri=$builder.Uri
    }
    if(-not$downloadUri.Scheme.Equals('https',[StringComparison]::OrdinalIgnoreCase)){throw 'INSECURE_DOWNLOAD_URL'}
    return [pscustomobject]@{Version='current';Url=$downloadUri.AbsoluteUri;FileName=$fileName;Source='JDownloader official MEGA file';ExpectedSize=[long]$entry.s;MegaKey=$aesKey;MegaIv=$iv}
}

function Write-HuMegaDecryptedStream {
    param([Parameter(Mandatory=$true)][IO.Stream]$SourceStream,[Parameter(Mandatory=$true)][IO.Stream]$DestinationStream,[Parameter(Mandatory=$true)][byte[]]$Key,[Parameter(Mandatory=$true)][byte[]]$CounterIv,[long]$Total,[object]$ProgressQueue,[string]$Name)
    $aes=[Security.Cryptography.Aes]::Create();$aes.Mode=[Security.Cryptography.CipherMode]::ECB;$aes.Padding=[Security.Cryptography.PaddingMode]::None;$aes.Key=$Key
    $encryptor=$aes.CreateEncryptor();$counter=New-Object byte[] 16;[Array]::Copy($CounterIv,$counter,16)
    try{
        $buffer=New-Object byte[] 131072;$readTotal=[long]0;$watch=[Diagnostics.Stopwatch]::StartNew();$lastReport=[long]0;$carry=New-Object byte[] 16;$carryOffset=16
        while(($read=$SourceStream.Read($buffer,0,$buffer.Length)) -gt 0){
            $position=0
            if($carryOffset -lt 16){
                $count=[Math]::Min($read,16-$carryOffset)
                for($i=0;$i -lt $count;$i++){$buffer[$i]=$buffer[$i] -bxor $carry[$carryOffset+$i]}
                $carryOffset+=$count;$position+=$count
            }
            $fullBytes=[int]([Math]::Floor(($read-$position)/16.0)*16)
            if($fullBytes -gt 0){
                $counterInput=New-Object byte[] $fullBytes
                for($block=0;$block -lt ($fullBytes/16);$block++){
                    [Array]::Copy($counter,0,$counterInput,$block*16,16)
                    for($i=15;$i -ge 8;$i--){$next=(([int]$counter[$i]+1) -band 0xff);$counter[$i]=[byte]$next;if($next -ne 0){break}}
                }
                $keystream=New-Object byte[] $fullBytes;[void]$encryptor.TransformBlock($counterInput,0,$counterInput.Length,$keystream,0)
                for($i=0;$i -lt $fullBytes;$i++){$buffer[$position+$i]=$buffer[$position+$i] -bxor $keystream[$i]}
                $position+=$fullBytes
            }
            if($position -lt $read){
                [void]$encryptor.TransformBlock($counter,0,16,$carry,0)
                for($i=15;$i -ge 8;$i--){$next=(([int]$counter[$i]+1) -band 0xff);$counter[$i]=[byte]$next;if($next -ne 0){break}}
                $count=$read-$position
                for($i=0;$i -lt $count;$i++){$buffer[$position+$i]=$buffer[$position+$i] -bxor $carry[$i]}
                $carryOffset=$count
            }
            $DestinationStream.Write($buffer,0,$read);$readTotal+=$read
            if(($watch.ElapsedMilliseconds-$lastReport)-ge 120){$lastReport=$watch.ElapsedMilliseconds;$percent=if($Total -gt 0){[math]::Min(99,[math]::Round(($readTotal*100.0)/$Total))}else{0};$speed=if($watch.Elapsed.TotalSeconds -gt 0){[long]($readTotal/$watch.Elapsed.TotalSeconds)}else{0};Send-HuInstallerEvent $ProgressQueue Progress Download Normal @{Name=$Name;Percent=$percent;Bytes=$readTotal;Total=$Total;Speed=$speed}}
        }
        if($Total -gt 0 -and $readTotal -ne $Total){throw 'DOWNLOAD_SIZE_MISMATCH'}
        $DestinationStream.Flush()
    } finally {$encryptor.Dispose();$aes.Dispose()}
}

function Resolve-HuLatestInstaller {
    param([Parameter(Mandatory=$true)][object]$Item,[object]$ProgressQueue,[string]$Language='')

    Send-HuInstallerEvent $ProgressQueue Progress Search Normal @{ Name=$Item.Name; Percent=3 }
    Send-HuInstallerEvent $ProgressQueue Log Search Normal @{ Name=$Item.Name }

    if ($Item.Provider -eq 'GitHubRelease') {
        $api = 'https://api.github.com/repos/{0}/releases/latest' -f $Item.Repository
        Send-HuInstallerEvent $ProgressQueue Log Source Normal @{ Source='GitHub Releases'; Url=$api }
        $release = Invoke-RestMethod -Uri $api -Headers @{ 'User-Agent'='WNST/1.0'; 'Accept'='application/vnd.github+json' } -UseBasicParsing -ErrorAction Stop
        $version = ([string]$release.tag_name).Trim()
        if ([string]::IsNullOrWhiteSpace($version)) { throw 'LATEST_VERSION_UNAVAILABLE' }
        Send-HuInstallerEvent $ProgressQueue Log Version Normal @{ Name=$Item.Name; Version=$version }
        $assets = @($release.assets | Where-Object { [string]$_.name -match [string]$Item.AssetPattern })
        if ($assets.Count -ne 1) { throw 'INSTALLABLE_ASSET_UNAVAILABLE' }
        $asset = $assets[0]
        return [pscustomobject]@{ Version=$version; Url=[string]$asset.browser_download_url; FileName=[string]$asset.name; Source='GitHub Releases'; ExpectedSize=[long]$asset.size }
    }

    if($Item.Provider -eq 'WingetManifest'){
        if([string]::IsNullOrWhiteSpace([string]$Item.MetadataUrl)){throw 'LATEST_VERSION_UNAVAILABLE'}
        $headers=@{'User-Agent'='WNST/1.0';'Accept'='application/vnd.github+json'}
        $versions=@()
        try{$versions=@(Invoke-RestMethod -Uri ([string]$Item.MetadataUrl) -Headers $headers -UseBasicParsing -ErrorAction Stop|Where-Object{$_.type -eq 'dir' -and [string]$_.name -match '^\d+(?:\.\d+){1,3}$'}|ForEach-Object{try{[Version]$_.name}catch{}}|Where-Object{$_}|Sort-Object -Descending)}catch{}
        if($versions.Count -eq 0){
            $directoryHtml=Get-HuInstallerRemoteText -Url 'https://github.com/microsoft/winget-pkgs/tree/master/manifests/f/File-New-Project/EarTrumpet'
            $versions=@([regex]::Matches([string]$directoryHtml,'(?i)EarTrumpet(?:/|%2F)(?<version>\d+(?:\.\d+){1,3})')|ForEach-Object{try{[Version]$_.Groups['version'].Value}catch{}}|Where-Object{$_}|Sort-Object -Descending -Unique)
        }
        if($versions.Count -eq 0){throw 'LATEST_VERSION_UNAVAILABLE'}
        $version=[string]$versions[0]
        $manifestUrl=('https://raw.githubusercontent.com/microsoft/winget-pkgs/master/manifests/f/File-New-Project/EarTrumpet/{0}/File-New-Project.EarTrumpet.installer.yaml' -f $version)
        $manifest=Get-HuInstallerRemoteText -Url $manifestUrl
        $urls=@([regex]::Matches([string]$manifest,'(?im)^\s*InstallerUrl:\s*(?<url>https://\S+)\s*$')|ForEach-Object{$_.Groups['url'].Value.Trim()}|Where-Object{$_ -match '(?i)EarTrumpet.+\.(?:appx|appxbundle|msix|msixbundle)(?:\?.*)?$'}|Select-Object -Unique)
        if($urls.Count -ne 1){throw 'INSTALLABLE_ASSET_UNAVAILABLE'}
        $resolved=Get-HuRemoteFileMetadata -Url ([string]$urls[0]) -Source 'WinGet community manifest' -VersionHint $version
        Send-HuInstallerEvent $ProgressQueue Log Source Normal @{Source=$resolved.Source;Url=$manifestUrl}
        Send-HuInstallerEvent $ProgressQueue Log Version Normal @{Name=$Item.Name;Version=$resolved.Version}
        return $resolved
    }

    if($Item.Provider -eq 'MegaResolver'){
        $megaUrl=''
        try{
            if(-not[string]::IsNullOrWhiteSpace([string]$Item.MetadataUrl)){
                $html=Get-HuInstallerRemoteText -Url ([string]$Item.MetadataUrl)
                $match=[regex]::Match([Net.WebUtility]::HtmlDecode([string]$html),[string]$Item.LinkPattern)
                if($match.Success){$megaUrl=$match.Value}
            }
        }catch{}
        if([string]::IsNullOrWhiteSpace($megaUrl)){$megaUrl=[string]$Item.DirectUrl}
        $resolved=Resolve-HuMegaPublicFile -Url $megaUrl
        Send-HuInstallerEvent $ProgressQueue Log Source Normal @{Source='JDownloader official MEGA file';Url=$megaUrl}
        Send-HuInstallerEvent $ProgressQueue Log Version Normal @{Name=$Item.Name;Version=$resolved.Version}
        return $resolved
    }

    if($Item.Provider -eq 'AsusSupportApi'){
        if([string]::IsNullOrWhiteSpace([string]$Item.MetadataUrl)){throw 'LATEST_VERSION_UNAVAILABLE'}
        $html=Get-HuInstallerRemoteText -Url ([string]$Item.MetadataUrl)
        $decoded=[Net.WebUtility]::HtmlDecode([string]$html).Replace('\/','/').Replace('\u002F','/').Replace('\u002f','/')
        $links=@([regex]::Matches($decoded,[string]$Item.LinkPattern)|ForEach-Object{
            $url=if($_.Groups['url'].Success){$_.Groups['url'].Value}else{$_.Value}
            if($url.StartsWith('/pub/',[StringComparison]::OrdinalIgnoreCase)){'https://dlcdnets.asus.com'+$url}else{$url}
        }|Select-Object -Unique)
        if($links.Count -eq 0){throw 'INSTALLABLE_ASSET_UNAVAILABLE'}
        $versionMatch=[regex]::Match($decoded,'(?i)"version"\s*:\s*"(?<version>\d+\.\d+(?:\.\d+){1,2})"')
        $versionHint=if($versionMatch.Success){$versionMatch.Groups['version'].Value}else{''}
        $resolved=$null;$lastError=$null
        foreach($url in $links){try{$resolved=Get-HuRemoteFileMetadata -Url $url -Source 'ASUS Support API' -VersionHint $versionHint -DefaultFileName 'ArmouryCrateInstallTool.zip';break}catch{$lastError=$_}}
        if(-not$resolved){if($lastError){throw $lastError};throw 'INSTALLABLE_ASSET_UNAVAILABLE'}
        Send-HuInstallerEvent $ProgressQueue Log Source Normal @{Source=$resolved.Source;Url=$resolved.Url}
        Send-HuInstallerEvent $ProgressQueue Log Version Normal @{Name=$Item.Name;Version=$resolved.Version}
        return $resolved
    }

    if($Item.Provider -eq 'GigabyteApi'){
        $fields=[Collections.Generic.Dictionary[string,string]]::new();$fields['ClassGroup']='2';$fields['Page']='1';$fields['KeyWord']='GIGABYTE Control Center'
        try{$html=Get-HuInstallerRemoteFormText -Url ([string]$Item.MetadataUrl) -Fields $fields -Referrer ([string]$Item.OfficialUrl)}
        catch{try{$html=Get-HuInstallerRenderedText -Url ([string]$Item.OfficialUrl)}catch{throw 'LATEST_VERSION_UNAVAILABLE'}}
        $links=@(Get-HuOfficialPageLinks -Html $html -Pattern ([string]$Item.LinkPattern) -BaseUrl ([string]$Item.OfficialUrl)|Sort-Object -Property @{Expression={
            $match=[regex]::Match([string]$_,'(?i)GCC_(?<version>\d+(?:\.\d+){3})\.zip')
            if($match.Success){try{[Version]$match.Groups['version'].Value}catch{[Version]'0.0'}}else{[Version]'0.0'}
        };Descending=$true})
        if($links.Count -eq 0){throw 'INSTALLABLE_ASSET_UNAVAILABLE'}
        $selected=[string]$links[0];$versionMatch=[regex]::Match($selected,'(?i)GCC_(?<version>\d+(?:\.\d+){3})\.zip')
        $versionHint=if($versionMatch.Success){$versionMatch.Groups['version'].Value}else{''}
        $resolved=Get-HuRemoteFileMetadata -Url $selected -Source 'GIGABYTE official utility API' -VersionHint $versionHint
        Send-HuInstallerEvent $ProgressQueue Log Source Normal @{Source=$resolved.Source;Url=$resolved.Url}
        Send-HuInstallerEvent $ProgressQueue Log Version Normal @{Name=$Item.Name;Version=$resolved.Version}
        return $resolved
    }

    if($Item.Provider -in @('OfficialPageResolver','RenderedPageResolver')){
        if([string]::IsNullOrWhiteSpace([string]$Item.MetadataUrl) -or [string]::IsNullOrWhiteSpace([string]$Item.LinkPattern)){throw 'LATEST_VERSION_UNAVAILABLE'}
        if($Item.Provider -eq 'RenderedPageResolver'){
            try{$html=Get-HuInstallerRenderedText -Url ([string]$Item.MetadataUrl)}catch{$html=Get-HuInstallerRemoteText -Url ([string]$Item.MetadataUrl)}
        }else{$html=Get-HuInstallerRemoteText -Url ([string]$Item.MetadataUrl)}
        $links=@(Get-HuOfficialPageLinks -Html $html -Pattern ([string]$Item.LinkPattern) -BaseUrl ([string]$Item.MetadataUrl))
        if($Item.Id -eq 'ttrgb' -and $links.Count -eq 0){
            $decoded=[Net.WebUtility]::HtmlDecode([string]$html)
            $versions=@([regex]::Matches($decoded,'(?is)TT\s*RGB\s*PLUS.{0,1600}?(?<version>\d+\.\d+\.\d+)')|ForEach-Object{try{[Version]$_.Groups['version'].Value}catch{}}|Where-Object{$_}|Sort-Object -Descending -Unique)
            if($versions.Count -gt 0){$links=@('https://bit.ly/TTRGBPlusV'+(([string]$versions[0]).Replace('.','')))}
        }
        if($links.Count -eq 0){throw 'INSTALLABLE_ASSET_UNAVAILABLE'}
        switch([string]$Item.Id){
            'afterburner' {$orderedLinks=@($links|Sort-Object -Property @{Expression={$m=[regex]::Match([string]$_,'(?i)MSIAfterburnerSetup(?<build>\d+)');if($m.Success){[int64]$m.Groups['build'].Value}else{[int64]0}};Descending=$true})}
            'masterctrl' {$orderedLinks=@($links|Sort-Object -Property @{Expression={$m=[regex]::Match([string]$_,'masterctrl-(?<build>\d+)');if($m.Success){[int64]$m.Groups['build'].Value}else{[int64]0}};Descending=$true})}
            'ttrgb' {$orderedLinks=@($links|Sort-Object -Property @{Expression={$m=[regex]::Match([string]$_,'V(?<build>\d+)$');if($m.Success){[int64]$m.Groups['build'].Value}else{[int64]0}};Descending=$true})}
            default {$orderedLinks=@($links)}
        }
        $fallbackUrl=''
        if(-not[string]::IsNullOrWhiteSpace([string]$Item.FallbackPattern)){
            $fallbacks=@(Get-HuOfficialPageLinks -Html $html -Pattern ([string]$Item.FallbackPattern) -BaseUrl ([string]$Item.MetadataUrl)|Where-Object{$_ -notin $orderedLinks})
            if($fallbacks.Count -gt 0){$fallbackUrl=[string]$fallbacks[0]}
        }
        $resolved=$null;$lastError=$null
        foreach($url in $orderedLinks){
            $versionHint='';$defaultFileName=''
            if($Item.Id -eq 'afterburner'){$m=[regex]::Match([string]$url,'(?i)MSIAfterburnerSetup(?<build>\d{3})');if($m.Success){$b=$m.Groups['build'].Value;$versionHint=('{0}.{1}.{2}' -f $b.Substring(0,1),$b.Substring(1,1),$b.Substring(2,1))}}
            elseif($Item.Id -eq 'masterctrl'){$m=[regex]::Match([string]$url,'masterctrl-(?<build>\d+)');if($m.Success){$b=$m.Groups['build'].Value;if($b.Length -ge 4){$versionHint=('{0}.{1}.{2}.{3}' -f $b.Substring(0,1),$b.Substring(1,1),$b.Substring(2,1),$b.Substring(3));$defaultFileName=('MasterCTRL_Installer_{0}.zip' -f $b)}}}
            elseif($Item.Id -eq 'ttrgb'){$m=[regex]::Match([string]$url,'V(?<build>\d+)$');if($m.Success){$b=$m.Groups['build'].Value;if($b.Length -eq 3){$versionHint=('{0}.{1}.{2}' -f $b.Substring(0,1),$b.Substring(1,1),$b.Substring(2,1))};$defaultFileName=('TTRGBPLUS_Setup_{0}_x64.zip' -f $b)}}
            try{$resolved=Get-HuRemoteFileMetadata -Url $url -Source 'Official download page' -VersionHint $versionHint -DefaultFileName $defaultFileName;break}catch{$lastError=$_}
        }
        if(-not$resolved -and -not[string]::IsNullOrWhiteSpace($fallbackUrl)){try{$resolved=Get-HuRemoteFileMetadata -Url $fallbackUrl -Source 'Official fallback mirror';$fallbackUrl=''}catch{$lastError=$_}}
        if(-not$resolved){if($lastError){throw $lastError};throw 'INSTALLABLE_ASSET_UNAVAILABLE'}
        $resolved|Add-Member -NotePropertyName FallbackUrl -NotePropertyValue $fallbackUrl -Force
        Send-HuInstallerEvent $ProgressQueue Log Source Normal @{Source=$resolved.Source;Url=$resolved.Url}
        Send-HuInstallerEvent $ProgressQueue Log Version Normal @{Name=$Item.Name;Version=$resolved.Version}
        return $resolved
    }

    if($Item.Provider -eq 'DellResolver'){
        $sources=New-Object 'System.Collections.Generic.List[string]'
        try{$sources.Add((Get-HuInstallerRemoteText -Url ([string]$Item.OfficialUrl)))}catch{}
        foreach($query in @('site:dell.com/support/home "Alienware Command Center 6.x" "Full Installer"','site:dell.com/support/home/drivers "non-Alienware" "Alienware Command Center"')){
            try{$sources.Add((Get-HuInstallerRemoteText -Url ('https://www.bing.com/search?format=rss&q='+[Uri]::EscapeDataString($query))))}catch{}
        }
        $searchText=[Uri]::UnescapeDataString([Net.WebUtility]::HtmlDecode(($sources -join "`n")))
        $driverPages=@([regex]::Matches($searchText,'(?i)https://www\.dell\.com/support/home/(?:[a-z]{2}-[a-z]{2}/)?drivers/(?:driversdetails|DriversDetails)\?driverid=[A-Z0-9]+')|ForEach-Object{$_.Value}|Select-Object -Unique)
        if(-not[string]::IsNullOrWhiteSpace([string]$Item.MetadataUrl) -and [string]$Item.MetadataUrl -notin $driverPages){$driverPages+=([string]$Item.MetadataUrl)}
        $candidates=New-Object 'System.Collections.Generic.List[object]'
        foreach($pageUrl in $driverPages|Select-Object -First 15){
            try{
                $page=Get-HuInstallerRemoteText -Url $pageUrl
                $decoded=[Net.WebUtility]::HtmlDecode([string]$page).Replace('\/','/')
                if($decoded -notmatch '(?i)non-Alienware' -or $decoded -notmatch '(?i)non-Dell\s+G'){continue}
                $direct=[regex]::Match($decoded,'(?i)(?<url>https://(?:dl|downloads)\.dell\.com/(?:FOLDER[^/"''<> ]+/(?:[0-9]+/)?)?Alienware-Command-Center[^"''<> ]+\.exe(?:\?[^"''<> ]*)?)')
                if(-not$direct.Success){continue}
                $fileName=[Uri]::UnescapeDataString([IO.Path]::GetFileName(([Uri]$direct.Groups['url'].Value).LocalPath))
                $versionMatch=[regex]::Match($fileName,'(?i)Full-Installer_[A-Z0-9]+_WIN(?:64)?_(?<version>\d+(?:\.\d+){2,3})_A\d+\.EXE$')
                if(-not$versionMatch.Success){continue}
                $candidates.Add([pscustomobject]@{Version=[Version]$versionMatch.Groups['version'].Value;Url=$direct.Groups['url'].Value})
            }catch{}
        }
        $latest=$candidates|Sort-Object Version -Descending|Select-Object -First 1
        if(-not$latest){throw 'LATEST_VERSION_UNAVAILABLE'}
        $resolved=Get-HuRemoteFileMetadata -Url $latest.Url -Source 'Dell Support generic AWCC package' -VersionHint ([string]$latest.Version)
        Send-HuInstallerEvent $ProgressQueue Log Source Normal @{Source=$resolved.Source;Url=$resolved.Url}
        Send-HuInstallerEvent $ProgressQueue Log Version Normal @{Name=$Item.Name;Version=$resolved.Version}
        return $resolved
    }

    if ($Item.Provider -eq 'OfficialRedirect') {
        if ([string]::IsNullOrWhiteSpace([string]$Item.DirectUrl)) { throw 'LATEST_VERSION_UNAVAILABLE' }
        $client = New-HuInstallerHttpClient
        try {
            $request = [Net.Http.HttpRequestMessage]::new([Net.Http.HttpMethod]::Get,[string]$Item.DirectUrl)
            $response = $client.SendAsync($request,[Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
            try {
                $response.EnsureSuccessStatusCode() | Out-Null
                $finalUrl = [string]$response.RequestMessage.RequestUri.AbsoluteUri
                $fileName = ''
                if ($response.Content.Headers.ContentDisposition -and $response.Content.Headers.ContentDisposition.FileName) {
                    $fileName = ([string]$response.Content.Headers.ContentDisposition.FileName).Trim('"')
                }
                if ([string]::IsNullOrWhiteSpace($fileName)) { $fileName = [IO.Path]::GetFileName(([Uri]$finalUrl).LocalPath) }
                $probe = $finalUrl + ' ' + $fileName
                $match = [regex]::Match($probe,'(?<!\d)(\d+\.\d+(?:\.\d+){0,3})(?!\d)')
                if (-not $match.Success) { throw 'LATEST_VERSION_UNAVAILABLE' }
                $version = $match.Groups[1].Value
                Send-HuInstallerEvent $ProgressQueue Log Source Normal @{ Source='Official latest redirect'; Url=$finalUrl }
                Send-HuInstallerEvent $ProgressQueue Log Version Normal @{ Name=$Item.Name; Version=$version }
                $expectedSize=if($response.Content.Headers.ContentLength){[long]$response.Content.Headers.ContentLength}else{[long]0}
                return [pscustomobject]@{ Version=$version; Url=$finalUrl; FileName=$fileName; Source='Official latest redirect'; ExpectedSize=$expectedSize }
            }
            finally { $response.Dispose(); $request.Dispose() }
        }
        finally { $client.Dispose() }
    }

    if ($Item.Provider -eq 'OfficialCurrent') {
        if ([string]::IsNullOrWhiteSpace([string]$Item.DirectUrl)) { throw 'LATEST_VERSION_UNAVAILABLE' }
        $client = New-HuInstallerHttpClient
        try {
            $request = [Net.Http.HttpRequestMessage]::new([Net.Http.HttpMethod]::Get,[string]$Item.DirectUrl)
            $response = $client.SendAsync($request,[Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
            try {
                $response.EnsureSuccessStatusCode() | Out-Null
                $finalUrl = [string]$response.RequestMessage.RequestUri.AbsoluteUri
                if (-not ([Uri]$finalUrl).Scheme.Equals('https',[StringComparison]::OrdinalIgnoreCase)) { throw 'INSECURE_DOWNLOAD_URL' }
                $fileName = ''
                if ($response.Content.Headers.ContentDisposition) {
                    if ($response.Content.Headers.ContentDisposition.FileNameStar) { $fileName=([string]$response.Content.Headers.ContentDisposition.FileNameStar).Trim('"') }
                    elseif ($response.Content.Headers.ContentDisposition.FileName) { $fileName=([string]$response.Content.Headers.ContentDisposition.FileName).Trim('"') }
                }
                if ([string]::IsNullOrWhiteSpace($fileName)) { $fileName=[IO.Path]::GetFileName(([Uri]$finalUrl).LocalPath) }
                if ([string]::IsNullOrWhiteSpace([IO.Path]::GetExtension($fileName))) {
                    $mediaType=if($response.Content.Headers.ContentType){[string]$response.Content.Headers.ContentType.MediaType}else{''}
                    if($mediaType -match '(?i)(msdownload|octet-stream)'){$fileName=([regex]::Replace([string]$Item.Name,'[^A-Za-z0-9._()+ -]','_')+'_Setup.exe')}
                }
                $match=[regex]::Match(($finalUrl+' '+$fileName),'(?<!\d)(\d+\.\d+(?:\.\d+){0,3})(?!\d)')
                $version=if($match.Success){$match.Groups[1].Value}else{'current'}
                Send-HuInstallerEvent $ProgressQueue Log Source Normal @{ Source='Official current installer'; Url=$finalUrl }
                Send-HuInstallerEvent $ProgressQueue Log Version Normal @{ Name=$Item.Name; Version=$version }
                $expectedSize=if($response.Content.Headers.ContentLength){[long]$response.Content.Headers.ContentLength}else{[long]0}
                return [pscustomobject]@{ Version=$version; Url=$finalUrl; FileName=$fileName; Source='Official current installer'; ExpectedSize=$expectedSize }
            }
            finally { $response.Dispose();$request.Dispose() }
        }
        finally { $client.Dispose() }
    }

    if ($Item.Provider -eq 'MozillaFirefox') {
        $metadataUrl=[string]$Item.MetadataUrl
        if ([string]::IsNullOrWhiteSpace($metadataUrl)) { throw 'LATEST_VERSION_UNAVAILABLE' }
        Send-HuInstallerEvent $ProgressQueue Log Source Normal @{ Source='Mozilla Product Details'; Url=$metadataUrl }
        $metadata=Invoke-RestMethod -Uri $metadataUrl -Headers @{ 'User-Agent'='WNST/1.0'; 'Accept'='application/json' } -UseBasicParsing -ErrorAction Stop
        $version=([string]$metadata.LATEST_FIREFOX_VERSION).Trim()
        if ($version -notmatch '^\d+(?:\.\d+){1,3}$') { throw 'LATEST_VERSION_UNAVAILABLE' }
        $locale=Get-HuMozillaLocale -Language $Language
        $url=Get-HuLocalizedCatalogUrl -Url ([string]$Item.DirectUrl) -Language $Language
        Send-HuInstallerEvent $ProgressQueue Log Version Normal @{ Name=$Item.Name; Version=$version }
        return [pscustomobject]@{ Version=$version; Url=$url; FileName=('Firefox_Setup_{0}_{1}.exe' -f $version,$locale); Source='Mozilla Product Details'; ExpectedSize=[long]0 }
    }

    if ($Item.Provider -eq 'DiscordLatest') {
        $manifestUrl='https://updates.discord.com/distributions/app/manifests/latest?channel=stable&platform=win&arch=x64'
        Send-HuInstallerEvent $ProgressQueue Log Source Normal @{ Source='Discord stable manifest'; Url=$manifestUrl }
        $manifest=Invoke-RestMethod -Uri $manifestUrl -Headers @{ 'User-Agent'='Discord-Updater/1.0 WNST/1.0'; 'Accept'='application/json' } -UseBasicParsing -ErrorAction Stop
        $version=''
        try { $version=(@($manifest.modules.discord_desktop_core.full.host_version) -join '.').Trim('.') } catch { }
        if ($version -notmatch '^\d+(?:\.\d+){1,3}$') {
            $json=$manifest|ConvertTo-Json -Depth 20 -Compress
            $match=[regex]::Match($json,'"host_version"\s*:\s*\[\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*\]')
            if ($match.Success) { $version=('{0}.{1}.{2}' -f $match.Groups[1].Value,$match.Groups[2].Value,$match.Groups[3].Value) }
        }
        if ($version -notmatch '^\d+(?:\.\d+){1,3}$') { throw 'LATEST_VERSION_UNAVAILABLE' }
        Send-HuInstallerEvent $ProgressQueue Log Version Normal @{ Name=$Item.Name; Version=$version }
        return [pscustomobject]@{ Version=$version; Url=[string]$Item.DirectUrl; FileName=('DiscordSetup_{0}_x64.exe' -f $version); Source='Discord stable manifest'; ExpectedSize=[long]0 }
    }

    if ($Item.Provider -eq 'OfficialPageAsset') {
        if ([string]::IsNullOrWhiteSpace([string]$Item.MetadataUrl) -or [string]::IsNullOrWhiteSpace([string]$Item.LinkPattern)) { throw 'LATEST_VERSION_UNAVAILABLE' }
        $html=Get-HuInstallerRemoteText -Url ([string]$Item.MetadataUrl)
        $html=[Net.WebUtility]::HtmlDecode([string]$html)
        $links=@([regex]::Matches($html,[string]$Item.LinkPattern)|ForEach-Object{$_.Value}|Select-Object -Unique)
        if ($links.Count -ne 1) { throw 'INSTALLABLE_ASSET_UNAVAILABLE' }
        $url=[string]$links[0]
        $fileName=[IO.Path]::GetFileName(([Uri]$url).LocalPath)
        $match=[regex]::Match($fileName,'(?<!\d)(\d+\.\d+(?:\.\d+){0,3})(?!\d)')
        if (-not $match.Success) { throw 'LATEST_VERSION_UNAVAILABLE' }
        $version=$match.Groups[1].Value
        Send-HuInstallerEvent $ProgressQueue Log Source Normal @{ Source='Official download page'; Url=[string]$Item.MetadataUrl }
        Send-HuInstallerEvent $ProgressQueue Log Version Normal @{ Name=$Item.Name; Version=$version }
        return [pscustomobject]@{ Version=$version; Url=$url; FileName=$fileName; Source='Official download page'; ExpectedSize=[long]0 }
    }

    throw 'LATEST_VERSION_UNAVAILABLE'
}

function Assert-HuInstallerPublisher {
    param([Parameter(Mandatory=$true)][string]$Path,[Parameter(Mandatory=$true)][object]$Item)
    if ([string]::IsNullOrWhiteSpace([string]$Item.ExpectedPublisher)) { return }
    if ([IO.Path]::GetExtension($Path).ToLowerInvariant() -notin @('.exe','.msi')) { return }
    $signature=Get-AuthenticodeSignature -LiteralPath $Path -ErrorAction Stop
    if ($signature.Status -ne [System.Management.Automation.SignatureStatus]::Valid -or -not $signature.SignerCertificate) { throw 'INVALID_INSTALLER_SIGNATURE' }
    if ([string]$signature.SignerCertificate.Subject -notmatch [string]$Item.ExpectedPublisher) { throw 'INVALID_INSTALLER_PUBLISHER' }
}

function Invoke-HuVerifiedInstallerDownload {
    param([Parameter(Mandatory=$true)][object]$Item,[object]$ProgressQueue,[string]$Language='')

    $resolved = Resolve-HuLatestInstaller -Item $Item -ProgressQueue $ProgressQueue -Language $Language
    if (-not ([Uri]$resolved.Url).Scheme.Equals('https',[StringComparison]::OrdinalIgnoreCase)) { throw 'INSECURE_DOWNLOAD_URL' }
    $extension = [IO.Path]::GetExtension([string]$resolved.FileName).ToLowerInvariant()
    if ($extension -notin @('.exe','.msi','.msix','.msixbundle','.appx','.appxbundle','.appinstaller','.zip')) { throw 'UNSUPPORTED_INSTALLER_FORMAT' }

    Send-HuInstallerEvent $ProgressQueue Log Url Normal @{ Url=$resolved.Url; Source=$resolved.Source }
    $downloadRoot = Get-HuDownloadsPath
    $safeName = [regex]::Replace([string]$resolved.FileName,'[^A-Za-z0-9._()+ -]','_')
    if ([string]::IsNullOrWhiteSpace($safeName)) { throw 'INVALID_INSTALLER_NAME' }
    $destination = Join-Path $downloadRoot $safeName
    $temporary = $destination + '.partial'

    if (Test-Path -LiteralPath $destination -PathType Leaf) {
        $existingSize=[long](Get-Item -LiteralPath $destination).Length
        if ([long]$resolved.ExpectedSize -gt 0 -and $existingSize -eq [long]$resolved.ExpectedSize) {
            try {
                Assert-HuInstallerPublisher -Path $destination -Item $Item
                Send-HuInstallerEvent $ProgressQueue Log Existing Normal @{ Path=$destination }
                Send-HuInstallerEvent $ProgressQueue Progress Complete Success @{ Name=$Item.Name; Percent=100; Path=$destination }
                $installerPath=Register-HuDownloadedCatalogArtifact -Item $Item -Path $destination -Version ([string]$resolved.Version)
                return [pscustomobject]@{ Path=$destination; InstallerPath=$installerPath; Version=$resolved.Version; Existing=$true }
            }
            catch {
                if($Item.Id -ne 'jdownloader'){throw}
                Remove-Item -LiteralPath $destination -Force -ErrorAction Stop
            }
        }
        if(Test-Path -LiteralPath $destination -PathType Leaf){$baseName=[IO.Path]::GetFileNameWithoutExtension($safeName);$extension=[IO.Path]::GetExtension($safeName);$destination=Join-Path $downloadRoot ('{0}_{1}{2}' -f $baseName,(Get-Date -Format 'yyyyMMdd-HHmmss'),$extension);$temporary=$destination+'.partial'}
    }

    $client = New-HuInstallerHttpClient -RawContent:([bool]$resolved.PSObject.Properties['MegaKey'])
    try {
        Send-HuInstallerEvent $ProgressQueue Progress Download Normal @{ Name=$Item.Name; Percent=5 }
        Send-HuInstallerEvent $ProgressQueue Log Download Normal @{ Name=$Item.Name; Path=$destination }
        $response=$null;$activeUrl=[string]$resolved.Url
        try{
            $response=$client.GetAsync($activeUrl,[Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult();$response.EnsureSuccessStatusCode()|Out-Null
        }catch{
            if($response){$response.Dispose();$response=$null}
            $fallback=if($resolved.PSObject.Properties['FallbackUrl']){[string]$resolved.FallbackUrl}else{''}
            if([string]::IsNullOrWhiteSpace($fallback)){throw}
            $activeUrl=$fallback;Send-HuInstallerEvent $ProgressQueue Log Url Normal @{Url=$activeUrl;Source='Official fallback mirror'}
            $response=$client.GetAsync($activeUrl,[Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult();$response.EnsureSuccessStatusCode()|Out-Null
        }
        try {
            $total = if ($response.Content.Headers.ContentLength) { [long]$response.Content.Headers.ContentLength } else { [long]0 }
            $input = $response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
            $output = [IO.File]::Open($temporary,[IO.FileMode]::Create,[IO.FileAccess]::Write,[IO.FileShare]::None)
            try {
                if($resolved.PSObject.Properties['MegaKey']){
                    Write-HuMegaDecryptedStream -SourceStream $input -DestinationStream $output -Key ([byte[]]$resolved.MegaKey) -CounterIv ([byte[]]$resolved.MegaIv) -Total $total -ProgressQueue $ProgressQueue -Name $Item.Name
                }else{
                    $buffer = New-Object byte[] 131072
                    $readTotal = [long]0
                    $watch = [Diagnostics.Stopwatch]::StartNew()
                    $lastReport = [long]0
                    $nextLogPercent = 10
                    while (($read = $input.Read($buffer,0,$buffer.Length)) -gt 0) {
                        $output.Write($buffer,0,$read)
                        $readTotal += $read
                        if (($watch.ElapsedMilliseconds - $lastReport) -ge 120) {
                            $lastReport = $watch.ElapsedMilliseconds
                            $percent = if ($total -gt 0) { [math]::Min(99,[math]::Round(($readTotal * 100.0) / $total)) } else { 0 }
                            $speed = if ($watch.Elapsed.TotalSeconds -gt 0) { [long]($readTotal / $watch.Elapsed.TotalSeconds) } else { [long]0 }
                            Send-HuInstallerEvent $ProgressQueue Progress Download Normal @{ Name=$Item.Name; Percent=$percent; Bytes=$readTotal; Total=$total; Speed=$speed }
                            if ($total -gt 0 -and $percent -ge $nextLogPercent) {
                                Send-HuInstallerEvent $ProgressQueue Log Progress Normal @{ Name=$Item.Name; Percent=$percent; Bytes=$readTotal; Total=$total; Speed=$speed }
                                while ($nextLogPercent -le $percent) { $nextLogPercent += 10 }
                            }
                        }
                    }
                    if ($total -gt 0 -and $readTotal -ne $total) { throw 'DOWNLOAD_SIZE_MISMATCH' }
                    $output.Flush()
                }
            }
            finally { $output.Dispose(); $input.Dispose() }
        }
        finally { $response.Dispose() }
    }
    catch {
        if (Test-Path -LiteralPath $temporary -PathType Leaf) { Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue }
        throw
    }
    finally { $client.Dispose() }

    Move-Item -LiteralPath $temporary -Destination $destination -Force -ErrorAction Stop
    try { Assert-HuInstallerPublisher -Path $destination -Item $Item }
    catch { Remove-Item -LiteralPath $destination -Force -ErrorAction SilentlyContinue; throw }
    Send-HuInstallerEvent $ProgressQueue Log Path Normal @{ Path=$destination }
    $installerPath=Register-HuDownloadedCatalogArtifact -Item $Item -Path $destination -Version ([string]$resolved.Version)
    if(-not[string]::IsNullOrWhiteSpace($installerPath)){Send-HuInstallerEvent $ProgressQueue Log Path Normal @{Path=$installerPath}}
    return [pscustomobject]@{ Path=$destination; InstallerPath=$installerPath; Version=$resolved.Version; Existing=$false }
}

function Invoke-HuCatalogInstall {
    param([Parameter(Mandatory=$true)][string]$Id,[object]$ProgressQueue,[string]$Language='')
    $item = Get-HuCatalogItem -Id $Id
    if (-not $item) { throw 'UNKNOWN_CATALOG_ITEM' }
    try {
        Send-HuInstallerEvent $ProgressQueue Progress Prepare Normal @{ Name=$item.Name; Percent=0 }
        if($item.Provider -eq 'Winget'){
            if([string]::IsNullOrWhiteSpace([string]$item.PackageId)){throw 'LATEST_VERSION_UNAVAILABLE'}
            $winget=Get-Command winget.exe -ErrorAction Stop
            Send-HuInstallerEvent $ProgressQueue Progress Search Normal @{Name=$item.Name;Percent=5}
            Send-HuInstallerEvent $ProgressQueue Log Source Normal @{Source='WinGet';Url=('winget:'+$item.PackageId)}
            $arguments=@('install','--id',[string]$item.PackageId,'--exact','--source','winget','--accept-package-agreements','--accept-source-agreements','--silent','--disable-interactivity')
            $process=Start-Process -FilePath $winget.Source -ArgumentList $arguments -Wait -PassThru -WindowStyle Hidden
            if($process.ExitCode -ne 0){throw ('WINGET_FAILED:{0}' -f $process.ExitCode)}
            Send-HuInstallerEvent $ProgressQueue Log Complete Success @{Name=$item.Name;Version='latest';Path=('winget:'+$item.PackageId)}
            Send-HuInstallerEvent $ProgressQueue Progress Complete Success @{Name=$item.Name;Percent=100;Path=('winget:'+$item.PackageId)}
            return [pscustomobject]@{Success=$true;Name=$item.Name;Version='latest';Path=('winget:'+$item.PackageId)}
        }
        $download = Invoke-HuVerifiedInstallerDownload -Item $item -ProgressQueue $ProgressQueue -Language $Language
        Send-HuInstallerEvent $ProgressQueue Log DownloadComplete Success @{ Name=$item.Name; Version=$download.Version; Path=$download.Path }
        Send-HuInstallerEvent $ProgressQueue Progress Complete Success @{ Name=$item.Name; Percent=100; Path=$download.Path }
        return [pscustomobject]@{ Success=$true; Name=$item.Name; Version=$download.Version; Path=$download.Path }
    }
    catch {
        $code = [string]$_.Exception.Message
        Send-HuInstallerEvent $ProgressQueue Log Error Error @{ Name=$item.Name; Code=$code; OfficialUrl=$item.OfficialUrl; GitHubUrl=$item.GitHubUrl; StoreUrl=$item.StoreUrl }
        Send-HuInstallerEvent $ProgressQueue Progress Error Error @{ Name=$item.Name; Percent=0; Code=$code }
        throw
    }
}

function Invoke-HuCatalogDownload {
    param([Parameter(Mandatory=$true)][string]$Id,[object]$ProgressQueue,[string]$Language='')
    $item=Get-HuCatalogItem -Id $Id
    if (-not $item) { throw 'UNKNOWN_CATALOG_ITEM' }
    try {
        Send-HuInstallerEvent $ProgressQueue Progress Prepare Normal @{ Name=$item.Name; Percent=0 }
        $download=Invoke-HuVerifiedInstallerDownload -Item $item -ProgressQueue $ProgressQueue -Language $Language
        Send-HuInstallerEvent $ProgressQueue Log DownloadComplete Success @{ Name=$item.Name; Version=$download.Version; Path=$download.Path }
        Send-HuInstallerEvent $ProgressQueue Progress Complete Success @{ Name=$item.Name; Percent=100; Path=$download.Path }
        return [pscustomobject]@{ Success=$true; Name=$item.Name; Version=$download.Version; Path=$download.Path }
    }
    catch {
        $code=[string]$_.Exception.Message
        Send-HuInstallerEvent $ProgressQueue Log Error Error @{ Name=$item.Name; Code=$code; OfficialUrl=$item.OfficialUrl; GitHubUrl=$item.GitHubUrl; StoreUrl=$item.StoreUrl }
        Send-HuInstallerEvent $ProgressQueue Progress Error Error @{ Name=$item.Name; Percent=0; Code=$code }
        throw
    }
}
