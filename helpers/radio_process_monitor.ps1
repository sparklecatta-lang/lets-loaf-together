[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [int]$ProcessId,

    [Parameter(Mandatory = $true)]
    [string]$PidFileBase64,

    [int]$OwnerProcessId = 0,

    [Parameter(Mandatory = $true)]
    [string]$OwnerPidFileBase64,

    [Parameter(Mandatory = $true)]
    [string]$MetadataPidFileBase64
)

$ErrorActionPreference = "SilentlyContinue"
$pidFile = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($PidFileBase64))
$ownerPidFile = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($OwnerPidFileBase64))
$metadataPidFile = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($MetadataPidFileBase64))

function Read-PidValue {
    param([string]$Path)

    $pidText = Get-Content -LiteralPath $Path -Raw -ErrorAction SilentlyContinue
    [int]$parsedPid = 0
    if ($null -ne $pidText -and [int]::TryParse($pidText.Trim(), [ref]$parsedPid)) {
        return $parsedPid
    }
    return 0
}

while ($null -ne (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue)) {
    if ($OwnerProcessId -gt 0 -and
        $null -eq (Get-Process -Id $OwnerProcessId -ErrorAction SilentlyContinue)) {
        $currentPid = Read-PidValue -Path $pidFile
        $currentOwnerPid = Read-PidValue -Path $ownerPidFile
        if ($currentPid -eq $ProcessId -and $currentOwnerPid -eq $OwnerProcessId) {
            Stop-Process -Id $ProcessId -Force -ErrorAction SilentlyContinue
        }
        break
    }
    Start-Sleep -Milliseconds 250
}

if (Test-Path -LiteralPath $pidFile -PathType Leaf) {
    $currentPid = Read-PidValue -Path $pidFile
    $currentOwnerPid = Read-PidValue -Path $ownerPidFile
    if ($currentPid -eq $ProcessId -and
        ($OwnerProcessId -le 0 -or $currentOwnerPid -eq $OwnerProcessId)) {
        $metadataPid = Read-PidValue -Path $metadataPidFile
        if ($metadataPid -gt 0) {
            $metadataProcess = Get-CimInstance Win32_Process -Filter "ProcessId = $metadataPid"
            if ($null -ne $metadataProcess -and
                $metadataProcess.Name -eq "powershell.exe" -and
                $metadataProcess.CommandLine -like "*radio_metadata.ps1*") {
                Stop-Process -Id $metadataPid -Force -ErrorAction SilentlyContinue
            }
        }
        Set-Content -LiteralPath $pidFile -Value "" -Encoding Ascii -NoNewline
        Set-Content -LiteralPath $ownerPidFile -Value "" -Encoding Ascii -NoNewline
        Set-Content -LiteralPath $metadataPidFile -Value "" -Encoding Ascii -NoNewline
    }
}
