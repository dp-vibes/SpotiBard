# SpotiBard

Control Spotify from inside Lord of the Rings Online — without alt-tabbing.

SpotiBard is a two-part system: a companion app that runs in your Windows system tray and a LOTRO plugin that shows a floating in-game panel with your current song, artist, album, and playlist. Use **global keyboard shortcuts** to skip tracks, play/pause, and adjust volume — instantly, even while playing.

## How It Works

The companion app (SpotiBridge) talks to Spotify and provides global hotkeys that work anywhere, even while LOTRO is in focus. It also feeds song information to the in-game plugin panel.

**Global Hotkeys (instant, recommended):**

| Shortcut | Action |
|---|---|
| `Ctrl+Alt+Right` | Next track |
| `Ctrl+Alt+Left` | Previous track |
| `Ctrl+Alt+Space` | Play / Pause |
| `Ctrl+Alt+Up` | Volume up |
| `Ctrl+Alt+Down` | Volume down |

**In-Game Panel:** Shows what's playing (song, artist, album, playlist) with a progress bar. The panel also has clickable buttons and a playlist browser, though these have a ~15 second delay due to how LOTRO's plugin system works. The hotkeys are the way to go for controlling playback.

## Requirements

- **Windows**
- **Spotify Premium** account (required for playback control)
- **LOTRO** installed and logged in at least once
- A free **Spotify Developer App** (we walk you through creating one — takes 2 minutes)
- **Python 3.8+** only if using the Python version — not needed if using SpotiBridge.exe ([Download Python here](https://www.python.org/downloads/) — check "Add Python to PATH")

## Installation

### Step 1: Download SpotiBard

Download or clone this repository to your computer. You can put it anywhere.

### Step 2: Install the LOTRO Plugin

Copy the `plugin/SpotiBard/` folder into your LOTRO plugins directory:

```
%USERPROFILE%\Documents\The Lord of the Rings Online\Plugins\
```

After copying, you should have:

```
Documents\The Lord of the Rings Online\Plugins\SpotiBard\
    SpotiBard.plugin
    Main.lua
    SpotiBard.lua
```

### Step 3: Create a Spotify Developer App (free, ~2 minutes)

SpotiBard needs a free Spotify Developer App to talk to Spotify. This sounds technical but it's quick:

1. Go to [developer.spotify.com/dashboard](https://developer.spotify.com/dashboard) and log in with your Spotify account
2. Click **Create App**
3. Fill in:
   - **App name:** SpotiBard (or anything)
   - **App description:** anything
   - **Redirect URI:** `http://127.0.0.1:8888/callback` (copy this exactly, then click **Add**)
   - Check the **Web API** box
   - Click **Save**
4. On your app page, click **Settings**
5. Copy your **Client ID** and click "View client secret" to copy your **Client Secret**

You'll paste these into SpotiBard in the next step.

### Step 4: First-Time Setup

1. Open the `bridge/` folder
2. Double-click **`setup.bat`** (Python version) or **`Run SpotiBridge.bat`** (.exe version)
3. Paste your **Client ID** and **Client Secret** when prompted
4. A browser window opens — click **Allow** to authorize
5. Done! Your credentials are saved — you won't need to do this again.

### Step 5: Daily Use

1. Double-click **`run_spotibridge.bat`** in the `bridge/` folder
2. A green music note icon appears in your system tray — that means it's running
3. Launch LOTRO and type in chat: `/plugins load SpotiBard`
4. Use the hotkeys to control Spotify. The in-game panel shows what's playing.
5. When you're done, right-click the green tray icon and choose **Quit**

> **Tip:** Type `/spotibard` in-game to show/hide the panel.

## Features

- **Global Hotkeys** — Skip, play/pause, and adjust volume instantly with keyboard shortcuts. Works even while LOTRO is in focus.
- **Now Playing Display** — See song title, artist, album, and playlist name in-game.
- **Progress Bar** — Visual indicator of where you are in the current track.
- **Playlist Browser** — Browse and switch between your Spotify playlists from the in-game panel.
- **Draggable & Resizable** — Position and size the panel however you like. Settings are saved.
- **System Tray** — The companion app runs quietly in the background. No terminal window.
- **LOTRO-Native Look** — Uses LOTRO's own window styling so it fits right in.

## Being Honest: What Works Great and What Doesn't

Let's be upfront about what to expect.

**What works great:**
- Global hotkeys are **instant**. Skip, pause, volume — no delay at all.
- The in-game panel looks native and shows your current song info.
- Playlist browsing works from inside the game.
- Everything runs quietly in the system tray.

**What's not perfect:**
- The in-game panel updates every **~15 seconds**. This is a hard limitation of LOTRO's plugin data system — the game engine queues file reads on a slow background thread, and there's no way around it. We tried everything (trust us, we REALLY tried).
- The in-game buttons (skip, pause, etc.) also have this ~15 second delay for the same reason. They work, just slowly.

**The bottom line:** Use the **hotkeys** for controlling playback (they're instant), and enjoy the in-game panel as a "now playing" display that updates periodically. It's not perfect, but it's the best that's possible within LOTRO's plugin sandbox.

If you're a plugin developer and know a faster way to read external data from a LOTRO Lua plugin, we'd love to hear from you! Open an issue on GitHub or find us on the LOTROInterface forums.

## Troubleshooting

### "SpotiBard bridge not running"
The plugin can't find the companion app's data. Make sure `run_spotibridge.bat` is running and you see the green tray icon.

### "No active device"
Spotify isn't playing on any device. Start playing something on Spotify first.

### Plugin doesn't show up in-game
- Make sure the plugin files are in the correct folder (see Step 2)
- Try `/plugins refresh` then `/plugins load SpotiBard`

### Hotkeys not working
- SpotiBridge needs administrator privileges for hotkeys to work while a game is running. The launch scripts request this automatically — click "Yes" on the Windows permission prompt.
- Make sure no other app is using the same hotkey combinations.

### Authentication failed
- Delete the `bridge/.spotify_cache` file and try again
- If using custom credentials, also delete `bridge/config.json`

### Controls not responding
- Make sure you have Spotify Premium (free accounts can't control playback)
- Make sure Spotify is actively playing on a device

### Need to see debug output?
Use `run_spotibridge_debug.bat` instead — it opens a terminal window showing all log messages.

## For Developers

SpotiBard uses a file-based communication architecture because LOTRO's Lua plugin sandbox blocks all network access and standard file I/O.

**Architecture:**

```
Spotify API  <-->  SpotiBridge (Python)  <-->  .plugindata files  <-->  LOTRO Lua Plugin
                   + Global Hotkeys
```

- The bridge writes state to rotating sequential keys (`SBS0.plugindata`, `SBS1.plugindata`, ...) plus a sync pointer (`SBSync.plugindata`)
- The plugin reads these via `Turbine.PluginData.Load` with async callbacks
- Commands go from plugin to bridge via `SpotiBardCommand.plugindata`
- The ~15 second delay is caused by LOTRO's async PluginData callback queue

All shared files live in: `%USERPROFILE%\Documents\The Lord of the Rings Online\PluginData\<account>\AllServers\`

## Credits & License

MIT License

Built by [dp-vibes](https://github.com/dp-vibes)

Built with:
- [spotipy](https://spotipy.readthedocs.io/) — Spotify Web API for Python
- [pystray](https://github.com/moses-palmer/pystray) — System tray icons
- [keyboard](https://github.com/boppreh/keyboard) — Global hotkeys
- [Turbine](https://www.lotrointerface.com/) — LOTRO's Lua plugin API
