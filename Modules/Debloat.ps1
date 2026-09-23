# WNST - Gestionnaire AppX intégré
# Backend uniquement : aucune UI, aucune sortie console.

$script:AppxFriendlyNames = @{
    'Clipchamp.Clipchamp'='Clipchamp'; 'Microsoft.549981C3F5F10'='Cortana';
    'Microsoft.BingNews'='Microsoft News'; 'Microsoft.BingWeather'='MSN Weather'; 'Microsoft.BingSearch'='Windows Search';
    'Microsoft.Copilot'='Microsoft Copilot'; 'Microsoft.GamingApp'='Xbox';
    'Microsoft.GetHelp'='Get Help'; 'Microsoft.Getstarted'='Tips';
    'Microsoft.Microsoft3DViewer'='3D Viewer'; 'Microsoft.MicrosoftOfficeHub'='Microsoft 365';
    'Microsoft.MicrosoftSolitaireCollection'='Microsoft Solitaire Collection'; 'Microsoft.MixedReality.Portal'='Mixed Reality Portal';
    'Microsoft.OutlookForWindows'='Outlook for Windows'; 'Microsoft.Paint'='Paint'; 'Microsoft.MSPaint'='Paint';
    'Microsoft.People'='People'; 'Microsoft.PowerAutomateDesktop'='Power Automate'; 'Microsoft.ScreenSketch'='Snipping Tool';
    'Microsoft.SkypeApp'='Skype'; 'Microsoft.StorePurchaseApp'='Microsoft Store Purchase App'; 'Microsoft.Todos'='Microsoft To Do';
    'Microsoft.Windows.DevHome'='Dev Home'; 'Microsoft.Windows.Photos'='Photos'; 'Microsoft.WindowsAlarms'='Clock';
    'Microsoft.WindowsCalculator'='Calculator'; 'Microsoft.WindowsCamera'='Camera'; 'Microsoft.WindowsFeedbackHub'='Feedback Hub';
    'Microsoft.WindowsMaps'='Maps'; 'Microsoft.WindowsNotepad'='Notepad'; 'Microsoft.WindowsSoundRecorder'='Sound Recorder';
    'Microsoft.WindowsStore'='Microsoft Store'; 'Microsoft.WindowsTerminal'='Terminal';
    'Microsoft.Windows.ShellExperienceHost'='Windows Shell Experience Host'; 'Microsoft.Windows.StartMenuExperienceHost'='Windows Start Menu';
    'Microsoft.Windows.Search'='Windows Search'; 'Microsoft.Xbox.TCUI'='Xbox TCUI'; 'Microsoft.XboxApp'='Xbox Console Companion';
    'Microsoft.XboxGameOverlay'='Xbox Game Overlay'; 'Microsoft.XboxGamingOverlay'='Xbox Game Bar';
    'Microsoft.XboxIdentityProvider'='Xbox Identity Provider'; 'Microsoft.XboxSpeechToTextOverlay'='Xbox Speech To Text';
    'Microsoft.YourPhone'='Phone Link'; 'Microsoft.ZuneMusic'='Media Player'; 'Microsoft.ZuneVideo'='Movies & TV';
    'microsoft.windowscommunicationsapps'='Mail and Calendar'; 'MicrosoftCorporationII.MicrosoftFamily'='Microsoft Family';
    'MicrosoftCorporationII.QuickAssist'='Quick Assist'; 'MicrosoftTeams'='Microsoft Teams Personal'; 'MSTeams'='Microsoft Teams';
    'MicrosoftWindows.Client.WebExperience'='Windows Web Experience Pack'; 'MicrosoftWindows.CrossDevice'='Windows Cross Device';
    'DolbyLaboratories.DolbyAccess'='Dolby Access'; '40459File-New-Project.EarTrumpet'='EarTrumpet';
    'MicaForEveryone.MicaForEveryone2'='Mica For Everyone'
}

$script:AppxRecommendedPatterns = @(
    'Clipchamp.Clipchamp','Microsoft.549981C3F5F10','Microsoft.BingNews','Microsoft.BingWeather','Microsoft.Copilot',
    'Microsoft.GamingApp','Microsoft.GetHelp','Microsoft.Getstarted','Microsoft.Microsoft3DViewer','Microsoft.MicrosoftOfficeHub',
    'Microsoft.MicrosoftSolitaireCollection','Microsoft.MixedReality.Portal','Microsoft.People','Microsoft.SkypeApp',
    'Microsoft.WindowsFeedbackHub','Microsoft.WindowsMaps','Microsoft.Xbox.TCUI','Microsoft.XboxApp','Microsoft.XboxGameOverlay',
    'Microsoft.XboxGamingOverlay','Microsoft.XboxSpeechToTextOverlay','MicrosoftTeams','microsoft.windowscommunicationsapps','Microsoft.ZuneVideo'
)

$script:AppxKnownRemovablePatterns = @(
    @($script:AppxRecommendedPatterns) + @(
        'Microsoft.XboxIdentityProvider', # volontairement jaune : certains jeux/services Xbox en dépendent
        'Microsoft.OutlookForWindows','Microsoft.Paint','Microsoft.MSPaint','Microsoft.PowerAutomateDesktop','Microsoft.ScreenSketch',
        'Microsoft.Todos','Microsoft.Windows.DevHome','Microsoft.Windows.Photos','Microsoft.WindowsAlarms','Microsoft.WindowsCalculator',
        'Microsoft.WindowsCamera','Microsoft.WindowsNotepad','Microsoft.WindowsSoundRecorder','Microsoft.WindowsTerminal','Microsoft.MicrosoftStickyNotes',
        'Microsoft.YourPhone','Microsoft.ZuneMusic','MicrosoftCorporationII.MicrosoftFamily','MicrosoftCorporationII.QuickAssist','MSTeams',
        'MicrosoftWindows.Client.WebExperience','MicrosoftWindows.CrossDevice'
    )
)

$script:AppxProtectedPatterns = @(
    'Microsoft.WindowsStore','Microsoft.StorePurchaseApp','Microsoft.DesktopAppInstaller','Microsoft.SecHealthUI','Microsoft.Windows.SecHealthUI',
    'Microsoft.Windows.ShellExperienceHost','Microsoft.Windows.StartMenuExperienceHost','Microsoft.Windows.Search','Microsoft.BingSearch',
    'Microsoft.AAD.BrokerPlugin','Microsoft.AccountsControl','Microsoft.AsyncTextService','Microsoft.BioEnrollment','Microsoft.CredDialogHost',
    'Microsoft.CredentialDialogHost','Microsoft.LockApp','Microsoft.Windows.CloudExperienceHost','Microsoft.Windows.ContentDeliveryManager',
    'Microsoft.Windows.OOBENetworkCaptivePortal','Microsoft.Windows.OOBENetworkConnectionFlow','MicrosoftWindows.Client.CBS',
    'MicrosoftWindows.Client.Core','MicrosoftWindows.Client.CoreAI','MicrosoftWindows.Client.AIX','MicrosoftWindows.Client.FileExp',
    'MicrosoftWindows.Client.OOBE','MicrosoftWindows.Client.Shell'
)

$script:AppxHiddenTechnicalPatterns = @(
    'Microsoft.VCLibs*','Microsoft.NET.Native*','Microsoft.UI.Xaml*','Microsoft.WindowsAppRuntime*','Microsoft.WinUI*',
    'Microsoft.DirectXRuntime*','Microsoft.Services.Store.Engagement*','Microsoft.Advertising.Xaml*','Microsoft.WinJS*'
)


$script:AppxAdditionalCatalog = $null

# Les fonctions dédiées de l'onglet Advanced restent la seule voie de gestion
# pour Edge/WebView, OneDrive et les composants Windows AI.
$script:AppxDedicatedFeaturePatterns = @(
    'Microsoft.MicrosoftEdge*','Microsoft.Edge*','MicrosoftEdge*','Microsoft.EdgeWebView2*','*EdgeWebView2*','Microsoft.Win32WebViewHost',
    '*OneDrive*','*Copilot*','Microsoft.Windows.AIHub','*CoreAI*','MicrosoftWindows.Client.AIX',
    '*WindowsAiFoundation*','*WindowsAIFoundation*','*Recall*'
)

function Get-WnstAdditionalAppCatalog {
    if ($null -ne $script:AppxAdditionalCatalog) { return @($script:AppxAdditionalCatalog) }

    $script:AppxAdditionalCatalog = @()
    try {
        $root = Split-Path -Parent $PSScriptRoot
        $path = Join-Path $root 'Data\AppxCatalog.json'
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return @() }
        $raw = [IO.File]::ReadAllText($path,[Text.Encoding]::UTF8)
        $data = $raw | ConvertFrom-Json -ErrorAction Stop
        $script:AppxAdditionalCatalog = @($data.Apps)
    }
    catch { $script:AppxAdditionalCatalog = @() }

    return @($script:AppxAdditionalCatalog)
}

