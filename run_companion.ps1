[CmdletBinding()]
param(
    [string]$GodotExe = "",
    [switch]$CheckExternalAssetsOnly
)

$ErrorActionPreference = "Stop"

$projectDirectory = $PSScriptRoot
$audioDirectory = Join-Path $projectDirectory "xsxb_frame_tuner\audio"
$externalAssetsManifestPath = Join-Path $projectDirectory "data\external_assets.json"

function Resolve-GodotExecutable {
    param([string]$ConfiguredPath)

    if (-not [string]::IsNullOrWhiteSpace($ConfiguredPath)) {
        if (Test-Path -LiteralPath $ConfiguredPath -PathType Leaf) {
            return [IO.Path]::GetFullPath($ConfiguredPath)
        }
        throw "Godot executable was not found at '$ConfiguredPath'."
    }

    foreach ($commandName in @("godot", "godot4")) {
        $command = Get-Command $commandName -CommandType Application -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($null -ne $command -and (Test-Path -LiteralPath $command.Source -PathType Leaf)) {
            return $command.Source
        }
    }

    $localGodot = Get-ChildItem -LiteralPath $projectDirectory -File -Filter "Godot_v4*_win64.exe" -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notlike "*_console.exe" } |
        Sort-Object Name -Descending |
        Select-Object -First 1
    if ($null -ne $localGodot) {
        return $localGodot.FullName
    }

    $developmentFallback = "E:\jiuming-huanchao\Godot_v4.7-stable_win64\Godot_v4.7-stable_win64.exe"
    if (Test-Path -LiteralPath $developmentFallback -PathType Leaf) {
        return $developmentFallback
    }

    return ""
}

function Get-MissingExternalAssets {
    if (-not (Test-Path -LiteralPath $externalAssetsManifestPath -PathType Leaf)) {
        return @("data/external_assets.json")
    }

    $manifest = Get-Content -LiteralPath $externalAssetsManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    return @(
        $manifest.required_files |
            Where-Object {
                -not (Test-Path -LiteralPath (Join-Path $projectDirectory $_) -PathType Leaf)
            }
    )
}

$missingExternalAssets = @(Get-MissingExternalAssets)
if ($CheckExternalAssetsOnly) {
    if ($missingExternalAssets.Count -eq 0) {
        Write-Output "External assets OK."
        exit 0
    }

    Write-Output ("External assets missing: {0}" -f $missingExternalAssets.Count)
    $missingExternalAssets | ForEach-Object { Write-Output $_ }
    exit 2
}

if ($missingExternalAssets.Count -gt 0) {
    $manifest = Get-Content -LiteralPath $externalAssetsManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $googleDrive = $manifest.download_mirrors | Where-Object { $_.name -eq "Google Drive" } | Select-Object -First 1
    $baidu = $manifest.download_mirrors | Where-Object { $_.name -eq "百度网盘" } | Select-Object -First 1
    $message = @"
游戏缺少美术与音频素材（检测到 $($missingExternalAssets.Count) 个关键文件缺失）。

请下载 $($manifest.archive_name)，然后直接解压到：
$projectDirectory

解压后，该目录下应直接包含 assets 和 xsxb_frame_tuner 文件夹。

选择“是”：打开 Google Drive
选择“否”：打开百度网盘（提取码：$($baidu.access_code)）
选择“取消”：暂不下载
"@

    Add-Type -AssemblyName System.Windows.Forms
    $choice = [System.Windows.Forms.MessageBox]::Show(
        $message,
        "一起磨洋工 - 需要素材包",
        [System.Windows.Forms.MessageBoxButtons]::YesNoCancel,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    )
    if ($choice -eq [System.Windows.Forms.DialogResult]::Yes) {
        Start-Process $googleDrive.url
    }
    elseif ($choice -eq [System.Windows.Forms.DialogResult]::No) {
        Start-Process $baidu.url
    }
    exit 2
}

$godotExe = Resolve-GodotExecutable -ConfiguredPath $GodotExe
if ([string]::IsNullOrWhiteSpace($godotExe)) {
    throw "Godot 4.7 was not found. Put the Windows Godot executable in the project root, add it to PATH, or run .\run_companion.ps1 -GodotExe 'C:\path\to\Godot.exe'."
}

# This desktop companion is keyboard/mouse-only. Disable every SDL controller
# backend before Godot initializes SDL so controllers cannot send input or
# receive rumble/LED feedback from this process.
$env:SDL_JOYSTICK_HIDAPI = "0"
$env:SDL_JOYSTICK_RAWINPUT = "0"
$env:SDL_JOYSTICK_DIRECTINPUT = "0"
$env:SDL_JOYSTICK_WGI = "0"
$env:SDL_JOYSTICK_GAMEINPUT = "0"
$env:SDL_XINPUT_ENABLED = "0"

$existingGame = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
    Where-Object {
        $_.Name -match '^Godot.*\.exe$' -and
        $_.CommandLine -like "*--path $projectDirectory*" -and
        $_.CommandLine -notlike "*--headless*" -and
        $_.CommandLine -notlike "*--qa-*"
    } |
    Select-Object -First 1
if ($null -ne $existingGame) {
    Write-Output "Watercolor Desk Companion is already running (PID $($existingGame.ProcessId))."
    exit 0
}

function Get-PendingAudioImports {
    if (-not (Test-Path -LiteralPath $audioDirectory -PathType Container)) {
        return @()
    }

    return @(
        Get-ChildItem -LiteralPath $audioDirectory -Recurse -File |
            Where-Object {
                $_.Extension -in @(".mp3", ".ogg", ".wav") -and (
                    -not (Test-Path -LiteralPath ($_.FullName + ".import") -PathType Leaf) -or
                    (Get-Item -LiteralPath ($_.FullName + ".import")).LastWriteTimeUtc -lt $_.LastWriteTimeUtc
                )
            }
    )
}

$pendingAudioImports = @(Get-PendingAudioImports)
if ($pendingAudioImports.Count -gt 0) {
    $importProcess = Start-Process -FilePath $godotExe `
        -ArgumentList @("--headless", "--import", "--path", $projectDirectory) `
        -WindowStyle Hidden `
        -Wait `
        -PassThru

    if ($importProcess.ExitCode -ne 0) {
        throw "Godot audio import failed with exit code $($importProcess.ExitCode)."
    }

    $pendingAudioImports = @(Get-PendingAudioImports)
    $missingAudioImports = @(
        $pendingAudioImports |
            Where-Object { -not (Test-Path -LiteralPath ($_.FullName + ".import") -PathType Leaf) }
    )
    if ($missingAudioImports.Count -gt 0) {
        $missingNames = $missingAudioImports.Name -join ", "
        throw "Godot did not create imports for audio files: $missingNames"
    }
}

Start-Process -FilePath $godotExe -ArgumentList @("--path", $projectDirectory)
