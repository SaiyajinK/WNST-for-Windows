# WNST - surfaces verticalement redimensionnables
# Conserve une hauteur séparée pour le mode fenêtré et le mode maximisé.

$script:WnstResizableSurfaces = @{}
$script:WnstApplyingResponsiveSize = $false

function Get-WnstResizeMode {
    if ($window.WindowState -eq [Windows.WindowState]::Maximized) { return 'Maximized' }
    return 'Windowed'
}

# Les fenêtres WPF sans bordure ne calculent pas toujours correctement la zone
# maximisée (taskbar, bordures invisibles, écrans secondaires). On laisse Windows
# fournir les vraies bornes du moniteur courant via WM_GETMINMAXINFO.
function Initialize-WnstMonitorWorkAreaHook {
    try {
        if (-not ('WNST.Native.MaximizeInterop' -as [type])) {
            Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

namespace WNST.Native
{
    [StructLayout(LayoutKind.Sequential)]
    public struct POINT
    {
        public int x;
        public int y;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct MINMAXINFO
    {
        public POINT ptReserved;
        public POINT ptMaxSize;
        public POINT ptMaxPosition;
        public POINT ptMinTrackSize;
        public POINT ptMaxTrackSize;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT
    {
        public int left;
        public int top;
        public int right;
        public int bottom;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
    public sealed class MONITORINFO
    {
        public int cbSize = Marshal.SizeOf(typeof(MONITORINFO));
        public RECT rcMonitor = new RECT();
        public RECT rcWork = new RECT();
        public int dwFlags = 0;
    }

    public static class MaximizeInterop
    {
        public const int MONITOR_DEFAULTTONEAREST = 2;

        [DllImport("user32.dll")]
        public static extern IntPtr MonitorFromWindow(IntPtr hwnd, int dwFlags);

        [DllImport("user32.dll", CharSet = CharSet.Auto)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool GetMonitorInfo(IntPtr hMonitor, MONITORINFO lpmi);
    }
}
"@ -ErrorAction Stop
        }

        # Annule les anciennes limites WorkArea appliquées par la v41/v42.
        $window.MaxWidth = [double]::PositiveInfinity
        $window.MaxHeight = [double]::PositiveInfinity

        if ($script:WnstMonitorWorkAreaHookInstalled) { return }

        $helper = [Windows.Interop.WindowInteropHelper]::new($window)
        $hwnd = $helper.Handle
        if ($hwnd -eq [IntPtr]::Zero) { return }

        $source = [Windows.Interop.HwndSource]::FromHwnd($hwnd)
        if (-not $source) { return }

        $script:WnstMonitorWorkAreaHook = [Windows.Interop.HwndSourceHook]{
            param($hookHwnd, $msg, $wParam, $lParam, [ref]$handled)

            # WM_GETMINMAXINFO
            if ($msg -eq 0x0024 -and $lParam -ne [IntPtr]::Zero) {
                try {
                    $mmi = [Runtime.InteropServices.Marshal]::PtrToStructure(
                        $lParam,
                        [type][WNST.Native.MINMAXINFO]
                    )

                    $monitor = [WNST.Native.MaximizeInterop]::MonitorFromWindow(
                        $hookHwnd,
                        [WNST.Native.MaximizeInterop]::MONITOR_DEFAULTTONEAREST
                    )

                    if ($monitor -ne [IntPtr]::Zero) {
                        $monitorInfo = [WNST.Native.MONITORINFO]::new()
                        if ([WNST.Native.MaximizeInterop]::GetMonitorInfo($monitor, $monitorInfo)) {
                            $work = $monitorInfo.rcWork
                            $monitorBounds = $monitorInfo.rcMonitor

                            # Position relative au moniteur et taille exacte de sa zone de travail.
                            # Les coordonnées sont en pixels natifs, comme attendu par ce message Win32.
                            # POINT est une structure imbriquée : modifier directement
                            # ptMaxPosition.x/ptMaxSize.x depuis PowerShell peut ne modifier
                            # qu'une copie. On reconstruit chaque POINT puis on le réaffecte.
                            $maxPosition = [WNST.Native.POINT]::new()
                            $maxPosition.x = [int]($work.left - $monitorBounds.left)
                            $maxPosition.y = [int]($work.top - $monitorBounds.top)

                            $maxSize = [WNST.Native.POINT]::new()
                            $maxSize.x = [int]($work.right - $work.left)
                            $maxSize.y = [int]($work.bottom - $work.top)

                            $mmi.ptMaxPosition = $maxPosition
                            $mmi.ptMaxSize = $maxSize
                            $mmi.ptMaxTrackSize = $maxSize

                            [Runtime.InteropServices.Marshal]::StructureToPtr($mmi, $lParam, $false)
                            $handled.Value = $true
                        }
                    }
                }
                catch { }
            }

            return [IntPtr]::Zero
        }

        $source.AddHook($script:WnstMonitorWorkAreaHook)
        $script:WnstMonitorWorkAreaHookInstalled = $true
    }
    catch { }
}

function Get-WnstSurfaceMaxHeight {
    param(
        [object]$State = $null,
        [double]$Minimum = 100.0
    )

    # Plafond général : une surface ne doit jamais consommer presque tout l'écran.
    # La fenêtre maximisée est déjà bornée à la zone de travail du moniteur courant
    # par WM_GETMINMAXINFO, donc ActualHeight est exprimé dans la même unité WPF que
    # TranslatePoint utilisé plus bas.
    $available = [double]$window.ActualHeight
    if ($available -le 0) {
        try { $available = [double][Windows.SystemParameters]::WorkArea.Height } catch {}
    }
    if ($available -le 0) { $available = 900.0 }

    $maxHeight = [Math]::Min(760.0, $available * 0.68)

    # Pour les journaux, le plafond doit aussi dépendre de leur position réelle dans
    # la fenêtre. Cela garantit que le bouton situé sous le journal reste toujours
    # dans la zone visible, même après un redimensionnement manuel en plein écran.
    if ($State -and [bool]$State.ViewportBound) {
        try {
            $top = [double]$State.Target.TranslatePoint([Windows.Point]::new(0,0),$window).Y
            $reserve = [Math]::Max(48.0,[double]$State.BottomReserve)
            $visibleLimit = [double]$window.ActualHeight - $top - $reserve
            if ($visibleLimit -gt 0) { $maxHeight = [Math]::Min($maxHeight,$visibleLimit) }
        }
        catch {}
    }

    return [Math]::Max($Minimum,$maxHeight)
}

function Set-WnstSurfaceHeight {
    param(
        [Parameter(Mandatory=$true)][object]$State,
        [Parameter(Mandatory=$true)][double]$Height,
        [switch]$Remember
    )

    $maxHeight = Get-WnstSurfaceMaxHeight -State $State -Minimum ([double]$State.MinHeight)
    $height = [Math]::Max([double]$State.MinHeight, [Math]::Min($maxHeight, $Height))

    $script:WnstApplyingResponsiveSize = $true
    try { $State.Target.Height = $height }
    finally { $script:WnstApplyingResponsiveSize = $false }

    if ($Remember) {
        if ((Get-WnstResizeMode) -eq 'Maximized') { $State.MaximizedHeight = $height }
        else { $State.WindowedHeight = $height }
    }
}

function Register-WnstResizableSurface {
    param(
        [Parameter(Mandatory=$true)][string]$Key,
        [Parameter(Mandatory=$true)][object]$Target,
        [object]$Grip = $null,
        [double]$WindowedHeight = 180.0,
        [double]$MaximizedHeight = 320.0,
        [double]$MinHeight = 100.0,
        [switch]$ViewportBound,
        [double]$BottomReserve = 78.0
    )

    if (-not $Target) { return }

    $state = [pscustomobject]@{
        Key = $Key
        Target = $Target
        Grip = $Grip
        WindowedHeight = $WindowedHeight
        MaximizedHeight = $MaximizedHeight
        MinHeight = $MinHeight
        ViewportBound = [bool]$ViewportBound
        BottomReserve = $BottomReserve
        Dragging = $false
        StartY = 0.0
        StartHeight = 0.0
    }
    $script:WnstResizableSurfaces[$Key] = $state

    $trigger = if ($Grip) { $Grip } else { $Target }
    if (-not $trigger) { return }

    $trigger.Add_PreviewMouseLeftButtonDown({
        param($sender,$eventArgs)
        if ($eventArgs.ChangedButton -ne [Windows.Input.MouseButton]::Left) { return }

        $local = $eventArgs.GetPosition($trigger)
        if (-not $Grip -and $local.Y -lt ([double]$trigger.ActualHeight - 7.0)) { return }

        $state.Dragging = $true
        $state.StartY = [double]$eventArgs.GetPosition($window).Y
        $state.StartHeight = [double]$state.Target.ActualHeight
        if ($state.StartHeight -lt $state.MinHeight) { $state.StartHeight = $state.WindowedHeight }

        [void]$trigger.CaptureMouse()
        $eventArgs.Handled = $true
    }.GetNewClosure())

    $trigger.Add_PreviewMouseMove({
        param($sender,$eventArgs)

        if (-not $state.Dragging) {
            if (-not $Grip) {
                $local = $eventArgs.GetPosition($trigger)
                $trigger.Cursor = if ($local.Y -ge ([double]$trigger.ActualHeight - 7.0)) {
                    [Windows.Input.Cursors]::SizeNS
                } else {
                    $null
                }
            }
            return
        }

        if ($eventArgs.LeftButton -ne [Windows.Input.MouseButtonState]::Pressed) {
            $state.Dragging = $false
            if ($trigger.IsMouseCaptured) { $trigger.ReleaseMouseCapture() }
            return
        }

        $delta = [double]$eventArgs.GetPosition($window).Y - [double]$state.StartY
        Set-WnstSurfaceHeight -State $state -Height ([double]$state.StartHeight + $delta) -Remember
        $eventArgs.Handled = $true
    }.GetNewClosure())

    $trigger.Add_PreviewMouseLeftButtonUp({
        param($sender,$eventArgs)
        if ($state.Dragging) {
            $state.Dragging = $false
            if ($trigger.IsMouseCaptured) { $trigger.ReleaseMouseCapture() }
            $eventArgs.Handled = $true
        }
    }.GetNewClosure())

    $Target.Add_SizeChanged({
        if ($script:WnstApplyingResponsiveSize -or $state.Dragging) { return }
        $height = [double]$state.Target.ActualHeight
        if ($height -lt $state.MinHeight) { return }
        if ((Get-WnstResizeMode) -eq 'Maximized') { $state.MaximizedHeight = $height }
        else { $state.WindowedHeight = $height }
    }.GetNewClosure())
}

function Update-WnstResponsiveSurfaceHeights {
    $mode = Get-WnstResizeMode
    foreach ($state in @($script:WnstResizableSurfaces.Values)) {
        $height = if ($mode -eq 'Maximized') { [double]$state.MaximizedHeight } else { [double]$state.WindowedHeight }
        Set-WnstSurfaceHeight -State $state -Height $height
    }
}

# Tableaux principaux
Register-WnstResizableSurface -Key 'AppxTable' -Target ($window.FindName('AppxTablePanel')) -WindowedHeight 360 -MaximizedHeight 500 -MinHeight 220
Register-WnstResizableSurface -Key 'ConnectionsTable' -Target $ConnectionsGrid -WindowedHeight 235 -MaximizedHeight 360 -MinHeight 150
Register-WnstResizableSurface -Key 'OpenPortsTable' -Target $OpenPortsGrid -WindowedHeight 190 -MaximizedHeight 320 -MinHeight 140
Register-WnstResizableSurface -Key 'FirewallPendingTable' -Target $FirewallPendingGrid -WindowedHeight 104 -MaximizedHeight 160 -MinHeight 90

$window.Add_SourceInitialized({
    try { Initialize-WnstMonitorWorkAreaHook }
    catch { }
})

$window.Add_StateChanged({
    try {
        $window.Dispatcher.BeginInvoke(
            [Action]{ Update-WnstResponsiveSurfaceHeights },
            [Windows.Threading.DispatcherPriority]::Loaded
        ) | Out-Null
    }
    catch {}
})

$window.Add_SizeChanged({
    try {
        $window.Dispatcher.BeginInvoke(
            [Action]{ Update-WnstResponsiveSurfaceHeights },
            [Windows.Threading.DispatcherPriority]::Background
        ) | Out-Null
    }
    catch {}
})

$window.Add_Loaded({
    try {
        # SourceInitialized peut déjà avoir eu lieu avant le chargement de ce fichier
        # selon le cycle de vie WPF ; ce second appel est volontairement idempotent.
        Initialize-WnstMonitorWorkAreaHook
        Update-WnstResponsiveSurfaceHeights
    }
    catch {}
})