function Test-WnstCatalogIdentifierMatch {
    param(
        [Parameter(Mandatory=$true)][string]$PackageName,
        [Parameter(Mandatory=$true)][string]$Identifier
    )

    if ([string]::IsNullOrWhiteSpace($PackageName) -or [string]::IsNullOrWhiteSpace($Identifier)) { return $false }
    if ([string]::Equals($PackageName,$Identifier,[StringComparison]::OrdinalIgnoreCase)) { return $true }
    return $PackageName.EndsWith(('.' + $Identifier),[StringComparison]::OrdinalIgnoreCase)
}

function Get-WnstAdditionalCatalogEntry {
    param([Parameter(Mandatory=$true)][string]$PackageName)

    foreach ($entry in @(Get-WnstAdditionalAppCatalog)) {
        foreach ($candidate in @([string]$entry.AppId) + @($entry.Aliases | Where-Object { $_ })) {
            if (Test-WnstCatalogIdentifierMatch -PackageName $PackageName -Identifier ([string]$candidate)) { return $entry }
        }
    }
    return $null
}

function Test-WnstDedicatedFeaturePackageName {
    param([Parameter(Mandatory=$true)][string]$PackageName)
    return (Test-WnstAppxPattern -Name $PackageName -Patterns $script:AppxDedicatedFeaturePatterns)
}

function Get-WnstStartSuggestionCandidate {
    param([Parameter(Mandatory=$true)][string]$PackageName)

    if (Test-WnstDedicatedFeaturePackageName -PackageName $PackageName) { return $null }

    $catalogEntry = Get-WnstAdditionalCatalogEntry -PackageName $PackageName
    if ($catalogEntry) {
        return [pscustomobject]@{
            CatalogId = [string]$catalogEntry.AppId
            FriendlyName = [string]$catalogEntry.FriendlyName
            Indicator = [string]$catalogEntry.Indicator
        }
    }

    foreach ($candidate in @($script:AppxRecommendedPatterns)) {
        $id = [string]$candidate
        if ($id -match '[*?]') { continue }
        if (Test-WnstCatalogIdentifierMatch -PackageName $PackageName -Identifier $id) {
            return [pscustomobject]@{ CatalogId=$id; FriendlyName=(Get-WnstAppxFriendlyName $id); Indicator='Green' }
        }
    }
    foreach ($candidate in @($script:AppxKnownRemovablePatterns)) {
        $id = [string]$candidate
        if ($id -match '[*?]') { continue }
        if (Test-WnstCatalogIdentifierMatch -PackageName $PackageName -Identifier $id) {
            return [pscustomobject]@{ CatalogId=$id; FriendlyName=(Get-WnstAppxFriendlyName $id); Indicator='Yellow' }
        }
    }

    return $null
}

function Test-WnstDebloatAdministrator {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = [Security.Principal.WindowsPrincipal]::new($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch { return $false }
}

function Test-WnstAppxPattern {
    param([Parameter(Mandatory=$true)][string]$Name,[Parameter(Mandatory=$true)][object[]]$Patterns)
    foreach ($pattern in $Patterns) { if ($Name -like [string]$pattern) { return $true } }
    return $false
}

function Test-WnstAppxPropertyTrue {
    param([Parameter(Mandatory=$true)][object]$Object,[Parameter(Mandatory=$true)][string]$PropertyName)
    $property = $Object.PSObject.Properties[$PropertyName]
    return ($null -ne $property -and [bool]$property.Value)
}

function Test-WnstTechnicalAppxPackage {
    param([Parameter(Mandatory=$true)][object]$Package)
    if (Test-WnstAppxPropertyTrue $Package 'IsFramework') { return $true }
    if (Test-WnstAppxPropertyTrue $Package 'IsResourcePackage') { return $true }
    return (Test-WnstAppxPattern -Name ([string]$Package.Name) -Patterns $script:AppxHiddenTechnicalPatterns)
}

function Get-WnstAppxFriendlyName {
    param([Parameter(Mandatory=$true)][string]$PackageName)
    if ($script:AppxFriendlyNames.ContainsKey($PackageName)) { return [string]$script:AppxFriendlyNames[$PackageName] }
    $catalogEntry = Get-WnstAdditionalCatalogEntry -PackageName $PackageName
    if ($catalogEntry -and -not [string]::IsNullOrWhiteSpace([string]$catalogEntry.FriendlyName)) { return [string]$catalogEntry.FriendlyName }
    return $PackageName
}


function Test-WnstReadableAppxMetadataText {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
    $value = $Text.Trim()
    if ($value -match '^(?i:ms-resource:|@\{)') { return $false }
    return $true
}

function Get-WnstAppxShellMetadata {
    # AppsFolder fournit les noms/descr. résolus par Windows dans la langue du système.
    # C'est nettement plus lisible que le nom technique du package et évite un appel
    # de manifeste coûteux pour chaque ligne.
    $map = @{}
    $shell = $null
    try {
        $shell = New-Object -ComObject Shell.Application
        $folder = $shell.Namespace('shell:AppsFolder')
        if ($null -eq $folder) { return $map }
        foreach ($item in @($folder.Items())) {
            $pfn = ''
            try { $pfn = [string]$item.ExtendedProperty('System.AppUserModel.PackageFamilyName') } catch {}
            if ([string]::IsNullOrWhiteSpace($pfn)) { continue }
            $display = ''
            try { $display = [string]$item.Name } catch {}
            $description = ''
            foreach ($propertyName in @('System.Comment','System.FileDescription')) {
                try {
                    $candidate = [string]$item.ExtendedProperty($propertyName)
                    if (Test-WnstReadableAppxMetadataText $candidate) { $description = $candidate.Trim(); break }
                } catch {}
            }
            if (-not $map.ContainsKey($pfn)) {
                $map[$pfn] = [pscustomobject]@{ DisplayName=$display; Description=$description }
            }
            else {
                $entry = $map[$pfn]
                if ([string]::IsNullOrWhiteSpace([string]$entry.DisplayName) -and $display) { $entry.DisplayName = $display }
                if ([string]::IsNullOrWhiteSpace([string]$entry.Description) -and $description) { $entry.Description = $description }
            }
        }
    }
    catch {}
    finally {
        if ($shell -and [Runtime.InteropServices.Marshal]::IsComObject($shell)) {
            try { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell) } catch {}
        }
    }
    return $map
}

function Get-WnstAppxManifestMetadata {
    param([object[]]$InstalledItems=@())
    foreach ($package in @($InstalledItems)) {
        try {
            if (-not $package.InstallLocation) { continue }
            $manifestPath = Join-Path ([string]$package.InstallLocation) 'AppxManifest.xml'
            if (-not (Test-Path -LiteralPath $manifestPath)) { continue }
            [xml]$manifest = [IO.File]::ReadAllText($manifestPath)
            $properties = $manifest.Package.Properties
            if ($null -eq $properties) { continue }
            $display = [string]$properties.DisplayName
            $description = [string]$properties.Description
            if (-not (Test-WnstReadableAppxMetadataText $display)) { $display = '' }
            if (-not (Test-WnstReadableAppxMetadataText $description)) { $description = '' }
            if ($display -or $description) { return [pscustomobject]@{ DisplayName=$display; Description=$description } }
        }
        catch {}
    }
    return [pscustomobject]@{ DisplayName=''; Description='' }
}

