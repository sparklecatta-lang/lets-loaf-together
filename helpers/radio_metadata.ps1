[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Url,

    [Parameter(Mandatory = $true)]
    [string]$OutputFileBase64,

    [ValidateRange(0, 120)]
    [int]$DelaySeconds = 0
)

$ErrorActionPreference = "Stop"
$outputFile = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($OutputFileBase64))
$outputDirectory = Split-Path -Parent $outputFile
if (-not (Test-Path -LiteralPath $outputDirectory -PathType Container)) {
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
}

function Read-Exact {
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.Stream]$Stream,

        [Parameter(Mandatory = $true)]
        [byte[]]$Buffer,

        [Parameter(Mandatory = $true)]
        [int]$Count
    )

    $offset = 0
    while ($offset -lt $Count) {
        $read = $Stream.Read($Buffer, $offset, $Count - $offset)
        if ($read -le 0) {
            return $false
        }
        $offset += $read
    }
    return $true
}

function Write-Title {
    param([string]$Title)

    $temporaryFile = "$outputFile.tmp"
    [IO.File]::WriteAllText($temporaryFile, $Title, [Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporaryFile -Destination $outputFile -Force
}

$pendingTitles = [Collections.Generic.Queue[object]]::new()
$lastQueuedTitle = ""

function Publish-DueTitles {
    while ($pendingTitles.Count -gt 0 -and
        $pendingTitles.Peek().DueAt -le [DateTime]::UtcNow) {
        $entry = $pendingTitles.Dequeue()
        Write-Title -Title $entry.Title
    }
}

Add-Type -AssemblyName System.Net.Http
$handler = [System.Net.Http.HttpClientHandler]::new()
$handler.AllowAutoRedirect = $true
$client = [System.Net.Http.HttpClient]::new($handler)
$client.Timeout = [TimeSpan]::FromSeconds(30)
$request = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::Get, $Url)
$request.Headers.TryAddWithoutValidation("Icy-MetaData", "1") | Out-Null
$request.Headers.TryAddWithoutValidation("User-Agent", "WatercolorDeskCompanion/0.1") | Out-Null

try {
    $response = $client.SendAsync(
        $request,
        [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead
    ).GetAwaiter().GetResult()
    $response.EnsureSuccessStatusCode() | Out-Null

    $metaIntervalValues = $null
    if (-not $response.Headers.TryGetValues("icy-metaint", [ref]$metaIntervalValues)) {
        throw "The radio stream does not expose an icy-metaint header."
    }
    $metaInterval = [int]($metaIntervalValues | Select-Object -First 1)
    if ($metaInterval -le 0) {
        throw "The radio stream returned an invalid icy-metaint value."
    }

    $stream = $response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
    $audioBuffer = New-Object byte[] $metaInterval
    while ($true) {
        if (-not (Read-Exact -Stream $stream -Buffer $audioBuffer -Count $metaInterval)) {
            break
        }
        $metadataBlockCount = $stream.ReadByte()
        if ($metadataBlockCount -lt 0) {
            break
        }
        $metadataLength = $metadataBlockCount * 16
        if ($metadataLength -gt 0) {
            $metadataBuffer = New-Object byte[] $metadataLength
            if (-not (Read-Exact -Stream $stream -Buffer $metadataBuffer -Count $metadataLength)) {
                break
            }
            $metadata = [Text.Encoding]::UTF8.GetString($metadataBuffer).Trim([char]0)
            if ($metadata -match "StreamTitle='([^']*)';") {
                $title = $Matches[1].Trim()
                if (-not [string]::IsNullOrWhiteSpace($title) -and $title -ne $lastQueuedTitle) {
                    $pendingTitles.Enqueue([pscustomobject]@{
                        Title = $title
                        DueAt = [DateTime]::UtcNow.AddSeconds($DelaySeconds)
                    })
                    $lastQueuedTitle = $title
                }
            }
        }
        Publish-DueTitles
    }
} finally {
    if ($null -ne $stream) {
        $stream.Dispose()
    }
    if ($null -ne $response) {
        $response.Dispose()
    }
    $request.Dispose()
    $client.Dispose()
    $handler.Dispose()
}
