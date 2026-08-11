function Get-LetsLoafExternalAssetPaths {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectRoot
    )

    $resolvedProjectRoot = [IO.Path]::GetFullPath($ProjectRoot)
    $assetPaths = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

    function Add-AssetPath {
        param([string]$Path)
        if ([string]::IsNullOrWhiteSpace($Path)) {
            return
        }
        $normalized = $Path.Replace("res://", "").Replace("\", "/").TrimStart("/")
        [void]$assetPaths.Add($normalized)
    }

    $sceneMediaPattern = 'res://(?<path>[^"\r\n]+\.(?:png|jpg|jpeg|webp|ogv|mp4|mp3|wav))'
    $sceneText = (Get-ChildItem -LiteralPath (Join-Path $resolvedProjectRoot "scenes") -File -Filter "*.tscn" |
        Get-Content -Encoding UTF8) -join "`n"
    foreach ($match in [regex]::Matches($sceneText, $sceneMediaPattern)) {
        $path = $match.Groups["path"].Value
        if ($path -match '^assets/(?:backgrounds|props|audio)/') {
            Add-AssetPath $path
        }
    }

    $scriptMediaPattern = '(?:preload|load)\("res://(?<path>[^"\r\n]+\.(?:png|jpg|jpeg|webp|ogv|mp4|mp3|wav))"\)'
    $scriptText = (Get-ChildItem -LiteralPath (Join-Path $resolvedProjectRoot "scripts") -File -Filter "*.gd" |
        Get-Content -Encoding UTF8) -join "`n"
    foreach ($match in [regex]::Matches($scriptText, $scriptMediaPattern)) {
        $path = $match.Groups["path"].Value
        if ($path -match '^assets/(?:backgrounds|props|audio)/') {
            Add-AssetPath $path
        }
    }

    function Visit-JsonNode {
        param([object]$Node)
        if ($null -eq $Node -or $Node -is [string]) {
            return
        }
        if ($Node -is [System.Collections.IEnumerable] -and $Node -isnot [pscustomobject]) {
            foreach ($item in $Node) {
                Visit-JsonNode $item
            }
            return
        }
        foreach ($property in $Node.PSObject.Properties) {
            if ($property.Name -eq "path" -and $property.Value -is [string]) {
                $candidate = $property.Value.Replace("res://", "").Replace("\", "/")
                if ($candidate -match '^xsxb_frame_tuner/' -and
                    $candidate -match '\.(?:png|jpg|jpeg|webp|ogv|mp4|mp3|wav)$') {
                    Add-AssetPath $candidate
                }
            }
            else {
                Visit-JsonNode $property.Value
            }
        }
    }

    $runtimeDataRoot = Join-Path $resolvedProjectRoot "xsxb_frame_tuner\data\projects\Watercolor_Desk_Companion"
    foreach ($fileName in @(
        "animation_manifest.json",
        "frame_audio_bindings.json",
        "frame_image_attachments.json",
        "attack_trails.json"
    )) {
        $jsonPath = Join-Path $runtimeDataRoot $fileName
        $json = Get-Content -LiteralPath $jsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
        Visit-JsonNode $json
    }

    return @($assetPaths | Sort-Object)
}