function Test-WnstTechnicalAppxName {
    param([Parameter(Mandatory=$true)][string]$PackageName,[string]$DisplayName)
    # GUID/identifiants internes et packages sans nom humain restent visibles, mais
    # regroupés en bas de liste au lieu de polluer les applications reconnaissables.
    $guidLike = ($PackageName -match '(?i)^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
    $opaque = ([string]::IsNullOrWhiteSpace($DisplayName) -or $DisplayName -eq $PackageName)
    if ($guidLike) { return $true }
    if ($opaque -and $PackageName -notmatch '\.') { return $true }
    return $false
}

function Test-WnstAppxMustStayOutOfDebloat {
    param(
        [Parameter(Mandatory=$true)][string]$PackageName,
        [object[]]$InstalledItems=@(),
        [object[]]$ProvisionedItems=@()
    )

    # Ne jamais déduire qu'un package est protégé à partir de son emplacement disque.
    # Des AppX légitimes peuvent vivre sous un chemin Windows ; seules les métadonnées
    # exposées par Windows et notre catalogue explicite décident de leur visibilité.
    foreach ($package in @($InstalledItems)) {
        if (Test-WnstAppxPropertyTrue $package 'NonRemovable') { return $true }

        # IsPartOfSystem peut être exposé sur certains packages Windows que WNST connaît
        # pourtant comme supprimables. Dans ce cas, notre liste explicite l'emporte.
        if (Test-WnstAppxPropertyTrue $package 'IsPartOfSystem') {
            if (Test-WnstAppxPattern -Name $PackageName -Patterns $script:AppxRecommendedPatterns) { continue }
            if (Test-WnstAppxPattern -Name $PackageName -Patterns $script:AppxKnownRemovablePatterns) { continue }

            $catalogEntry = Get-WnstAdditionalCatalogEntry -PackageName $PackageName
            if ($catalogEntry -and ([string]$catalogEntry.Indicator -in @('Green','Yellow'))) { continue }

            return $true
        }
    }

    return $false
}

function Get-WnstAppxClassification {
    param([Parameter(Mandatory=$true)][string]$PackageName,[object[]]$InstalledItems=@(),[object[]]$ProvisionedItems=@())
    $installed = @($InstalledItems)
    foreach ($package in $installed) {
        if (Test-WnstAppxPropertyTrue $package 'NonRemovable') { return [pscustomobject]@{ Indicator='Red'; IsSelectable=$false; IsChecked=$false; ReasonCode='NonRemovable' } }
    }
    if (Test-WnstAppxPattern -Name $PackageName -Patterns $script:AppxProtectedPatterns) { return [pscustomobject]@{ Indicator='Red'; IsSelectable=$false; IsChecked=$false; ReasonCode='Protected' } }
    if (Test-WnstAppxPattern -Name $PackageName -Patterns $script:AppxRecommendedPatterns) { return [pscustomobject]@{ Indicator='Green'; IsSelectable=$true; IsChecked=$false; ReasonCode='Recommended' } }
    if (Test-WnstAppxPattern -Name $PackageName -Patterns $script:AppxKnownRemovablePatterns) { return [pscustomobject]@{ Indicator='Yellow'; IsSelectable=$true; IsChecked=$false; ReasonCode='Optional' } }

    $catalogEntry = Get-WnstAdditionalCatalogEntry -PackageName $PackageName
    if ($catalogEntry) {
        switch ([string]$catalogEntry.Indicator) {
            'Green' { return [pscustomobject]@{ Indicator='Green'; IsSelectable=$true; IsChecked=$false; ReasonCode='RecommendedCatalog' } }
            'Red'   { return [pscustomobject]@{ Indicator='Red'; IsSelectable=$false; IsChecked=$false; ReasonCode='ProtectedCatalog' } }
            default { return [pscustomobject]@{ Indicator='Yellow'; IsSelectable=$true; IsChecked=$false; ReasonCode='OptionalCatalog' } }
        }
    }

    foreach ($package in $installed) {
        if (Test-WnstAppxPropertyTrue $package 'IsPartOfSystem') { return [pscustomobject]@{ Indicator='Red'; IsSelectable=$false; IsChecked=$false; ReasonCode='SystemUnknown' } }
    }
    # Un package uniquement provisionné et inconnu est protégé par défaut : WNST ne peut pas
    # consulter IsPartOfSystem/NonRemovable dans ce cas.
    if ($installed.Count -eq 0 -and @($ProvisionedItems).Count -gt 0) { return [pscustomobject]@{ Indicator='Red'; IsSelectable=$false; IsChecked=$false; ReasonCode='ProvisionedUnknown' } }
    return [pscustomobject]@{ Indicator='Yellow'; IsSelectable=$true; IsChecked=$false; ReasonCode='Dynamic' }
}

function Get-WnstStartMenuSuggestionInventory {
    param(
        [Parameter(Mandatory=$true)][hashtable]$InstalledByName,
        [Parameter(Mandatory=$true)][hashtable]$ProvisionedByName
    )

    $results = [Collections.Generic.List[object]]::new()
    $tempPath = Join-Path $env:TEMP ('WNST-StartLayout-{0}.json' -f ([Guid]::NewGuid().ToString('N')))
    try {
        $command = Get-Command Export-StartLayout -ErrorAction SilentlyContinue
        if (-not $command) { return @() }

        Export-StartLayout -Path $tempPath -ErrorAction Stop | Out-Null
        if (-not (Test-Path -LiteralPath $tempPath -PathType Leaf)) { return @() }

        $raw = [IO.File]::ReadAllText($tempPath,[Text.Encoding]::UTF8)
        if ([string]::IsNullOrWhiteSpace($raw)) { return @() }
        $layout = $raw | ConvertFrom-Json -ErrorAction Stop
        if ($null -eq $layout.pinnedList) { return @() }

        $seen = @{}
        foreach ($pin in @($layout.pinnedList)) {
            $aumid = [string]$pin.packagedAppId
            if ([string]::IsNullOrWhiteSpace($aumid) -or $seen.ContainsKey($aumid)) { continue }

            $bang = $aumid.IndexOf('!')
            if ($bang -le 0) { continue }
            $family = $aumid.Substring(0,$bang)
            $underscore = $family.LastIndexOf('_')
            if ($underscore -le 0) { continue }
            $packageName = $family.Substring(0,$underscore)
            if ([string]::IsNullOrWhiteSpace($packageName)) { continue }
            if (Test-WnstDedicatedFeaturePackageName -PackageName $packageName) { continue }

            # Une vraie application installée/provisionnée est déjà représentée par
            # l'inventaire AppX normal : ne pas créer de doublon "suggestion".
            if ($InstalledByName.ContainsKey($packageName) -or $ProvisionedByName.ContainsKey($packageName)) { continue }

            $candidate = Get-WnstStartSuggestionCandidate -PackageName $packageName
            if (-not $candidate) { continue }

            $seen[$aumid] = $true
            $indicator = [string]$candidate.Indicator
            $results.Add([pscustomobject]@{
                DisplayName = [string]$candidate.FriendlyName
                PackageName = $packageName
                CatalogId = [string]$candidate.CatalogId
                PackageFamilyName = $family
                Description = ''
                DescriptionKind = 'StartSuggestion'
                IsTechnicalName = $false
                SortGroup = 0
                Indicator = $indicator
                IsSelectable = ($indicator -ne 'Red')
                IsChecked = $false
                Installed = $false
                Provisioned = $false
                InstalledPackageFullNames = @()
                InstallLocations = @()
                Versions = @()
                Architectures = @()
                Publishers = @()
                SignatureKinds = @()
                ProvisionedPackageNames = @()
                ReasonCode = 'StartSuggestion'
                IsStartSuggestion = $true
                StartPinId = $aumid
            })
        }
    }
    catch {
        # Une impossibilité d'exporter le menu Démarrer ne doit jamais casser
        # l'inventaire AppX principal.
    }
    finally {
        if (Test-Path -LiteralPath $tempPath) { Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue }
    }

    return @($results)
}

function Get-WnstAppxInventory {
    [CmdletBinding()] param()
    if (-not (Test-WnstDebloatAdministrator)) { throw 'AdministratorRequired' }

    $installedByName = @{}
    foreach ($package in @(Get-AppxPackage -AllUsers -ErrorAction Ignore)) {
        if (-not $package.Name -or (Test-WnstTechnicalAppxPackage $package)) { continue }
        if (Test-WnstDedicatedFeaturePackageName -PackageName ([string]$package.Name)) { continue }
        if (-not $installedByName.ContainsKey($package.Name)) { $installedByName[$package.Name] = [Collections.Generic.List[object]]::new() }
        $installedByName[$package.Name].Add($package)
    }

    $provisionedByName = @{}
    foreach ($package in @(Get-AppxProvisionedPackage -Online -ErrorAction Ignore)) {
        $name = [string]$package.DisplayName
        if (-not $name -or (Test-WnstAppxPattern -Name $name -Patterns $script:AppxHiddenTechnicalPatterns)) { continue }
        if (Test-WnstDedicatedFeaturePackageName -PackageName $name) { continue }
        if (-not $provisionedByName.ContainsKey($name)) { $provisionedByName[$name] = [Collections.Generic.List[object]]::new() }
        $provisionedByName[$name].Add($package)
    }

    # Une seule énumération du dossier Applications. Les métadonnées retournées sont
    # déjà résolues par Windows et donnent notamment EarTrumpet, Calculatrice, etc.
    $shellMetadata = Get-WnstAppxShellMetadata
    $names = @((@($installedByName.Keys) + @($provisionedByName.Keys)) | Sort-Object -Unique)
    $results = [Collections.Generic.List[object]]::new()

    foreach ($name in $names) {
        $installedItems = if ($installedByName.ContainsKey($name)) { @($installedByName[$name]) } else { @() }
        $provisionedItems = if ($provisionedByName.ContainsKey($name)) { @($provisionedByName[$name]) } else { @() }

        if (Test-WnstAppxMustStayOutOfDebloat -PackageName $name -InstalledItems $installedItems -ProvisionedItems $provisionedItems) {
            continue
        }

        $classification = Get-WnstAppxClassification -PackageName $name -InstalledItems $installedItems -ProvisionedItems $provisionedItems
        $catalogEntry = Get-WnstAdditionalCatalogEntry -PackageName $name
        $catalogId = if ($catalogEntry) { [string]$catalogEntry.AppId } else { $name }

        $pfn = $null
        foreach ($package in $installedItems) { if ($package.PackageFamilyName) { $pfn=[string]$package.PackageFamilyName; break } }

        $displayName = ''
        $description = ''
        if ($pfn -and $shellMetadata.ContainsKey($pfn)) {
            $meta = $shellMetadata[$pfn]
            if (Test-WnstReadableAppxMetadataText ([string]$meta.DisplayName)) { $displayName = ([string]$meta.DisplayName).Trim() }
            if (Test-WnstReadableAppxMetadataText ([string]$meta.Description)) { $description = ([string]$meta.Description).Trim() }
        }
        if (-not $displayName -or -not $description) {
            $manifestMeta = Get-WnstAppxManifestMetadata -InstalledItems $installedItems
            if (-not $displayName -and (Test-WnstReadableAppxMetadataText ([string]$manifestMeta.DisplayName))) { $displayName = ([string]$manifestMeta.DisplayName).Trim() }
            if (-not $description -and (Test-WnstReadableAppxMetadataText ([string]$manifestMeta.Description))) { $description = ([string]$manifestMeta.Description).Trim() }
        }
        if (-not $displayName) { $displayName = Get-WnstAppxFriendlyName $name }

        $isTechnicalName = Test-WnstTechnicalAppxName -PackageName $name -DisplayName $displayName
        $descriptionKind = if ($isTechnicalName) { 'Technical' } elseif (-not [bool]$classification.IsSelectable) { 'Protected' } elseif ($name -like 'Microsoft*' -or $name -like 'microsoft*') { 'Windows' } else { 'ThirdParty' }

        $results.Add([pscustomobject]@{
            DisplayName = $displayName
            PackageName = $name
            CatalogId = $catalogId
            PackageFamilyName = $pfn
            Description = $description
            DescriptionKind = $descriptionKind
            IsTechnicalName = [bool]$isTechnicalName
            SortGroup = if ($isTechnicalName) { 1 } else { 0 }
            Indicator = $classification.Indicator
            IsSelectable = [bool]$classification.IsSelectable
            IsChecked = [bool]$classification.IsChecked
            Installed = ($installedItems.Count -gt 0)
            Provisioned = ($provisionedItems.Count -gt 0)
            InstalledPackageFullNames = @($installedItems | ForEach-Object { [string]$_.PackageFullName } | Where-Object { $_ } | Sort-Object -Unique)
            InstallLocations = @($installedItems | ForEach-Object { [string]$_.InstallLocation } | Where-Object { $_ } | Sort-Object -Unique)
            Versions = @($installedItems | ForEach-Object { [string]$_.Version } | Where-Object { $_ } | Sort-Object -Unique)
            Architectures = @($installedItems | ForEach-Object { [string]$_.Architecture } | Where-Object { $_ } | Sort-Object -Unique)
            Publishers = @($installedItems | ForEach-Object { [string]$_.Publisher } | Where-Object { $_ } | Sort-Object -Unique)
            SignatureKinds = @($installedItems | ForEach-Object { [string]$_.SignatureKind } | Where-Object { $_ } | Sort-Object -Unique)
            ProvisionedPackageNames = @($provisionedItems | ForEach-Object { [string]$_.PackageName } | Where-Object { $_ } | Sort-Object -Unique)
            ReasonCode = [string]$classification.ReasonCode
            IsStartSuggestion = $false
            StartPinId = ''
        })
    }

    foreach ($suggestion in @(Get-WnstStartMenuSuggestionInventory -InstalledByName $installedByName -ProvisionedByName $provisionedByName)) {
        $results.Add($suggestion)
    }

    return @($results | Sort-Object @{Expression='SortGroup';Ascending=$true}, @{Expression='DisplayName';Ascending=$true}, @{Expression='PackageName';Ascending=$true})
}

function Add-WnstAppxProgress {
    param(
        [object]$Queue,
        [string]$Kind,
        [string]$PackageName = '',
        [string]$DisplayName = '',
        [string]$Text = ''
    )

    if (-not $Queue) { return }
    try {
        $Queue.Enqueue([pscustomobject]@{
            Kind = $Kind
            PackageName = $PackageName
            DisplayName = $DisplayName
            Text = $Text
        })
    }
    catch {}
}

function Remove-WnstAppxUserData {
    param([Parameter(Mandatory=$true)][string]$PackageFamilyName)
    $results = [Collections.Generic.List[object]]::new()
    foreach ($profile in @(Get-CimInstance Win32_UserProfile -ErrorAction Ignore | Where-Object { -not $_.Special -and $_.LocalPath -and (Test-Path -LiteralPath $_.LocalPath) })) {
        $path = Join-Path ([string]$profile.LocalPath) ("AppData\Local\Packages\{0}" -f $PackageFamilyName)
        if (-not (Test-Path -LiteralPath $path)) { continue }
        try { Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction Stop; $results.Add([pscustomobject]@{Path=$path;Success=$true;Error=''}) }
        catch { $results.Add([pscustomobject]@{Path=$path;Success=$false;Error=[string]$_.Exception.Message}) }
    }
    return @($results)
}

function Remove-WnstAppxPackages {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string[]]$PackageNames,
        [string[]]$AllowedProtectedPackageNames = @(),
        [switch]$RemoveUserData,
        [object]$ProgressQueue = $null
    )

    if (-not (Test-WnstDebloatAdministrator)) { throw 'AdministratorRequired' }

    $inventory = @(Get-WnstAppxInventory)
    $byName = @{}
    foreach ($item in $inventory) { $byName[[string]$item.PackageName] = $item }

    $allowedProtected = @{}
    foreach ($name in @($AllowedProtectedPackageNames | Where-Object { $_ })) {
        $allowedProtected[[string]$name] = $true
    }

    $provisionedSnapshot = @(Get-AppxProvisionedPackage -Online -ErrorAction Ignore)
    $workResults = [Collections.Generic.List[object]]::new()

    foreach ($packageName in @($PackageNames | Where-Object { $_ } | Sort-Object -Unique)) {
        if (-not $byName.ContainsKey($packageName)) {
            $workResults.Add([pscustomobject]@{
                PackageName=$packageName; DisplayName=$packageName; Status='NotFound'
                InstalledRemoved=0; ProvisionedRemoved=0; UserDataRemoved=0
                Errors=@(); IgnoredErrors=@()
            })
            continue
        }

        $item = $byName[$packageName]
        $displayName = if ([string]::IsNullOrWhiteSpace([string]$item.DisplayName)) { $packageName } else { [string]$item.DisplayName }

        if (-not [bool]$item.IsSelectable -and -not $allowedProtected.ContainsKey([string]$packageName)) {
            $workResults.Add([pscustomobject]@{
                PackageName=$packageName; DisplayName=$displayName; Status='Blocked'
                InstalledRemoved=0; ProvisionedRemoved=0; UserDataRemoved=0
                Errors=@(); IgnoredErrors=@()
            })
            continue
        }

        Add-WnstAppxProgress -Queue $ProgressQueue -Kind 'PackageStart' -PackageName $packageName -DisplayName $displayName

        $packageErrors = [Collections.Generic.List[string]]::new()
        $userDataErrors = [Collections.Generic.List[string]]::new()
        $installedRemoved = 0
        $provisionedRemoved = 0
        $userDataRemoved = 0

        # IMPORTANT : retirer d'abord le package provisionné.
        # Si on supprime d'abord l'AppX installé, Windows peut supprimer son chemin
        # physique puis Remove-AppxProvisionedPackage renvoie "chemin introuvable".
        foreach ($package in @($provisionedSnapshot | Where-Object { $_.DisplayName -eq $packageName })) {
            if (-not $package.PackageName) { continue }
            $provName = [string]$package.PackageName
            Add-WnstAppxProgress -Queue $ProgressQueue -Kind 'Command' -PackageName $packageName -DisplayName $displayName -Text ('Remove-AppxProvisionedPackage -Online -PackageName "{0}" -AllUsers' -f $provName)
            try {
                Remove-AppxProvisionedPackage -Online -PackageName $provName -AllUsers -ErrorAction Stop | Out-Null
                $provisionedRemoved++
                Add-WnstAppxProgress -Queue $ProgressQueue -Kind 'Ok' -PackageName $packageName -DisplayName $displayName -Text $provName
            }
            catch {
                $message = [string]$_.Exception.Message
                $packageErrors.Add($message)
                Add-WnstAppxProgress -Queue $ProgressQueue -Kind 'DeferredWarning' -PackageName $packageName -DisplayName $displayName -Text $message
            }
        }

        foreach ($package in @(Get-AppxPackage -AllUsers -Name $packageName -ErrorAction Ignore)) {
            if (-not $package.PackageFullName) { continue }
            $fullName = [string]$package.PackageFullName
            Add-WnstAppxProgress -Queue $ProgressQueue -Kind 'Command' -PackageName $packageName -DisplayName $displayName -Text ('Remove-AppxPackage -Package "{0}" -AllUsers' -f $fullName)
            try {
                Remove-AppxPackage -Package $fullName -AllUsers -ErrorAction Stop
                $installedRemoved++
                Add-WnstAppxProgress -Queue $ProgressQueue -Kind 'Ok' -PackageName $packageName -DisplayName $displayName -Text $fullName
            }
            catch {
                $message = [string]$_.Exception.Message
                $packageErrors.Add($message)
                Add-WnstAppxProgress -Queue $ProgressQueue -Kind 'DeferredWarning' -PackageName $packageName -DisplayName $displayName -Text $message
            }
        }

        if ($RemoveUserData -and $item.PackageFamilyName) {
            foreach ($dataResult in @(Remove-WnstAppxUserData -PackageFamilyName ([string]$item.PackageFamilyName))) {
                if ($dataResult.Success) {
                    $userDataRemoved++
                    Add-WnstAppxProgress -Queue $ProgressQueue -Kind 'Ok' -PackageName $packageName -DisplayName $displayName -Text ([string]$dataResult.Path)
                }
                else {
                    $message = [string]$dataResult.Error
                    $userDataErrors.Add($message)
                    Add-WnstAppxProgress -Queue $ProgressQueue -Kind 'DeferredWarning' -PackageName $packageName -DisplayName $displayName -Text $message
                }
            }
        }

        $workResults.Add([pscustomobject]@{
            PackageName=$packageName
            DisplayName=$displayName
            Status='PendingVerification'
            InstalledRemoved=$installedRemoved
            ProvisionedRemoved=$provisionedRemoved
            UserDataRemoved=$userDataRemoved
            Errors=@()
            PackageErrors=@($packageErrors)
            UserDataErrors=@($userDataErrors)
            IgnoredErrors=@()
        })
    }

    # L'état réellement présent après les commandes décide du résultat.
    $remainingInstalled = @{}
    foreach ($package in @(Get-AppxPackage -AllUsers -ErrorAction Ignore)) {
        if ($package.Name) { $remainingInstalled[[string]$package.Name] = $true }
    }

    $remainingProvisioned = @{}
    foreach ($package in @(Get-AppxProvisionedPackage -Online -ErrorAction Ignore)) {
        if ($package.DisplayName) { $remainingProvisioned[[string]$package.DisplayName] = $true }
    }

    foreach ($result in $workResults) {
        if ($result.Status -ne 'PendingVerification') { continue }

        $stillInstalled = $remainingInstalled.ContainsKey([string]$result.PackageName)
        $stillProvisioned = $remainingProvisioned.ContainsKey([string]$result.PackageName)
        $packageGone = (-not $stillInstalled -and -not $stillProvisioned)

        $finalErrors = [Collections.Generic.List[string]]::new()
        $ignoredErrors = [Collections.Generic.List[string]]::new()

        if ($packageGone) {
            # Les erreurs des commandes AppX/provisioning sont sans conséquence
            # si la vérification finale confirme que le package a réellement disparu.
            foreach ($e in @($result.PackageErrors)) {
                if (-not [string]::IsNullOrWhiteSpace([string]$e)) { $ignoredErrors.Add([string]$e) }
            }

            # Les données utilisateur sont une demande distincte : leur échec reste réel.
            foreach ($e in @($result.UserDataErrors)) {
                if (-not [string]::IsNullOrWhiteSpace([string]$e)) { $finalErrors.Add([string]$e) }
            }

            $result.Status = if ($finalErrors.Count -eq 0) { 'Removed' } else { 'Partial' }
        }
        else {
            foreach ($e in @($result.PackageErrors) + @($result.UserDataErrors)) {
                if (-not [string]::IsNullOrWhiteSpace([string]$e)) { $finalErrors.Add([string]$e) }
            }

            if ($stillInstalled) {
                $finalErrors.Add('RemainingInstalled')
            }
            if ($stillProvisioned) {
                $finalErrors.Add('RemainingProvisioned')
            }
            $result.Status = 'Partial'
        }

        $result.Errors = @($finalErrors)
        $result.IgnoredErrors = @($ignoredErrors)
        Add-Member -InputObject $result -NotePropertyName RemainingInstalled -NotePropertyValue ([int]$stillInstalled) -Force
        Add-Member -InputObject $result -NotePropertyName RemainingProvisioned -NotePropertyValue ([int]$stillProvisioned) -Force

        # Le journal n'affiche les erreurs qu'après vérification, uniquement si elles
        # correspondent encore à un vrai problème final.
        foreach ($e in @($finalErrors)) {
            Add-WnstAppxProgress -Queue $ProgressQueue -Kind 'FinalError' -PackageName ([string]$result.PackageName) -DisplayName ([string]$result.DisplayName) -Text ([string]$e)
        }
        Add-WnstAppxProgress -Queue $ProgressQueue -Kind 'Verified' -PackageName ([string]$result.PackageName) -DisplayName ([string]$result.DisplayName) -Text ([string]$result.Status)
    }

    return @($workResults)
}

