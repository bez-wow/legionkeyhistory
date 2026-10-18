# Legion Key History updater, run by "LKH Updater.cmd".
#   (no switch)  download the newest leaderboard file; also what the hourly task runs
#   -Addon       install the newest addon version from GitHub, then refresh the leaderboard
#   -Auto        what the hourly task runs: the leaderboard, plus the addon when you chose
#                "leaderboard and addon" (auto-addon.txt) and WoW is not running
# Every run also shares the keys you finished, with their talents, with Keystone Tauri (see
# Send-Runs), unless sharing is off (no-upload.txt, option 6 in LKH Updater.cmd).
# A failed or incomplete download never replaces what you have. /reload in WoW to load changes.
# Exit codes: 0 done (or already up to date), 1 failed, 3 this folder is not writable.
param([switch]$Addon, [switch]$Auto, [switch]$Pause)  # -Pause: kept for updaters from 1.4.1
$ErrorActionPreference = 'Stop'
$DataSource = 'https://github.com/bez-wow/lkh-data/releases/latest/download/LeaderboardData.lua'
$AddonRelease = 'https://api.github.com/repos/bez-wow/legionkeyhistory/releases/latest'
# Optional overrides for testing: source.txt (data URL) and release.txt (release API URL).
$override = Join-Path $PSScriptRoot 'source.txt'
if (Test-Path $override) { $DataSource = (Get-Content $override -TotalCount 1).Trim() }
$override = Join-Path $PSScriptRoot 'release.txt'
if (Test-Path $override) { $AddonRelease = (Get-Content $override -TotalCount 1).Trim() }
# Keystone Tauri, where finished keys and their talents are shared; api.txt overrides it for testing.
$KeystoneApi = 'https://keystone-tauri.vercel.app'
$override = Join-Path $PSScriptRoot 'api.txt'
if (Test-Path $override) { $KeystoneApi = (Get-Content $override -TotalCount 1).Trim().TrimEnd('/') }

$dataFile = Join-Path $PSScriptRoot 'LeaderboardData.lua'
# The log lives in your own AppData, so it works even where the addon folder is protected.
$logDir = Join-Path $env:LOCALAPPDATA 'LegionKeyHistory'
$log = Join-Path $logDir 'update.log'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
function Log($message) {
    Write-Host $message
    try {
        if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }
        if ((Test-Path $log) -and (Get-Item $log).Length -gt 200KB) { Remove-Item $log }
        "$(Get-Date -Format 'yyyy-MM-dd HH:mm')  $message" | Add-Content -Path $log -Encoding UTF8
    } catch { }
}
function FileHash($path) { $sha = [Security.Cryptography.SHA256]::Create(); try { [BitConverter]::ToString($sha.ComputeHash([IO.File]::ReadAllBytes($path))) } finally { $sha.Dispose() } }
# The "downloaded" time inside a leaderboard file ("2026-10-06 19:56 UTC"); sorts as text.
function DataStamp($path) { if (-not (Test-Path $path)) { return '' }; [regex]::Match([IO.File]::ReadAllText($path), '\["downloaded"\]="([^"]*)"').Groups[1].Value }
function Writable {
    $probe = Join-Path $PSScriptRoot '.lkh-write-test'
    try { [IO.File]::WriteAllText($probe, 'ok'); Remove-Item $probe; return $true } catch { return $false }
}

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
        if (Test-Path $tmp) { Remove-Item $tmp -ErrorAction SilentlyContinue }
        Log "Leaderboard update failed, keeping the current file: $($_.Exception.Message)"
        return $false
    }
}

