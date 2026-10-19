# Legion Key History updater, run by "LKH Updater.cmd".
#   (no switch)  download the newest leaderboard file; also what the hourly task runs
#   -Addon       install the newest addon version from GitHub, then refresh the leaderboard
#   -Auto        what the hourly task runs: the leaderboard, plus the addon when you chose
#                "leaderboard and addon" (auto-addon.txt) and WoW is not running
# A failed or incomplete download never replaces what you have. /reload in WoW to load changes.
# Exit codes: 0 done (or already up to date), 1 failed, 3 this folder is not writable.
# Runs on Windows PowerShell 2 (Windows 7) and newer: no $PSScriptRoot, Invoke-WebRequest,
# ConvertFrom-Json or .NET 4.5 zip classes.
param([switch]$Addon, [switch]$Auto, [switch]$Pause)  # -Pause: kept for updaters from 1.4.1
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Definition
$DataSource = 'https://github.com/bez-wow/lkh-data/releases/latest/download/LeaderboardData.lua'
$AddonRelease = 'https://api.github.com/repos/bez-wow/legionkeyhistory/releases/latest'
# Optional overrides for testing: source.txt (data URL) and release.txt (release API URL).
$override = Join-Path $here 'source.txt'
if (Test-Path $override) { $DataSource = (Get-Content $override -TotalCount 1).Trim() }
$override = Join-Path $here 'release.txt'
if (Test-Path $override) { $AddonRelease = (Get-Content $override -TotalCount 1).Trim() }

$dataFile = Join-Path $here 'LeaderboardData.lua'
# The log lives in your own AppData, so it works even where the addon folder is protected.
$logDir = Join-Path $env:LOCALAPPDATA 'LegionKeyHistory'
$log = Join-Path $logDir 'update.log'
# GitHub only accepts TLS 1.2 (3072). Older .NET (PowerShell 2) only knows it with Windows updates
# installed; without them, downloads go through WinHTTP instead (Get-Url).
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]3072 } catch { }
function Log($message) {
    Write-Host $message
    try {
        if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }
        if ((Test-Path $log) -and (Get-Item $log).Length -gt 200KB) { Remove-Item $log }
        "$(Get-Date -Format 'yyyy-MM-dd HH:mm')  $message" | Add-Content -Path $log -Encoding UTF8
    } catch { }
}
# Anything not caught below still fails with exit 1 (PowerShell 2 would otherwise exit 0).
trap { Log "Update failed: $($_.Exception.Message)"; exit 1 }

function FileHash($path) { $sha = [Security.Cryptography.SHA256]::Create(); try { [BitConverter]::ToString($sha.ComputeHash([IO.File]::ReadAllBytes($path))) } finally { $sha.Clear() } }
# The "downloaded" time inside a leaderboard file ("2026-10-06 19:56 UTC"); sorts as text.
function DataStamp($path) { if (-not (Test-Path $path)) { return '' }; [regex]::Match([IO.File]::ReadAllText($path), '\["downloaded"\]="([^"]*)"').Groups[1].Value }
function Writable {
    $probe = Join-Path $here '.lkh-write-test'
    try { [IO.File]::WriteAllText($probe, 'ok'); Remove-Item $probe; return $true } catch { return $false }
}

