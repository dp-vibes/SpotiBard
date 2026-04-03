# SpotiBard

Control Spotify from inside Lord of the Rings Online — without alt-tabbing.

SpotiBard puts a floating "now playing" panel inside LOTRO showing your current track, artist, album, and playlist — plus lets you browse and switch between all your Spotify playlists without leaving the game. It also gives you **instant global keyboard shortcuts** to skip tracks, play/pause, and adjust volume, even mid-raid.

> **This is my first LOTRO plugin.** I built it because I wanted it and couldn't find anything like it. Feedback is very welcome — please be kind!

---

## Read This First

**SpotiBard is not a typical LOTRO plugin.** It has two parts:

1. **SpotiBridge** — a small companion app that runs in your Windows system tray and talks to Spotify
2. **SpotiBard plugin** — the in-game panel that shows what's playing

Both need to be running. The plugin alone does nothing without the bridge.

**You need Spotify Premium.** Free Spotify accounts can't control playback through the API. That's Spotify's rule, not ours.

**You need to set up a free Spotify Developer App.** Takes about 2 minutes. If you already have one from another project, you can reuse it.

**You need Python installed.** [Download here](https://www.python.org/downloads/) — check "Add Python to PATH" during install.

### About the In-Game Panel Delay

Let's be upfront: the in-game panel has a **~15 second delay** on display updates and button clicks. This is a hard limitation of LOTRO's plugin data system. We spent days trying every possible workaround. There is no fix — it's baked into the game engine.

**But here's the thing:** SpotiBard also gives you **global keyboard shortcuts that work instantly** — skip, pause, volume, all without leaving the game. The hotkeys are how you control things. The in-game panel is your "now playing" display that shows your track info and lets you browse your playlists.

Let's be real — the important part is seeing what's playing and being able to change it without alt-tabbing out of LOTRO. Who cares if the display takes a few seconds to catch up, right?

If you need instant everything, we're planning a standalone overlay version down the road that won't have any of these limitations. But for now, this works and it's pretty cool.

**If you're a plugin developer and know a faster way to read external data from a LOTRO Lua plugin, please reach out! We'd love to be wrong about this.**

---

## Global Hotkeys

These work **instantly**, even while LOTRO has focus:

| Shortcut | Action |
|---|---|
| `Ctrl+Alt+Right` | Next track |
| `Ctrl+Alt+Left` | Previous track |
| `Ctrl+Alt+Space` | Play / Pause |
| `Ctrl+Alt+Up` | Volume up |
| `Ctrl+Alt+Down` | Volume down |

---

## Install

### Plugin

Unzip and copy the `plugin/SpotiBard/` folder to your Plugins directory:

```
Documents\The Lord of the Rings Online\Plugins\
```

Or use [LOTRO Plugin Compendium](http://www.lotrointerface.com/downloads/info663-LOTROPluginCompendium.html) to install and keep it updated.

### Spotify Developer App (one time, ~2 minutes)

1. Go to [developer.spotify.com/dashboard](https://developer.spotify.com/dashboard) and log in with your Spotify account
2. Click **Create App**
3. Fill in:
   - **App name:** SpotiBard (or anything)
   - **App description:** anything
   - **Redirect URI:** `http://127.0.0.1:8888/callback` — copy/paste exactly, click **Add**
   - Check **Web API**, click **Save**
4. Click **Settings**, copy your **Client ID** and **Client Secret**

> Already have a Spotify Developer App from another project? Just add `http://127.0.0.1:8888/callback` to its Redirect URIs and use the same credentials.

### Bridge Setup (one time)

1. Open the `bridge/` folder
2. Double-click **`setup.bat`**
3. Paste your Client ID and Client Secret when prompted
4. A browser opens — click **Allow** to authorize
5. Done. Credentials are saved.

### Daily Use

I recommend adding SpotiBridge to your Windows Startup so you never have to think about it. Press `Win+R`, type `shell:startup`, and drop a shortcut to `bridge/run_spotibridge.bat` in there. It'll quietly start with Windows and sit in your system tray — even when you're not playing LOTRO, the keyboard shortcuts are handy for controlling Spotify from anywhere.

If you don't want it starting automatically, just double-click **`run_spotibridge.bat`** before you play. Click **Yes** on the Windows permission prompt (needed for hotkeys to work in-game).

In LOTRO: `/plugins load SpotiBard`

---

## In-Game Panel

- **Drag** the title bar to move it anywhere
- **Resize** by dragging the `///` handle in the bottom-right corner
- **Close** with the X button — it shrinks to a small "SB" icon you can click to reopen
- **Toggle** with `/spotibard` in chat
- **Browse playlists** — click "Playlists" to see all your Spotify playlists and switch between them
- Position and size are saved between sessions

---

## Known Issues / Limitations

- In-game panel updates every ~15 seconds (LOTRO engine limitation, not a bug)
- In-game buttons have the same ~15 second delay
- Plugin can't be unloaded without restarting LOTRO (timer cleanup issue)
- If you restart SpotiBridge while LOTRO is running, you need to restart LOTRO too (they lose sync)
- Long song titles get cut off — resize the panel wider to see more

---

## Troubleshooting

| Problem | Fix |
|---|---|
| "SpotiBard bridge not running" | Make sure `run_spotibridge.bat` is running (green tray icon) |
| "No active device" | Start playing something on Spotify first |
| Plugin won't load | Check plugin files are in the right folder, try `/plugins refresh` |
| Hotkeys don't work in-game | Run SpotiBridge as administrator (the bat file should prompt for this) |
| Authentication failed | Delete `bridge/.spotify_cache` and `bridge/config.json`, run setup again |
| Display stuck for over a minute | Restart SpotiBridge, then restart LOTRO |
| Debug output needed | Use `run_spotibridge_debug.bat` to see log messages |

---

## For Developers

File-based communication architecture (LOTRO's Lua sandbox blocks all network access and file I/O):

```
Spotify API  <-->  SpotiBridge (Python)  <-->  .plugindata files  <-->  LOTRO Lua Plugin
                   + Global Hotkeys
```

- Bridge writes state to rotating keys (`SBS0.plugindata`, `SBS1.plugindata`, ...) + sync pointer (`SBSync.plugindata`)
- Plugin reads via `Turbine.PluginData.Load` async callbacks
- Commands go plugin → bridge via `SpotiBardCommand.plugindata`
- ~15s delay = LOTRO's async PluginData callback queue. If you know a faster path, please open an issue.

---

## Privacy

All data stays on your computer. Nothing is uploaded, collected, or shared. Full policy: [djshiggl.es/spotibard/privacy](https://www.djshiggl.es/spotibard/privacy)

---

## Credits

This is my first LOTRO plugin. Built it because I wanted it and figured others might too. If it breaks, be gentle. If it works, tell your kinship.

MIT License — Built by [dp-vibes](https://github.com/dp-vibes)

[spotipy](https://spotipy.readthedocs.io/) | [pystray](https://github.com/moses-palmer/pystray) | [keyboard](https://github.com/boppreh/keyboard) | [Turbine](https://www.lotrointerface.com/)
