#!/usr/bin/env bash
# Legion Key History - updater for Linux (WoW in Wine, Lutris, Bottles or Steam) and macOS
# (CrossOver, Whisky or Wine).
# Keeps LeaderboardData.lua up to date every hour (on Linux a systemd user timer, or cron where
# there is no systemd; on macOS a launchd agent), and can install new addon versions.
# Works with the bash 3.2 that macOS ships. Run it from the addon folder:
#   bash LKH-Updater.sh                 the menu
#   bash LKH-Updater.sh install         hourly update: leaderboard only
#   bash LKH-Updater.sh installaddon    hourly update: leaderboard and addon
#   bash LKH-Updater.sh update          update the leaderboard now
#   bash LKH-Updater.sh addon           update the addon now
#   bash LKH-Updater.sh uninstall       turn the hourly update off
#   bash LKH-Updater.sh auto            what the hourly update runs
# Needs curl or wget, and unzip, bsdtar or python3 for addon updates (macOS has all it needs).
# A failed or incomplete download never replaces what you have. /reload in WoW to load changes.

set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
SELF="$DIR/$(basename "$0")"
DATA_URL='https://github.com/bez-wow/lkh-data/releases/latest/download/LeaderboardData.lua'
RELEASE_API='https://api.github.com/repos/bez-wow/legionkeyhistory/releases/latest'
# Optional overrides for testing: source.txt (data URL) and release.txt (release API URL).
[ -f "$DIR/source.txt" ] && DATA_URL="$(head -n 1 "$DIR/source.txt" | tr -d '\r')"
[ -f "$DIR/release.txt" ] && RELEASE_API="$(head -n 1 "$DIR/release.txt" | tr -d '\r')"
UNIT="${LKH_TASK:-lkh-leaderboard-update}"
UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
CRON_MARK="# Legion Key History hourly update: $DIR"
# Present when the hourly update also installs new addon versions (same file as on Windows).
AUTO_ADDON="$DIR/auto-addon.txt"
MAC=0
[ "$(uname -s 2>/dev/null)" = Darwin ] && MAC=1
# macOS: a launchd agent in ~/Library/LaunchAgents.
LABEL="io.github.bez-wow.$UNIT"
AGENT="${LKH_AGENT_DIR:-$HOME/Library/LaunchAgents}/$LABEL.plist"
if [ "$MAC" = 1 ]; then
    LOG_DIR="$HOME/Library/Logs/LegionKeyHistory"
else
    LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/LegionKeyHistory"
fi
LOG="$LOG_DIR/update.log"
QUIET=0

log() {
    [ "$QUIET" = 1 ] || echo "$1"
    mkdir -p "$LOG_DIR" 2>/dev/null || return 0
    if [ -f "$LOG" ] && [ "$(wc -c < "$LOG")" -gt 200000 ]; then rm -f "$LOG"; fi
    echo "$(date '+%Y-%m-%d %H:%M')  $1" >> "$LOG" 2>/dev/null
}

# fetch URL FILE: download to FILE; nonzero on any failure.
fetch() {
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --retry 2 --max-time 300 -H 'User-Agent: LKH-Updater' -o "$2" "$1"
    elif command -v wget >/dev/null 2>&1; then
        wget -q --tries=3 --timeout=300 --user-agent='LKH-Updater' -O "$2" "$1"
    else
        log "Neither curl nor wget is installed. Install one of them: $(install_hint curl)"
        return 1
    fi
}

# The package manager's install command, for messages about a missing tool.
install_hint() {
    if [ "$MAC" = 1 ]; then echo "brew install $1"
    elif command -v pacman >/dev/null 2>&1; then echo "sudo pacman -S $1"
    elif command -v apt-get >/dev/null 2>&1; then echo "sudo apt install $1"
    elif command -v dnf >/dev/null 2>&1; then echo "sudo dnf install $1"
    elif command -v zypper >/dev/null 2>&1; then echo "sudo zypper install $1"
    else echo "install the $1 package"; fi
}

# Whether two files are identical (cksum is in coreutils, so it is everywhere; cmp is not).
same_file() {
    [ "$(cksum < "$1")" = "$(cksum < "$2")" ]
}

writable() {
    local probe="$DIR/.lkh-write-test"
    ( : > "$probe" ) 2>/dev/null && rm -f "$probe"
}

# The "downloaded" time inside a leaderboard file ("2026-10-06 19:56 UTC"); sorts as text.
data_stamp() {
    [ -f "$1" ] || return 0
    grep -o '\["downloaded"\]="[^"]*"' "$1" | head -n 1 | sed 's/.*="\(.*\)"/\1/'
}