# Downloads a URL as bytes: .NET first, then WinHTTP, which can have TLS 1.2 on Windows 7 where
# PowerShell 2's .NET doesn't.
function Get-Url($url, $timeoutSec) {
    try {
        $request = [Net.HttpWebRequest]::Create($url)
        $request.UserAgent = 'LKH-Updater'
        $request.Timeout = $timeoutSec * 1000
        $request.ReadWriteTimeout = $timeoutSec * 1000
        $response = $request.GetResponse()
        try {
            $stream = $response.GetResponseStream()
            $memory = New-Object IO.MemoryStream
            $buffer = New-Object byte[] 65536
            while (($read = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) { $memory.Write($buffer, 0, $read) }
            return , $memory.ToArray()
        } finally { $response.Close() }
    } catch {
        $netError = $_.Exception.Message
        try {
            # WinHTTP follows GitHub's redirect to its download server (Internet Explorer's engine
            # refuses that). Option 9 asks for TLS 1.1/1.2, which Windows 7 has with KB3140245.
            $http = New-Object -ComObject 'WinHttp.WinHttpRequest.5.1'
            try { $http.Option(9) = 0x0A00 } catch { }
            $http.SetTimeouts(30000, 30000, 30000, $timeoutSec * 1000)
            $http.Open('GET', $url, $false)
            $http.SetRequestHeader('User-Agent', 'LKH-Updater')
            $http.Send()
            if ($http.Status -ne 200) { throw "HTTP $($http.Status)" }
            return , [byte[]]$http.ResponseBody
        } catch {
            $hint = ''
            if ($PSVersionTable.PSVersion.Major -lt 3) {
                $hint = ' On Windows 7, run Windows Update, or install Windows Management Framework 5.1 (https://www.microsoft.com/download/details.aspx?id=54616), then try again.'
            }
            throw "$netError (also tried WinHTTP: $($_.Exception.Message.Trim()))$hint"
        }
    }
}

# Unpacks a zip into a folder. .NET 2 (PowerShell 2) has no zip classes, but it has DeflateStream,
# which is all a zip of deflated files needs: the central directory lists each file.
function Expand-Zip($zipPath, $destination) {
    $bytes = [IO.File]::ReadAllBytes($zipPath)
    $end = -1
    for ($i = $bytes.Length - 22; $i -ge [Math]::Max(0, $bytes.Length - 65557); $i--) {
        if ([BitConverter]::ToUInt32($bytes, $i) -eq 0x06054b50) { $end = $i; break }
    }
    if ($end -lt 0) { throw 'the download is not a zip file' }
    $count = [BitConverter]::ToUInt16($bytes, $end + 10)
    $entry = [BitConverter]::ToUInt32($bytes, $end + 16)
    for ($n = 0; $n -lt $count; $n++) {
        if ([BitConverter]::ToUInt32($bytes, $entry) -ne 0x02014b50) { throw 'the zip file is damaged' }
        $method = [BitConverter]::ToUInt16($bytes, $entry + 10)
        $packed = [BitConverter]::ToUInt32($bytes, $entry + 20)
        $nameLength = [BitConverter]::ToUInt16($bytes, $entry + 28)
        $extraLength = [BitConverter]::ToUInt16($bytes, $entry + 30)
        $commentLength = [BitConverter]::ToUInt16($bytes, $entry + 32)
        $local = [BitConverter]::ToUInt32($bytes, $entry + 42)
        $name = [Text.Encoding]::UTF8.GetString($bytes, $entry + 46, $nameLength)
        $entry += 46 + $nameLength + $extraLength + $commentLength
        if ($name.EndsWith('/')) { continue }
        if ($name.Contains('..')) { throw "the zip has an unsafe path: $name" }
        $target = Join-Path $destination ($name -replace '/', '\')
        $folder = Split-Path -Parent $target
        if (-not (Test-Path $folder)) { New-Item -ItemType Directory -Path $folder | Out-Null }
        $start = $local + 30 + [BitConverter]::ToUInt16($bytes, $local + 26) + [BitConverter]::ToUInt16($bytes, $local + 28)
        $out = [IO.File]::Create($target)
        try {
            if ($method -eq 0) { $out.Write($bytes, $start, $packed) }
            elseif ($method -eq 8) {
                $inflate = New-Object IO.Compression.DeflateStream((New-Object IO.MemoryStream($bytes, $start, $packed)), [IO.Compression.CompressionMode]::Decompress)
                $buffer = New-Object byte[] 65536
                while (($read = $inflate.Read($buffer, 0, $buffer.Length)) -gt 0) { $out.Write($buffer, 0, $read) }
                $inflate.Close()
            } else { throw "the zip uses an unknown compression ($method) for $name" }
        } finally { $out.Close() }
    }
}

function Update-Data {
    $tmp = "$dataFile.download"
    try {
        [IO.File]::WriteAllBytes($tmp, (Get-Url $DataSource 120))
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
        if (Test-Path $tmp) { Remove-Item $tmp -ErrorAction SilentlyContinue }
        Log "Leaderboard update failed, keeping the current file: $($_.Exception.Message)"
        return $false
    }
}

function Update-Addon {
    $work = Join-Path ([IO.Path]::GetTempPath()) ("lkh-update-" + [guid]::NewGuid())
    try {
        $toc = Get-Content (Join-Path $here 'LegionKeyHistory.toc') | Where-Object { $_ -match '^## Version:' } | Select-Object -First 1
        $current = ($toc -replace '^## Version:\s*', '').Trim()
        Write-Host "Checking for a new version (you have $current)..."
        $release = [Text.Encoding]::UTF8.GetString((Get-Url $AddonRelease 60))
        $latest = [regex]::Match($release, '"tag_name"\s*:\s*"v?([^"]+)"').Groups[1].Value
        if (-not $latest) { throw 'GitHub did not say which version is the newest' }
        if ([version]$latest -le [version]$current) {
            if (-not $Auto) { Log "You already have the newest version ($current). Nothing to update." }  # not every hour in the log
            return $true
        }
        $zipUrl = [regex]::Match($release, '"browser_download_url"\s*:\s*"([^"]+\.zip)"').Groups[1].Value
        if (-not $zipUrl) { throw "release $latest has no zip" }
        Write-Host "Downloading Legion Key History $latest..."
        New-Item -ItemType Directory -Path $work | Out-Null
        $zip = Join-Path $work 'addon.zip'
        [IO.File]::WriteAllBytes($zip, (Get-Url $zipUrl 300))
        Expand-Zip $zip (Join-Path $work 'unpacked')
        $source = Join-Path $work 'unpacked\LegionKeyHistory'
        if (-not (Test-Path (Join-Path $source 'LegionKeyHistory.toc'))) { throw 'the download does not contain the LegionKeyHistory addon' }
        # Copy the new version over this folder. The leaderboard file is only replaced when the
        # one in the zip is newer. "LKH Updater.cmd" is still running, so its new version is
        # saved next to it and swapped in by the .cmd itself once it is safe.
        foreach ($file in Get-ChildItem $source | Where-Object { -not $_.PSIsContainer }) {
            $target = Join-Path $here $file.Name
            if ($file.Name -eq 'LeaderboardData.lua' -and (DataStamp $target) -ge (DataStamp $file.FullName)) { continue }
            # The zip's ImportedRuns.lua is an empty placeholder: never replace your own imported runs.
            if ($file.Name -eq 'ImportedRuns.lua' -and (Test-Path $target)) { continue }
            # Only the menu (not the hourly task) has "LKH Updater.cmd" open while this runs.
            if ($file.Name -eq 'LKH Updater.cmd' -and -not $Auto) { $target = "$target.new" }
            Copy-Item $file.FullName $target -Force
        }
        Log "Addon updated from $current to $latest. Restart WoW (or /reload) to load it."
        return $true
    } catch {
        Log "Addon update failed: $($_.Exception.Message)"
        return $false
    } finally {
        if (Test-Path $work) { Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

if (-not (Writable)) {
    Log "Cannot write to $here (Windows protects this folder). Right-click LKH Updater.cmd and choose Run as administrator."
    if ($Pause) { Read-Host 'Press Enter to close' | Out-Null }
    exit 3
}
# The hourly task installs new addon versions only when asked to, and never while WoW is running:
# WoW reads the addon when it starts, and a version that adds a file needs a full restart anyway.
function WowRunning {
    $wow = (Resolve-Path (Join-Path $here '..\..\..')).Path
    [bool](Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Path -and $_.Path.StartsWith($wow, [StringComparison]::OrdinalIgnoreCase) })
}
if ($Auto -and (Test-Path (Join-Path $here 'auto-addon.txt')) -and -not (WowRunning)) { $Addon = $true }
# A new menu saved as "LKH Updater.cmd.new" while the old one was open, and the window was closed
# before it could swap itself: the hourly task puts it in place (unless the menu is open now).
function Install-NewMenu {
    $new = Join-Path $here 'LKH Updater.cmd.new'
    if (-not (Test-Path $new)) { return }
    $open = Get-WmiObject Win32_Process -Filter "Name='cmd.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -like '*LKH Updater.cmd*' }
    if ($open) { return }
    try { Move-Item $new (Join-Path $here 'LKH Updater.cmd') -Force; Log 'Installed the new LKH Updater.cmd menu.' } catch { }
}
if ($Auto) { Install-NewMenu }
if ($Addon) { $ok = Update-Addon; if ($ok) { $ok = Update-Data } } else { $ok = Update-Data }
if ($Pause) { Write-Host ''; Read-Host 'Press Enter to close' | Out-Null }
if ($ok) { exit 0 } else { exit 1 }