function Disable-WnstStartMenuSuggestions {
    # Désactive les principaux mécanismes Windows qui injectent des applications,
    # raccourcis et recommandations sponsorisées. Cela ne modifie pas les épingles
    # choisies manuellement par l'utilisateur.
    $contentPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
    $advancedPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
    $accountPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\SystemSettings\AccountNotifications'
    $engagementPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement'
    $suggestedToastPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings\Windows.SystemToast.Suggested'

    New-Item -Path $contentPath -Force -ErrorAction Stop | Out-Null
    foreach ($name in @(
        'SubscribedContent-310093Enabled',
        'SubscribedContent-338388Enabled',
        'SubscribedContent-338389Enabled',
        'SubscribedContent-338393Enabled',
        'SubscribedContent-353694Enabled',
        'SubscribedContent-353696Enabled',
        'SubscribedContent-353698Enabled',
        'SystemPaneSuggestionsEnabled',
        'SoftLandingEnabled',
        'SilentInstalledAppsEnabled'
    )) {
        New-ItemProperty -Path $contentPath -Name $name -PropertyType DWord -Value 0 -Force -ErrorAction Stop | Out-Null
    }

    New-Item -Path $advancedPath -Force -ErrorAction Stop | Out-Null
    foreach ($entry in @{
        Start_IrisRecommendations = 0
        ShowSyncProviderNotifications = 0
        Start_AccountNotifications = 0
    }.GetEnumerator()) {
        New-ItemProperty -Path $advancedPath -Name ([string]$entry.Key) -PropertyType DWord -Value ([int]$entry.Value) -Force -ErrorAction Stop | Out-Null
    }

    New-Item -Path $accountPath -Force -ErrorAction SilentlyContinue | Out-Null
    New-ItemProperty -Path $accountPath -Name 'EnableAccountNotifications' -PropertyType DWord -Value 0 -Force -ErrorAction SilentlyContinue | Out-Null

    New-Item -Path $engagementPath -Force -ErrorAction SilentlyContinue | Out-Null
    New-ItemProperty -Path $engagementPath -Name 'ScoobeSystemSettingEnabled' -PropertyType DWord -Value 0 -Force -ErrorAction SilentlyContinue | Out-Null

    New-Item -Path $suggestedToastPath -Force -ErrorAction SilentlyContinue | Out-Null
    New-ItemProperty -Path $suggestedToastPath -Name 'Enabled' -PropertyType DWord -Value 0 -Force -ErrorAction SilentlyContinue | Out-Null
}