function Update-Addon {
    $work = Join-Path ([IO.Path]::GetTempPath()) ("lkh-update-" + [guid]::NewGuid())
    try {
        $toc = Get-Content (Join-Path $PSScriptRoot 'LegionKeyHistory.toc') | Where-Object { $_ -match '^## Version:' } | Select-Object -First 1
        $current = ($toc -replace '^## Version:\s*', '').Trim()
        Write-Host "Checking for a new version (you have $current)..."
        $release = Invoke-RestMethod -Uri $AddonRelease -Headers @{ 'User-Agent' = 'LKH-Updater' } -TimeoutSec 60
        $latest = $release.tag_name.TrimStart('v')
        if ([version]$latest -le [version]$current) {
            if (-not $Auto) { Log "You already have the newest version ($current). Nothing to update." }  # not every hour in the log
            return $true
        }
        $asset = $release.assets | Where-Object { $_.name -like '*.zip' } | Select-Object -First 1
        if (-not $asset) { throw "release $latest has no zip" }
        Write-Host "Downloading Legion Key History $latest..."
        New-Item -ItemType Directory -Path $work | Out-Null
        $zip = Join-Path $work 'addon.zip'
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zip -UseBasicParsing -TimeoutSec 300
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [IO.Compression.ZipFile]::ExtractToDirectory($zip, (Join-Path $work 'unpacked'))
        $source = Join-Path $work 'unpacked\LegionKeyHistory'
        if (-not (Test-Path (Join-Path $source 'LegionKeyHistory.toc'))) { throw 'the download does not contain the LegionKeyHistory addon' }
        # Copy the new version over this folder. The leaderboard file is only replaced when the
        # one in the zip is newer. "LKH Updater.cmd" is still running, so its new version is
        # saved next to it and swapped in by the .cmd itself once it is safe.
        foreach ($file in Get-ChildItem $source -File) {
            $target = Join-Path $PSScriptRoot $file.Name
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

# ---------------------------------------------------------------------------------------------------------
# Sharing finished keys with Keystone Tauri. Talents.lua saves each finished key with its group's talents
# as run.upload (JSON) in WTF\Account\<account>\SavedVariables\LegionKeyHistory.lua; this sends the ones
# not sent yet. The site checks every key against the Tauri leaderboard and keeps only real ones. What was
# sent is listed in keystone-sent.txt, and keystone-token.txt holds the anonymous token the site gave us,
# both next to the log.

# POSTs JSON; returns the status (0: no answer) and the parsed reply.
function Post-Keystone($path, $body, $token) {
    $request = [Net.HttpWebRequest]::Create("$KeystoneApi$path")
    $request.Method = 'POST'
    $request.ContentType = 'application/json; charset=utf-8'
    $request.UserAgent = 'LKH-Updater'
    $request.Timeout = 90000
    if ($token) { $request.Headers['Authorization'] = "Bearer $token" }
    $bytes = [Text.Encoding]::UTF8.GetBytes($body)
    $response = $null
    try {
        $stream = $request.GetRequestStream(); $stream.Write($bytes, 0, $bytes.Length); $stream.Close()
        $response = $request.GetResponse()
    } catch {
        $e = $_.Exception
        while ($e -and -not ($e -is [Net.WebException])) { $e = $e.InnerException }
        if ($e) { $response = $e.Response }
        if (-not $response) { return @{ Status = 0; Body = $null } }
    }
    try {
        $text = (New-Object IO.StreamReader($response.GetResponseStream(), [Text.Encoding]::UTF8)).ReadToEnd()
        $json = $null
        try { $json = $text | ConvertFrom-Json } catch { }
        return @{ Status = [int]$response.StatusCode; Body = $json }
    } finally { $response.Close() }
}

# Every run.upload in the saved files of each account on this WoW.
function Read-Uploads {
    $accounts = Join-Path (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path 'WTF\Account'
    $found = @()
    if (-not (Test-Path $accounts)) { return $found }
    # Undoes the saved file's string escapes (\" \\ \n and \ddd).
    $unescape = [Text.RegularExpressions.MatchEvaluator]{
        param($m)
        $c = $m.Groups[1].Value
        if ($c -match '^\d+$') { [string][char][int]$c } elseif ($c -eq 'n') { "`n" } else { $c }
    }
    foreach ($account in Get-ChildItem $accounts -Directory) {
        $file = Join-Path $account.FullName 'SavedVariables\LegionKeyHistory.lua'
        if (-not (Test-Path $file)) { continue }
        $text = [IO.File]::ReadAllText($file, [Text.Encoding]::UTF8)
        foreach ($match in [regex]::Matches($text, '\["upload"\]\s*=\s*"((?:[^"\\]|\\.)*)"')) {
            $json = [regex]::Replace($match.Groups[1].Value, '\\(\d{1,3}|.)', $unescape)
            try { $found += , @{ Json = $json; Run = ($json | ConvertFrom-Json) } } catch { }
        }
    }
    return $found
}

function Send-Runs {
    $sentFile = Join-Path $logDir 'keystone-sent.txt'
    $tokenFile = Join-Path $logDir 'keystone-token.txt'
    $sent = @{}
    if (Test-Path $sentFile) { foreach ($line in Get-Content $sentFile) { $sent[$line.Split("`t")[0]] = $true } }
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    # Keystone Tauri takes keys from the last 8 days.
    $todo = @(Read-Uploads | Where-Object { -not $sent[$_.Run.addonRunId] -and $now - $_.Run.endedAt -lt 8 * 86400 })
    if ($todo.Count -eq 0) { return }
    $toc = Get-Content (Join-Path $PSScriptRoot 'LegionKeyHistory.toc') | Where-Object { $_ -match '^## Version:' } | Select-Object -First 1
    $version = ($toc -replace '^## Version:\s*', '').Trim()
    $token = $null
    if (Test-Path $tokenFile) { $token = (Get-Content $tokenFile -TotalCount 1).Trim() }
    $shared = 0; $waiting = 0; $newToken = $false; $i = 0
    while ($i -lt $todo.Count) {
        if (-not $token) {
            $reply = Post-Keystone '/api/v1/updater/tokens' ('{"version":1,"client":{"updater":"' + $version + '"}}') $null
            if ($reply.Status -ne 201 -or -not $reply.Body.token) { Log 'Keystone Tauri did not answer; your keys are shared next time.'; break }
            $token = $reply.Body.token
            if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }
            Set-Content -Path $tokenFile -Value $token -Encoding ASCII
        }
        $item = $todo[$i]
        $body = '{"version":1,"client":{"updater":"' + $version + '","addon":"' + $version + '"},"run":' + $item.Json + '}'
        $reply = Post-Keystone '/api/v1/uploads' $body $token
        $status = $null
        if ($reply.Status -eq 200) { $status = $reply.Body.status }
        elseif ($reply.Status -eq 422) {
            # Not on the leaderboard yet (retryable): tried again next hour. Any other reason is final.
            if ($reply.Body.reason.retryable) { $waiting++ } else { $status = "rejected:$($reply.Body.reason.code)" }
        } elseif ($reply.Status -eq 401 -and -not $newToken) {
            # The token was revoked: ask for a new one, once, and send this key again.
            $newToken = $true; $token = $null
            Remove-Item $tokenFile -ErrorAction SilentlyContinue
            continue
        } elseif ($reply.Status -eq 426) {
            Log 'Keystone Tauri needs a newer Legion Key History: update the addon (option 3).'
            break
        } elseif ($reply.Status -eq 0 -or $reply.Status -eq 401 -or $reply.Status -eq 429 -or $reply.Status -ge 500) {
            # Unreachable, refusing the new token, busy or failing: the rest waits for the next hour.
            Log "Keystone Tauri did not take your keys now (HTTP $($reply.Status)); they are shared next time."
            break
        } elseif ($reply.Status -ge 400) { $status = "invalid:$($reply.Status)" }
        if ($status) {
            Add-Content -Path $sentFile -Value "$($item.Run.addonRunId)`t$status`t$now" -Encoding UTF8
            if ($status -eq 'accepted' -or $status -eq 'duplicate') { $shared++ }
        }
        $i++
    }
    if ($shared -gt 0) { Log "Shared $shared key(s) and their talents with Keystone Tauri." }
    if ($waiting -gt 0) { Log "$waiting key(s) not on the Tauri leaderboard yet; they are shared once they are (next update)." }
}

if (-not (Writable)) {
    Log "Cannot write to $PSScriptRoot (Windows protects this folder). Right-click LKH Updater.cmd and choose Run as administrator."
    if ($Pause) { Read-Host 'Press Enter to close' | Out-Null }
    exit 3
}
# The hourly task installs new addon versions only when asked to, and never while WoW is running:
# WoW reads the addon when it starts, and a version that adds a file needs a full restart anyway.
function WowRunning {
    $wow = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
    [bool](Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Path -and $_.Path.StartsWith($wow, [StringComparison]::OrdinalIgnoreCase) })
}
if ($Auto -and (Test-Path (Join-Path $PSScriptRoot 'auto-addon.txt')) -and -not (WowRunning)) { $Addon = $true }
# A new menu saved as "LKH Updater.cmd.new" while the old one was open, and the window was closed
# before it could swap itself: the hourly task puts it in place (unless the menu is open now).
function Install-NewMenu {
    $new = Join-Path $PSScriptRoot 'LKH Updater.cmd.new'
    if (-not (Test-Path $new)) { return }
    $open = Get-CimInstance Win32_Process -Filter "Name='cmd.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -like '*LKH Updater.cmd*' }
    if ($open) { return }
    try { Move-Item $new (Join-Path $PSScriptRoot 'LKH Updater.cmd') -Force; Log 'Installed the new LKH Updater.cmd menu.' } catch { }
}
if ($Auto) { Install-NewMenu }
if ($Addon) { $ok = Update-Addon; if ($ok) { $ok = Update-Data } } else { $ok = Update-Data }
if (-not (Test-Path (Join-Path $PSScriptRoot 'no-upload.txt'))) {
    try { Send-Runs } catch { Log "Sharing keys with Keystone Tauri failed: $($_.Exception.Message)" }
}
if ($Pause) { Write-Host ''; Read-Host 'Press Enter to close' | Out-Null }
if ($ok) { exit 0 } else { exit 1 }
