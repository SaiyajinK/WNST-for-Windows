$script:DisplayMonitors = @()
$script:DisplayCarouselIndex = 0
$script:DisplayUiUpdating = $false
$script:DisplayInventoryLoaded = $false
$script:DisplayNativeAvailable = $false
$script:DisplayNativeError = ''

try {
    if (-not ('WnstDisplayNative' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public sealed class WnstDisplayMode
{
    public int Width { get; set; }
    public int Height { get; set; }
    public int Frequency { get; set; }
}

public sealed class WnstDisplayInfo
{
    public string DeviceName { get; set; }
    public string FriendlyName { get; set; }
    public string ManufacturerCode { get; set; }
    public string ConnectionCode { get; set; }
    public bool IsPrimary { get; set; }
    public int Width { get; set; }
    public int Height { get; set; }
    public int Frequency { get; set; }
    public long AdapterLuid { get; set; }
    public uint SourceId { get; set; }
    public uint TargetId { get; set; }
    public int CurrentScale { get; set; }
    public int RecommendedScale { get; set; }
    public int[] ScaleValues { get; set; }
    public List<WnstDisplayMode> Modes { get; set; }
}

public static class WnstDisplayNative
{
    private const uint QDC_ONLY_ACTIVE_PATHS = 0x00000002;
    private const int ERROR_SUCCESS = 0;
    private const int ERROR_INSUFFICIENT_BUFFER = 122;
    private const int ENUM_CURRENT_SETTINGS = -1;
    private const uint DISPLAY_DEVICE_PRIMARY_DEVICE = 0x00000004;
    private const uint CDS_UPDATEREGISTRY = 0x00000001;
    private const uint CDS_TEST = 0x00000002;
    private const int DISP_CHANGE_SUCCESSFUL = 0;
    private const uint DM_BITSPERPEL = 0x00040000;
    private const uint DM_PELSWIDTH = 0x00080000;
    private const uint DM_PELSHEIGHT = 0x00100000;
    private const uint DM_DISPLAYFREQUENCY = 0x00400000;
    private const int DM_INTERLACED = 0x00000002;

    private static readonly int[] StandardScales = new int[] { 100, 125, 150, 175, 200, 225, 250, 300, 350, 400, 450, 500 };

    [StructLayout(LayoutKind.Sequential)]
    private struct LUID
    {
        public uint LowPart;
        public int HighPart;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct DISPLAYCONFIG_RATIONAL
    {
        public uint Numerator;
        public uint Denominator;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct DISPLAYCONFIG_PATH_SOURCE_INFO
    {
        public LUID adapterId;
        public uint id;
        public uint modeInfoIdx;
        public uint statusFlags;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct DISPLAYCONFIG_PATH_TARGET_INFO
    {
        public LUID adapterId;
        public uint id;
        public uint modeInfoIdx;
        public int outputTechnology;
        public int rotation;
        public int scaling;
        public DISPLAYCONFIG_RATIONAL refreshRate;
        public int scanLineOrdering;
        [MarshalAs(UnmanagedType.Bool)] public bool targetAvailable;
        public uint statusFlags;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct DISPLAYCONFIG_PATH_INFO
    {
        public DISPLAYCONFIG_PATH_SOURCE_INFO sourceInfo;
        public DISPLAYCONFIG_PATH_TARGET_INFO targetInfo;
        public uint flags;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct POINTL
    {
        public int x;
        public int y;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct RECT
    {
        public int left;
        public int top;
        public int right;
        public int bottom;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct DISPLAYCONFIG_2DREGION
    {
        public uint cx;
        public uint cy;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct DISPLAYCONFIG_VIDEO_SIGNAL_INFO
    {
        public ulong pixelRate;
        public DISPLAYCONFIG_RATIONAL hSyncFreq;
        public DISPLAYCONFIG_RATIONAL vSyncFreq;
        public DISPLAYCONFIG_2DREGION activeSize;
        public DISPLAYCONFIG_2DREGION totalSize;
        public uint videoStandard;
        public int scanLineOrdering;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct DISPLAYCONFIG_TARGET_MODE
    {
        public DISPLAYCONFIG_VIDEO_SIGNAL_INFO targetVideoSignalInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct DISPLAYCONFIG_SOURCE_MODE
    {
        public uint width;
        public uint height;
        public int pixelFormat;
        public POINTL position;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct DISPLAYCONFIG_DESKTOP_IMAGE_INFO
    {
        public POINTL PathSourceSize;
        public RECT DesktopImageRegion;
        public RECT DesktopImageClip;
    }

    [StructLayout(LayoutKind.Explicit)]
    private struct DISPLAYCONFIG_MODE_INFO_UNION
    {
        [FieldOffset(0)] public DISPLAYCONFIG_TARGET_MODE targetMode;
        [FieldOffset(0)] public DISPLAYCONFIG_SOURCE_MODE sourceMode;
        [FieldOffset(0)] public DISPLAYCONFIG_DESKTOP_IMAGE_INFO desktopImageInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct DISPLAYCONFIG_MODE_INFO
    {
        public int infoType;
        public uint id;
        public LUID adapterId;
        public DISPLAYCONFIG_MODE_INFO_UNION modeInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct DISPLAYCONFIG_DEVICE_INFO_HEADER
    {
        public int type;
        public uint size;
        public LUID adapterId;
        public uint id;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct DISPLAYCONFIG_SOURCE_DEVICE_NAME
    {
        public DISPLAYCONFIG_DEVICE_INFO_HEADER header;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string viewGdiDeviceName;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct DISPLAYCONFIG_TARGET_DEVICE_NAME
    {
        public DISPLAYCONFIG_DEVICE_INFO_HEADER header;
        public uint flags;
        public int outputTechnology;
        public ushort edidManufactureId;
        public ushort edidProductCodeId;
        public uint connectorInstance;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 64)] public string monitorFriendlyDeviceName;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string monitorDevicePath;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct DISPLAYCONFIG_SOURCE_DPI_SCALE_GET
    {
        public DISPLAYCONFIG_DEVICE_INFO_HEADER header;
        public int minScaleRel;
        public int curScaleRel;
        public int maxScaleRel;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct DISPLAYCONFIG_SOURCE_DPI_SCALE_SET
    {
        public DISPLAYCONFIG_DEVICE_INFO_HEADER header;
        public int scaleRel;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct DISPLAY_DEVICE
    {
        public int cb;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string DeviceName;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceString;
        public uint StateFlags;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceID;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceKey;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct DEVMODE
    {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmDeviceName;
        public short dmSpecVersion;
        public short dmDriverVersion;
        public short dmSize;
        public short dmDriverExtra;
        public int dmFields;
        public int dmPositionX;
        public int dmPositionY;
        public int dmDisplayOrientation;
        public int dmDisplayFixedOutput;
        public short dmColor;
        public short dmDuplex;
        public short dmYResolution;
        public short dmTTOption;
        public short dmCollate;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmFormName;
        public short dmLogPixels;
        public int dmBitsPerPel;
        public int dmPelsWidth;
        public int dmPelsHeight;
        public int dmDisplayFlags;
        public int dmDisplayFrequency;
        public int dmICMMethod;
        public int dmICMIntent;
        public int dmMediaType;
        public int dmDitherType;
        public int dmReserved1;
        public int dmReserved2;
        public int dmPanningWidth;
        public int dmPanningHeight;
    }

    [DllImport("user32.dll")]
    private static extern int GetDisplayConfigBufferSizes(uint flags, out uint numPathArrayElements, out uint numModeInfoArrayElements);

    [DllImport("user32.dll")]
    private static extern int QueryDisplayConfig(uint flags, ref uint numPathArrayElements, [Out] DISPLAYCONFIG_PATH_INFO[] pathInfoArray, ref uint numModeInfoArrayElements, [Out] DISPLAYCONFIG_MODE_INFO[] modeInfoArray, IntPtr currentTopologyId);

    [DllImport("user32.dll", EntryPoint = "DisplayConfigGetDeviceInfo")]
    private static extern int DisplayConfigGetSourceDeviceName(ref DISPLAYCONFIG_SOURCE_DEVICE_NAME requestPacket);

    [DllImport("user32.dll", EntryPoint = "DisplayConfigGetDeviceInfo")]
    private static extern int DisplayConfigGetTargetDeviceName(ref DISPLAYCONFIG_TARGET_DEVICE_NAME requestPacket);

    [DllImport("user32.dll", EntryPoint = "DisplayConfigGetDeviceInfo")]
    private static extern int DisplayConfigGetDpiScale(ref DISPLAYCONFIG_SOURCE_DPI_SCALE_GET requestPacket);

    [DllImport("user32.dll", EntryPoint = "DisplayConfigSetDeviceInfo")]
    private static extern int DisplayConfigSetDpiScale(ref DISPLAYCONFIG_SOURCE_DPI_SCALE_SET requestPacket);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool EnumDisplayDevices(string lpDevice, uint iDevNum, ref DISPLAY_DEVICE lpDisplayDevice, uint dwFlags);

    [DllImport("user32.dll", CharSet = CharSet.Unicode, EntryPoint = "EnumDisplaySettingsExW")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool EnumDisplaySettingsEx(string lpszDeviceName, int iModeNum, ref DEVMODE lpDevMode, uint dwFlags);

    [DllImport("user32.dll", CharSet = CharSet.Unicode, EntryPoint = "ChangeDisplaySettingsExW")]
    private static extern int ChangeDisplaySettingsEx(string lpszDeviceName, ref DEVMODE lpDevMode, IntPtr hwnd, uint dwflags, IntPtr lParam);

    private static long PackLuid(LUID value)
    {
        return ((long)value.HighPart << 32) | (long)value.LowPart;
    }

    private static LUID UnpackLuid(long value)
    {
        LUID result = new LUID();
        result.LowPart = unchecked((uint)(value & 0xffffffffL));
        result.HighPart = unchecked((int)(value >> 32));
        return result;
    }

    private static DEVMODE NewDevMode()
    {
        DEVMODE mode = new DEVMODE();
        mode.dmDeviceName = String.Empty;
        mode.dmFormName = String.Empty;
        mode.dmSize = (short)Marshal.SizeOf(typeof(DEVMODE));
        return mode;
    }

    private static string GetManufacturerCode(string monitorDevicePath)
    {
        if (String.IsNullOrEmpty(monitorDevicePath)) return String.Empty;
        int marker = monitorDevicePath.IndexOf("DISPLAY#", StringComparison.OrdinalIgnoreCase);
        if (marker < 0) return String.Empty;
        int start = marker + 8;
        if (monitorDevicePath.Length < start + 3) return String.Empty;
        return monitorDevicePath.Substring(start, 3).ToUpperInvariant();
    }

    private static string GetConnectionCode(int value)
    {
        switch (value)
        {
            case 0: return "VGA";
            case 4: return "DVI";
            case 5: return "HDMI";
            case 6: return "Internal";
            case 10: return "DisplayPort";
            case 11: return "Internal";
            case 15: return "Wireless";
            case 16: return "Internal";
            case 17: return "USBC";
            default: return "Unknown";
        }
    }

    private static bool IsPrimaryDevice(string deviceName)
    {
        for (uint index = 0; ; index++)
        {
            DISPLAY_DEVICE adapter = new DISPLAY_DEVICE();
            adapter.cb = Marshal.SizeOf(typeof(DISPLAY_DEVICE));
            if (!EnumDisplayDevices(null, index, ref adapter, 0)) break;
            if (String.Equals(adapter.DeviceName, deviceName, StringComparison.OrdinalIgnoreCase))
                return (adapter.StateFlags & DISPLAY_DEVICE_PRIMARY_DEVICE) != 0;
        }
        return false;
    }

    private static List<WnstDisplayMode> EnumerateModes(string deviceName)
    {
        List<WnstDisplayMode> result = new List<WnstDisplayMode>();
        HashSet<string> unique = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        for (int index = 0; ; index++)
        {
            DEVMODE mode = NewDevMode();
            if (!EnumDisplaySettingsEx(deviceName, index, ref mode, 0)) break;
            if (mode.dmBitsPerPel < 32 || mode.dmPelsWidth <= 0 || mode.dmPelsHeight <= 0 || mode.dmDisplayFrequency <= 1) continue;
            if ((mode.dmDisplayFlags & DM_INTERLACED) != 0) continue;
            DEVMODE testedMode = mode;
            if (ChangeDisplaySettingsEx(deviceName, ref testedMode, IntPtr.Zero, CDS_TEST, IntPtr.Zero) != DISP_CHANGE_SUCCESSFUL) continue;
            string key = mode.dmPelsWidth.ToString() + "x" + mode.dmPelsHeight.ToString() + "@" + mode.dmDisplayFrequency.ToString();
            if (!unique.Add(key)) continue;
            result.Add(new WnstDisplayMode { Width = mode.dmPelsWidth, Height = mode.dmPelsHeight, Frequency = mode.dmDisplayFrequency });
        }
        result.Sort(delegate(WnstDisplayMode left, WnstDisplayMode right)
        {
            long leftPixels = (long)left.Width * left.Height;
            long rightPixels = (long)right.Width * right.Height;
            int pixels = rightPixels.CompareTo(leftPixels);
            if (pixels != 0) return pixels;
            int width = right.Width.CompareTo(left.Width);
            if (width != 0) return width;
            return right.Frequency.CompareTo(left.Frequency);
        });
        return result;
    }

    private static bool TryGetScaleInfo(LUID adapterId, uint sourceId, out int currentScale, out int recommendedScale, out int[] values)
    {
        currentScale = 0;
        recommendedScale = 0;
        values = new int[0];
        DISPLAYCONFIG_SOURCE_DPI_SCALE_GET request = new DISPLAYCONFIG_SOURCE_DPI_SCALE_GET();
        request.header.type = -3;
        request.header.size = (uint)Marshal.SizeOf(typeof(DISPLAYCONFIG_SOURCE_DPI_SCALE_GET));
        request.header.adapterId = adapterId;
        request.header.id = sourceId;
        int code = DisplayConfigGetDpiScale(ref request);
        if (code != ERROR_SUCCESS) return false;

        int recommendedIndex = -request.minScaleRel;
        int currentIndex = recommendedIndex + request.curScaleRel;
        int minIndex = recommendedIndex + request.minScaleRel;
        int maxIndex = recommendedIndex + request.maxScaleRel;
        if (recommendedIndex < 0 || recommendedIndex >= StandardScales.Length) return false;
        if (minIndex < 0) minIndex = 0;
        if (maxIndex >= StandardScales.Length) maxIndex = StandardScales.Length - 1;
        if (currentIndex < minIndex || currentIndex > maxIndex) return false;

        List<int> scaleValues = new List<int>();
        for (int index = minIndex; index <= maxIndex; index++) scaleValues.Add(StandardScales[index]);
        currentScale = StandardScales[currentIndex];
        recommendedScale = StandardScales[recommendedIndex];
        values = scaleValues.ToArray();
        return true;
    }

    public static WnstDisplayMode GetCurrentMode(string deviceName)
    {
        DEVMODE mode = NewDevMode();
        if (!EnumDisplaySettingsEx(deviceName, ENUM_CURRENT_SETTINGS, ref mode, 0)) return null;
        return new WnstDisplayMode { Width = mode.dmPelsWidth, Height = mode.dmPelsHeight, Frequency = mode.dmDisplayFrequency };
    }

    public static WnstDisplayInfo[] GetDisplays()
    {
        uint pathCount;
        uint modeCount;
        int code = GetDisplayConfigBufferSizes(QDC_ONLY_ACTIVE_PATHS, out pathCount, out modeCount);
        if (code != ERROR_SUCCESS) return new WnstDisplayInfo[0];

        DISPLAYCONFIG_PATH_INFO[] paths = null;
        DISPLAYCONFIG_MODE_INFO[] modes = null;
        for (int attempt = 0; attempt < 3; attempt++)
        {
            paths = new DISPLAYCONFIG_PATH_INFO[(int)pathCount];
            modes = new DISPLAYCONFIG_MODE_INFO[(int)modeCount];
            code = QueryDisplayConfig(QDC_ONLY_ACTIVE_PATHS, ref pathCount, paths, ref modeCount, modes, IntPtr.Zero);
            if (code == ERROR_SUCCESS) break;
            if (code != ERROR_INSUFFICIENT_BUFFER) return new WnstDisplayInfo[0];
            code = GetDisplayConfigBufferSizes(QDC_ONLY_ACTIVE_PATHS, out pathCount, out modeCount);
            if (code != ERROR_SUCCESS) return new WnstDisplayInfo[0];
        }
        if (code != ERROR_SUCCESS || paths == null) return new WnstDisplayInfo[0];

        List<WnstDisplayInfo> result = new List<WnstDisplayInfo>();
        HashSet<string> seenTargets = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        for (int index = 0; index < (int)pathCount; index++)
        {
            DISPLAYCONFIG_PATH_INFO path = paths[index];
            string targetKey = PackLuid(path.targetInfo.adapterId).ToString() + ":" + path.targetInfo.id.ToString();
            if (!seenTargets.Add(targetKey)) continue;

            DISPLAYCONFIG_SOURCE_DEVICE_NAME source = new DISPLAYCONFIG_SOURCE_DEVICE_NAME();
            source.header.type = 1;
            source.header.size = (uint)Marshal.SizeOf(typeof(DISPLAYCONFIG_SOURCE_DEVICE_NAME));
            source.header.adapterId = path.sourceInfo.adapterId;
            source.header.id = path.sourceInfo.id;
            if (DisplayConfigGetSourceDeviceName(ref source) != ERROR_SUCCESS || String.IsNullOrEmpty(source.viewGdiDeviceName)) continue;

            DISPLAYCONFIG_TARGET_DEVICE_NAME target = new DISPLAYCONFIG_TARGET_DEVICE_NAME();
            target.header.type = 2;
            target.header.size = (uint)Marshal.SizeOf(typeof(DISPLAYCONFIG_TARGET_DEVICE_NAME));
            target.header.adapterId = path.targetInfo.adapterId;
            target.header.id = path.targetInfo.id;
            DisplayConfigGetTargetDeviceName(ref target);

            WnstDisplayMode current = GetCurrentMode(source.viewGdiDeviceName);
            if (current == null) continue;
            int currentScale;
            int recommendedScale;
            int[] scaleValues;
            TryGetScaleInfo(path.sourceInfo.adapterId, path.sourceInfo.id, out currentScale, out recommendedScale, out scaleValues);

            WnstDisplayInfo display = new WnstDisplayInfo();
            display.DeviceName = source.viewGdiDeviceName;
            display.FriendlyName = target.monitorFriendlyDeviceName ?? String.Empty;
            display.ManufacturerCode = GetManufacturerCode(target.monitorDevicePath);
            display.ConnectionCode = GetConnectionCode(path.targetInfo.outputTechnology);
            display.IsPrimary = IsPrimaryDevice(source.viewGdiDeviceName);
            display.Width = current.Width;
            display.Height = current.Height;
            display.Frequency = current.Frequency;
            display.AdapterLuid = PackLuid(path.sourceInfo.adapterId);
            display.SourceId = path.sourceInfo.id;
            display.TargetId = path.targetInfo.id;
            display.CurrentScale = currentScale;
            display.RecommendedScale = recommendedScale;
            display.ScaleValues = scaleValues;
            display.Modes = EnumerateModes(source.viewGdiDeviceName);
            result.Add(display);
        }

        result.Sort(delegate(WnstDisplayInfo left, WnstDisplayInfo right)
        {
            if (left.IsPrimary != right.IsPrimary) return left.IsPrimary ? -1 : 1;
            int device = StringComparer.OrdinalIgnoreCase.Compare(left.DeviceName, right.DeviceName);
            if (device != 0) return device;
            return left.TargetId.CompareTo(right.TargetId);
        });
        bool primaryAssigned = false;
        for (int index = 0; index < result.Count; index++)
        {
            if (result[index].IsPrimary && !primaryAssigned) primaryAssigned = true;
            else result[index].IsPrimary = false;
        }
        if (!primaryAssigned && result.Count > 0) result[0].IsPrimary = true;
        return result.ToArray();
    }

    public static int ApplyMode(string deviceName, int width, int height, int frequency)
    {
        DEVMODE mode = NewDevMode();
        if (!EnumDisplaySettingsEx(deviceName, ENUM_CURRENT_SETTINGS, ref mode, 0)) return -1;
        mode.dmPelsWidth = width;
        mode.dmPelsHeight = height;
        mode.dmDisplayFrequency = frequency;
        mode.dmFields = unchecked((int)(DM_BITSPERPEL | DM_PELSWIDTH | DM_PELSHEIGHT | DM_DISPLAYFREQUENCY));
        int test = ChangeDisplaySettingsEx(deviceName, ref mode, IntPtr.Zero, CDS_TEST, IntPtr.Zero);
        if (test != DISP_CHANGE_SUCCESSFUL) return test;
        return ChangeDisplaySettingsEx(deviceName, ref mode, IntPtr.Zero, CDS_UPDATEREGISTRY, IntPtr.Zero);
    }

    public static int ApplyScale(long adapterLuid, uint sourceId, int scalePercent)
    {
        int requestedIndex = Array.IndexOf(StandardScales, scalePercent);
        if (requestedIndex < 0) return 87;

        LUID adapterId = UnpackLuid(adapterLuid);
        DISPLAYCONFIG_SOURCE_DPI_SCALE_GET current = new DISPLAYCONFIG_SOURCE_DPI_SCALE_GET();
        current.header.type = -3;
        current.header.size = (uint)Marshal.SizeOf(typeof(DISPLAYCONFIG_SOURCE_DPI_SCALE_GET));
        current.header.adapterId = adapterId;
        current.header.id = sourceId;
        int code = DisplayConfigGetDpiScale(ref current);
        if (code != ERROR_SUCCESS) return code;

        int recommendedIndex = -current.minScaleRel;
        int relative = requestedIndex - recommendedIndex;
        if (relative < current.minScaleRel || relative > current.maxScaleRel) return 87;

        DISPLAYCONFIG_SOURCE_DPI_SCALE_SET request = new DISPLAYCONFIG_SOURCE_DPI_SCALE_SET();
        request.header.type = -4;
        request.header.size = (uint)Marshal.SizeOf(typeof(DISPLAYCONFIG_SOURCE_DPI_SCALE_SET));
        request.header.adapterId = adapterId;
        request.header.id = sourceId;
        request.scaleRel = relative;
        return DisplayConfigSetDpiScale(ref request);
    }
}
'@ -ErrorAction Stop
    }
    $script:DisplayNativeAvailable = $true
}
catch {
    $script:DisplayNativeAvailable = $false
    $script:DisplayNativeError = [string]$_.Exception.Message
}

function Get-HuDisplayManufacturerName {
    param([AllowEmptyString()][string]$Code)

    $manufacturers = @{
        'ACR'='Acer'; 'ACI'='ASUS'; 'AUS'='ASUS'; 'APP'='Apple'; 'AOC'='AOC'
        'BNQ'='BenQ'; 'DEL'='Dell'; 'GSM'='LG'; 'HWP'='HP'; 'IVM'='iiyama'
        'LEN'='Lenovo'; 'MSI'='MSI'; 'PHI'='Philips'; 'SAM'='Samsung'; 'VSC'='ViewSonic'
    }
    $key = ([string]$Code).Trim().ToUpperInvariant()
    if ($manufacturers.ContainsKey($key)) { return [string]$manufacturers[$key] }
    return $key
}

function Get-HuDisplayName {
    param([Parameter(Mandatory=$true)][object]$Display)

    $friendly = ([string]$Display.FriendlyName).Trim()
    $manufacturer = Get-HuDisplayManufacturerName -Code ([string]$Display.ManufacturerCode)
    if ([string]::IsNullOrWhiteSpace($friendly)) {
        if (-not [string]::IsNullOrWhiteSpace($manufacturer)) { return $manufacturer }
        return T 'Unavailable'
    }
    if (-not [string]::IsNullOrWhiteSpace($manufacturer) -and $friendly -notmatch ('(?i)^' + [regex]::Escape($manufacturer) + '\b')) {
        return ($manufacturer + ' ' + $friendly).Trim()
    }
    return $friendly
}

function Get-HuDisplayConnectionText {
    param([AllowEmptyString()][string]$Code)

    switch ([string]$Code) {
        'DisplayPort' { return 'DisplayPort' }
        'HDMI' { return 'HDMI' }
        'DVI' { return 'DVI' }
        'VGA' { return 'VGA' }
        'USBC' { return 'USB-C' }
        'Internal' { return T 'ThisPcDisplayConnectionInternal' }
        'Wireless' { return T 'ThisPcDisplayConnectionWireless' }
        default { return T 'ThisPcDisplayConnectionUnknown' }
    }
}

function Get-HuDisplayRoleText {
    param([int]$Index,[bool]$IsPrimary)

    if ($IsPrimary) { return T 'ThisPcDisplayPrimary' }
    switch ($Index + 1) {
        2 { return T 'ThisPcDisplaySecond' }
        3 { return T 'ThisPcDisplayThird' }
        4 { return T 'ThisPcDisplayFourth' }
        5 { return T 'ThisPcDisplayFifth' }
        6 { return T 'ThisPcDisplaySixth' }
        default { return TF 'ThisPcDisplayNumberFormat' @($Index + 1) }
    }
}

function Update-HuDisplayRefreshOptions {
    if ($script:DisplayUiUpdating) { return }
    $monitors = @($script:DisplayMonitors)
    if ($monitors.Count -eq 0 -or $script:DisplayCarouselIndex -ge $monitors.Count) { return }
    $resolution = $DisplayResolutionCombo.SelectedItem
    if (-not $resolution) { return }

    $display = $monitors[$script:DisplayCarouselIndex]
    $previousFrequency = if ($DisplayRefreshCombo.SelectedItem) { [int]$DisplayRefreshCombo.SelectedItem.Value } else { [int]$display.Frequency }
    $frequencies = @($display.Modes | Where-Object {
        [int]$_.Width -eq [int]$resolution.Width -and [int]$_.Height -eq [int]$resolution.Height
    } | ForEach-Object { [int]$_.Frequency } | Sort-Object -Unique -Descending | ForEach-Object {
        [pscustomobject]@{ Value=[int]$_; Name=(TF 'ThisPcDisplayHzFormat' @([int]$_)) }
    })

    $script:DisplayUiUpdating = $true
    try {
        $DisplayRefreshCombo.ItemsSource = $frequencies
        $selected = $frequencies | Where-Object { [int]$_.Value -eq $previousFrequency } | Select-Object -First 1
        if (-not $selected) { $selected = $frequencies | Select-Object -First 1 }
        $DisplayRefreshCombo.SelectedItem = $selected
        $DisplayApplyRefreshButton.IsEnabled = $null -ne $selected
    }
    finally { $script:DisplayUiUpdating = $false }
}

function Update-HuDisplayCarousel {
    if (-not $DisplayContentPanel) { return }
    $monitors = @($script:DisplayMonitors)
    if ($monitors.Count -eq 0) {
        $DisplayContentPanel.Visibility = 'Collapsed'
        $DisplayEmptyText.Visibility = 'Visible'
        return
    }

    if ($script:DisplayCarouselIndex -lt 0) { $script:DisplayCarouselIndex = $monitors.Count - 1 }
    if ($script:DisplayCarouselIndex -ge $monitors.Count) { $script:DisplayCarouselIndex = 0 }
    $display = $monitors[$script:DisplayCarouselIndex]

    $script:DisplayUiUpdating = $true
    try {
        $DisplayEmptyText.Visibility = 'Collapsed'
        $DisplayContentPanel.Visibility = 'Visible'
        $DisplayRoleText.Text = Get-HuDisplayRoleText -Index $script:DisplayCarouselIndex -IsPrimary ([bool]$display.IsPrimary)
        $DisplayCounterText.Text = '{0} / {1}' -f ($script:DisplayCarouselIndex + 1),$monitors.Count
        $DisplayMonitorName.Text = Get-HuDisplayName -Display $display
        $DisplayConnectionValue.Text = Get-HuDisplayConnectionText -Code ([string]$display.ConnectionCode)

        $showNavigation = $monitors.Count -gt 1
        $DisplayPreviousButton.Visibility = 'Visible'
        $DisplayNextButton.Visibility = 'Visible'
        $DisplayPreviousButton.IsEnabled = $showNavigation
        $DisplayNextButton.IsEnabled = $showNavigation
        $DisplayPreviousButton.Opacity = if ($showNavigation) { 1.0 } else { 0.42 }
        $DisplayNextButton.Opacity = if ($showNavigation) { 1.0 } else { 0.42 }

        $resolutionValues = New-Object 'System.Collections.Generic.List[object]'
        $resolutionKeys = @{}
        foreach ($mode in @($display.Modes)) {
            $key = '{0}x{1}' -f ([int]$mode.Width),([int]$mode.Height)
            if ($resolutionKeys.ContainsKey($key)) { continue }
            $resolutionKeys[$key] = $true
            $resolutionValues.Add([pscustomobject]@{
                Width = [int]$mode.Width
                Height = [int]$mode.Height
                Name = "$([int]$mode.Width) $([char]0x00D7) $([int]$mode.Height)"
            })
        }
        $resolutions = @($resolutionValues.ToArray())
        $DisplayResolutionCombo.ItemsSource = $resolutions
        $selectedResolution = $resolutions | Where-Object { $_.Width -eq [int]$display.Width -and $_.Height -eq [int]$display.Height } | Select-Object -First 1
        if (-not $selectedResolution) { $selectedResolution = $resolutions | Select-Object -First 1 }
        $DisplayResolutionCombo.SelectedItem = $selectedResolution
        $DisplayApplyResolutionButton.IsEnabled = $null -ne $selectedResolution

        $frequencyValues = @($display.Modes | Where-Object {
            [int]$_.Width -eq [int]$selectedResolution.Width -and [int]$_.Height -eq [int]$selectedResolution.Height
        } | ForEach-Object { [int]$_.Frequency } | Sort-Object -Unique -Descending | ForEach-Object {
            [pscustomobject]@{ Value=[int]$_; Name=(TF 'ThisPcDisplayHzFormat' @([int]$_)) }
        })
        $DisplayRefreshCombo.ItemsSource = $frequencyValues
        $selectedFrequency = $frequencyValues | Where-Object { [int]$_.Value -eq [int]$display.Frequency } | Select-Object -First 1
        if (-not $selectedFrequency) { $selectedFrequency = $frequencyValues | Select-Object -First 1 }
        $DisplayRefreshCombo.SelectedItem = $selectedFrequency
        $DisplayApplyRefreshButton.IsEnabled = $null -ne $selectedFrequency

        $scaleValues = @($display.ScaleValues | ForEach-Object {
            $value = [int]$_
            [pscustomobject]@{
                Value = $value
                Name = if ($value -eq [int]$display.RecommendedScale) { TF 'ThisPcDisplayRecommendedFormat' @($value) } else { '{0} %' -f $value }
            }
        })
        $DisplayScalingCombo.ItemsSource = $scaleValues
        $selectedScale = $scaleValues | Where-Object { [int]$_.Value -eq [int]$display.CurrentScale } | Select-Object -First 1
        $DisplayScalingCombo.SelectedItem = $selectedScale
        $DisplayScalingCombo.IsEnabled = $null -ne $selectedScale
        $DisplayApplyScalingButton.IsEnabled = $null -ne $selectedScale

        $DisplayIndicatorsPanel.Children.Clear()
        for ($index = 0; $index -lt $monitors.Count; $index++) {
            $indicator = New-Object Windows.Shapes.Ellipse
            $indicator.Width = 7
            $indicator.Height = 7
            $indicator.Margin = New-Object Windows.Thickness(3,0,3,0)
            $resource = if ($index -eq $script:DisplayCarouselIndex) { 'AccentBrush' } else { 'MutedBrush' }
            $indicator.SetResourceReference([Windows.Shapes.Shape]::FillProperty,$resource)
            [void]$DisplayIndicatorsPanel.Children.Add($indicator)
        }
    }
    finally { $script:DisplayUiUpdating = $false }
}

function Update-HuDisplayInventory {
    param([AllowEmptyString()][string]$PreserveDeviceName='',[Nullable[uint32]]$PreserveTargetId=$null)

    $script:DisplayInventoryLoaded = $true
    if (-not $script:DisplayNativeAvailable) {
        $script:DisplayMonitors = @()
        Update-HuDisplayCarousel
        return
    }

    if ([string]::IsNullOrWhiteSpace($PreserveDeviceName) -and @($script:DisplayMonitors).Count -gt 0 -and $script:DisplayCarouselIndex -lt @($script:DisplayMonitors).Count) {
        $current = @($script:DisplayMonitors)[$script:DisplayCarouselIndex]
        $PreserveDeviceName = [string]$current.DeviceName
        $PreserveTargetId = [uint32]$current.TargetId
    }

    try { $script:DisplayMonitors = @([WnstDisplayNative]::GetDisplays()) }
    catch { $script:DisplayMonitors = @() }

    $script:DisplayCarouselIndex = 0
    if (-not [string]::IsNullOrWhiteSpace($PreserveDeviceName)) {
        for ($index = 0; $index -lt @($script:DisplayMonitors).Count; $index++) {
            $candidate = @($script:DisplayMonitors)[$index]
            if ([string]$candidate.DeviceName -ieq $PreserveDeviceName -and ($null -eq $PreserveTargetId -or [uint32]$candidate.TargetId -eq [uint32]$PreserveTargetId)) {
                $script:DisplayCarouselIndex = $index
                break
            }
        }
    }
    Update-HuDisplayCarousel
}

function Show-HuDisplayChangeConfirmation {
    param([int]$Seconds=15)

    $dialogBackground = Get-AppThemeColor 'WindowBrush' '#20242B'
    $dialogSurface = Get-AppThemeColor 'CardBrush' '#171A1F'
    $dialogText = Get-AppThemeColor 'TextBrush' '#F4F4F4'
    $dialogMuted = Get-AppThemeColor 'MutedBrush' '#A8ADB5'
    $dialogBorder = Get-AppThemeColor 'WindowBorderBrush' '#59616B'
    $dialogAccent = ConvertTo-AccentHex ([string]$script:Settings.AccentColor)
    if (-not $dialogAccent) { $dialogAccent = '#1A9FFF' }
    [xml]$confirmationXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Width="470" Height="205" WindowStartupLocation="CenterOwner" WindowStyle="None" ResizeMode="NoResize" AllowsTransparency="True" Background="Transparent" Foreground="$dialogText">
  <Window.Resources><Style x:Key="DisplayDialogButton" TargetType="Button"><Setter Property="Height" Value="32"/><Setter Property="MinWidth" Value="110"/><Setter Property="Padding" Value="12,4"/><Setter Property="Foreground" Value="$dialogText"/><Setter Property="Background" Value="$dialogSurface"/><Setter Property="BorderBrush" Value="$dialogBorder"/><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Border x:Name="B" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="1" CornerRadius="$([int](Get-AppCornerRadiusValue))" Padding="{TemplateBinding Padding}"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="B" Property="Background" Value="$dialogAccent"/><Setter TargetName="B" Property="BorderBrush" Value="$dialogAccent"/><Setter Property="Foreground" Value="#FFFFFF"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style></Window.Resources>
  <Border Margin="1" Background="$dialogBackground" BorderBrush="$dialogBorder" BorderThickness="1" CornerRadius="$([int](Get-AppCornerRadiusValue))"><Grid><Grid.RowDefinitions><RowDefinition Height="42"/><RowDefinition Height="*"/></Grid.RowDefinitions><Border Background="$dialogSurface" CornerRadius="$([int](Get-AppCornerRadiusValue)),$([int](Get-AppCornerRadiusValue)),0,0"><TextBlock x:Name="DialogTitle" Margin="14,0" VerticalAlignment="Center" FontSize="15" FontWeight="SemiBold"/></Border><Grid Grid.Row="1" Margin="14"><Grid.RowDefinitions><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions><TextBlock x:Name="DialogMessage" VerticalAlignment="Center" TextWrapping="Wrap" Foreground="$dialogMuted"/><StackPanel Grid.Row="1" Orientation="Horizontal" HorizontalAlignment="Right"><Button x:Name="DialogRevert" Style="{StaticResource DisplayDialogButton}" Margin="0,0,8,0"/><Button x:Name="DialogKeep" Style="{StaticResource DisplayDialogButton}"/></StackPanel></Grid></Grid></Border>
</Window>
"@
    $reader = New-Object Xml.XmlNodeReader($confirmationXaml)
    $dialog = [Windows.Markup.XamlReader]::Load($reader)
    $dialog.Owner = $window
    $dialog.FontFamily = $script:UiFontFamily
    Enable-RoundedDialogFrame $dialog
    $title = $dialog.FindName('DialogTitle')
    $message = $dialog.FindName('DialogMessage')
    $revert = $dialog.FindName('DialogRevert')
    $keep = $dialog.FindName('DialogKeep')
    $title.Text = T 'ConfirmTitle'
    $revert.Content = T 'ThisPcDisplayRevert'
    $keep.Content = T 'ThisPcDisplayKeep'
    $state = [pscustomobject]@{ Remaining=[int]$Seconds; Keep=$false }
    $updateMessage = { $message.Text = TF 'ThisPcDisplayConfirmFormat' @($state.Remaining) }
    $timer = New-Object Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromSeconds(1)
    $timer.Add_Tick({
        $state.Remaining--
        & $updateMessage
        if ($state.Remaining -le 0) { $timer.Stop(); $dialog.Close() }
    })
    $keep.Add_Click({ $state.Keep=$true; $timer.Stop(); $dialog.Close() })
    $revert.Add_Click({ $state.Keep=$false; $timer.Stop(); $dialog.Close() })
    $dialog.Add_ContentRendered({ & $updateMessage; $timer.Start() })
    $dialog.Add_Closed({ $timer.Stop() })
    [void]$dialog.ShowDialog()
    return [bool]$state.Keep
}

function Invoke-HuDisplayModeChange {
    $monitors = @($script:DisplayMonitors)
    if ($monitors.Count -eq 0 -or $script:DisplayCarouselIndex -ge $monitors.Count) { return }
    $display = $monitors[$script:DisplayCarouselIndex]
    $resolution = $DisplayResolutionCombo.SelectedItem
    $refresh = $DisplayRefreshCombo.SelectedItem
    if (-not $resolution -or -not $refresh) { return }

    $oldMode = [WnstDisplayNative]::GetCurrentMode([string]$display.DeviceName)
    if (-not $oldMode) { Show-AppError (T 'ThisPcDisplayApplyFailed'); return }
    $code = [WnstDisplayNative]::ApplyMode([string]$display.DeviceName,[int]$resolution.Width,[int]$resolution.Height,[int]$refresh.Value)
    if ($code -ne 0) { Show-AppError (TF 'ThisPcDisplayApplyErrorFormat' @($code)); return }

    $keep = Show-HuDisplayChangeConfirmation -Seconds 15
    if (-not $keep) {
        [void][WnstDisplayNative]::ApplyMode([string]$display.DeviceName,[int]$oldMode.Width,[int]$oldMode.Height,[int]$oldMode.Frequency)
    }
    Update-HuDisplayInventory -PreserveDeviceName ([string]$display.DeviceName) -PreserveTargetId ([uint32]$display.TargetId)
}

function Invoke-HuDisplayScaleChange {
    $monitors = @($script:DisplayMonitors)
    if ($monitors.Count -eq 0 -or $script:DisplayCarouselIndex -ge $monitors.Count) { return }
    $display = $monitors[$script:DisplayCarouselIndex]
    $scale = $DisplayScalingCombo.SelectedItem
    if (-not $scale) { return }

    $code = [WnstDisplayNative]::ApplyScale([long]$display.AdapterLuid,[uint32]$display.SourceId,[int]$scale.Value)
    if ($code -ne 0) { Show-AppError (TF 'ThisPcDisplayApplyErrorFormat' @($code)); return }
    Update-HuDisplayInventory -PreserveDeviceName ([string]$display.DeviceName) -PreserveTargetId ([uint32]$display.TargetId)
}
