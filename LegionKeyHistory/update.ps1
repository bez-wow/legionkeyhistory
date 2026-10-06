# Legion Key History updater, run by "LKH Updater.cmd".
#   (no switch)  download the newest leaderboard file; also what the hourly task runs
#   -Addon       install the newest addon version from GitHub, then refresh the leaderboard
# A failed or incomplete download never replaces what you have. /reload in WoW to load changes.
param([switch]$Addon, [switch]$Pause)
$ErrorActionPreference = 'Stop'
$DataSource = 'https://github.com/bez-wow/lkh-data/releases/latest/download/LeaderboardData.lua'
$AddonRelease = 'https://api.github.com/repos/bez-wow/legionkeyhistory/releases/latest'
# Optional overrides for testing: source.txt (data URL) and release.txt (release API URL).
$override = Join-Path $PSScriptRoot 'source.txt'
if (Test-Path $override) { $DataSource = (Get-Content $override -TotalCount 1).Trim() }
$override = Join-Path $PSScriptRoot 'release.txt'
if (Test-Path $override) { $AddonRelease = (Get-Content $override -TotalCount 1).Trim() }

$dataFile = Join-Path $PSScriptRoot 'LeaderboardData.lua'
$log = Join-Path $PSScriptRoot 'update.log'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
function Log($message) { "$(Get-Date -Format 'yyyy-MM-dd HH:mm')  $message" | Add-Content -Path $log -Encoding UTF8; Write-Host $message }
if ((Test-Path $log) -and (Get-Item $log).Length -gt 200KB) { Remove-Item $log }
function FileHash($path) { $sha = [Security.Cryptography.SHA256]::Create(); try { [BitConverter]::ToString($sha.ComputeHash([IO.File]::ReadAllBytes($path))) } finally { $sha.Dispose() } }
# The "downloaded" time inside a leaderboard file ("2026-10-06 19:56 UTC"); sorts as text.
function DataStamp($path) { if (-not (Test-Path $path)) { return '' }; [regex]::Match([IO.File]::ReadAllText($path), '\["downloaded"\]="([^"]*)"').Groups[1].Value }

function Update-Data {
    $tmp = "$dataFile.download"
    try {
        Invoke-WebRequest -Uri $DataSource -OutFile $tmp -UseBasicParsing -TimeoutSec 120
        $text = [IO.File]::ReadAllText($tmp)
        if ($text.Length -lt 500KB -or -not $text.Contains('LegionKeyHistoryLeaderboard=')) { throw 'the download is not a complete leaderboard file' }
        if ((Test-Path $dataFile) -and (FileHash $tmp) -eq (FileHash $dataFile)) {
            Remove-Item $tmp
            Log 'Leaderboard already up to date.'
            return $true
        }
        Move-Item $tmp $dataFile -Force
        Log "Leaderboard updated: data from $(DataStamp $dataFile). /reload in WoW to load it."
        return $true
    } catch {
        if (Test-Path $tmp) { Remove-Item $tmp }
        Log "Leaderboard update failed, keeping the current file: $($_.Exception.Message)"
        return $false
    }
}

function Update-Addon {
    $work = Join-Path ([IO.Path]::GetTempPath()) ("lkh-update-" + [guid]::NewGuid())
    try {
        $toc = Get-Content (Join-Path $PSScriptRoot 'LegionKeyHistory.toc') | Where-Object { $_ -match '^## Version:' } | Select-Object -First 1
        $current = ($toc -replace '^## Version:\s*', '').Trim()
        $release = Invoke-RestMethod -Uri $AddonRelease -Headers @{ 'User-Agent' = 'LKH-Updater' } -TimeoutSec 60
        $latest = $release.tag_name.TrimStart('v')
        if ([version]$latest -le [version]$current) { Log "You already have the newest addon version ($current)."; return $true }
        $asset = $release.assets | Where-Object { $_.name -like '*.zip' } | Select-Object -First 1
        if (-not $asset) { throw "release $latest has no zip" }
        Write-Host "Downloading Legion Key History $latest (you have $current)..."
        New-Item -ItemType Directory -Path $work | Out-Null
        $zip = Join-Path $work 'addon.zip'
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zip -UseBasicParsing -TimeoutSec 300
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [IO.Compression.ZipFile]::ExtractToDirectory($zip, (Join-Path $work 'unpacked'))
        $source = Join-Path $work 'unpacked\LegionKeyHistory'
        if (-not (Test-Path (Join-Path $source 'LegionKeyHistory.toc'))) { throw 'the download does not contain the LegionKeyHistory addon' }
        # Copy the new version over this folder. The leaderboard file is only replaced when the
        # one in the zip is newer; update.log and any other files of yours are left alone.
        foreach ($file in Get-ChildItem $source -File) {
            $target = Join-Path $PSScriptRoot $file.Name
            if ($file.Name -eq 'LeaderboardData.lua' -and (DataStamp $target) -ge (DataStamp $file.FullName)) { continue }
            Copy-Item $file.FullName $target -Force
        }
        Log "Addon updated from $current to $latest. Restart WoW (or /reload) to load it."
        return $true
    } catch {
        Log "Addon update failed: $($_.Exception.Message)"
        return $false
    } finally {
        if (Test-Path $work) { Remove-Item $work -Recurse -Force }
    }
}

if ($Addon) { $ok = Update-Addon; if ($ok) { $ok = Update-Data } } else { $ok = Update-Data }
if ($Pause) { Write-Host ''; Read-Host 'Press Enter to close' | Out-Null }
if ($ok) { exit 0 } else { exit 1 }
