# Legion Key History

A Mythic+ addon for **Legion (7.3.5) on Tauri** — Evermoon, Tauri and Warriors of Darkness.
It keeps a journal of every key you complete and shows Raider.IO-style scores and ranks for
everyone on the Tauri Mythic+ leaderboard, right in the game.

## How to download

1. Go to **[Releases](https://github.com/bez-wow/legionkeyhistory/releases/latest)** and download
   **`LegionKeyHistory.zip`** (not the green "Code" button — that one has the wrong folder name).
2. Extract it into `World of Warcraft\Interface\AddOns\`, so you end up with
   `Interface\AddOns\LegionKeyHistory\LegionKeyHistory.toc`.
3. Start WoW, enable the addon and type `/lkh`.

**Keep the leaderboard up to date (recommended):** open the addon folder and double-click
**`LKH Updater.cmd`**, then choose **Install the hourly leaderboard update service**.
It refreshes the leaderboard every hour in the background (`/reload` in WoW to load it).
The same menu can **update the addon to the newest version** or **uninstall the service**.
No .exe, no Python, no account or API key needed.

## What it does

- **Scores everywhere:** friends list, group finder applicants and search results show each
  player's score; hover for their overall / spec / class rank and best key per dungeon.
- **Leaderboard** (`/lkh lb`): search, realm and class filters, click a player to see all their
  runs, or **Compare** up to five players with the best run per dungeon highlighted.
- **Personal Bests** next to the Dungeon Finder: your score, ranks and best Fortified and
  Tyrannical key per dungeon.
- **Journal** of every key you finish, with tank / healer / DPS, affixes and time; stats on
  your favourite dungeons and the people you play with.
- **Sync** runs with friends in your party, and **Import from file** to fill in your history.
- **Settings** (`/lkh config`): choose where scores show, the score style and colour, tooltip
  contents, sync behaviour, and profiles.

Keys you complete count straight away for everyone in that group; other runs arrive with the
next leaderboard update. Scores are unofficial: the sum of each character's best run score per
dungeon (formula from [Tauri Achievements](https://github.com/tauriachievements/tauriachievements.github.io)).

## Screenshots

| Leaderboard | A player's runs |
|---|---|
| ![Leaderboard](docs/screenshots/leaderboard.png) | ![Player runs](docs/screenshots/player-runs.png) |
| **Compare** | **Friends list** |
| ![Compare](docs/screenshots/compare.png) | ![Friends list](docs/screenshots/friends-list.png) |
| **Your journal** | **Stats** |
| ![Journal](docs/screenshots/journal.png) | ![Stats](docs/screenshots/stats.png) |

## Commands

| Command | Opens |
|---|---|
| `/lkh` | your journal |
| `/lkh lb` | the leaderboard |
| `/lkh config` | settings |
| `/lkh sync` | sync with a party member |
| `/lkh import` | import your runs from the leaderboard file |
