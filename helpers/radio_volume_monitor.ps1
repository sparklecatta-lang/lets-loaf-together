[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [int]$ProcessId,

    [Parameter(Mandatory = $true)]
    [string]$VolumeFileBase64,

    [Parameter(Mandatory = $true)]
    [string]$PauseFileBase64
)

$ErrorActionPreference = "Stop"
$volumeFile = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($VolumeFileBase64))
$pauseFile = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($PauseFileBase64))
$ackFile = Join-Path (Split-Path -Parent $volumeFile) "watercolor_desk_radio_control_ack.txt"

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class ProcessAudioVolume
{
    enum EDataFlow { eRender, eCapture, eAll }
    enum ERole { eConsole, eMultimedia, eCommunications }
    [Flags] enum CLSCTX : uint { InprocServer = 0x1, InprocHandler = 0x2, LocalServer = 0x4, RemoteServer = 0x10, All = 0x17 }

    [ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]
    class MMDeviceEnumerator { }

    [ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMMDeviceEnumerator
    {
        int EnumAudioEndpoints(EDataFlow dataFlow, uint stateMask, out IntPtr devices);
        int GetDefaultAudioEndpoint(EDataFlow dataFlow, ERole role, out IMMDevice endpoint);
        int GetDevice([MarshalAs(UnmanagedType.LPWStr)] string id, out IMMDevice device);
        int RegisterEndpointNotificationCallback(IntPtr client);
        int UnregisterEndpointNotificationCallback(IntPtr client);
    }

    [ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMMDevice
    {
        int Activate(ref Guid iid, CLSCTX context, IntPtr activationParams, [MarshalAs(UnmanagedType.IUnknown)] out object result);
    }

    [ComImport, Guid("77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IAudioSessionManager2
    {
        int GetAudioSessionControl(ref Guid sessionGuid, uint streamFlags, out IntPtr sessionControl);
        int GetSimpleAudioVolume(ref Guid sessionGuid, uint streamFlags, out IntPtr audioVolume);
        int GetSessionEnumerator(out IAudioSessionEnumerator sessionEnumerator);
    }

    [ComImport, Guid("E2F5BB11-0570-40CA-ACDD-3AA01277DEE8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IAudioSessionEnumerator
    {
        int GetCount(out int count);
        int GetSession(int index, out IAudioSessionControl session);
    }

    [ComImport, Guid("BFB7FF88-7239-4FC9-8FA2-07C950BE9C6D"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IAudioSessionControl2
    {
        int GetState(out int state);
        int GetDisplayName([MarshalAs(UnmanagedType.LPWStr)] out string displayName);
        int SetDisplayName([MarshalAs(UnmanagedType.LPWStr)] string displayName, ref Guid eventContext);
        int GetIconPath([MarshalAs(UnmanagedType.LPWStr)] out string iconPath);
        int SetIconPath([MarshalAs(UnmanagedType.LPWStr)] string iconPath, ref Guid eventContext);
        int GetGroupingParam(out Guid groupingId);
        int SetGroupingParam(ref Guid groupingId, ref Guid eventContext);
        int RegisterAudioSessionNotification(IntPtr client);
        int UnregisterAudioSessionNotification(IntPtr client);
        int GetSessionIdentifier([MarshalAs(UnmanagedType.LPWStr)] out string sessionIdentifier);
        int GetSessionInstanceIdentifier([MarshalAs(UnmanagedType.LPWStr)] out string sessionInstanceIdentifier);
        int GetProcessId(out uint processId);
        int IsSystemSoundsSession();
        int SetDuckingPreference([MarshalAs(UnmanagedType.Bool)] bool optOut);
    }

    [ComImport, Guid("87CE5498-68D6-44E5-9215-6DA47EF883D8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface ISimpleAudioVolume
    {
        int SetMasterVolume(float level, ref Guid eventContext);
        int GetMasterVolume(out float level);
        int SetMute([MarshalAs(UnmanagedType.Bool)] bool mute, ref Guid eventContext);
        int GetMute(out bool mute);
    }

    [ComImport, Guid("F4B1A599-7266-4319-A8CA-E70ACB11E8CD"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IAudioSessionControl { }

    public static bool Set(uint targetProcessId, float level)
    {
        IMMDevice device = null;
        IAudioSessionManager2 manager = null;
        IAudioSessionEnumerator sessions = null;
        try
        {
            var enumerator = (IMMDeviceEnumerator)(new MMDeviceEnumerator());
            Marshal.ThrowExceptionForHR(enumerator.GetDefaultAudioEndpoint(EDataFlow.eRender, ERole.eMultimedia, out device));
            Guid managerId = typeof(IAudioSessionManager2).GUID;
            object activated;
            Marshal.ThrowExceptionForHR(device.Activate(ref managerId, CLSCTX.All, IntPtr.Zero, out activated));
            manager = (IAudioSessionManager2)activated;
            Marshal.ThrowExceptionForHR(manager.GetSessionEnumerator(out sessions));
            int count;
            Marshal.ThrowExceptionForHR(sessions.GetCount(out count));
            for (int index = 0; index < count; index++)
            {
                IAudioSessionControl control = null;
                try
                {
                    Marshal.ThrowExceptionForHR(sessions.GetSession(index, out control));
                    var control2 = (IAudioSessionControl2)control;
                    uint processId;
                    Marshal.ThrowExceptionForHR(control2.GetProcessId(out processId));
                    if (processId != targetProcessId) continue;
                    var volume = (ISimpleAudioVolume)control;
                    Guid context = Guid.Empty;
                    Marshal.ThrowExceptionForHR(volume.SetMasterVolume(Math.Max(0.0f, Math.Min(1.0f, level)), ref context));
                    Marshal.ThrowExceptionForHR(volume.SetMute(level <= 0.0001f, ref context));
                    return true;
                }
                finally
                {
                    if (control != null) Marshal.ReleaseComObject(control);
                }
            }
            return false;
        }
        finally
        {
            if (sessions != null) Marshal.ReleaseComObject(sessions);
            if (manager != null) Marshal.ReleaseComObject(manager);
            if (device != null) Marshal.ReleaseComObject(device);
        }
    }
}

public static class NativeProcessPause
{
    [DllImport("ntdll.dll")]
    public static extern uint NtSuspendProcess(IntPtr processHandle);
    [DllImport("ntdll.dll")]
    public static extern uint NtResumeProcess(IntPtr processHandle);
}
'@

$lastVolumeText = ""
$applied = $false
$lastPaused = $false
while ($null -ne (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue)) {
    $volumeText = Get-Content -LiteralPath $volumeFile -Raw -ErrorAction SilentlyContinue
    if ($null -ne $volumeText) {
        $volumeText = $volumeText.Trim()
        [float]$volume = 0.0
        if ([float]::TryParse($volumeText, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$volume) -and
            (-not $applied -or $volumeText -ne $lastVolumeText)) {
            $applied = [ProcessAudioVolume]::Set([uint32]$ProcessId, [Math]::Max(0.0, [Math]::Min(1.0, $volume)))
            if ($applied) {
                $lastVolumeText = $volumeText
                Set-Content -LiteralPath $ackFile -Value ("{0}|{1}|{2}" -f $ProcessId, $lastVolumeText, [int]$lastPaused) -Encoding Ascii -NoNewline
            }
        }
    }
    $pauseText = Get-Content -LiteralPath $pauseFile -Raw -ErrorAction SilentlyContinue
    if ($null -ne $pauseText) {
        $paused = $pauseText.Trim() -eq "1"
        if ($paused -ne $lastPaused) {
            $ownedProcess = [Diagnostics.Process]::GetProcessById($ProcessId)
            try {
                $result = if ($paused) {
                    [NativeProcessPause]::NtSuspendProcess($ownedProcess.Handle)
                } else {
                    [NativeProcessPause]::NtResumeProcess($ownedProcess.Handle)
                }
                if ($result -eq 0) {
                    $lastPaused = $paused
                    Set-Content -LiteralPath $ackFile -Value ("{0}|{1}|{2}" -f $ProcessId, $lastVolumeText, [int]$lastPaused) -Encoding Ascii -NoNewline
                }
            } finally {
                $ownedProcess.Dispose()
            }
        }
    }
    Start-Sleep -Milliseconds 50
}
