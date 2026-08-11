[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$PackagePath
)

$ErrorActionPreference = "Stop"
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$zipPath = [IO.Path]::GetFullPath($PackagePath)
$sidecarPath = $zipPath + ".sha256"
if (-not (Test-Path -LiteralPath $zipPath -PathType Leaf)) {
    throw "Package is missing: $zipPath"
}
if (-not (Test-Path -LiteralPath $sidecarPath -PathType Leaf)) {
    throw "Checksum sidecar is missing: $sidecarPath"
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
. (Join-Path $PSScriptRoot "external_asset_dependencies.ps1")
$expectedAssets = @(Get-LetsLoafExternalAssetPaths -ProjectRoot $projectRoot)
$archive = [IO.Compression.ZipFile]::OpenRead($zipPath)
try {
    $entryNames = @($archive.Entries | ForEach-Object { $_.FullName.Replace("\", "/") })
    $required = (Get-Content -LiteralPath (Join-Path $projectRoot "data\external_assets.json") -Raw -Encoding UTF8 | ConvertFrom-Json).required_files
    $missing = @($required | Where-Object { $_ -notin $entryNames })
    $expectedMissing = @($expectedAssets | Where-Object { $_ -notin $entryNames })
    $assetEntries = @($entryNames | Where-Object {
        $_ -notin @("external_assets_manifest.json", "ASSET_PACK_README.txt")
    })
    $unexpectedAssets = @($assetEntries | Where-Object { $_ -notin $expectedAssets })
    $archiveSummary = [ordered]@{
        entries = $archive.Entries.Count
        has_manifest = $null -ne $archive.GetEntry("external_assets_manifest.json")
        has_readme = $null -ne $archive.GetEntry("ASSET_PACK_README.txt")
        required_missing = $missing.Count
        expected_missing = $expectedMissing.Count
        unexpected_assets = $unexpectedAssets.Count
    }
}
finally {
    $archive.Dispose()
}

$actualHash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
$recordedHash = ((Get-Content -LiteralPath $sidecarPath -Raw).Split(" ")[0]).Trim().ToLowerInvariant()
$tempBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$extractRoot = Join-Path $tempBase ("lets-loaf-verify-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $extractRoot | Out-Null

try {
    [IO.Compression.ZipFile]::ExtractToDirectory($zipPath, $extractRoot)
    $requiredAfterExtract = @($required | Where-Object {
        -not (Test-Path -LiteralPath (Join-Path $extractRoot $_) -PathType Leaf)
    })
    $manifest = Get-Content -LiteralPath (Join-Path $extractRoot "external_assets_manifest.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    $actualAssetFiles = @(Get-ChildItem -LiteralPath $extractRoot -File -Recurse | Where-Object {
        $_.Name -notin @("external_assets_manifest.json", "ASSET_PACK_README.txt")
    }).Count
    [pscustomobject]@{
        Package = $zipPath
        Sha256 = $actualHash
        HashMatchesSidecar = $actualHash -eq $recordedHash
        ZipEntries = $archiveSummary.entries
        ManifestPresent = $archiveSummary.has_manifest
        ReadmePresent = $archiveSummary.has_readme
        RequiredMissingInZip = $archiveSummary.required_missing
        ExpectedDependenciesMissing = $archiveSummary.expected_missing
        UnexpectedAssets = $archiveSummary.unexpected_assets
        RequiredMissingAfterExtract = $requiredAfterExtract.Count
        ManifestAssetFiles = $manifest.file_count
        ExtractedAssetFiles = $actualAssetFiles
        Valid = ($actualHash -eq $recordedHash) -and
            $archiveSummary.has_manifest -and
            $archiveSummary.has_readme -and
            $archiveSummary.required_missing -eq 0 -and
            $archiveSummary.expected_missing -eq 0 -and
            $archiveSummary.unexpected_assets -eq 0 -and
            $requiredAfterExtract.Count -eq 0 -and
            $manifest.file_count -eq $expectedAssets.Count -and
            $manifest.file_count -eq $actualAssetFiles
    }
}
finally {
    $resolvedExtractRoot = [IO.Path]::GetFullPath($extractRoot)
    $isDirectTempChild = (Split-Path $resolvedExtractRoot -Parent) -eq $tempBase
    $hasExpectedName = (Split-Path $resolvedExtractRoot -Leaf).StartsWith("lets-loaf-verify-")
    if ($resolvedExtractRoot.StartsWith($tempBase, [StringComparison]::OrdinalIgnoreCase) -and
        $isDirectTempChild -and $hasExpectedName) {
        Remove-Item -LiteralPath $resolvedExtractRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
