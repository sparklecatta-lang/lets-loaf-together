[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("start", "stop")]
    [string]$Action,

    [string]$Url = "",

    [ValidateRange(0, 100)]
    [int]$Volume = 72,

    [string]$FfplayPath = "I:\FF\bin\ffplay.exe",

    [string]$PidFile = "",

    [string]$VolumeFile = "",

    [string]$PauseFile = "",

    [ValidateRange(0, 120)]
    [int]$BufferDelaySeconds = 0,

    [ValidateRange(0, [int]::MaxValue)]
    [int]$OwnerProcessId = 0,

    [switch]$EnableIcyMetadata
)

$ErrorActionPreference = "Stop"
$expectedPidName = "watercolor_desk_radio.pid"
$expectedVolumeName = "watercolor_desk_radio_volume.txt"
$expectedPauseName = "watercolor_desk_radio_pause.txt"
$processMarker = "WatercolorDeskRadio"

if ([string]::IsNullOrWhiteSpace($PidFile)) {
    $stateDirectory = Join-Path ([Environment]::GetFolderPath("LocalApplicationData")) "WatercolorDeskCompanion"
    $PidFile = Join-Path $stateDirectory $expectedPidName
}

$PidFile = [System.IO.Path]::GetFullPath($PidFile)
if ([System.IO.Path]::GetFileName($PidFile) -ne $expectedPidName) {
    throw "The PID file must be named '$expectedPidName'."
}

if ([string]::IsNullOrWhiteSpace($VolumeFile)) {
    $VolumeFile = Join-Path (Split-Path -Parent $PidFile) $expectedVolumeName
}
$VolumeFile = [System.IO.Path]::GetFullPath($VolumeFile)
if ([System.IO.Path]::GetFileName($VolumeFile) -ne $expectedVolumeName) {
    throw "The volume file must be named '$expectedVolumeName'."
}
if ([string]::IsNullOrWhiteSpace($PauseFile)) {
    $PauseFile = Join-Path (Split-Path -Parent $PidFile) $expectedPauseName
}
$PauseFile = [System.IO.Path]::GetFullPath($PauseFile)
if ([System.IO.Path]::GetFileName($PauseFile) -ne $expectedPauseName) {
    throw "The pause file must be named '$expectedPauseName'."
}

$FfplayPath = [System.IO.Path]::GetFullPath($FfplayPath)
$stateDirectory = Split-Path -Parent $PidFile
$metadataFile = Join-Path $stateDirectory "watercolor_desk_radio_title.txt"
$metadataPidFile = Join-Path $stateDirectory "watercolor_desk_radio_metadata.pid"
$ownerPidFile = Join-Path $stateDirectory "watercolor_desk_radio_owner.pid"
$metadataHelper = Join-Path $PSScriptRoot "radio_metadata.ps1"
$processMonitor = Join-Path $PSScriptRoot "radio_process_monitor.ps1"
$volumeMonitor = Join-Path $PSScriptRoot "radio_volume_monitor.ps1"
$mutexSource = ("{0}|{1}" -f $PidFile, $FfplayPath).ToLowerInvariant()
$mutexBytes = [Text.Encoding]::UTF8.GetBytes($mutexSource)
$mutexHash = [Security.Cryptography.SHA256]::Create().ComputeHash($mutexBytes)
$mutexSuffix = ([BitConverter]::ToString($mutexHash)).Replace("-", "").Substring(0, 32)
$radioMutex = [Threading.Mutex]::new($false, "Local\WatercolorDeskCompanion.Radio.$mutexSuffix")
$mutexAcquired = $false

function Read-PidValue {
    param([string]$Path)

    $pidText = Get-Content -LiteralPath $Path -Raw -ErrorAction SilentlyContinue
    if ($null -eq $pidText) {
        return 0
    }
    [int]$parsedPid = 0
    if ([int]::TryParse($pidText.Trim(), [ref]$parsedPid)) {
        return $parsedPid
    }
    return 0
}

