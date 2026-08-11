using System;
using System.Globalization;
using System.Runtime.InteropServices;

internal static class WindowBorderHelper
{
    private const int GwlStyle = -16;
    private const long WsBorder = 0x00800000L;
    private const long WsSysMenu = 0x00080000L;
    private const long WsMinimizeBox = 0x00020000L;
    private const long WsMaximizeBox = 0x00010000L;
    private const uint SwpNoSize = 0x0001;
    private const uint SwpNoMove = 0x0002;
    private const uint SwpNoZOrder = 0x0004;
    private const uint SwpNoActivate = 0x0010;
    private const uint SwpFrameChanged = 0x0020;

    private const int DwmwaNcRenderingPolicy = 2;
    private const uint DwmncrpDisabled = 1;
    private const int DwmwaWindowCornerPreference = 33;
    private const uint DwmwcpDoNotRound = 1;
    private const int DwmwaBorderColor = 34;
    private const uint DwmwaColorNone = 0xFFFFFFFE;
    private const int DwmwaSystemBackdropType = 38;
    private const uint DwmsbtNone = 1;

    [DllImport("user32.dll")]
    private static extern IntPtr SetThreadDpiAwarenessContext(IntPtr dpiContext);

    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW", SetLastError = true)]
    private static extern IntPtr GetWindowLongPtr64(IntPtr windowHandle, int index);

    [DllImport("user32.dll", EntryPoint = "GetWindowLongW", SetLastError = true)]
    private static extern IntPtr GetWindowLongPtr32(IntPtr windowHandle, int index);

    [DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW", SetLastError = true)]
    private static extern IntPtr SetWindowLongPtr64(IntPtr windowHandle, int index, IntPtr value);

    [DllImport("user32.dll", EntryPoint = "SetWindowLongW", SetLastError = true)]
    private static extern IntPtr SetWindowLongPtr32(IntPtr windowHandle, int index, IntPtr value);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool SetWindowPos(
        IntPtr windowHandle,
        IntPtr insertAfter,
        int x,
        int y,
        int width,
        int height,
        uint flags
    );

    [DllImport("dwmapi.dll", PreserveSig = true)]
    private static extern int DwmSetWindowAttribute(
        IntPtr windowHandle,
        int attribute,
        ref uint attributeValue,
        int attributeSize
    );

    private static IntPtr GetWindowStyle(IntPtr windowHandle)
    {
        return IntPtr.Size == 8
            ? GetWindowLongPtr64(windowHandle, GwlStyle)
            : GetWindowLongPtr32(windowHandle, GwlStyle);
    }

    private static void SetWindowStyle(IntPtr windowHandle, IntPtr style)
    {
        if (IntPtr.Size == 8)
        {
            SetWindowLongPtr64(windowHandle, GwlStyle, style);
        }
        else
        {
            SetWindowLongPtr32(windowHandle, GwlStyle, style);
        }
    }

    private static void SetDwmUInt(IntPtr windowHandle, int attribute, uint value)
    {
        DwmSetWindowAttribute(
            windowHandle,
            attribute,
            ref value,
            Marshal.SizeOf(typeof(uint))
        );
    }

    private static int Main(string[] args)
    {
        if (args.Length != 1)
        {
            return 2;
        }

        long rawHandle;
        if (!long.TryParse(args[0], NumberStyles.Integer, CultureInfo.InvariantCulture, out rawHandle) || rawHandle == 0)
        {
            return 3;
        }

        IntPtr windowHandle = new IntPtr(rawHandle);
        // PER_MONITOR_AWARE_V2 ensures the region uses the actual pixel size on
        // the user's secondary high-DPI display instead of a virtualized size.
        SetThreadDpiAwarenessContext(new IntPtr(-4));

        // A Godot borderless window can retain non-client menu/min/max styles.
        // Windows then reports a one-pixel visible frame and composites it as a
        // solid black column on a transparent surface. This app uses custom UI,
        // so those native chrome styles are unnecessary.
        long style = GetWindowStyle(windowHandle).ToInt64();
        long nativeChromeStyles = WsBorder | WsSysMenu | WsMinimizeBox | WsMaximizeBox;
        SetWindowStyle(windowHandle, new IntPtr(style & ~nativeChromeStyles));
        SetWindowPos(
            windowHandle,
            IntPtr.Zero,
            0,
            0,
            0,
            0,
            SwpNoSize | SwpNoMove | SwpNoZOrder | SwpNoActivate | SwpFrameChanged
        );

        // Disable the remaining DWM non-client line, shadow, rounded-corner and
        // backdrop treatments. Unsupported attributes are intentionally ignored.
        SetDwmUInt(windowHandle, DwmwaNcRenderingPolicy, DwmncrpDisabled);
        SetDwmUInt(windowHandle, DwmwaWindowCornerPreference, DwmwcpDoNotRound);
        SetDwmUInt(windowHandle, DwmwaBorderColor, DwmwaColorNone);
        SetDwmUInt(windowHandle, DwmwaSystemBackdropType, DwmsbtNone);

        return 0;
    }
}