function Get-WnstStartPinPackageName {
    param([AllowEmptyString()][string]$PackagedAppId)

    if ([string]::IsNullOrWhiteSpace($PackagedAppId)) { return '' }
    $bang = $PackagedAppId.IndexOf('!')
    if ($bang -le 0) { return '' }
    $family = $PackagedAppId.Substring(0,$bang)
    $underscore = $family.LastIndexOf('_')
    if ($underscore -le 0) { return '' }
    return $family.Substring(0,$underscore)
}

function Get-WnstStartPinTargetsForPackageNames {
    [CmdletBinding()]
    param([AllowEmptyCollection()][string[]]$PackageNames=@())

    $wanted = @{}
    foreach ($name in @($PackageNames)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$name)) {
            $wanted[[string]$name.ToLowerInvariant()] = [string]$name
        }
    }
    if ($wanted.Count -eq 0) { return @() }

    $tempPath = Join-Path $env:TEMP ('WNST-StartPinsScan-{0}.json' -f ([Guid]::NewGuid().ToString('N')))
    $targets = [Collections.Generic.List[object]]::new()
    try {
        if (-not (Get-Command Export-StartLayout -ErrorAction SilentlyContinue)) { return @() }
        Export-StartLayout -Path $tempPath -ErrorAction Stop | Out-Null
        $layout = ([IO.File]::ReadAllText($tempPath,[Text.Encoding]::UTF8) | ConvertFrom-Json -ErrorAction Stop)
        foreach ($pin in @($layout.pinnedList)) {
            $pinId = [string]$pin.packagedAppId
            $packageName = Get-WnstStartPinPackageName -PackagedAppId $pinId
            if ([string]::IsNullOrWhiteSpace($packageName)) { continue }
            if (-not $wanted.ContainsKey($packageName.ToLowerInvariant())) { continue }
            $targets.Add([pscustomobject]@{
                PackageName = $packageName
                DisplayName = Get-WnstAppxFriendlyName $packageName
                StartPinId = $pinId
                ReportResult = $false
            })
        }
    }
    catch {}
    finally {
        if (Test-Path -LiteralPath $tempPath) { Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue }
    }
    return @($targets)
}