update_data() {
    local data="$DIR/LeaderboardData.lua" tmp="$DIR/LeaderboardData.lua.download"
    if ! fetch "$DATA_URL" "$tmp"; then
        rm -f "$tmp"
        log 'Leaderboard update failed, keeping the current file: the download did not work.'
        return 1
    fi
    if [ "$(wc -c < "$tmp")" -lt 512000 ] || ! grep -q 'LegionKeyHistoryLeaderboard=' "$tmp"; then
        rm -f "$tmp"
        log 'Leaderboard update failed, keeping the current file: the download is not a complete leaderboard file.'
        return 1
    fi
    if [ -f "$data" ] && same_file "$tmp" "$data"; then
        rm -f "$tmp"
        log 'Leaderboard already up to date.'
        return 0
    fi
    mv -f "$tmp" "$data"
    log "Leaderboard updated: data from $(data_stamp "$data"). /reload in WoW to load it."
}

toc_version() {
    sed -n 's/^## Version:[[:space:]]*//p' "$1" | head -n 1 | tr -d '\r[:space:]'
}

# newer A B: whether version A is newer than B (1.10.0 > 1.9.7). Number by number, without
# sort -V, which older macOS does not have.
newer() {
    local a="$1" b="$2" x y
    while [ -n "$a" ] || [ -n "$b" ]; do
        x="${a%%.*}"; y="${b%%.*}"
        case "$a" in *.*) a="${a#*.}" ;; *) a='' ;; esac
        case "$b" in *.*) b="${b#*.}" ;; *) b='' ;; esac
        x="${x//[!0-9]/}"; y="${y//[!0-9]/}"
        [ "${x:-0}" -gt "${y:-0}" ] && return 0
        [ "${x:-0}" -lt "${y:-0}" ] && return 1
    done
    return 1
}

unpack() {
    if command -v unzip >/dev/null 2>&1; then unzip -q -o "$1" -d "$2"
    elif command -v bsdtar >/dev/null 2>&1; then bsdtar -xf "$1" -C "$2"
    elif command -v ditto >/dev/null 2>&1; then ditto -x -k "$1" "$2"
    elif command -v python3 >/dev/null 2>&1; then python3 -m zipfile -e "$1" "$2"
    else
        log "Cannot unpack the addon: install unzip ($(install_hint unzip)), then try again."
        return 1
    fi
}

