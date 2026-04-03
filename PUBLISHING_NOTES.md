# Publishing SpotiBard to LOTROInterface.com

## 1. Create an Account

Go to [lotrointerface.com](https://www.lotrointerface.com/) and click "Register" in the top navigation.

## 2. Prepare the ZIP File

Create a ZIP containing only the plugin files:

```
SpotiBard/
    SpotiBard.plugin
    Main.lua
    SpotiBard.lua
```

The companion app (bridge) should be linked from the description (e.g., GitHub release).

## 3. Upload

1. Log in to lotrointerface.com
2. Go to **Downloads** > **Upload & Update** ([direct link](https://www.lotrointerface.com/downloads/upload-update.php))
3. Category: **LotRO Stand-Alone Plugins** > subcategory **Other** (it has an external companion component)

## 4. Details

- **Title:** SpotiBard
- **Version:** 1.0

### Suggested Description

```
SpotiBard — Control Spotify from Inside LOTRO

SpotiBard lets you control Spotify without leaving Middle-earth.

FEATURES:
- Global keyboard shortcuts for instant playback control
  (Ctrl+Alt+Right/Left/Space/Up/Down)
- In-game floating panel showing song, artist, album, and playlist
- Progress bar and playlist browser
- LOTRO-native window styling
- Runs silently in the system tray

HOW IT WORKS:
SpotiBard has two parts:
1. A lightweight companion app (SpotiBridge) that runs in your system tray
2. This LOTRO plugin that shows a "now playing" panel in-game

The companion app provides global hotkeys that work instantly — even while
LOTRO is in focus. The in-game panel shows what's playing and lets you
browse playlists. Note: in-game panel buttons have a ~15 second delay due
to LOTRO's plugin data system. The keyboard shortcuts are the recommended
way to control playback.

IMPORTANT NOTE:
The in-game panel updates every ~15 seconds. This is a limitation of
LOTRO's plugin data system — not a bug. Use the keyboard shortcuts
for instant control, and enjoy the panel as a "now playing" display.
If you know a faster way to read external data from a LOTRO plugin,
please reach out!

REQUIREMENTS:
- Windows
- Spotify Premium account
- The SpotiBridge companion app (download from GitHub)
  (Standalone .exe included — no Python needed!)

SETUP:
Full instructions and the companion app are at:
https://github.com/dp-vibes/SpotiBard

Setup takes about 2 minutes: run SpotiBridge, log in to Spotify
in your browser, copy the plugin folder, done. After that, just
run SpotiBridge before LOTRO and type /plugins load SpotiBard.

HOTKEYS:
  Ctrl+Alt+Right    Next track
  Ctrl+Alt+Left     Previous track
  Ctrl+Alt+Space    Play / Pause
  Ctrl+Alt+Up       Volume up
  Ctrl+Alt+Down     Volume down
```

- **Changelog:** `v1.0 — Initial release`

## 5. Review Process

Submissions are reviewed by moderators before going live. Usually takes a day or two.

## 6. Announce It

After approval, post in the **Released Interfaces (L)** forum:
https://www.lotrointerface.com/forums/forumdisplay.php?f=6

Include:
- What SpotiBard does (one paragraph)
- Screenshot of the in-game panel
- Link to the lotrointerface download page
- Link to the GitHub repo for the companion app
- The hotkey list
- Brief setup instructions

## 7. Updates

When releasing new versions:
1. Update version in `SpotiBard.plugin`
2. Use the "Update" option on your upload page
3. Add a changelog entry
4. Post an update in your forum thread