function Test-WnstStartPinsStillPresent {
    param(
        [Parameter(Mandatory=$true)][string[]]$PinIds,
        [switch]$ThrowOnError
    )

    $wanted = @{}
    foreach ($id in @($PinIds)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$id)) { $wanted[[string]$id] = $true }
    }
    if ($wanted.Count -eq 0) { return @() }

    $tempPath = Join-Path $env:TEMP ('WNST-StartPinsVerify-{0}.json' -f ([Guid]::NewGuid().ToString('N')))
    try {
        Export-StartLayout -Path $tempPath -ErrorAction Stop | Out-Null
        $layout = ([IO.File]::ReadAllText($tempPath,[Text.Encoding]::UTF8) | ConvertFrom-Json -ErrorAction Stop)
        $remaining = [Collections.Generic.List[string]]::new()
        foreach ($pin in @($layout.pinnedList)) {
            $id = [string]$pin.packagedAppId
            if ($wanted.ContainsKey($id)) { $remaining.Add($id) }
        }
        return @($remaining)
    }
    catch {
        if ($ThrowOnError) { throw }
        return @($PinIds)
    }
    finally {
        if (Test-Path -LiteralPath $tempPath) { Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue }
    }
}

function Restart-WnstStartMenuHost {
    try { Get-Process -Name 'StartMenuExperienceHost' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue } catch {}
}

function Get-WnstStartMenuCleanupPaths {
    param([Parameter(Mandatory=$true)][string]$DataRoot)

    $root = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($DataRoot))
    $folder = Join-Path $root 'StartMenu'
    return [pscustomobject]@{
        Folder = $folder
        Manifest = Join-Path $folder 'PendingCleanup.json'
        Layout = Join-Path $folder 'LayoutModification.json'
    }
}

function Read-WnstPendingStartMenuCleanup {
    param([Parameter(Mandatory=$true)][string]$DataRoot)

    $paths = Get-WnstStartMenuCleanupPaths -DataRoot $DataRoot
    if (-not (Test-Path -LiteralPath $paths.Manifest -PathType Leaf)) { return $null }
    try {
        $raw = [IO.File]::ReadAllText($paths.Manifest,[Text.Encoding]::UTF8)
        if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
        return ($raw | ConvertFrom-Json -ErrorAction Stop)
    }
    catch { return $null }
}

function Get-WnstBootSessionId {
    try {
        $bootTime = (Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop).LastBootUpTime
        if ($bootTime) {
            if ($bootTime -is [DateTime]) { return ('CIM:{0}' -f $bootTime.ToUniversalTime().Ticks) }
            $converted = [Management.ManagementDateTimeConverter]::ToDateTime([string]$bootTime)
            return ('CIM:{0}' -f $converted.ToUniversalTime().Ticks)
        }
    }
    catch {}

    try {
        $bootId = Get-ItemPropertyValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters' -Name 'BootId' -ErrorAction Stop
        if ($null -ne $bootId) { return ('REG:{0}' -f [string]$bootId) }
    }
    catch {}

    throw 'BootSessionUnavailable'
}

function Save-WnstPendingStartMenuCleanup {
    param(
        [Parameter(Mandatory=$true)][string]$DataRoot,
        [Parameter(Mandatory=$true)][string[]]$PinIds,
        [AllowEmptyString()][string]$PolicyArmedBootId = ''
    )

    $paths = Get-WnstStartMenuCleanupPaths -DataRoot $DataRoot
    New-Item -ItemType Directory -Path $paths.Folder -Force -ErrorAction Stop | Out-Null
    $previous = Read-WnstPendingStartMenuCleanup -DataRoot $DataRoot
    $createdUtc = if ($previous -and $previous.CreatedUtc) { [string]$previous.CreatedUtc } else { [DateTime]::UtcNow.ToString('o') }
    $previousBootId = if ($previous -and $null -ne $previous.PSObject.Properties['PolicyArmedBootId']) { [string]$previous.PolicyArmedBootId } else { '' }
    $armedBootId = if (-not [string]::IsNullOrWhiteSpace($PolicyArmedBootId)) { $PolicyArmedBootId } else { $previousBootId }
    $payload = [ordered]@{
        SchemaVersion = 2
        CreatedUtc = $createdUtc
        UpdatedUtc = [DateTime]::UtcNow.ToString('o')
        PinIds = @($PinIds | Where-Object { $_ } | Sort-Object -Unique)
        LayoutPath = [string]$paths.Layout
        PolicyArmedBootId = $armedBootId
    } | ConvertTo-Json -Depth 8
    $temporaryPath = $paths.Manifest + '.' + [Guid]::NewGuid().ToString('N') + '.tmp'
    try {
        [IO.File]::WriteAllText($temporaryPath,$payload,(New-Object Text.UTF8Encoding($false)))
        Move-Item -LiteralPath $temporaryPath -Destination $paths.Manifest -Force -ErrorAction Stop
    }
    finally {
        if (Test-Path -LiteralPath $temporaryPath) { Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue }
    }
    return $paths
}

function Test-WnstStartPinsPathEqual {
    param(
        [AllowEmptyString()][string]$FirstPath,
        [AllowEmptyString()][string]$SecondPath
    )

    if ([string]::IsNullOrWhiteSpace($FirstPath) -or [string]::IsNullOrWhiteSpace($SecondPath)) { return $false }
    try {
        $first = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($FirstPath))
        $second = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($SecondPath))
        return [string]::Equals($first,$second,[StringComparison]::OrdinalIgnoreCase)
    }
    catch { return $false }
}

function Get-WnstRegistryPropertyValue {
    param([Parameter(Mandatory=$true)][string]$Path,[Parameter(Mandatory=$true)][string]$Name)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try {
        $properties = Get-ItemProperty -LiteralPath $Path -ErrorAction Stop
        $property = $properties.PSObject.Properties[$Name]
        if ($property) { return $property.Value }
    }
    catch { }
    return $null
}

function Remove-WnstRegistryPropertyIfPresent {
    param([Parameter(Mandatory=$true)][string]$Path,[Parameter(Mandatory=$true)][string]$Name)
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    $properties = Get-ItemProperty -LiteralPath $Path -ErrorAction Stop
    if (-not $properties.PSObject.Properties[$Name]) { return $false }
    Remove-ItemProperty -LiteralPath $Path -Name $Name -Force -ErrorAction Stop
    return $true
}

function Test-WnstStartPinsPolicyOwned {
    param([Parameter(Mandatory=$true)][string]$LayoutPath)

    $policyPath = 'HKCU:\Software\Policies\Microsoft\Windows\Explorer'
    try {
        $configured = Get-WnstRegistryPropertyValue -Path $policyPath -Name 'ConfigureStartPins'
        $configuredJson = [string](Get-WnstRegistryPropertyValue -Path $policyPath -Name 'ConfigureStartPinsJSON')
        if ($null -eq $configured) { return $false }

        # Format ADMX Windows 11 24H2+ : activation DWORD + chemin JSON séparé.
        if ($configured -isnot [string] -and [int]$configured -eq 1 -and
            (Test-WnstStartPinsPathEqual -FirstPath $configuredJson -SecondPath $LayoutPath)) { return $true }

        # Compatibilité/migration avec les RC WNST qui avaient écrit directement
        # le chemin dans ConfigureStartPins sous forme de chaîne.
        return ($configured -is [string] -and
            (Test-WnstStartPinsPathEqual -FirstPath ([string]$configured) -SecondPath $LayoutPath))
    }
    catch { return $false }
}

