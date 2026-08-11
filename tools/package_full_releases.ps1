[CmdletBinding()]
param(
    [string]$OutputDirectory = "",
    [string]$GodotConsoleExe = "E:\jiuming-huanchao\Godot_v4.7-stable_win64\Godot_v4.7-stable_win64_console.exe",
    [string]$WindowsFfplayExe = "I:\FF\bin\ffplay.exe",
    [string]$FfmpegLicensePath = "I:\FF\ffmpeg-master-latest-win64-gpl\LICENSE.txt",
    [switch]$WindowsOnly,
    [switch]$Force
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName Microsoft.VisualBasic
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$windowsIconEmbedder = Join-Path $projectRoot "tools\embed_windows_icon.py"
$windowsIcon = Join-Path $projectRoot "assets\branding\cat_food_mascot\app_icon.ico"
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path (Split-Path $projectRoot -Parent) "watercolor-desk-companion-deliverables"
}
$outputRoot = [IO.Path]::GetFullPath($OutputDirectory)
$windowsArchive = Join-Path $outputRoot "LetsLoafTogether-Windows.zip"
$macosArchive = Join-Path $outputRoot "LetsLoafTogether-macOS.zip"
$requestedArchives = @($windowsArchive)
if (-not $WindowsOnly) {
    $requestedArchives += $macosArchive
}

foreach ($requiredFile in @($GodotConsoleExe, $WindowsFfplayExe, $FfmpegLicensePath, $windowsIconEmbedder, $windowsIcon)) {
    if (-not (Test-Path -LiteralPath $requiredFile -PathType Leaf)) {
        throw "Required packaging file is missing: $requiredFile"
    }
}
foreach ($target in $requestedArchives) {
    if ((Test-Path -LiteralPath $target -PathType Leaf) -and -not $Force) {
        throw "Release archive already exists: $target. Use -Force to replace it."
    }
}

$tempBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$stagingRoot = Join-Path $tempBase ("lets-loaf-full-release-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $stagingRoot | Out-Null

function Invoke-GodotExport {
    param(
        [string]$Preset,
        [string]$Target
    )
    & $GodotConsoleExe --headless --editor --path $projectRoot --export-release $Preset $Target
    if ($LASTEXITCODE -ne 0) {
        throw "Godot export failed for '$Preset' with exit code $LASTEXITCODE."
    }
    if (-not (Test-Path -LiteralPath $Target -PathType Leaf)) {
        throw "Godot did not create the expected export: $Target"
    }
}

function Add-ZipFileEntry {
    param(
        [IO.Compression.ZipArchive]$Archive,
        [string]$EntryName,
        [string]$SourcePath,
        [int]$ExternalAttributes = 0
    )
    $existing = $Archive.GetEntry($EntryName)
    if ($null -ne $existing) {
        $existing.Delete()
    }
    $entry = $Archive.CreateEntry($EntryName, [IO.Compression.CompressionLevel]::Optimal)
    if ($ExternalAttributes -ne 0) {
        $entry.ExternalAttributes = $ExternalAttributes
    }
    $source = [IO.File]::OpenRead($SourcePath)
    $target = $entry.Open()
    try {
        $source.CopyTo($target)
    }
    finally {
        $target.Dispose()
        $source.Dispose()
    }
}

function Add-ZipTextEntry {
    param(
        [IO.Compression.ZipArchive]$Archive,
        [string]$EntryName,
        [string]$Text
    )
    $existing = $Archive.GetEntry($EntryName)
    if ($null -ne $existing) {
        $existing.Delete()
    }
    $entry = $Archive.CreateEntry($EntryName, [IO.Compression.CompressionLevel]::Optimal)
    $writer = [IO.StreamWriter]::new($entry.Open(), [Text.UTF8Encoding]::new($false))
    try {
        $writer.Write($Text)
    }
    finally {
        $writer.Dispose()
    }
}

function Get-FfplayEntry {
    param([IO.Compression.ZipArchive]$Archive)
    $entry = $Archive.Entries | Where-Object { $_.Name -eq "ffplay" } | Select-Object -First 1
    if ($null -eq $entry) {
        throw "Downloaded macOS FFplay archive does not contain ffplay."
    }
    return $entry
}

$thirdPartyNotice = @"
Let's Loaf Together - Third-party notices

Godot Engine
License: MIT
Source and license: https://github.com/godotengine/godot

FFplay / FFmpeg
FFplay is distributed as a separate executable and is started as a child process for online radio playback.
License: GNU GPL version 3 or later for the distributed builds. See FFMPEG_LICENSE.txt.
FFmpeg source: https://github.com/FFmpeg/FFmpeg
Windows build source revision: https://github.com/FFmpeg/FFmpeg/commit/fc8d975b0b
Windows build provider: https://github.com/BtbN/FFmpeg-Builds
macOS 9.0 build provider: https://ffmpeg.martin-riedl.de/
macOS release source: https://github.com/FFmpeg/FFmpeg/tree/n9.0
"@

try {
    New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null
    $windowsRoot = Join-Path $stagingRoot "windows"
    New-Item -ItemType Directory -Path $windowsRoot | Out-Null
    $windowsExe = Join-Path $windowsRoot "LetsLoafTogether.exe"
    Invoke-GodotExport -Preset "Windows Portable" -Target $windowsExe
    $iconEmbeddedExe = Join-Path $stagingRoot "LetsLoafTogether-icon.exe"
    & python $windowsIconEmbedder --input-exe $windowsExe --icon $windowsIcon --output-exe $iconEmbeddedExe
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $iconEmbeddedExe -PathType Leaf)) {
        throw "Failed to embed the Windows application icon."
    }
    Copy-Item -LiteralPath $iconEmbeddedExe -Destination $windowsExe -Force
    $windowsPck = [IO.Path]::ChangeExtension($windowsExe, ".pck")
    if (-not (Test-Path -LiteralPath $windowsPck -PathType Leaf)) {
        throw "Windows export is missing its PCK: $windowsPck"
    }
    Copy-Item -LiteralPath $WindowsFfplayExe -Destination (Join-Path $windowsRoot "ffplay.exe")
    Copy-Item -LiteralPath $FfmpegLicensePath -Destination (Join-Path $windowsRoot "FFMPEG_LICENSE.txt")
    $thirdPartyNotice | Set-Content -LiteralPath (Join-Path $windowsRoot "THIRD_PARTY_NOTICES.txt") -Encoding UTF8
    @(
        "Let's Loaf Together",
        "",
        "Double-click LetsLoafTogether.exe to run.",
        "Keep the EXE, PCK, ffplay.exe, and license files in the same directory.",
        "Artwork, animation, and local audio are already included in the PCK."
    ) | Set-Content -LiteralPath (Join-Path $windowsRoot "README.txt") -Encoding UTF8

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    if (Test-Path -LiteralPath $windowsArchive) {
        [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile(
            $windowsArchive,
            [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
            [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin
        )
    }
    [IO.Compression.ZipFile]::CreateFromDirectory(
        $windowsRoot,
        $windowsArchive,
        [IO.Compression.CompressionLevel]::Optimal,
        $false
    )

    if (-not $WindowsOnly) {
    $macosBase = Join-Path $stagingRoot "macos-base.zip"
    Invoke-GodotExport -Preset "macOS Portable" -Target $macosBase
    $armArchivePath = Join-Path $stagingRoot "ffplay-macos-arm64.zip"
    $intelArchivePath = Join-Path $stagingRoot "ffplay-macos-x86_64.zip"
    & curl.exe -L --fail --retry 2 --output $armArchivePath "https://ffmpeg.martin-riedl.de/download/macos/arm64/1785863997_9.0/ffplay.zip"
    if ($LASTEXITCODE -ne 0) { throw "Failed to download macOS arm64 FFplay." }
    & curl.exe -L --fail --retry 2 --output $intelArchivePath "https://ffmpeg.martin-riedl.de/download/macos/amd64/1785871427_9.0/ffplay.zip"
    if ($LASTEXITCODE -ne 0) { throw "Failed to download macOS x86_64 FFplay." }
    $armHash = (Get-FileHash -LiteralPath $armArchivePath -Algorithm SHA256).Hash.ToLowerInvariant()
    $intelHash = (Get-FileHash -LiteralPath $intelArchivePath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($armHash -ne "ce68639aaf32d7b20963d43613bb3651484071048abc9a18c05ab6fe6ca7f180") {
        throw "macOS arm64 FFplay checksum mismatch: $armHash"
    }
    if ($intelHash -ne "bb6248c3919744c4b809a6defa306e2a00e235a076fe12805ae2cc5bf04abfa9") {
        throw "macOS x86_64 FFplay checksum mismatch: $intelHash"
    }

    if (Test-Path -LiteralPath $macosArchive) {
        [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile(
            $macosArchive,
            [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
            [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin
        )
    }
    Copy-Item -LiteralPath $macosBase -Destination $macosArchive
    $armZip = [IO.Compression.ZipFile]::OpenRead($armArchivePath)
    $intelZip = [IO.Compression.ZipFile]::OpenRead($intelArchivePath)
    $macZip = [IO.Compression.ZipFile]::Open($macosArchive, [IO.Compression.ZipArchiveMode]::Update)
    try {
        $appExecutable = $macZip.Entries | Where-Object { $_.FullName -like "*.app/Contents/MacOS/*" } | Select-Object -First 1
        if ($null -eq $appExecutable) {
            throw "macOS export does not contain an app executable."
        }
        $macosDirectory = ($appExecutable.FullName -split "/Contents/MacOS/")[0] + "/Contents/MacOS"
        $armEntry = Get-FfplayEntry -Archive $armZip
        $intelEntry = Get-FfplayEntry -Archive $intelZip
        $armExtracted = Join-Path $stagingRoot "ffplay-arm64"
        $intelExtracted = Join-Path $stagingRoot "ffplay-x86_64"
        [IO.Compression.ZipFileExtensions]::ExtractToFile($armEntry, $armExtracted, $true)
        [IO.Compression.ZipFileExtensions]::ExtractToFile($intelEntry, $intelExtracted, $true)
        Add-ZipFileEntry -Archive $macZip -EntryName "$macosDirectory/ffplay-arm64" -SourcePath $armExtracted -ExternalAttributes $armEntry.ExternalAttributes
        Add-ZipFileEntry -Archive $macZip -EntryName "$macosDirectory/ffplay-x86_64" -SourcePath $intelExtracted -ExternalAttributes $intelEntry.ExternalAttributes
        Add-ZipFileEntry -Archive $macZip -EntryName "FFMPEG_LICENSE.txt" -SourcePath $FfmpegLicensePath
        Add-ZipTextEntry -Archive $macZip -EntryName "THIRD_PARTY_NOTICES.txt" -Text $thirdPartyNotice
        Add-ZipTextEntry -Archive $macZip -EntryName "README.txt" -Text @"
Let's Loaf Together

Open the app bundle to run. Artwork, animation, and local audio are included.
The app is not signed or notarized with an Apple Developer certificate, so macOS may show a security warning on first launch.
Online music uses the bundled FFplay child process. Pausing or changing volume reconnects the live stream on macOS.
"@
    }
    finally {
        $macZip.Dispose()
        $intelZip.Dispose()
        $armZip.Dispose()
    }
    }

    $results = foreach ($archive in $requestedArchives) {
        $hash = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
        "$hash  $([IO.Path]::GetFileName($archive))" |
            Set-Content -LiteralPath ($archive + ".sha256") -Encoding ASCII
        [pscustomobject]@{
            Package = $archive
            Bytes = (Get-Item -LiteralPath $archive).Length
            Sha256 = $hash
        }
    }
    $results
}
finally {
    $resolvedStaging = [IO.Path]::GetFullPath($stagingRoot)
    if ($resolvedStaging.StartsWith($tempBase, [StringComparison]::OrdinalIgnoreCase) -and
        (Split-Path $resolvedStaging -Parent) -eq $tempBase -and
        (Split-Path $resolvedStaging -Leaf).StartsWith("lets-loaf-full-release-")) {
        Remove-Item -LiteralPath $resolvedStaging -Recurse -Force -ErrorAction SilentlyContinue
    }
}
