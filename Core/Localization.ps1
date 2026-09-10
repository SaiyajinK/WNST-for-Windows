$script:LanguageDictionaryCache = @{}

function Get-AvailableLanguages {
    $languages = New-Object System.Collections.Generic.List[object]
    $localeRoot = Join-Path $script:AppRoot 'Locales'

    foreach ($path in @([IO.Directory]::EnumerateFiles($localeRoot, '*.json') | Sort-Object)) {
        try {
            $name = ''
            $reader = [IO.StreamReader]::new($path, [Text.Encoding]::UTF8, $true)
            try {
                for ($lineIndex = 0; $lineIndex -lt 6 -and -not $reader.EndOfStream; $lineIndex++) {
                    $line = $reader.ReadLine()
                    if ($line -match '"LanguageName"\s*:\s*"(?<LanguageName>[^"]+)"') {
                        $name = [string]$matches.LanguageName
                        break
                    }
                }
            }
            finally { $reader.Dispose() }

            if ([string]::IsNullOrWhiteSpace($name)) { continue }

            $languages.Add([pscustomobject]@{
                Code = [IO.Path]::GetFileNameWithoutExtension($path)
                Name = $name
            })
        }
        catch { }
    }

    return @($languages.ToArray())
}

function Get-HuLanguageDictionary {
    param([Parameter(Mandatory=$true)][string]$Code)

    if ($script:LanguageDictionaryCache.ContainsKey($Code)) {
        return $script:LanguageDictionaryCache[$Code]
    }

    $path = Join-Path (Join-Path $script:AppRoot 'Locales') ($Code + '.json')
    $data = [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8) | ConvertFrom-Json -ErrorAction Stop
    $dictionary = @{}
    foreach ($property in $data.PSObject.Properties) {
        $dictionary[$property.Name] = [string]$property.Value
    }

    $script:LanguageDictionaryCache[$Code] = $dictionary
    return $dictionary
}

function Import-AppLanguage {
    param([Parameter(Mandatory = $true)][string]$Code)

    $localeRoot = Join-Path $script:AppRoot 'Locales'
    $path = Join-Path $localeRoot ($Code + '.json')
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { $Code = 'en-US' }

    $fallback = Get-HuLanguageDictionary -Code 'en-US'
    if ($Code -eq 'en-US') {
        $script:Translations = $fallback.Clone()
        return $Code
    }

    $selected = Get-HuLanguageDictionary -Code $Code
    $dictionary = $fallback.Clone()
    foreach ($key in $selected.Keys) { $dictionary[$key] = [string]$selected[$key] }
    $script:Translations = $dictionary
    return $Code
}

function T {
    param([Parameter(Mandatory = $true)][string]$Key)
    if ($script:Translations.ContainsKey($Key)) { return [string]$script:Translations[$Key] }
    return $Key
}

function TF {
    param([string]$Key, [object[]]$Arguments)
    return ([string]::Format((T $Key), $Arguments))
}