function Test-WnstStartPinsPolicyConflict {
    param([Parameter(Mandatory=$true)][string]$OwnedLayoutPath)

    foreach ($path in @(
        'HKCU:\Software\Policies\Microsoft\Windows\Explorer',
        'HKLM:\Software\Policies\Microsoft\Windows\Explorer'
    )) {
        $configured = Get-WnstRegistryPropertyValue -Path $path -Name 'ConfigureStartPins'
        $legacyPath = Get-WnstRegistryPropertyValue -Path $path -Name 'ConfigureStartPinsJSON'
        if ($null -eq $configured -and $null -eq $legacyPath) { continue }
        if ($path.StartsWith('HKCU:',[StringComparison]::OrdinalIgnoreCase) -and (Test-WnstStartPinsPolicyOwned -LayoutPath $OwnedLayoutPath)) { continue }
        return $true
    }
    return $false
}

function Enable-WnstStartPinsPolicy {
    param([Parameter(Mandatory=$true)][string]$LayoutPath)

    $policyPath = 'HKCU:\Software\Policies\Microsoft\Windows\Explorer'
    New-Item -Path $policyPath -Force -ErrorAction Stop | Out-Null

    # New-ItemProperty -Force ne change pas toujours le type d'une valeur déjà
    # présente. Supprimer les deux valeurs WNST avant de recréer exactement le
    # couple attendu par StartMenu.admx évite l'échec DWORD -> String observé.
    [void](Remove-WnstRegistryPropertyIfPresent -Path $policyPath -Name 'ConfigureStartPins')
    [void](Remove-WnstRegistryPropertyIfPresent -Path $policyPath -Name 'ConfigureStartPinsJSON')
    New-ItemProperty -Path $policyPath -Name 'ConfigureStartPinsJSON' -PropertyType ExpandString -Value $LayoutPath -Force -ErrorAction Stop | Out-Null
    New-ItemProperty -Path $policyPath -Name 'ConfigureStartPins' -PropertyType DWord -Value 1 -Force -ErrorAction Stop | Out-Null
}

function Clear-WnstStartPinsPolicy {
    param([Parameter(Mandatory=$true)][string]$LayoutPath)

    if (-not (Test-WnstStartPinsPolicyOwned -LayoutPath $LayoutPath)) { return $false }
    $policyPath = 'HKCU:\Software\Policies\Microsoft\Windows\Explorer'
    [void](Remove-WnstRegistryPropertyIfPresent -Path $policyPath -Name 'ConfigureStartPins')
    [void](Remove-WnstRegistryPropertyIfPresent -Path $policyPath -Name 'ConfigureStartPinsJSON')
    return $true
}

function Remove-WnstPendingStartMenuCleanupFiles {
    param([Parameter(Mandatory=$true)][string]$DataRoot)

    $paths = Get-WnstStartMenuCleanupPaths -DataRoot $DataRoot
    foreach ($path in @($paths.Manifest,$paths.Layout)) {
        if (Test-Path -LiteralPath $path -PathType Leaf) { Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue }
    }
    if (Test-Path -LiteralPath $paths.Folder -PathType Container) {
        if (@(Get-ChildItem -LiteralPath $paths.Folder -Force -ErrorAction SilentlyContinue).Count -eq 0) {
            Remove-Item -LiteralPath $paths.Folder -Force -ErrorAction SilentlyContinue
        }
    }
}

function Complete-WnstPendingStartMenuCleanup {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$DataRoot)

    $pending = Read-WnstPendingStartMenuCleanup -DataRoot $DataRoot
    if (-not $pending) { return [pscustomobject]@{ State='None'; RemainingCount=0; ErrorCode='' } }

    $paths = Get-WnstStartMenuCleanupPaths -DataRoot $DataRoot
    $pinIds = @($pending.PinIds | Where-Object { $_ } | Sort-Object -Unique)
    if ($pinIds.Count -eq 0) {
        [void](Clear-WnstStartPinsPolicy -LayoutPath $paths.Layout)
        Remove-WnstPendingStartMenuCleanupFiles -DataRoot $DataRoot
        return [pscustomobject]@{ State='Completed'; RemainingCount=0; ErrorCode='' }
    }

    if (-not (Test-Path -LiteralPath $paths.Layout -PathType Leaf)) {
        return [pscustomobject]@{ State='Failed'; RemainingCount=$pinIds.Count; ErrorCode='StartLayoutApplyFailed' }
    }
    if (Test-WnstStartPinsPolicyConflict -OwnedLayoutPath $paths.Layout) {
        return [pscustomobject]@{ State='Failed'; RemainingCount=$pinIds.Count; ErrorCode='StartPinsPolicyManaged' }
    }

    try { $currentBootId = Get-WnstBootSessionId }
    catch { return [pscustomobject]@{ State='Failed'; RemainingCount=$pinIds.Count; ErrorCode='StartLayoutApplyFailed' } }

    $armedBootId = if ($null -ne $pending.PSObject.Properties['PolicyArmedBootId']) { [string]$pending.PolicyArmedBootId } else { '' }
    $policyOwned = Test-WnstStartPinsPolicyOwned -LayoutPath $paths.Layout

    # Une ancienne RC peut avoir laissé un manifeste sans identifiant de boot,
    # ou la stratégie peut avoir été retirée avant son application. Dans les deux
    # cas on la réarme et on exige un véritable redémarrage avant toute validation.
    if (-not $policyOwned -or [string]::IsNullOrWhiteSpace($armedBootId)) {
        try {
            Enable-WnstStartPinsPolicy -LayoutPath $paths.Layout
            [void](Save-WnstPendingStartMenuCleanup -DataRoot $DataRoot -PinIds $pinIds -PolicyArmedBootId $currentBootId)
        }
        catch {
            [void](Clear-WnstStartPinsPolicy -LayoutPath $paths.Layout)
            return [pscustomobject]@{ State='Failed'; RemainingCount=$pinIds.Count; ErrorCode='StartLayoutApplyFailed' }
        }
        return [pscustomobject]@{ State='PendingRestart'; RemainingCount=$pinIds.Count; ErrorCode='' }
    }

    # Export-StartLayout reflète immédiatement le JSON de la stratégie, même si
    # le menu affiché utilise encore son ancien cache. Tant que Windows n'a pas
    # redémarré, son résultat ne constitue donc pas une preuve de suppression.
    if ([string]::Equals($armedBootId,$currentBootId,[StringComparison]::Ordinal)) {
        return [pscustomobject]@{ State='PendingRestart'; RemainingCount=$pinIds.Count; ErrorCode='' }
    }

    try {
        $remaining = @(Test-WnstStartPinsStillPresent -PinIds $pinIds -ThrowOnError)
    }
    catch {
        [void](Clear-WnstStartPinsPolicy -LayoutPath $paths.Layout)
        Remove-WnstPendingStartMenuCleanupFiles -DataRoot $DataRoot
        return [pscustomobject]@{
            State='Completed'
            RemainingCount=0
            ErrorCode=''
        }
    }
    if ($remaining.Count -eq 0) {
        [void](Clear-WnstStartPinsPolicy -LayoutPath $paths.Layout)
        Remove-WnstPendingStartMenuCleanupFiles -DataRoot $DataRoot
        return [pscustomobject]@{ State='Completed'; RemainingCount=0; ErrorCode='' }
    }

    # Le redémarrage a eu lieu mais Windows expose encore des épingles ciblées :
    # réarmer proprement la stratégie pour une nouvelle tentative contrôlée.
    try {
        Enable-WnstStartPinsPolicy -LayoutPath $paths.Layout
        [void](Save-WnstPendingStartMenuCleanup -DataRoot $DataRoot -PinIds $remaining -PolicyArmedBootId $currentBootId)
    }
    catch { return [pscustomobject]@{ State='Failed'; RemainingCount=$remaining.Count; ErrorCode='StartLayoutApplyFailed' } }
    return [pscustomobject]@{ State='PendingRestart'; RemainingCount=$remaining.Count; ErrorCode='' }
}