update_addon() {
    local current latest json url work source file name target
    current="$(toc_version "$DIR/LegionKeyHistory.toc")"
    [ "$QUIET" = 1 ] || echo "Checking for a new version (you have $current)..."
    work="$(mktemp -d "${TMPDIR:-/tmp}/lkh-update-XXXXXX")" || return 1
    json="$work/release.json"
    if ! fetch "$RELEASE_API" "$json"; then
        log 'Addon update failed: could not reach GitHub.'; rm -rf "$work"; return 1
    fi
    latest="$(grep -o '"tag_name"[[:space:]]*:[[:space:]]*"[^"]*"' "$json" | head -n 1 | sed 's/.*"v\{0,1\}\([^"]*\)"$/\1/')"
    url="$(grep -o '"browser_download_url"[[:space:]]*:[[:space:]]*"[^"]*\.zip"' "$json" | head -n 1 | sed 's/.*"\(http[^"]*\)"$/\1/')"
    if [ -z "$latest" ] || [ -z "$url" ]; then
        log 'Addon update failed: the release has no version or no zip.'; rm -rf "$work"; return 1
    fi
    if ! newer "$latest" "$current"; then
        [ "$QUIET" = 1 ] || log "You already have the newest version ($current). Nothing to update."
        rm -rf "$work"; return 0
    fi
    [ "$QUIET" = 1 ] || echo "Downloading Legion Key History $latest..."
    if ! fetch "$url" "$work/addon.zip" || ! mkdir -p "$work/unpacked" || ! unpack "$work/addon.zip" "$work/unpacked"; then
        log 'Addon update failed: the download or unpacking did not work.'; rm -rf "$work"; return 1
    fi
    source="$work/unpacked/LegionKeyHistory"
    if [ ! -f "$source/LegionKeyHistory.toc" ]; then
        log 'Addon update failed: the download does not contain the LegionKeyHistory addon.'; rm -rf "$work"; return 1
    fi
    for file in "$source"/*; do
        [ -f "$file" ] || continue
        name="$(basename "$file")"; target="$DIR/$name"
        # The leaderboard only when the one in the zip is newer; never your own imported runs.
        if [ "$name" = 'LeaderboardData.lua' ] && [ -f "$target" ] && [[ ! "$(data_stamp "$file")" > "$(data_stamp "$target")" ]]; then continue; fi
        if [ "$name" = 'ImportedRuns.lua' ] && [ -f "$target" ]; then continue; fi
        # Copy beside, then rename over: a running copy of this script keeps reading the old file.
        cp -f "$file" "$target.new" && mv -f "$target.new" "$target"
    done
    chmod +x "$DIR/LKH-Updater.sh" 2>/dev/null
    rm -rf "$work"
    log "Addon updated from $current to $latest. Restart WoW (or /reload) to load it."
}

# WoW running in Wine: addon files change only while it is closed (it reads them when it starts).
# Matches the process name Wine gives the game, not whole command lines (a terminal or launcher
# command mentioning Wow.exe must not count).
wow_running() {
    pgrep -i '^(wow|wow-64|wowt|wowb)\.exe$' >/dev/null 2>&1 && return 0
    # macOS: Wine (CrossOver, Whisky) keeps its own process name, so look for the game's path as
    # an argument ("...\Wow-64.exe"), and for the Mac client by name.
    [ "$MAC" = 1 ] || return 1
    pgrep -if '[\\/](wow|wow-64|wowt|wowb)\.exe([[:space:]]|$)' >/dev/null 2>&1 || pgrep -x 'World of Warcraft' >/dev/null 2>&1
}

# The text, safe inside the launchd plist (XML).
xml() {
    local t="$1"
    t="${t//&/&amp;}"; t="${t//</&lt;}"; t="${t//>/&gt;}"
    printf '%s' "$t"
}

agent_loaded() {
    launchctl list "$LABEL" >/dev/null 2>&1
}

have_systemd() {
    command -v systemctl >/dev/null 2>&1 && systemctl --user show-environment >/dev/null 2>&1
}

schedule_status() {
    if [ "$MAC" = 1 ]; then [ -f "$AGENT" ] && agent_loaded; return; fi
    if [ -f "$UNIT_DIR/$UNIT.timer" ] && have_systemd && systemctl --user is-enabled "$UNIT.timer" >/dev/null 2>&1; then return 0; fi
    command -v crontab >/dev/null 2>&1 && crontab -l 2>/dev/null | grep -qF "$CRON_MARK"
}

remove_schedule() {
    if [ "$MAC" = 1 ]; then
        if agent_loaded; then
            launchctl bootout "gui/$(id -u)/$LABEL" >/dev/null 2>&1 || launchctl unload "$AGENT" >/dev/null 2>&1
        fi
        rm -f "$AGENT"
        return 0
    fi
    if [ -f "$UNIT_DIR/$UNIT.timer" ]; then
        have_systemd && systemctl --user disable --now "$UNIT.timer" >/dev/null 2>&1
        rm -f "$UNIT_DIR/$UNIT.timer" "$UNIT_DIR/$UNIT.service"
        have_systemd && systemctl --user daemon-reload >/dev/null 2>&1
    fi
    if command -v crontab >/dev/null 2>&1 && crontab -l 2>/dev/null | grep -qF "$CRON_MARK"; then
        crontab -l 2>/dev/null | grep -vF "$CRON_MARK" | crontab -
    fi
}

# install data|both
install_schedule() {
    echo
    if ! writable; then
        echo "This folder is not writable by your user: $DIR"
        return 1
    fi
    echo 'Downloading the newest leaderboard...'
    if ! update_data; then
        echo
        echo 'The download did not work, so the hourly update was NOT installed.'
        echo 'Check your internet connection and try again.'
        return 1
    fi
    remove_schedule
    if [ "$MAC" = 1 ]; then
        # Every hour; launchd catches up after the Mac wakes from sleep.
        mkdir -p "$(dirname "$AGENT")"
        cat > "$AGENT" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$LABEL</string>
    <key>ProgramArguments</key>
    <array><string>/bin/bash</string><string>$(xml "$SELF")</string><string>auto</string></array>
    <key>StartInterval</key><integer>3600</integer>
    <key>ProcessType</key><string>Background</string>
    <key>LowPriorityIO</key><true/>
</dict>
</plist>
EOF
        launchctl bootstrap "gui/$(id -u)" "$AGENT" >/dev/null 2>&1 || launchctl load -w "$AGENT" >/dev/null 2>&1
        agent_loaded || { echo 'Could not start the launchd agent.'; return 1; }
    elif have_systemd; then
        # systemd treats % specially, so a folder name with one is escaped.
        local exec_path="${SELF//%/%%}"
        mkdir -p "$UNIT_DIR"
        printf '[Unit]\nDescription=Legion Key History leaderboard update\n\n[Service]\nType=oneshot\nExecStart=/usr/bin/env bash "%s" auto\n' "$exec_path" > "$UNIT_DIR/$UNIT.service"
        printf '[Unit]\nDescription=Legion Key History hourly leaderboard update\n\n[Timer]\nOnCalendar=hourly\nRandomizedDelaySec=300\nPersistent=true\n\n[Install]\nWantedBy=timers.target\n' > "$UNIT_DIR/$UNIT.timer"
        systemctl --user daemon-reload && systemctl --user enable --now "$UNIT.timer" >/dev/null 2>&1 || {
            echo 'Could not start the systemd timer.'; return 1; }
    elif command -v crontab >/dev/null 2>&1; then
        local cron_path="${SELF//%/\\%}"
        { crontab -l 2>/dev/null; echo "$((RANDOM % 60)) * * * * /usr/bin/env bash \"$cron_path\" auto >/dev/null 2>&1 $CRON_MARK"; } | crontab - || {
            echo 'Could not add the cron job.'; return 1; }
    else
        echo 'Neither systemd (user timers) nor cron is available, so there is nothing to run it every hour.'
        echo 'You can still choose "Update the leaderboard now" whenever you like.'
        return 1
    fi
    if [ "$1" = both ]; then echo 'Hourly update with new addon versions' > "$AUTO_ADDON"; else rm -f "$AUTO_ADDON"; fi
    echo
    if [ "$1" = both ]; then
        echo 'Installed. Every hour, while you are logged in, the leaderboard is updated in the background,'
        echo 'and a new version of the addon is installed when there is one.'
        echo 'New versions are only installed while WoW is closed; start WoW again to load them.'
    else
        echo 'Installed. Every hour, while you are logged in, the leaderboard is updated in the'
        echo 'background. In WoW, /reload or log in to load the newest one.'
    fi
    echo 'To stop it, run this again and choose 5.'
}

uninstall_schedule() {
    echo
    rm -f "$AUTO_ADDON"
    if ! schedule_status; then
        echo 'The hourly update is not installed.'
        return 0
    fi
    remove_schedule
    echo 'Turned off. The leaderboard file you have stays; it just no longer updates by itself.'
}

auto_run() {
    QUIET=1
    writable || { log "Cannot write to $DIR."; return 3; }
    if [ -f "$AUTO_ADDON" ] && ! wow_running; then update_addon; fi
    update_data
}

menu() {
    while true; do
        clear 2>/dev/null
        echo ' Legion Key History - updater'
        echo ' ============================'
        echo
        if schedule_status; then
            if [ -f "$AUTO_ADDON" ]; then echo ' Hourly update: leaderboard and addon'; else echo ' Hourly update: leaderboard only'; fi
        else
            echo ' Hourly update: not installed'
        fi
        writable || echo " Note: this folder is not writable by your user: $DIR"
        echo
        echo '  1. Hourly update: leaderboard only'
        echo '  2. Hourly update: leaderboard and addon (new versions install by themselves)'
        echo '  3. Update the addon to the newest version now'
        echo '  4. Update the leaderboard now'
        echo '  5. Turn off the hourly update'
        echo '  6. Exit'
        echo
        read -r -p ' Choose 1-6: ' choice || exit 0
        case "$choice" in
            1) install_schedule data ;;
            2) install_schedule both ;;
            3) echo; update_addon && update_data ;;
            4) echo; update_data ;;
            5) uninstall_schedule ;;
            6) exit 0 ;;
            *) continue ;;
        esac
        echo; read -r -p ' Press Enter to continue...' _ || exit 0
    done
}

if [ ! -f "$DIR/LegionKeyHistory.toc" ]; then
    echo 'This file must stay inside the LegionKeyHistory addon folder:'
    echo '  .../Interface/AddOns/LegionKeyHistory/'
    exit 1
fi

case "${1:-}" in
    install) install_schedule data ;;
    installaddon) install_schedule both ;;
    update) update_data ;;
    addon) update_addon && update_data ;;
    uninstall) uninstall_schedule ;;
    auto) auto_run ;;
    '') menu ;;
    *) echo "Unknown option: $1 (use install, installaddon, update, addon, uninstall or auto)"; exit 2 ;;
esac
