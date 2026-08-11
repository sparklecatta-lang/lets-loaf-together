[CmdletBinding()]
param(
    [string]$OutputDirectory = "",
    [string]$PackageName = "LetsLoafTogether-ArtAudio.zip",
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path (Split-Path $projectRoot -Parent) "watercolor-desk-companion-deliverables"
}
$outputRoot = [System.IO.Path]::GetFullPath($OutputDirectory)
$packagePath = Join-Path $outputRoot $PackageName

. (Join-Path $PSScriptRoot "external_asset_dependencies.ps1")
$assetFiles = @(Get-LetsLoafExternalAssetPaths -ProjectRoot $projectRoot)
if ($assetFiles.Count -eq 0) {
    throw "No runtime asset dependencies were discovered."
}
foreach ($relativePath in $assetFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $projectRoot $relativePath) -PathType Leaf)) {
        throw "Required runtime asset is missing: $relativePath"
    }
}

New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null
if (Test-Path -LiteralPath $packagePath) {
    if (-not $Force) {
        throw "Package already exists: $packagePath. Use -Force to replace it."
    }
    Remove-Item -LiteralPath $packagePath -Force
}

$tempBase = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
$stagingRoot = Join-Path $tempBase ("lets-loaf-assets-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $stagingRoot | Out-Null

try {
    $manifestFiles = [System.Collections.Generic.List[object]]::new()
    [long]$totalUncompressedBytes = 0
    foreach ($relativePath in $assetFiles) {
        $sourceFile = Get-Item -LiteralPath (Join-Path $projectRoot $relativePath)
        $targetPath = Join-Path $stagingRoot $relativePath
        $targetDirectory = Split-Path $targetPath -Parent
        New-Item -ItemType Directory -Path $targetDirectory -Force | Out-Null
        Copy-Item -LiteralPath $sourceFile.FullName -Destination $targetPath
        $manifestFiles.Add([ordered]@{
            path = $relativePath.Replace("\", "/")
            size = $sourceFile.Length
            sha256 = (Get-FileHash -LiteralPath $sourceFile.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        })
        $totalUncompressedBytes += $sourceFile.Length
    }

    $manifest = [ordered]@{
        format_version = 1
        product = "Let's Loaf Together"
        display_name = "Lets Loaf Together"
        install_root = "project root"
        includes = @("runtime artwork", "animation frames", "sound effects", "ambient audio")
        excludes = @("online radio stream", "qa output", "Godot cache", "backups", "unused candidates", "source intermediates")
        file_count = $manifestFiles.Count
        total_uncompressed_bytes = $totalUncompressedBytes
        files = $manifestFiles
    }
    $manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $stagingRoot "external_assets_manifest.json") -Encoding UTF8

    @(
        "Let's Loaf Together - Artwork and Audio Asset Pack",
        "",
        "Installation:",
        "1. Extract this archive directly into the project root.",
        "2. Merge the included assets and xsxb_frame_tuner directories with the existing directories.",
        "3. Do not add an extra wrapper directory.",
        "",
        "This pack contains runtime backgrounds, props, animation frames, frame sound effects, and ambience.",
        "Online radio remains a direct connection to the original live stream and is not included."
    ) | Set-Content -LiteralPath (Join-Path $stagingRoot "ASSET_PACK_README.txt") -Encoding UTF8

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::CreateFromDirectory(
        $stagingRoot,
        $packagePath,
        [System.IO.Compression.CompressionLevel]::Optimal,
        $false
    )

    $packageHash = (Get-FileHash -LiteralPath $packagePath -Algorithm SHA256).Hash.ToLowerInvariant()
    "$packageHash  $PackageName" | Set-Content -LiteralPath ($packagePath + ".sha256") -Encoding ASCII
    [pscustomobject]@{
        Package = $packagePath
        Sha256 = $packageHash
        ArchiveBytes = (Get-Item -LiteralPath $packagePath).Length
        UncompressedBytes = $manifest.total_uncompressed_bytes
        Files = $manifest.file_count
    }
}
finally {
    $resolvedStaging = [System.IO.Path]::GetFullPath($stagingRoot)
    if ($resolvedStaging.StartsWith($tempBase, [System.StringComparison]::OrdinalIgnoreCase) -and
        (Split-Path $resolvedStaging -Parent) -eq $tempBase -and
        (Split-Path $resolvedStaging -Leaf).StartsWith("lets-loaf-assets-")) {
        Remove-Item -LiteralPath $resolvedStaging -Recurse -Force -ErrorAction SilentlyContinue
    }
}