function Invoke-WnstStartMenuPostDebloatCleanup {
    [CmdletBinding()]
    param([object]$ProgressQueue=$null)

    # Un AppX supprimé peut laisser un nom ms-resource:* dans « Toutes les applications ».
    # On ne détruit ni start2.bin ni les épingles utilisateur : seul le cache TempState du
    # StartMenuExperienceHost est vidé, et uniquement lorsqu'un résidu est réellement vu.
    $ghosts = @()
    try { $ghosts = @(Get-StartApps -ErrorAction SilentlyContinue | Where-Object { [string]$_.Name -match '^(?i)ms-resource:' }) } catch {}
    if ($ghosts.Count -eq 0) {
        Restart-WnstStartMenuHost
        return
    }

    Add-WnstAppxProgress -Queue $ProgressQueue -Kind 'SuggestionAction' -Text 'StartMenuCacheCleanup'
    try {
        Restart-WnstStartMenuHost
        Start-Sleep -Milliseconds 250
        $tempState = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.Windows.StartMenuExperienceHost_cw5n1h2txyewy\TempState'
        if (Test-Path -LiteralPath $tempState) {
            Remove-Item -LiteralPath $tempState -Recurse -Force -ErrorAction SilentlyContinue
        }
        Restart-WnstStartMenuHost
        Add-WnstAppxProgress -Queue $ProgressQueue -Kind 'SuggestionAction' -Text 'StartMenuCacheUpdated'
    }
    catch {}
}

function Remove-WnstStartMenuSuggestions {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object[]]$Suggestions,
        [Parameter(Mandatory=$true)][string]$DataRoot,
        [object]$ProgressQueue = $null
    )

    $targets = @($Suggestions | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.StartPinId) })
    if ($targets.Count -eq 0) { return @() }

    $results = [Collections.Generic.List[object]]::new()
    $targetByPin = @{}
    foreach ($target in $targets) { $targetByPin[[string]$target.StartPinId] = $target }
    $paths = Get-WnstStartMenuCleanupPaths -DataRoot $DataRoot
    $pending = Read-WnstPendingStartMenuCleanup -DataRoot $DataRoot
    $pendingPinIds = if ($pending) { @($pending.PinIds) } else { @() }
    $pinIds = @(@($targetByPin.Keys) + $pendingPinIds | Where-Object { $_ } | Sort-Object -Unique)

    try { Disable-WnstStartMenuSuggestions } catch {}

    foreach ($target in $targets) {
        Add-WnstAppxProgress -Queue $ProgressQueue -Kind 'SuggestionStart' -PackageName ([string]$target.PackageName) -DisplayName ([string]$target.DisplayName) -Text ([string]$target.StartPinId)
    }

    $failureCode = ''
    $failureDetail = ''
    $policyArmed = $false
    $sourcePath = Join-Path $env:TEMP ('WNST-StartPins-{0}.json' -f ([Guid]::NewGuid().ToString('N')))
    try {
        if (-not (Get-Command Export-StartLayout -ErrorAction SilentlyContinue)) { throw 'StartLayoutUnsupported' }
        if (Test-WnstStartPinsPolicyConflict -OwnedLayoutPath $paths.Layout) { throw 'StartPinsPolicyManaged' }

        # Le dossier n'existe pas encore lors du tout premier nettoyage. Il doit
        # être créé avant l'écriture atomique de LayoutModification.json ; la
        # sauvegarde du manifeste, appelée plus bas, arrive trop tard pour cela.
        New-Item -ItemType Directory -Path $paths.Folder -Force -ErrorAction Stop | Out-Null

        Export-StartLayout -Path $sourcePath -ErrorAction Stop | Out-Null
        $layout = ([IO.File]::ReadAllText($sourcePath,[Text.Encoding]::UTF8) | ConvertFrom-Json -ErrorAction Stop)
        if ($null -eq $layout.pinnedList) { throw 'StartLayoutUnsupported' }

        $targetSet = @{}
        foreach ($id in $pinIds) { $targetSet[[string]$id] = $true }
        $layout.pinnedList = @($layout.pinnedList | Where-Object {
            $id = [string]$_.packagedAppId
            [string]::IsNullOrWhiteSpace($id) -or -not $targetSet.ContainsKey($id)
        })
        if ($null -eq $layout.PSObject.Properties['applyOnce']) {
            Add-Member -InputObject $layout -NotePropertyName applyOnce -NotePropertyValue $true
        }
        else { $layout.applyOnce = $true }

        $json = $layout | ConvertTo-Json -Depth 30 -Compress
        $layoutTemporaryPath = $paths.Layout + '.' + [Guid]::NewGuid().ToString('N') + '.tmp'
        try {
            [IO.File]::WriteAllText($layoutTemporaryPath,$json,(New-Object Text.UTF8Encoding($false)))
            Move-Item -LiteralPath $layoutTemporaryPath -Destination $paths.Layout -Force -ErrorAction Stop
        }
        finally {
            if (Test-Path -LiteralPath $layoutTemporaryPath) { Remove-Item -LiteralPath $layoutTemporaryPath -Force -ErrorAction SilentlyContinue }
        }

        Enable-WnstStartPinsPolicy -LayoutPath $paths.Layout
        try {
            $armedBootId = Get-WnstBootSessionId
            [void](Save-WnstPendingStartMenuCleanup -DataRoot $DataRoot -PinIds $pinIds -PolicyArmedBootId $armedBootId)
        }
        catch {
            [void](Clear-WnstStartPinsPolicy -LayoutPath $paths.Layout)
            throw
        }
        $policyArmed = $true
        Add-WnstAppxProgress -Queue $ProgressQueue -Kind 'SuggestionAction' -Text 'StartPinsPolicyArmed'
        Restart-WnstStartMenuHost
    }
    catch {
        $code = [string]$_.Exception.Message
        if ($code -notin @('StartLayoutUnsupported','StartPinsPolicyManaged')) {
            $failureDetail = $code
            $code = 'StartLayoutApplyFailed'
        }
        $failureCode = $code
    }
    finally {
        if (Test-Path -LiteralPath $sourcePath) { Remove-Item -LiteralPath $sourcePath -Force -ErrorAction SilentlyContinue }
    }

    # Ne jamais utiliser Export-StartLayout comme validation dans le même boot :
    # une stratégie nouvellement armée modifie déjà l'export avant le menu visible.
    $remaining = if ($policyArmed) { @($pinIds) } else { @(Test-WnstStartPinsStillPresent -PinIds $pinIds) }
    $remainingSet = @{}
    foreach ($id in $remaining) { $remainingSet[[string]$id] = $true }
    if ($remaining.Count -eq 0) {
        [void](Clear-WnstStartPinsPolicy -LayoutPath $paths.Layout)
        Remove-WnstPendingStartMenuCleanupFiles -DataRoot $DataRoot
        Add-WnstAppxProgress -Queue $ProgressQueue -Kind 'SuggestionAction' -Text 'StartPinsCleanupCompleted'
    }
    elseif ($policyArmed) {
        Add-WnstAppxProgress -Queue $ProgressQueue -Kind 'SuggestionAction' -Text 'StartPinsPendingRestart'
    }

    foreach ($target in $targets) {
        $pinId = [string]$target.StartPinId
        $status = if ($policyArmed) { 'PendingRestart' } elseif (-not $remainingSet.ContainsKey($pinId)) { 'Removed' } else { 'Partial' }
        $errorCode = if ($status -eq 'Partial' -and -not [string]::IsNullOrWhiteSpace($failureCode)) {
            if ($failureCode -eq 'StartLayoutApplyFailed' -and -not [string]::IsNullOrWhiteSpace($failureDetail)) {
                '{0}|{1}' -f $failureCode,$failureDetail
            }
            else { $failureCode }
        } elseif ($status -eq 'Partial') { 'StartSuggestionStillPinned' } else { '' }
        $errors = if ($status -eq 'Partial') { @($errorCode) } else { @() }
        if ($status -eq 'Partial') {
            Add-WnstAppxProgress -Queue $ProgressQueue -Kind 'FinalError' -PackageName ([string]$target.PackageName) -DisplayName ([string]$target.DisplayName) -Text $errorCode
        }
        Add-WnstAppxProgress -Queue $ProgressQueue -Kind 'Verified' -PackageName ([string]$target.PackageName) -DisplayName ([string]$target.DisplayName) -Text $status
        $report = $true
        if ($null -ne $target.PSObject.Properties['ReportResult']) { $report = [bool]$target.ReportResult }
        $results.Add([pscustomobject]@{
            PackageName=[string]$target.PackageName; DisplayName=[string]$target.DisplayName; Status=$status
            InstalledRemoved=0; ProvisionedRemoved=0; UserDataRemoved=0; Errors=$errors; IgnoredErrors=@()
            IsStartSuggestion=$true; StartPinId=$pinId; ReportResult=$report; RestartRequired=($status -eq 'PendingRestart')
        })
    }

    return @($results)
}