function Stop-MetadataProcess {
    if (Test-Path -LiteralPath $metadataPidFile -PathType Leaf) {
        $metadataPid = Read-PidValue -Path $metadataPidFile
        if ($metadataPid -gt 0) {
            $process = Get-CimInstance Win32_Process -Filter "ProcessId = $metadataPid" -ErrorAction SilentlyContinue
            if ($null -ne $process -and
                $process.Name -eq "powershell.exe" -and
                $process.CommandLine -like "*radio_metadata.ps1*") {
                Stop-Process -Id $metadataPid -Force
            }
        }
    }
    if (Test-Path -LiteralPath $stateDirectory -PathType Container) {
        Set-Content -LiteralPath $metadataPidFile -Value "" -Encoding Ascii -NoNewline
        Set-Content -LiteralPath $metadataFile -Value "" -Encoding UTF8 -NoNewline
    }
}

function Stop-AuxiliaryProcesses {
    $helperPaths = @($metadataHelper, $processMonitor, $volumeMonitor)
    $processes = Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" -ErrorAction SilentlyContinue
    foreach ($process in $processes) {
        if ([string]::IsNullOrWhiteSpace($process.CommandLine)) {
            continue
        }
        $isOwnedHelper = $false
        foreach ($helperPath in $helperPaths) {
            if ($process.CommandLine.IndexOf($helperPath, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
                $isOwnedHelper = $true
                break
            }
        }
        if ($isOwnedHelper) {
            Stop-Process -Id $process.ProcessId -Force -ErrorAction SilentlyContinue
        }
    }
}

function Stop-RadioProcess {
    $processes = Get-CimInstance Win32_Process -Filter "Name = 'ffplay.exe'" -ErrorAction SilentlyContinue
    foreach ($process in $processes) {
        if ([string]::Equals($process.ExecutablePath, $FfplayPath, [StringComparison]::OrdinalIgnoreCase) -and
            $process.CommandLine -like "*-window_title $processMarker*") {
            Stop-Process -Id $process.ProcessId -Force -ErrorAction SilentlyContinue
        }
    }
    Set-Content -LiteralPath $PidFile -Value "" -Encoding Ascii -NoNewline
}

try {
    try {
        $mutexAcquired = $radioMutex.WaitOne([TimeSpan]::FromSeconds(15))
    } catch [Threading.AbandonedMutexException] {
        $mutexAcquired = $true
    }
    if (-not $mutexAcquired) {
        throw "Timed out waiting for the radio lifecycle lock."
    }

    if (-not (Test-Path -LiteralPath $stateDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $stateDirectory -Force | Out-Null
    }

    if ($Action -eq "stop") {
        $recordedOwnerPid = Read-PidValue -Path $ownerPidFile
        if ($OwnerProcessId -le 0 -or $recordedOwnerPid -le 0 -or $recordedOwnerPid -eq $OwnerProcessId) {
            Stop-AuxiliaryProcesses
            Stop-RadioProcess
            Stop-MetadataProcess
            Set-Content -LiteralPath $ownerPidFile -Value "" -Encoding Ascii -NoNewline
        }
        exit 0
    }

    if (-not (Test-Path -LiteralPath $FfplayPath -PathType Leaf)) {
        throw "ffplay was not found at '$FfplayPath'."
    }

    $streamUri = $null
    if (-not [System.Uri]::TryCreate($Url, [System.UriKind]::Absolute, [ref]$streamUri) -or
        $streamUri.Scheme -notin @("http", "https") -or
        $Url -match "\s") {
        throw "Only an absolute HTTP or HTTPS stream URL without whitespace is accepted."
    }

    # Every start is serialized and removes every process carrying this app's
    # private marker. This repairs stale PID files and prevents overlapping audio.
    Stop-AuxiliaryProcesses
    Stop-RadioProcess
    Stop-MetadataProcess

    $pidDirectory = Split-Path -Parent $PidFile
    if (-not (Test-Path -LiteralPath $pidDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $pidDirectory -Force | Out-Null
    }

$ffplayArguments = @(
    "-hide_banner",
    "-loglevel", "error",
    "-nostats",
    "-nodisp",
    "-window_title", $processMarker,
    "-volume", "100",
    "-rtbufsize", "33554432",
    "-reconnect", "1",
    "-reconnect_streamed", "1",
    "-reconnect_at_eof", "1",
    "-reconnect_on_network_error", "1",
    "-reconnect_on_http_error", "4xx,5xx",
    "-reconnect_delay_max", "2"
)
if ($BufferDelaySeconds -gt 0) {
    $ffplayArguments += @(
        "-af", ("adelay={0}:all=1" -f ($BufferDelaySeconds * 1000))
    )
}
$ffplayArguments += $streamUri.AbsoluteUri

$processOptions = @{
    FilePath = $FfplayPath
    ArgumentList = $ffplayArguments
    WindowStyle = "Hidden"
    PassThru = $true
}
    $radioProcess = Start-Process @processOptions
    Set-Content -LiteralPath $PidFile -Value $radioProcess.Id -Encoding Ascii -NoNewline
    Set-Content -LiteralPath $ownerPidFile -Value $OwnerProcessId -Encoding Ascii -NoNewline
    Set-Content -LiteralPath $VolumeFile -Value ($Volume / 100.0).ToString([System.Globalization.CultureInfo]::InvariantCulture) -Encoding Ascii -NoNewline
    Set-Content -LiteralPath $PauseFile -Value "0" -Encoding Ascii -NoNewline
    $encodedPidFile = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($PidFile))
    $encodedOwnerPidFile = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($ownerPidFile))
    $encodedMetadataPidFile = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($metadataPidFile))
    $monitorArguments = @(
    "-NoLogo",
    "-NoProfile",
    "-NonInteractive",
    "-ExecutionPolicy", "Bypass",
    "-WindowStyle", "Hidden",
    "-File", $processMonitor,
    "-ProcessId", $radioProcess.Id,
        "-PidFileBase64", $encodedPidFile,
        "-OwnerProcessId", $OwnerProcessId,
        "-OwnerPidFileBase64", $encodedOwnerPidFile,
        "-MetadataPidFileBase64", $encodedMetadataPidFile
    )
    Start-Process -FilePath "powershell.exe" -ArgumentList $monitorArguments -WindowStyle Hidden | Out-Null
    $encodedVolumeFile = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($VolumeFile))
    $encodedPauseFile = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($PauseFile))
    $volumeArguments = @(
    "-NoLogo",
    "-NoProfile",
    "-NonInteractive",
    "-ExecutionPolicy", "Bypass",
    "-WindowStyle", "Hidden",
    "-File", $volumeMonitor,
    "-ProcessId", $radioProcess.Id,
    "-VolumeFileBase64", $encodedVolumeFile,
    "-PauseFileBase64", $encodedPauseFile
    )
    Start-Process -FilePath "powershell.exe" -ArgumentList $volumeArguments -WindowStyle Hidden | Out-Null
    if ($EnableIcyMetadata) {
        $encodedMetadataFile = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($metadataFile))
        $metadataArguments = @(
        "-NoLogo",
        "-NoProfile",
        "-NonInteractive",
        "-ExecutionPolicy", "Bypass",
        "-WindowStyle", "Hidden",
        "-File", $metadataHelper,
        "-Url", $streamUri.AbsoluteUri,
        "-OutputFileBase64", $encodedMetadataFile,
        "-DelaySeconds", $BufferDelaySeconds
        )
        $metadataProcess = Start-Process -FilePath "powershell.exe" -ArgumentList $metadataArguments -WindowStyle Hidden -PassThru
        Set-Content -LiteralPath $metadataPidFile -Value $metadataProcess.Id -Encoding Ascii -NoNewline
    }
    Write-Output $radioProcess.Id
} finally {
    if ($mutexAcquired) {
        $radioMutex.ReleaseMutex()
    }
    $radioMutex.Dispose()
}