function Show-LanguageDialog {
    param([object[]]$Languages)

    [xml]$languageXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="WNST" Width="320" Height="205" WindowStartupLocation="CenterScreen"
        ResizeMode="NoResize" WindowStyle="None" AllowsTransparency="True" Background="Transparent">
  <Window.Resources>
    <SolidColorBrush x:Key="DialogInputBrush" Color="#15181D"/>
    <SolidColorBrush x:Key="DialogTextBrush" Color="#F4F4F4"/>
    <SolidColorBrush x:Key="DialogAccentBrush" Color="#1A9FFF"/>
    <SolidColorBrush x:Key="DialogScrollHoverBrush" Color="#1A9FFF"/>
    <DataTemplate x:Key="Flag_sa">
      <Viewbox Width="30" Height="20" Stretch="Fill" xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation">
        <Canvas Width="30" Height="20"><Canvas.Clip><RectangleGeometry Rect="0,0,30,20" RadiusX="5" RadiusY="5"/></Canvas.Clip>
          <Rectangle Canvas.Left="0" Canvas.Top="0" Width="30" Height="20" Fill="#006C35"/><Path Data="M5 7 H24 M6 8.7 H22 M9 5.2 V10.2 M13 5.7 V9.6 M17 5.2 V10.1 M21 5.7 V9.2" Stroke="#fff" StrokeThickness="0.75"/><Path Data="M7 14.3 C13 15.1 19 15.1 24 13.8 M23.8 13.8 L25.6 13.1" Stroke="#fff" StrokeThickness="0.8"/>
        </Canvas>
      </Viewbox>
    </DataTemplate>
    <DataTemplate x:Key="Flag_bg">
      <Viewbox Width="30" Height="20" Stretch="Fill" xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation">
        <Canvas Width="30" Height="20"><Canvas.Clip><RectangleGeometry Rect="0,0,30,20" RadiusX="5" RadiusY="5"/></Canvas.Clip>
          <Rectangle Canvas.Left="0" Canvas.Top="0" Width="30" Height="20" Fill="#fff"/><Rectangle Canvas.Left="0" Canvas.Top="6.666666666666667" Width="30" Height="6.666666666666667" Fill="#00966E"/><Rectangle Canvas.Left="0" Canvas.Top="13.333333333333334" Width="30" Height="6.666666666666667" Fill="#D62612"/>
        </Canvas>
      </Viewbox>
    </DataTemplate>
    <DataTemplate x:Key="Flag_cz">
      <Viewbox Width="30" Height="20" Stretch="Fill" xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation">
        <Canvas Width="30" Height="20"><Canvas.Clip><RectangleGeometry Rect="0,0,30,20" RadiusX="5" RadiusY="5"/></Canvas.Clip>
          <Rectangle Canvas.Left="0" Canvas.Top="0" Width="30" Height="10" Fill="#fff"/><Rectangle Canvas.Left="0" Canvas.Top="10" Width="30" Height="10" Fill="#D7141A"/><Polygon Points="0,0 13,10 0,20" Fill="#11457E"/>
        </Canvas>
      </Viewbox>
    </DataTemplate>
    <DataTemplate x:Key="Flag_dk">
      <Viewbox Width="30" Height="20" Stretch="Fill" xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation">
        <Canvas Width="30" Height="20"><Canvas.Clip><RectangleGeometry Rect="0,0,30,20" RadiusX="5" RadiusY="5"/></Canvas.Clip>
          <Rectangle Canvas.Left="0" Canvas.Top="0" Width="30" Height="20" Fill="#C60C30"/><Rectangle Canvas.Left="9" Canvas.Top="0" Width="3" Height="20" Fill="#fff"/><Rectangle Canvas.Left="0" Canvas.Top="8.5" Width="30" Height="3" Fill="#fff"/>
        </Canvas>
      </Viewbox>
    </DataTemplate>
    <DataTemplate x:Key="Flag_de">
      <Viewbox Width="30" Height="20" Stretch="Fill" xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation">
        <Canvas Width="30" Height="20"><Canvas.Clip><RectangleGeometry Rect="0,0,30,20" RadiusX="5" RadiusY="5"/></Canvas.Clip>
          <Rectangle Canvas.Left="0" Canvas.Top="0" Width="30" Height="6.666666666666667" Fill="#000"/><Rectangle Canvas.Left="0" Canvas.Top="6.666666666666667" Width="30" Height="6.666666666666667" Fill="#DD0000"/><Rectangle Canvas.Left="0" Canvas.Top="13.333333333333334" Width="30" Height="6.666666666666667" Fill="#FFCE00"/>
        </Canvas>
      </Viewbox>
    </DataTemplate>
    <DataTemplate x:Key="Flag_gr">
      <Viewbox Width="30" Height="20" Stretch="Fill" xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation">
        <Canvas Width="30" Height="20"><Canvas.Clip><RectangleGeometry Rect="0,0,30,20" RadiusX="5" RadiusY="5"/></Canvas.Clip>
          <Rectangle Canvas.Left="0" Canvas.Top="0" Width="30" Height="20" Fill="#0D5EAF"/><Rectangle Canvas.Left="0" Canvas.Top="2.2222222222222223" Width="30" Height="2.2222222222222223" Fill="#fff"/><Rectangle Canvas.Left="0" Canvas.Top="6.666666666666667" Width="30" Height="2.2222222222222223" Fill="#fff"/><Rectangle Canvas.Left="0" Canvas.Top="11.11111111111111" Width="30" Height="2.2222222222222223" Fill="#fff"/><Rectangle Canvas.Left="0" Canvas.Top="15.555555555555557" Width="30" Height="2.2222222222222223" Fill="#fff"/><Rectangle Canvas.Left="0" Canvas.Top="0" Width="11.1" Height="11.1" Fill="#0D5EAF"/><Rectangle Canvas.Left="4.45" Canvas.Top="0" Width="2.2" Height="11.1" Fill="#fff"/><Rectangle Canvas.Left="0" Canvas.Top="4.45" Width="11.1" Height="2.2" Fill="#fff"/>
        </Canvas>
      </Viewbox>
    </DataTemplate>
    <DataTemplate x:Key="Flag_gb">
      <Viewbox xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" Width="30" Height="20" Stretch="Fill">
        <Canvas Width="30" Height="20">
          <Canvas.Clip><RectangleGeometry Rect="0,0,30,20" RadiusX="5" RadiusY="5"/></Canvas.Clip>
          <Rectangle Width="30" Height="20" Fill="#012169"/>
          <Path Data="M0,0 L3.4,0 L30,17.73 L30,20 L26.6,20 L0,2.27 Z" Fill="#FFFFFF"/>
          <Path Data="M30,0 L26.6,0 L0,17.73 L0,20 L3.4,20 L30,2.27 Z" Fill="#FFFFFF"/>
          <Path Data="M0,0 L1.7,0 L12.75,7.37 L10.2,7.37 Z" Fill="#C8102E"/>
          <Path Data="M30,0 L28.3,0 L17.25,7.37 L19.8,7.37 Z" Fill="#C8102E"/>
          <Path Data="M0,20 L1.7,20 L12.75,12.63 L10.2,12.63 Z" Fill="#C8102E"/>
          <Path Data="M30,20 L28.3,20 L17.25,12.63 L19.8,12.63 Z" Fill="#C8102E"/>
          <Rectangle Canvas.Top="7" Width="30" Height="6" Fill="#FFFFFF"/>
          <Rectangle Canvas.Left="12" Width="6" Height="20" Fill="#FFFFFF"/>
          <Rectangle Canvas.Top="8.5" Width="30" Height="3" Fill="#C8102E"/>
          <Rectangle Canvas.Left="13.5" Width="3" Height="20" Fill="#C8102E"/>
        </Canvas>
      </Viewbox>
    </DataTemplate>
    <DataTemplate x:Key="Flag_mx">
      <Viewbox Width="30" Height="20" Stretch="Fill" xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation">
        <Canvas Width="30" Height="20"><Canvas.Clip><RectangleGeometry Rect="0,0,30,20" RadiusX="5" RadiusY="5"/></Canvas.Clip>
          <Rectangle Canvas.Left="0" Canvas.Top="0" Width="10" Height="20" Fill="#006847"/><Rectangle Canvas.Left="10" Canvas.Top="0" Width="10" Height="20" Fill="#fff"/><Rectangle Canvas.Left="20" Canvas.Top="0" Width="10" Height="20" Fill="#CE1126"/><Ellipse Canvas.Left="13.5" Canvas.Top="8.5" Width="3.0" Height="3.0" Fill="#7A5B2E"/><Path Data="M13.3 12 C14 13.2 16 13.2 16.7 12" Stroke="#00843D" StrokeThickness="0.6"/>
        </Canvas>
      </Viewbox>
    </DataTemplate>
    <DataTemplate x:Key="Flag_es">
      <Viewbox xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" Width="30" Height="20" Stretch="Fill">
        <Canvas Width="30" Height="20">
          <Canvas.Clip><RectangleGeometry Rect="0,0,30,20" RadiusX="5" RadiusY="5"/></Canvas.Clip>
          <Rectangle Width="30" Height="20" Fill="#AA151B"/>
          <Rectangle Canvas.Top="5" Width="30" Height="10" Fill="#F1BF00"/>
        </Canvas>
      </Viewbox>
    </DataTemplate>
    <DataTemplate x:Key="Flag_fi">
      <Viewbox Width="30" Height="20" Stretch="Fill" xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation">
        <Canvas Width="30" Height="20"><Canvas.Clip><RectangleGeometry Rect="0,0,30,20" RadiusX="5" RadiusY="5"/></Canvas.Clip>
          <Rectangle Canvas.Left="0" Canvas.Top="0" Width="30" Height="20" Fill="#fff"/><Rectangle Canvas.Left="8" Canvas.Top="0" Width="4" Height="20" Fill="#003580"/><Rectangle Canvas.Left="0" Canvas.Top="8" Width="30" Height="4" Fill="#003580"/>
        </Canvas>
      </Viewbox>
    </DataTemplate>
    <DataTemplate x:Key="Flag_fr">
      <Viewbox Width="30" Height="20" Stretch="Fill" xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation">
        <Canvas Width="30" Height="20"><Canvas.Clip><RectangleGeometry Rect="0,0,30,20" RadiusX="5" RadiusY="5"/></Canvas.Clip>
          <Rectangle Canvas.Left="0" Canvas.Top="0" Width="10" Height="20" Fill="#0055A4"/><Rectangle Canvas.Left="10" Canvas.Top="0" Width="10" Height="20" Fill="#fff"/><Rectangle Canvas.Left="20" Canvas.Top="0" Width="10" Height="20" Fill="#EF4135"/>
        </Canvas>
      </Viewbox>
    </DataTemplate>
    <DataTemplate x:Key="Flag_hu">
      <Viewbox Width="30" Height="20" Stretch="Fill" xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation">
        <Canvas Width="30" Height="20"><Canvas.Clip><RectangleGeometry Rect="0,0,30,20" RadiusX="5" RadiusY="5"/></Canvas.Clip>
          <Rectangle Canvas.Left="0" Canvas.Top="0" Width="30" Height="6.666666666666667" Fill="#CE2939"/><Rectangle Canvas.Left="0" Canvas.Top="6.666666666666667" Width="30" Height="6.666666666666667" Fill="#fff"/><Rectangle Canvas.Left="0" Canvas.Top="13.333333333333334" Width="30" Height="6.666666666666667" Fill="#477050"/>
        </Canvas>
      </Viewbox>
    </DataTemplate>
    <DataTemplate x:Key="Flag_id">
      <Viewbox Width="30" Height="20" Stretch="Fill" xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation">
        <Canvas Width="30" Height="20"><Canvas.Clip><RectangleGeometry Rect="0,0,30,20" RadiusX="5" RadiusY="5"/></Canvas.Clip>
          <Rectangle Canvas.Left="0" Canvas.Top="0" Width="30" Height="10" Fill="#FF0000"/><Rectangle Canvas.Left="0" Canvas.Top="10" Width="30" Height="10" Fill="#fff"/>
        </Canvas>
      </Viewbox>
    </DataTemplate>
    <DataTemplate x:Key="Flag_it">
      <Viewbox Width="30" Height="20" Stretch="Fill" xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation">
        <Canvas Width="30" Height="20"><Canvas.Clip><RectangleGeometry Rect="0,0,30,20" RadiusX="5" RadiusY="5"/></Canvas.Clip>
          <Rectangle Canvas.Left="0" Canvas.Top="0" Width="10" Height="20" Fill="#009246"/><Rectangle Canvas.Left="10" Canvas.Top="0" Width="10" Height="20" Fill="#fff"/><Rectangle Canvas.Left="20" Canvas.Top="0" Width="10" Height="20" Fill="#CE2B37"/>
        </Canvas>
      </Viewbox>
    </DataTemplate>
    <DataTemplate x:Key="Flag_jp">
      <Viewbox Width="30" Height="20" Stretch="Fill" xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation">
        <Canvas Width="30" Height="20"><Canvas.Clip><RectangleGeometry Rect="0,0,30,20" RadiusX="5" RadiusY="5"/></Canvas.Clip>
          <Rectangle Canvas.Left="0" Canvas.Top="0" Width="30" Height="20" Fill="#fff"/><Ellipse Canvas.Left="10.3" Canvas.Top="5.3" Width="9.4" Height="9.4" Fill="#BC002D"/>
        </Canvas>
      </Viewbox>
    </DataTemplate>
    <DataTemplate x:Key="Flag_kr">
      <Viewbox xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" Width="30" Height="20" Stretch="Fill">
        <Canvas Width="30" Height="20">
          <Canvas.Clip><RectangleGeometry Rect="0,0,30,20" RadiusX="5" RadiusY="5"/></Canvas.Clip>
          <Rectangle Width="30" Height="20" Fill="#FFFFFF"/>
          <Canvas RenderTransformOrigin="0,0">
            <Canvas.RenderTransform>
              <TransformGroup>
                <RotateTransform Angle="33.6900675"/>
                <TranslateTransform X="15" Y="10"/>
              </TransformGroup>
            </Canvas.RenderTransform>
            <Path Data="M0,-4 A4,4 0 0 1 0,4 A2,2 0 0 1 0,0 A2,2 0 0 0 0,-4 Z" Fill="#CD2E3A"/>
            <Path Data="M0,4 A4,4 0 0 1 0,-4 A2,2 0 0 1 0,0 A2,2 0 0 0 0,4 Z" Fill="#0047A0"/>
          </Canvas>
          <Canvas RenderTransformOrigin="0,0">
            <Canvas.RenderTransform><TransformGroup><RotateTransform Angle="-34"/><TranslateTransform X="6.3" Y="5.2"/></TransformGroup></Canvas.RenderTransform>
            <Rectangle Canvas.Left="-2.5" Canvas.Top="-1.95" Width="5" Height="0.7" Fill="#000"/>
            <Rectangle Canvas.Left="-2.5" Canvas.Top="-0.35" Width="5" Height="0.7" Fill="#000"/>
            <Rectangle Canvas.Left="-2.5" Canvas.Top="1.25" Width="5" Height="0.7" Fill="#000"/>
          </Canvas>
          <Canvas RenderTransformOrigin="0,0">
            <Canvas.RenderTransform><TransformGroup><RotateTransform Angle="-34"/><TranslateTransform X="23.7" Y="14.8"/></TransformGroup></Canvas.RenderTransform>
            <Rectangle Canvas.Left="-2.5" Canvas.Top="-1.95" Width="2" Height="0.7" Fill="#000"/><Rectangle Canvas.Left="0.5" Canvas.Top="-1.95" Width="2" Height="0.7" Fill="#000"/>
            <Rectangle Canvas.Left="-2.5" Canvas.Top="-0.35" Width="2" Height="0.7" Fill="#000"/><Rectangle Canvas.Left="0.5" Canvas.Top="-0.35" Width="2" Height="0.7" Fill="#000"/>
            <Rectangle Canvas.Left="-2.5" Canvas.Top="1.25" Width="2" Height="0.7" Fill="#000"/><Rectangle Canvas.Left="0.5" Canvas.Top="1.25" Width="2" Height="0.7" Fill="#000"/>
          </Canvas>
          <Canvas RenderTransformOrigin="0,0">
            <Canvas.RenderTransform><TransformGroup><RotateTransform Angle="34"/><TranslateTransform X="23.7" Y="5.2"/></TransformGroup></Canvas.RenderTransform>
            <Rectangle Canvas.Left="-2.5" Canvas.Top="-1.95" Width="2" Height="0.7" Fill="#000"/><Rectangle Canvas.Left="0.5" Canvas.Top="-1.95" Width="2" Height="0.7" Fill="#000"/>
            <Rectangle Canvas.Left="-2.5" Canvas.Top="-0.35" Width="5" Height="0.7" Fill="#000"/>
            <Rectangle Canvas.Left="-2.5" Canvas.Top="1.25" Width="2" Height="0.7" Fill="#000"/><Rectangle Canvas.Left="0.5" Canvas.Top="1.25" Width="2" Height="0.7" Fill="#000"/>
          </Canvas>
          <Canvas RenderTransformOrigin="0,0">
            <Canvas.RenderTransform><TransformGroup><RotateTransform Angle="34"/><TranslateTransform X="6.3" Y="14.8"/></TransformGroup></Canvas.RenderTransform>
            <Rectangle Canvas.Left="-2.5" Canvas.Top="-1.95" Width="5" Height="0.7" Fill="#000"/>
            <Rectangle Canvas.Left="-2.5" Canvas.Top="-0.35" Width="2" Height="0.7" Fill="#000"/><Rectangle Canvas.Left="0.5" Canvas.Top="-0.35" Width="2" Height="0.7" Fill="#000"/>
            <Rectangle Canvas.Left="-2.5" Canvas.Top="1.25" Width="5" Height="0.7" Fill="#000"/>
          </Canvas>
        </Canvas>
      </Viewbox>
    </DataTemplate>
    <DataTemplate x:Key="Flag_my">
      <Viewbox Width="30" Height="20" Stretch="Fill" xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation">
        <Canvas Width="30" Height="20"><Canvas.Clip><RectangleGeometry Rect="0,0,30,20" RadiusX="5" RadiusY="5"/></Canvas.Clip>
          <Rectangle Canvas.Left="0" Canvas.Top="0" Width="30" Height="20" Fill="#fff"/><Rectangle Canvas.Left="0" Canvas.Top="0.0" Width="30" Height="1.4285714285714286" Fill="#CC0001"/><Rectangle Canvas.Left="0" Canvas.Top="1.4285714285714286" Width="30" Height="1.4285714285714286" Fill="#fff"/><Rectangle Canvas.Left="0" Canvas.Top="2.857142857142857" Width="30" Height="1.4285714285714286" Fill="#CC0001"/><Rectangle Canvas.Left="0" Canvas.Top="4.285714285714286" Width="30" Height="1.4285714285714286" Fill="#fff"/><Rectangle Canvas.Left="0" Canvas.Top="5.714285714285714" Width="30" Height="1.4285714285714286" Fill="#CC0001"/><Rectangle Canvas.Left="0" Canvas.Top="7.142857142857143" Width="30" Height="1.4285714285714286" Fill="#fff"/><Rectangle Canvas.Left="0" Canvas.Top="8.571428571428571" Width="30" Height="1.4285714285714286" Fill="#CC0001"/><Rectangle Canvas.Left="0" Canvas.Top="10.0" Width="30" Height="1.4285714285714286" Fill="#fff"/><Rectangle Canvas.Left="0" Canvas.Top="11.428571428571429" Width="30" Height="1.4285714285714286" Fill="#CC0001"/><Rectangle Canvas.Left="0" Canvas.Top="12.857142857142858" Width="30" Height="1.4285714285714286" Fill="#fff"/><Rectangle Canvas.Left="0" Canvas.Top="14.285714285714286" Width="30" Height="1.4285714285714286" Fill="#CC0001"/><Rectangle Canvas.Left="0" Canvas.Top="15.714285714285715" Width="30" Height="1.4285714285714286" Fill="#fff"/><Rectangle Canvas.Left="0" Canvas.Top="17.142857142857142" Width="30" Height="1.4285714285714286" Fill="#CC0001"/><Rectangle Canvas.Left="0" Canvas.Top="18.571428571428573" Width="30" Height="1.4285714285714286" Fill="#fff"/><Rectangle Canvas.Left="0" Canvas.Top="0" Width="15" Height="11.428571428571429" Fill="#010066"/><Ellipse Canvas.Left="3.1" Canvas.Top="2.6" Width="6.2" Height="6.2" Fill="#FFCC00"/><Ellipse Canvas.Left="4.6" Canvas.Top="3.0" Width="5.4" Height="5.4" Fill="#010066"/><Polygon Points="10.4,4.0 10.544505094511232,5.066881813829124 11.13760235649985,4.1683529245658875 10.804894277327062,5.192278635285262 11.72911352019565,4.640067336840153 10.985089182815832,5.418235899817058 12.057377450709101,5.3217144122742654 11.0494,5.7 12.057377450709101,6.078285587725735 10.985089182815832,5.981764100182942 11.72911352019565,6.759932663159848 10.804894277327062,6.207721364714739 11.13760235649985,7.231647075434113 10.544505094511232,6.333118186170877 10.4,7.4 10.255494905488769,6.333118186170877 9.662397643500151,7.231647075434113 9.995105722672939,6.207721364714739 9.07088647980435,6.759932663159847 9.81491081718417,5.981764100182943 8.7426225492909,6.078285587725734 9.7506,5.7 8.7426225492909,5.321714412274266 9.814910817184169,5.418235899817058 9.070886479804349,4.640067336840153 9.995105722672939,5.192278635285262 9.662397643500151,4.1683529245658875 10.25549490548877,5.066881813829124" Fill="#FFCC00"/>
        </Canvas>
      </Viewbox>
    </DataTemplate>
    <DataTemplate x:Key="Flag_no">
      <Viewbox Width="30" Height="20" Stretch="Fill" xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation">
        <Canvas Width="30" Height="20"><Canvas.Clip><RectangleGeometry Rect="0,0,30,20" RadiusX="5" RadiusY="5"/></Canvas.Clip>
          <Rectangle Canvas.Left="0" Canvas.Top="0" Width="30" Height="20" Fill="#BA0C2F"/><Rectangle Canvas.Left="8" Canvas.Top="0" Width="5" Height="20" Fill="#fff"/><Rectangle Canvas.Left="0" Canvas.Top="7.5" Width="30" Height="5" Fill="#fff"/><Rectangle Canvas.Left="9.5" Canvas.Top="0" Width="2" Height="20" Fill="#00205B"/><Rectangle Canvas.Left="0" Canvas.Top="9" Width="30" Height="2" Fill="#00205B"/>
        </Canvas>
      </Viewbox>
    </DataTemplate>
    <DataTemplate x:Key="Flag_nl">
      <Viewbox Width="30" Height="20" Stretch="Fill" xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation">
        <Canvas Width="30" Height="20"><Canvas.Clip><RectangleGeometry Rect="0,0,30,20" RadiusX="5" RadiusY="5"/></Canvas.Clip>
          <Rectangle Canvas.Left="0" Canvas.Top="0" Width="30" Height="6.666666666666667" Fill="#AE1C28"/><Rectangle Canvas.Left="0" Canvas.Top="6.666666666666667" Width="30" Height="6.666666666666667" Fill="#fff"/><Rectangle Canvas.Left="0" Canvas.Top="13.333333333333334" Width="30" Height="6.666666666666667" Fill="#21468B"/>
        </Canvas>
      </Viewbox>
    </DataTemplate>
    <DataTemplate x:Key="Flag_pl">
      <Viewbox Width="30" Height="20" Stretch="Fill" xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation">
        <Canvas Width="30" Height="20"><Canvas.Clip><RectangleGeometry Rect="0,0,30,20" RadiusX="5" RadiusY="5"/></Canvas.Clip>
          <Rectangle Canvas.Left="0" Canvas.Top="0" Width="30" Height="10" Fill="#fff"/><Rectangle Canvas.Left="0" Canvas.Top="10" Width="30" Height="10" Fill="#DC143C"/>
        </Canvas>
      </Viewbox>
    </DataTemplate>
    <DataTemplate x:Key="Flag_br">
      <Viewbox Width="30" Height="20" Stretch="Fill" xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation">
        <Canvas Width="30" Height="20"><Canvas.Clip><RectangleGeometry Rect="0,0,30,20" RadiusX="5" RadiusY="5"/></Canvas.Clip>
          <Rectangle Canvas.Left="0" Canvas.Top="0" Width="30" Height="20" Fill="#009B3A"/><Polygon Points="15,2 27,10 15,18 3,10" Fill="#FFDF00"/><Ellipse Canvas.Left="9.7" Canvas.Top="4.7" Width="10.6" Height="10.6" Fill="#002776"/><Path Data="M10.4 9.2 C13.2 8.1 17.1 8.5 19.8 10.1" Stroke="#fff" StrokeThickness="0.7"/>
        </Canvas>
      </Viewbox>
    </DataTemplate>
    <DataTemplate x:Key="Flag_pt">
      <Viewbox Width="30" Height="20" Stretch="Fill" xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation">
        <Canvas Width="30" Height="20"><Canvas.Clip><RectangleGeometry Rect="0,0,30,20" RadiusX="5" RadiusY="5"/></Canvas.Clip>
          <Rectangle Canvas.Left="0" Canvas.Top="0" Width="12" Height="20" Fill="#046A38"/><Rectangle Canvas.Left="12" Canvas.Top="0" Width="18" Height="20" Fill="#DA291C"/><Ellipse Canvas.Left="8.6" Canvas.Top="6.6" Width="6.8" Height="6.8"/><Path Data="M12 6.7 A3.3 3.3 0 1 0 12 13.3 A3.3 3.3 0 1 0 12 6.7" Stroke="#FFCC00" StrokeThickness="0.8"/><Rectangle Canvas.Left="10.6" Canvas.Top="8.2" Width="2.8" Height="3.6" Fill="#fff"/><Ellipse Canvas.Left="11.2" Canvas.Top="9.2" Width="1.6" Height="1.6" Fill="#0055A4"/>
        </Canvas>
      </Viewbox>
    </DataTemplate>
    <DataTemplate x:Key="Flag_ro">
      <Viewbox Width="30" Height="20" Stretch="Fill" xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation">
        <Canvas Width="30" Height="20"><Canvas.Clip><RectangleGeometry Rect="0,0,30,20" RadiusX="5" RadiusY="5"/></Canvas.Clip>
          <Rectangle Canvas.Left="0" Canvas.Top="0" Width="10" Height="20" Fill="#002B7F"/><Rectangle Canvas.Left="10" Canvas.Top="0" Width="10" Height="20" Fill="#FCD116"/><Rectangle Canvas.Left="20" Canvas.Top="0" Width="10" Height="20" Fill="#CE1126"/>
        </Canvas>
      </Viewbox>
    </DataTemplate>
    <DataTemplate x:Key="Flag_ru">
      <Viewbox Width="30" Height="20" Stretch="Fill" xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation">
        <Canvas Width="30" Height="20"><Canvas.Clip><RectangleGeometry Rect="0,0,30,20" RadiusX="5" RadiusY="5"/></Canvas.Clip>
          <Rectangle Canvas.Left="0" Canvas.Top="0" Width="30" Height="6.666666666666667" Fill="#fff"/><Rectangle Canvas.Left="0" Canvas.Top="6.666666666666667" Width="30" Height="6.666666666666667" Fill="#0039A6"/><Rectangle Canvas.Left="0" Canvas.Top="13.333333333333334" Width="30" Height="6.666666666666667" Fill="#D52B1E"/>
        </Canvas>
      </Viewbox>
    </DataTemplate>
    <DataTemplate x:Key="Flag_se">
      <Viewbox Width="30" Height="20" Stretch="Fill" xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation">
        <Canvas Width="30" Height="20"><Canvas.Clip><RectangleGeometry Rect="0,0,30,20" RadiusX="5" RadiusY="5"/></Canvas.Clip>
          <Rectangle Canvas.Left="0" Canvas.Top="0" Width="30" Height="20" Fill="#006AA7"/><Rectangle Canvas.Left="9" Canvas.Top="0" Width="4" Height="20" Fill="#FECC00"/><Rectangle Canvas.Left="0" Canvas.Top="8" Width="30" Height="4" Fill="#FECC00"/>
        </Canvas>
      </Viewbox>
    </DataTemplate>
    <DataTemplate x:Key="Flag_th">
      <Viewbox Width="30" Height="20" Stretch="Fill" xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation">
        <Canvas Width="30" Height="20"><Canvas.Clip><RectangleGeometry Rect="0,0,30,20" RadiusX="5" RadiusY="5"/></Canvas.Clip>
          <Rectangle Canvas.Left="0" Canvas.Top="0" Width="30" Height="20" Fill="#A51931"/><Rectangle Canvas.Left="0" Canvas.Top="3.3" Width="30" Height="3.3" Fill="#fff"/><Rectangle Canvas.Left="0" Canvas.Top="6.6" Width="30" Height="6.8" Fill="#2D2A4A"/><Rectangle Canvas.Left="0" Canvas.Top="13.4" Width="30" Height="3.3" Fill="#fff"/><Rectangle Canvas.Left="0" Canvas.Top="16.7" Width="30" Height="3.3" Fill="#A51931"/>
        </Canvas>
      </Viewbox>
    </DataTemplate>
    <DataTemplate x:Key="Flag_tr">
      <Viewbox Width="30" Height="20" Stretch="Fill" xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation">
        <Canvas Width="30" Height="20"><Canvas.Clip><RectangleGeometry Rect="0,0,30,20" RadiusX="5" RadiusY="5"/></Canvas.Clip>
          <Rectangle Canvas.Left="0" Canvas.Top="0" Width="30" Height="20" Fill="#E30A17"/><Ellipse Canvas.Left="7.0" Canvas.Top="5.0" Width="10.0" Height="10.0" Fill="#fff"/><Ellipse Canvas.Left="9.700000000000001" Canvas.Top="5.9" Width="8.2" Height="8.2" Fill="#E30A17"/><Polygon Points="18.1,8.0 18.549067932751452,9.38191101629754 20.00211303259031,9.381966011250105 18.8266071784495,10.23608898370246 19.275570504584948,11.618033988749895 18.1,10.764 16.924429495415055,11.618033988749895 17.373392821550503,10.23608898370246 16.197886967409694,9.381966011250105 17.65093206724855,9.38191101629754" Fill="#fff"/>
        </Canvas>
      </Viewbox>
    </DataTemplate>
    <DataTemplate x:Key="Flag_ua">
      <Viewbox Width="30" Height="20" Stretch="Fill" xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation">
        <Canvas Width="30" Height="20"><Canvas.Clip><RectangleGeometry Rect="0,0,30,20" RadiusX="5" RadiusY="5"/></Canvas.Clip>
          <Rectangle Canvas.Left="0" Canvas.Top="0" Width="30" Height="10" Fill="#0057B7"/><Rectangle Canvas.Left="0" Canvas.Top="10" Width="30" Height="10" Fill="#FFD700"/>
        </Canvas>
      </Viewbox>
    </DataTemplate>
    <DataTemplate x:Key="Flag_vn">
      <Viewbox Width="30" Height="20" Stretch="Fill" xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation">
        <Canvas Width="30" Height="20"><Canvas.Clip><RectangleGeometry Rect="0,0,30,20" RadiusX="5" RadiusY="5"/></Canvas.Clip>
          <Rectangle Canvas.Left="0" Canvas.Top="0" Width="30" Height="20" Fill="#DA251D"/><Polygon Points="15.0,5.8 15.943042658778044,8.702013134224835 18.994437368439645,8.70212862362522 16.525875074743944,10.495786865775166 17.468698059628387,13.39787137637478 15.0,11.6044 12.531301940371613,13.39787137637478 13.474124925256056,10.495786865775166 11.005562631560355,8.70212862362522 14.056957341221956,8.702013134224835" Fill="#FF0"/>
        </Canvas>
      </Viewbox>
    </DataTemplate>
    <DataTemplate x:Key="Flag_cn">
      <Viewbox Width="30" Height="20" Stretch="Fill" xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation">
        <Canvas Width="30" Height="20"><Canvas.Clip><RectangleGeometry Rect="0,0,30,20" RadiusX="5" RadiusY="5"/></Canvas.Clip>
          <Rectangle Canvas.Left="0" Canvas.Top="0" Width="30" Height="20" Fill="#DE2910"/><Polygon Points="5.0,2.4 5.583788312576885,4.196484321186802 7.472746942367399,4.196555814625137 5.944589331984346,5.306915678813198 6.52824165596043,7.1034441853748636 5.0,5.9932 3.47175834403957,7.1034441853748636 4.055410668015654,5.306915678813198 2.5272530576326004,4.196555814625137 4.416211687423115,4.196484321186802" Fill="#FFDE00"/><Polygon Points="8.692181871006898,1.4542766412926822 9.094764122929885,1.9695182289364057 9.709209678246049,1.7459046722069074 9.343590566329166,2.28800155303368 9.746133815299537,2.803273613123672 9.117586525275366,2.6230663230261952 8.7519263797647,3.165135526344487 8.729081902910009,2.5116644152169614 8.100548255682813,2.331409547032251 8.714976882555577,2.107749479786757" Fill="#FFDE00"/><Polygon Points="10.7,3.5000000000000004 10.902080569738152,4.121859957333894 11.555950864665638,4.121884705062548 11.026973230302273,4.506240042666107 11.229006727063226,5.128115294937453 10.7,4.7438 10.170993272936773,5.128115294937453 10.373026769697725,4.506240042666107 9.84404913533436,4.121884705062548 10.497919430261847,4.121859957333894" Fill="#FFDE00"/><Polygon Points="10.707818128993102,6.154276641292682 10.685023117444423,6.807749479786757 11.299451744317187,7.031409547032251 10.670918097089992,7.211664415216961 10.6480736202353,7.865135526344487 10.282413474724635,7.323066323026195 9.653866184700464,7.503273613123672 10.056409433670835,6.98800155303368 9.690790321753951,6.4459046722069075 10.305235877070116,6.669518228936406" Fill="#FFDE00"/><Polygon Points="9.278508848717884,8.31056000119292 9.033587670693686,8.916827252292833 9.534465469110108,9.337145934074321 8.882186243043375,9.291558935458578 8.637219173630287,9.897807645233842 8.479009619789768,9.263366079544305 7.826733846351602,9.217729706039702 8.381234190799939,8.871210253183609 8.223072662190114,8.236756713459217 8.72398227567323,8.657037479520673" Fill="#FFDE00"/>
        </Canvas>
      </Viewbox>
    </DataTemplate>
    <DataTemplate x:Key="Flag_tw">
      <Viewbox Width="30" Height="20" Stretch="Fill" xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation">
        <Canvas Width="30" Height="20"><Canvas.Clip><RectangleGeometry Rect="0,0,30,20" RadiusX="5" RadiusY="5"/></Canvas.Clip>
          <Rectangle Canvas.Left="0" Canvas.Top="0" Width="30" Height="20" Fill="#FE0000"/><Rectangle Canvas.Left="0" Canvas.Top="0" Width="15" Height="10" Fill="#000095"/><Ellipse Canvas.Left="5.3" Canvas.Top="2.8" Width="4.4" Height="4.4" Fill="#fff"/><Polygon Points="10.1,5.0 10.874656915580495,5.414355767577502 10.874656915580495,4.585644232422498" Fill="#fff"/><Polygon Points="9.75166604983954,6.3 10.215360734160797,7.046171078716965 10.629716501738297,6.32848583686353" Fill="#fff"/><Polygon Points="8.8,7.251666049839541 8.828485836863532,8.129716501738297 9.546171078716965,7.715360734160796" Fill="#fff"/><Polygon Points="7.5,7.6 7.085644232422499,8.374656915580495 7.914355767577502,8.374656915580495" Fill="#fff"/><Polygon Points="6.200000000000001,7.251666049839541 5.453828921283037,7.715360734160797 6.17151416313647,8.129716501738297" Fill="#fff"/><Polygon Points="5.248333950160459,6.3 4.370283498261703,6.328485836863531 4.784639265839204,7.046171078716964" Fill="#fff"/><Polygon Points="4.9,5.0 4.125343084419505,4.585644232422499 4.125343084419505,5.414355767577502" Fill="#fff"/><Polygon Points="5.248333950160459,3.6999999999999997 4.784639265839204,2.9538289212830358 4.370283498261703,3.671514163136469" Fill="#fff"/><Polygon Points="6.199999999999999,2.7483339501604602 6.171514163136469,1.8702834982617031 5.4538289212830335,2.284639265839206" Fill="#fff"/><Polygon Points="7.499999999999999,2.4 7.9143557675775025,1.6253430844195051 7.085644232422497,1.6253430844195051" Fill="#fff"/><Polygon Points="8.8,2.74833395016046 9.546171078716966,2.284639265839205 8.82848583686353,1.8702834982617023" Fill="#fff"/><Polygon Points="9.751666049839539,3.699999999999999 10.629716501738297,3.671514163136469 10.215360734160793,2.953828921283033" Fill="#fff"/>
        </Canvas>
      </Viewbox>
    </DataTemplate>
    <DataTemplate x:Key="DialogLanguageItemTemplate">
      <StackPanel Orientation="Horizontal" HorizontalAlignment="Center">
        <ContentControl Content="{Binding}" Width="30" Height="20" Margin="0,0,9,0" Focusable="False">
          <ContentControl.Style>
            <Style TargetType="ContentControl">
              <Setter Property="ContentTemplate" Value="{StaticResource Flag_gb}"/>
              <Style.Triggers>
              <DataTrigger Binding="{Binding Code}" Value="ar-SA"><Setter Property="ContentTemplate" Value="{StaticResource Flag_sa}"/></DataTrigger>
              <DataTrigger Binding="{Binding Code}" Value="bg-BG"><Setter Property="ContentTemplate" Value="{StaticResource Flag_bg}"/></DataTrigger>
              <DataTrigger Binding="{Binding Code}" Value="cs-CZ"><Setter Property="ContentTemplate" Value="{StaticResource Flag_cz}"/></DataTrigger>
              <DataTrigger Binding="{Binding Code}" Value="da-DK"><Setter Property="ContentTemplate" Value="{StaticResource Flag_dk}"/></DataTrigger>
              <DataTrigger Binding="{Binding Code}" Value="de-DE"><Setter Property="ContentTemplate" Value="{StaticResource Flag_de}"/></DataTrigger>
              <DataTrigger Binding="{Binding Code}" Value="el-GR"><Setter Property="ContentTemplate" Value="{StaticResource Flag_gr}"/></DataTrigger>
              <DataTrigger Binding="{Binding Code}" Value="en-US"><Setter Property="ContentTemplate" Value="{StaticResource Flag_gb}"/></DataTrigger>
              <DataTrigger Binding="{Binding Code}" Value="es-419"><Setter Property="ContentTemplate" Value="{StaticResource Flag_mx}"/></DataTrigger>
              <DataTrigger Binding="{Binding Code}" Value="es-ES"><Setter Property="ContentTemplate" Value="{StaticResource Flag_es}"/></DataTrigger>
              <DataTrigger Binding="{Binding Code}" Value="fi-FI"><Setter Property="ContentTemplate" Value="{StaticResource Flag_fi}"/></DataTrigger>
              <DataTrigger Binding="{Binding Code}" Value="fr-FR"><Setter Property="ContentTemplate" Value="{StaticResource Flag_fr}"/></DataTrigger>
              <DataTrigger Binding="{Binding Code}" Value="hu-HU"><Setter Property="ContentTemplate" Value="{StaticResource Flag_hu}"/></DataTrigger>
              <DataTrigger Binding="{Binding Code}" Value="id-ID"><Setter Property="ContentTemplate" Value="{StaticResource Flag_id}"/></DataTrigger>
              <DataTrigger Binding="{Binding Code}" Value="it-IT"><Setter Property="ContentTemplate" Value="{StaticResource Flag_it}"/></DataTrigger>
              <DataTrigger Binding="{Binding Code}" Value="ja-JP"><Setter Property="ContentTemplate" Value="{StaticResource Flag_jp}"/></DataTrigger>
              <DataTrigger Binding="{Binding Code}" Value="ko-KR"><Setter Property="ContentTemplate" Value="{StaticResource Flag_kr}"/></DataTrigger>
              <DataTrigger Binding="{Binding Code}" Value="ms-MY"><Setter Property="ContentTemplate" Value="{StaticResource Flag_my}"/></DataTrigger>
              <DataTrigger Binding="{Binding Code}" Value="nb-NO"><Setter Property="ContentTemplate" Value="{StaticResource Flag_no}"/></DataTrigger>
              <DataTrigger Binding="{Binding Code}" Value="nl-NL"><Setter Property="ContentTemplate" Value="{StaticResource Flag_nl}"/></DataTrigger>
              <DataTrigger Binding="{Binding Code}" Value="pl-PL"><Setter Property="ContentTemplate" Value="{StaticResource Flag_pl}"/></DataTrigger>
              <DataTrigger Binding="{Binding Code}" Value="pt-BR"><Setter Property="ContentTemplate" Value="{StaticResource Flag_br}"/></DataTrigger>
              <DataTrigger Binding="{Binding Code}" Value="pt-PT"><Setter Property="ContentTemplate" Value="{StaticResource Flag_pt}"/></DataTrigger>
              <DataTrigger Binding="{Binding Code}" Value="ro-RO"><Setter Property="ContentTemplate" Value="{StaticResource Flag_ro}"/></DataTrigger>
              <DataTrigger Binding="{Binding Code}" Value="ru-RU"><Setter Property="ContentTemplate" Value="{StaticResource Flag_ru}"/></DataTrigger>
              <DataTrigger Binding="{Binding Code}" Value="sv-SE"><Setter Property="ContentTemplate" Value="{StaticResource Flag_se}"/></DataTrigger>
              <DataTrigger Binding="{Binding Code}" Value="th-TH"><Setter Property="ContentTemplate" Value="{StaticResource Flag_th}"/></DataTrigger>
              <DataTrigger Binding="{Binding Code}" Value="tr-TR"><Setter Property="ContentTemplate" Value="{StaticResource Flag_tr}"/></DataTrigger>
              <DataTrigger Binding="{Binding Code}" Value="uk-UA"><Setter Property="ContentTemplate" Value="{StaticResource Flag_ua}"/></DataTrigger>
              <DataTrigger Binding="{Binding Code}" Value="vi-VN"><Setter Property="ContentTemplate" Value="{StaticResource Flag_vn}"/></DataTrigger>
              <DataTrigger Binding="{Binding Code}" Value="zh-CN"><Setter Property="ContentTemplate" Value="{StaticResource Flag_cn}"/></DataTrigger>
              <DataTrigger Binding="{Binding Code}" Value="zh-TW"><Setter Property="ContentTemplate" Value="{StaticResource Flag_tw}"/></DataTrigger>
              </Style.Triggers>
            </Style>
          </ContentControl.Style>
        </ContentControl>
        <TextBlock Text="{Binding Name}" VerticalAlignment="Center"/>
      </StackPanel>
    </DataTemplate>
    <Style x:Key="DialogComboItemStyle" TargetType="ComboBoxItem">
      <Setter Property="Foreground" Value="{StaticResource DialogTextBrush}"/>
      <Setter Property="Background" Value="#20242B"/>
      <Setter Property="Padding" Value="10,7"/>
      <Setter Property="HorizontalContentAlignment" Value="Stretch"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ComboBoxItem">
            <Border x:Name="ItemBorder" Background="{TemplateBinding Background}" Padding="{TemplateBinding Padding}">
              <ContentPresenter/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="ItemBorder" Property="Background" Value="#1A9FFF"/><Setter Property="Foreground" Value="#FFFFFF"/></Trigger>
              <Trigger Property="IsSelected" Value="True"><Setter TargetName="ItemBorder" Property="Background" Value="#174B66"/><Setter Property="Foreground" Value="#FFFFFF"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="DialogScrollThumbStyle" TargetType="Thumb">
      <Setter Property="Background" Value="#59616B"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Thumb">
            <Grid Margin="1">
              <Border x:Name="DialogThumbBorder" Background="{TemplateBinding Background}" CornerRadius="5"/>
            </Grid>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="DialogThumbBorder" Property="Background" Value="{StaticResource DialogScrollHoverBrush}"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style TargetType="ScrollBar">
      <Setter Property="Width" Value="9"/>
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ScrollBar">
            <Grid Width="9" Background="Transparent">
              <Track x:Name="PART_Track" Orientation="{TemplateBinding Orientation}" IsDirectionReversed="True" Focusable="False">
                <Track.DecreaseRepeatButton>
                  <RepeatButton Command="ScrollBar.PageUpCommand" CommandTarget="{Binding RelativeSource={RelativeSource TemplatedParent}}" Opacity="0" Focusable="False"/>
                </Track.DecreaseRepeatButton>
                <Track.Thumb>
                  <Thumb Style="{StaticResource DialogScrollThumbStyle}" MinHeight="28"/>
                </Track.Thumb>
                <Track.IncreaseRepeatButton>
                  <RepeatButton Command="ScrollBar.PageDownCommand" CommandTarget="{Binding RelativeSource={RelativeSource TemplatedParent}}" Opacity="0" Focusable="False"/>
                </Track.IncreaseRepeatButton>
              </Track>
            </Grid>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="DialogComboStyle" TargetType="ComboBox">
      <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
      <Setter Property="HorizontalContentAlignment" Value="Center"/>
      <Setter Property="Height" Value="38"/><Setter Property="Foreground" Value="{StaticResource DialogTextBrush}"/><Setter Property="Background" Value="{StaticResource DialogInputBrush}"/><Setter Property="BorderBrush" Value="#5B626D"/><Setter Property="ItemContainerStyle" Value="{StaticResource DialogComboItemStyle}"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ComboBox">
            <Grid>
              <Border x:Name="Outer" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="1" CornerRadius="5">
                <Grid><ContentPresenter Margin="10,0,30,0" VerticalAlignment="Center" Content="{TemplateBinding SelectionBoxItem}" ContentTemplate="{TemplateBinding SelectionBoxItemTemplate}" ContentTemplateSelector="{TemplateBinding ItemTemplateSelector}" ContentStringFormat="{TemplateBinding SelectionBoxItemStringFormat}"/><Path HorizontalAlignment="Right" VerticalAlignment="Center" Margin="0,0,12,0" Fill="{TemplateBinding Foreground}" Data="M 0 0 L 5 5 L 10 0 Z"/></Grid>
              </Border>
              <ToggleButton Background="Transparent" BorderThickness="0" Focusable="False" ClickMode="Press" IsChecked="{Binding IsDropDownOpen, Mode=TwoWay, RelativeSource={RelativeSource TemplatedParent}}"><ToggleButton.Template><ControlTemplate TargetType="ToggleButton"><Border Background="Transparent" CornerRadius="5"/></ControlTemplate></ToggleButton.Template></ToggleButton>
              <Popup x:Name="PART_Popup" IsOpen="{TemplateBinding IsDropDownOpen}" Placement="Bottom" AllowsTransparency="True" Focusable="False" PopupAnimation="None">
                <Border MinWidth="{Binding ActualWidth, RelativeSource={RelativeSource TemplatedParent}}" Margin="0,3,0,0" Background="#15181D" BorderBrush="#5B626D" BorderThickness="1" CornerRadius="5"><ScrollViewer MaxHeight="240"><ItemsPresenter/></ScrollViewer></Border>
              </Popup>
            </Grid>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Outer" Property="Background" Value="#2A3038"/><Setter TargetName="Outer" Property="BorderBrush" Value="{StaticResource DialogAccentBrush}"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="DialogButtonStyle" TargetType="Button">
      <Setter Property="VerticalContentAlignment" Value="Center"/>
      <Setter Property="HorizontalContentAlignment" Value="Center"/>
      <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
      <Setter Property="Width" Value="42"/><Setter Property="Height" Value="36"/><Setter Property="Foreground" Value="{StaticResource DialogTextBrush}"/><Setter Property="Background" Value="#2A3038"/><Setter Property="BorderBrush" Value="#5B626D"/><Setter Property="BorderThickness" Value="1"/><Setter Property="Padding" Value="0"/>
      <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Border x:Name="ButtonBorder" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="5"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="ButtonBorder" Property="Background" Value="#1A9FFF"/><Setter TargetName="ButtonBorder" Property="BorderBrush" Value="#1A9FFF"/><Setter Property="Foreground" Value="#FFFFFF"/></Trigger><Trigger Property="IsPressed" Value="True"><Setter TargetName="ButtonBorder" Property="Opacity" Value="0.78"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter>
    </Style>
  </Window.Resources>
  <Border Background="#20242B" BorderBrush="#3B414A" BorderThickness="1" CornerRadius="5" Padding="24">
    <Grid>
      <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="24"/>
        <RowDefinition Height="*"/>
      </Grid.RowDefinitions>
      <StackPanel Orientation="Horizontal" HorizontalAlignment="Center">
        <Viewbox Width="27" Height="27" Stretch="Uniform" Margin="0,0,9,0">
          <Canvas Width="512" Height="512">
            <Path Data="M126.176,147.386 L131.132,142.429 L212.018,223.315 L207.061,228.272 Z" Fill="{StaticResource DialogAccentBrush}" Opacity="0.4"/>
            <Path Data="M299.298,292.656 L304.255,287.699 L385.141,368.585 L380.184,373.542 Z" Fill="{StaticResource DialogAccentBrush}" Opacity="0.4"/>
            <Path Data="M364.95,399.25 L364.95,434.35 L147.14,434.35 L147.14,399.25 Z" Fill="{StaticResource DialogAccentBrush}" Opacity="0.4"/>
            <Path Data="M365.4,82.26 L365.4,117.36 L147.59,117.36 L147.59,82.26 Z" Fill="{StaticResource DialogAccentBrush}" Opacity="0.4"/>
            <Path Fill="{StaticResource DialogAccentBrush}" Data="F0 M430.61,354.52 v-197.61 c24.1-7.79,41.54-30.4,41.54-57.09 c0-33.14-26.86-60-60-60 s-60,26.86-60,60 c0,10.16,2.53,19.72,6.99,28.11 l-75.22,75.22 c-8.22-4.23-17.54-6.64-27.42-6.64 c-10.66,0-20.67,2.79-29.35,7.67 l-74.93-74.93 c4.91-8.7,7.72-18.73,7.72-29.43 c0-33.14-26.86-60-60-60 s-60,26.86-60,60 c0,27.03,17.88,49.88,42.45,57.39 v197.03 c-24.57,7.51-42.45,30.36-42.45,57.39 c0,33.14,26.86,60,60,60 s60-26.86,60-60 c0-12.2-3.65-23.53-9.9-33 l72.59-72.59 c9.64,6.61,21.3,10.48,33.87,10.48 c9.44,0,18.37-2.19,26.31-6.07 l75.23,75.23 c-3.77,7.85-5.89,16.65-5.89,25.95 c0,33.14,26.86,60,60,60 s60-26.86,60-60 c0-26.7-17.44-49.31-41.54-57.09 Z M203.14,283.92 l-74.82,74.82 c-3.43-1.84-7.05-3.36-10.84-4.52 v-197.03 c9.54-2.91,18.07-8.13,24.93-15.01 l71.78,71.78 c-10.93,10.87-17.69,25.91-17.69,42.54 c0,9.89,2.41,19.2,6.64,27.42 Z M256.5,286.16 c-16.38,0-29.66-13.28-29.66-29.66 s13.28-29.66,29.66-29.66 s29.66,13.28,29.66,29.66 s-13.28,29.66-29.66,29.66 Z M395.51,353.97 c-11.14,3.21-20.94,9.55-28.4,18.02 l-70.7-70.7 c12.32-10.99,20.09-26.98,20.09-44.79 c0-12.57-3.87-24.23-10.48-33.87 l72.88-72.88 c5.05,3.37,10.64,5.98,16.62,7.71 v196.51 Z"/>
          </Canvas>
        </Viewbox>
        <TextBlock Text="WNST" Foreground="#F4F4F4" FontSize="27" FontWeight="SemiBold" VerticalAlignment="Center"/>
      </StackPanel>
      <ComboBox x:Name="LanguagePicker" Grid.Row="1" Style="{StaticResource DialogComboStyle}" ItemTemplate="{StaticResource DialogLanguageItemTemplate}" Margin="0,20,0,0" VerticalAlignment="Top"/>
      <Grid Grid.Row="3" VerticalAlignment="Stretch">
        <Button x:Name="ContinueButton" Style="{StaticResource DialogButtonStyle}" HorizontalAlignment="Center" VerticalAlignment="Center" VerticalContentAlignment="Center" Margin="0"><Viewbox Width="14" Height="14" HorizontalAlignment="Center" VerticalAlignment="Center"><Canvas Width="14" Height="14"><Path Stroke="{Binding Foreground, RelativeSource={RelativeSource AncestorType=Button}}" StrokeThickness="1.6" StrokeStartLineCap="Round" StrokeEndLineCap="Round" StrokeLineJoin="Round" Data="M2,7 L12,7 M7,2 L12,7 L7,12"/></Canvas></Viewbox></Button>
      </Grid>
    </Grid>
  </Border>
</Window>
'@
    $reader = New-Object Xml.XmlNodeReader($languageXaml)
    $dialog = [Windows.Markup.XamlReader]::Load($reader)
    try {
        $dialogAccent = [string]$script:Settings.AccentColor
        if ($dialogAccent -notmatch '^#[0-9A-Fa-f]{6}$') { $dialogAccent = '#1A9FFF' }
        $accentColor = [Windows.Media.ColorConverter]::ConvertFromString($dialogAccent)
        $dialog.Resources['DialogAccentBrush'].Color = $accentColor
        $dialog.Resources['DialogScrollHoverBrush'].Color = $accentColor
    }
    catch { }
    $dialog.FontFamily = $script:UiFontFamily
    $picker = $dialog.FindName('LanguagePicker')
    $continue = $dialog.FindName('ContinueButton')
    $picker.ItemsSource = $Languages
    # Ajuste le champ au nom de langue le plus large, puis garde 24 px de padding de chaque côté.
    try {
        $maxLanguageWidth = 0.0
        foreach ($language in @($Languages)) {
            $measure = New-Object Windows.Controls.TextBlock
            $measure.FontFamily = $script:UiFontFamily
            $measure.FontSize = 12
            $measure.Text = [string]$language.Name
            $measure.Measure([Windows.Size]::new([double]::PositiveInfinity,[double]::PositiveInfinity))
            if ($measure.DesiredSize.Width -gt $maxLanguageWidth) {
                $maxLanguageWidth = $measure.DesiredSize.Width
            }
        }

        # 30 px drapeau + 9 px espace + texte + espace interne + zone flèche.
        $pickerWidth = [math]::Ceiling($maxLanguageWidth + 30 + 9 + 72)
        if ($pickerWidth -lt 220) { $pickerWidth = 220 }

        $picker.Width = $pickerWidth
        $picker.HorizontalAlignment = 'Center'

        # Border externe : 24 px de padding de chaque côté + 1 px de bordure de chaque côté.
        $dialog.Width = $pickerWidth + 50
    }
    catch { }

    $cultureName = [Globalization.CultureInfo]::CurrentUICulture.Name
    $preferred = $Languages | Where-Object { $_.Code -eq $cultureName } | Select-Object -First 1
    if (-not $preferred) {
        $preferred = $Languages | Where-Object { $_.Code.StartsWith([Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName) } | Select-Object -First 1
    }
    if (-not $preferred) { $preferred = $Languages | Where-Object Code -eq 'en-US' | Select-Object -First 1 }
    $picker.SelectedItem = $preferred

    $dialog.Add_MouseLeftButtonDown({ try { $dialog.DragMove() } catch { } })
    $continue.Add_Click({ if ($picker.SelectedItem) { $dialog.DialogResult = $true; $dialog.Close() } })
    if ($dialog.ShowDialog() -eq $true) { return [string]$picker.SelectedItem.Code }
    return $(if ($preferred) { [string]$preferred.Code } else { 'en-US' })
}
