"""
SpotiBridge — The Python bridge between Spotify and LOTRO's SpotiBard plugin.
Runs in the Windows system tray, provides global hotkeys, and communicates
via .plugindata files in LOTRO's PluginData directory.
"""

import json
import os
import re
import sys
import time
import threading
import logging
from pathlib import Path
from io import BytesIO

import spotipy
from spotipy.oauth2 import SpotifyOAuth
from spotipy.exceptions import SpotifyException
import pystray
from PIL import Image, ImageDraw
import keyboard

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
BRIDGE_DIR = Path(__file__).parent
CONFIG_PATH = BRIDGE_DIR / "config.json"

LOTRO_DOCS = Path(os.environ["USERPROFILE"]) / "Documents" / "The Lord of the Rings Online"
PLUGIN_DATA_DIR = LOTRO_DOCS / "PluginData"
PLUGINS_DIR = LOTRO_DOCS / "Plugins" / "SpotiBard"

REDIRECT_URI = "http://127.0.0.1:8888/callback"
SCOPES = (
    "user-read-playback-state "
    "user-modify-playback-state "
    "user-read-currently-playing "
    "playlist-read-private "
    "playlist-read-collaborative"
)

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%H:%M:%S",
)
log = logging.getLogger("spotibridge")

# ---------------------------------------------------------------------------
# Lua PluginData format helpers
# ---------------------------------------------------------------------------

def lua_escape_string(s: str) -> str:
    s = s.replace("\\", "\\\\")
    s = s.replace('"', '\\"')
    s = s.replace("\n", "\\n")
    s = s.replace("\r", "\\r")
    s = s.replace("\t", "\\t")
    return s


def to_plugindata(value, indent: int = 0) -> str:
    prefix = "  " * indent
    if value is None:
        return "nil"
    elif isinstance(value, bool):
        return "true" if value else "false"
    elif isinstance(value, (int, float)):
        return str(value)
    elif isinstance(value, str):
        return f'"{lua_escape_string(value)}"'
    elif isinstance(value, list):
        if len(value) == 0:
            return "{}"
        lines = ["{\n"]
        for i, item in enumerate(value):
            lines.append(f"{prefix}  [{i + 1}] = {to_plugindata(item, indent + 1)},\n")
        lines.append(f"{prefix}}}")
        return "".join(lines)
    elif isinstance(value, dict):
        if len(value) == 0:
            return "{}"
        lines = ["{\n"]
        for k, v in value.items():
            key_str = f'["{lua_escape_string(str(k))}"]'
            lines.append(f"{prefix}  {key_str} = {to_plugindata(v, indent + 1)},\n")
        lines.append(f"{prefix}}}")
        return "".join(lines)
    return "nil"


def write_plugindata(path: Path, data) -> None:
    content = f"return \n{to_plugindata(data)}"
    tmp = path.with_suffix(".tmp")
    tmp.write_text(content, encoding="utf-8")
    tmp.replace(path)


def parse_plugindata(content: str):
    content = content.strip()
    if content.startswith("return"):
        content = content[6:].strip()
    return _parse_lua_value(content, 0)[0]


def _parse_lua_value(s: str, pos: int):
    while pos < len(s) and s[pos] in " \t\n\r":
        pos += 1
    if pos >= len(s):
        return None, pos
    c = s[pos]
    if c == '"':
        return _parse_lua_string(s, pos)
    elif c == '{':
        return _parse_lua_table(s, pos)
    elif s[pos:pos+4] == "true":
        return True, pos + 4
    elif s[pos:pos+5] == "false":
        return False, pos + 5
    elif s[pos:pos+3] == "nil":
        return None, pos + 3
    elif c in "-0123456789.":
        return _parse_lua_number(s, pos)
    return None, pos


def _parse_lua_string(s: str, pos: int):
    pos += 1
    result = []
    while pos < len(s):
        c = s[pos]
        if c == '\\':
            pos += 1
            esc = s[pos] if pos < len(s) else ''
            if esc == '"': result.append('"')
            elif esc == '\\': result.append('\\')
            elif esc == 'n': result.append('\n')
            elif esc == 'r': result.append('\r')
            elif esc == 't': result.append('\t')
            else: result.append(esc)
            pos += 1
        elif c == '"':
            pos += 1
            return ''.join(result), pos
        else:
            result.append(c)
            pos += 1
    return ''.join(result), pos


def _parse_lua_number(s: str, pos: int):
    start = pos
    if s[pos] == '-':
        pos += 1
    while pos < len(s) and s[pos] in "0123456789.eE+-":
        pos += 1
    num_str = s[start:pos]
    try:
        if '.' in num_str or 'e' in num_str or 'E' in num_str:
            return float(num_str), pos
        return int(num_str), pos
    except ValueError:
        return 0, pos


def _parse_lua_table(s: str, pos: int):
    pos += 1
    entries = {}
    max_int_key = 0
    has_string_keys = False
    while pos < len(s):
        while pos < len(s) and s[pos] in " \t\n\r,;":
            pos += 1
        if pos >= len(s) or s[pos] == '}':
            pos += 1
            break
        if s[pos] == '[':
            pos += 1
            while pos < len(s) and s[pos] in " \t\n\r":
                pos += 1
            if s[pos] == '"':
                key, pos = _parse_lua_string(s, pos)
                has_string_keys = True
            else:
                key, pos = _parse_lua_number(s, pos)
                if isinstance(key, (int, float)):
                    key = int(key)
                    max_int_key = max(max_int_key, key)
            while pos < len(s) and s[pos] in " \t\n\r":
                pos += 1
            if pos < len(s) and s[pos] == ']':
                pos += 1
            while pos < len(s) and s[pos] in " \t\n\r":
                pos += 1
            if pos < len(s) and s[pos] == '=':
                pos += 1
            value, pos = _parse_lua_value(s, pos)
            entries[key] = value
        else:
            start = pos
            while pos < len(s) and s[pos] not in " \t\n\r=":
                pos += 1
            key = s[start:pos]
            has_string_keys = True
            while pos < len(s) and s[pos] in " \t\n\r":
                pos += 1
            if pos < len(s) and s[pos] == '=':
                pos += 1
            value, pos = _parse_lua_value(s, pos)
            entries[key] = value
    if not has_string_keys and max_int_key > 0:
        result = []
        for i in range(1, max_int_key + 1):
            result.append(entries.get(i))
        return result, pos
    result = {}
    for k, v in entries.items():
        result[str(k) if isinstance(k, int) else k] = v
    return result, pos


# ---------------------------------------------------------------------------
# Find all LOTRO account PluginData directories
# ---------------------------------------------------------------------------

def get_account_dirs() -> list[Path]:
    dirs = []
    if not PLUGIN_DATA_DIR.exists():
        return dirs
    for account_dir in PLUGIN_DATA_DIR.iterdir():
        if account_dir.is_dir():
            all_servers = account_dir / "AllServers"
            if all_servers.exists():
                dirs.append(all_servers)
            else:
                all_servers.mkdir(parents=True, exist_ok=True)
                dirs.append(all_servers)
    return dirs


def write_to_all_accounts(filename: str, data) -> None:
    for account_dir in get_account_dirs():
        try:
            write_plugindata(account_dir / filename, data)
        except Exception as exc:
            log.warning("Failed to write %s to %s: %s", filename, account_dir, exc)


def read_from_any_account(filename: str):
    for account_dir in get_account_dirs():
        filepath = account_dir / filename
        if filepath.exists():
            try:
                content = filepath.read_text(encoding="utf-8")
                filepath.unlink()
                return parse_plugindata(content)
            except Exception as exc:
                log.warning("Failed to read %s from %s: %s", filename, account_dir, exc)
                try:
                    filepath.unlink()
                except Exception:
                    pass
    return None


# ---------------------------------------------------------------------------
# Config helpers
# ---------------------------------------------------------------------------

def load_config() -> dict | None:
    if CONFIG_PATH.exists():
        try:
            return json.loads(CONFIG_PATH.read_text(encoding="utf-8"))
        except Exception:
            return None
    return None


def save_config(client_id: str, client_secret: str) -> None:
    CONFIG_PATH.write_text(
        json.dumps({"client_id": client_id, "client_secret": client_secret}, indent=2),
        encoding="utf-8",
    )


def prompt_credentials_friendly() -> None:
    """First-run setup: walk the user through creating a Spotify Developer App."""
    print("""
============================================================
  SPOTIBARD - First-Time Setup
============================================================

  You need a FREE Spotify Developer App to use SpotiBard.
  This only takes about 2 minutes! Here's how:

  1. Open this link in your browser:
     https://developer.spotify.com/dashboard

  2. Log in with your regular Spotify account

  3. Click "Create App" and fill in:
     - App name: SpotiBard (or anything you like)
     - App description: anything
     - Redirect URI: http://127.0.0.1:8888/callback
       (copy/paste this EXACTLY, then click Add)
     - Check the "Web API" box
     - Click Save

  4. On your new app's page, click "Settings"

  5. You'll see your Client ID on the settings page.
     Click "View client secret" to reveal the secret.

  Copy those two values and paste them below.
============================================================
""")
    client_id = input("  Spotify Client ID: ").strip()
    client_secret = input("  Spotify Client Secret: ").strip()
    if not client_id or not client_secret:
        print("\n  ERROR: Both Client ID and Client Secret are required.")
        print("  Run this again when you have them.")
        sys.exit(1)
    save_config(client_id, client_secret)
    print("\n  Credentials saved! You won't need to do this again.")
    print()


# ---------------------------------------------------------------------------
# Spotify helpers
# ---------------------------------------------------------------------------

def build_spotify(client_id: str, client_secret: str) -> spotipy.Spotify:
    auth_manager = SpotifyOAuth(
        client_id=client_id,
        client_secret=client_secret,
        redirect_uri=REDIRECT_URI,
        scope=SCOPES,
        cache_path=str(BRIDGE_DIR / ".spotify_cache"),
    )
    return spotipy.Spotify(auth_manager=auth_manager)


# ---------------------------------------------------------------------------
# Rate limit protection
# ---------------------------------------------------------------------------
_rate_limited_until = 0.0  # time.time() when we can make API calls again

def is_rate_limited() -> bool:
    return time.time() < _rate_limited_until

def handle_rate_limit(exc: Exception) -> None:
    global _rate_limited_until
    if isinstance(exc, SpotifyException) and exc.http_status == 429:
        retry_after = int(exc.headers.get("Retry-After", 30)) if hasattr(exc, 'headers') and exc.headers else 30
        _rate_limited_until = time.time() + retry_after
        log.warning("Rate limited by Spotify. Backing off for %d seconds.", retry_after)
    elif "rate" in str(exc).lower() or "429" in str(exc):
        _rate_limited_until = time.time() + 30
        log.warning("Rate limited by Spotify. Backing off for 30 seconds.")


def get_playback_state(sp: spotipy.Spotify, cached_playlists: list[dict]) -> dict:
    empty = {
        "track": "No active device",
        "artist": "",
        "album": "",
        "is_playing": False,
        "shuffle": False,
        "playlist_name": "",
        "playlist_id": "",
        "progress_ms": 0,
        "duration_ms": 0,
    }
    if is_rate_limited():
        return empty
    try:
        pb = sp.current_playback()
        if pb is None or pb.get("item") is None:
            return empty

        item = pb["item"]
        context = pb.get("context") or {}
        playlist_name = ""
        playlist_id = ""

        if context.get("type") == "playlist":
            uri = context.get("uri", "")
            playlist_id = uri.split(":")[-1] if uri else ""
            for p in cached_playlists:
                if p["id"] == playlist_id:
                    playlist_name = p["name"]
                    break
            if not playlist_name and playlist_id:
                playlist_name = "Unknown Playlist"

        return {
            "track": item.get("name", "Unknown"),
            "artist": ", ".join(a["name"] for a in item.get("artists", [])),
            "album": item.get("album", {}).get("name", ""),
            "is_playing": pb.get("is_playing", False),
            "shuffle": pb.get("shuffle_state", False),
            "playlist_name": playlist_name,
            "playlist_id": playlist_id,
            "progress_ms": pb.get("progress_ms", 0),
            "duration_ms": item.get("duration_ms", 0),
        }
    except Exception as exc:
        handle_rate_limit(exc)
        log.warning("Failed to get playback: %s", exc)
        return empty


def fetch_playlists(sp: spotipy.Spotify) -> list[dict]:
    results: list[dict] = []
    if is_rate_limited():
        return results
    try:
        offset = 0
        while True:
            page = sp.current_user_playlists(limit=50, offset=offset)
            items = page.get("items") or []
            for pl in items:
                results.append({"name": pl["name"], "id": pl["id"]})
            if page.get("next") is None:
                break
            offset += 50
    except Exception as exc:
        log.warning("Failed to fetch playlists: %s", exc)
    return results


def handle_command(sp: spotipy.Spotify, cmd: dict) -> None:
    action = cmd.get("command", "")
    if is_rate_limited():
        log.warning("Command '%s' skipped — rate limited", action)
        return
    log.info("Command received: %s", action)
    try:
        if action == "play_pause":
            pb = sp.current_playback()
            if pb and pb.get("is_playing"):
                sp.pause_playback()
            else:
                sp.start_playback()
        elif action == "next":
            sp.next_track()
        elif action == "previous":
            sp.previous_track()
        elif action == "shuffle_toggle":
            pb = sp.current_playback()
            if pb is not None:
                current = pb.get("shuffle_state", False)
                sp.shuffle(not current)
        elif action == "play_playlist":
            playlist_id = cmd.get("playlist_id", "")
            if playlist_id:
                sp.start_playback(context_uri=f"spotify:playlist:{playlist_id}")
        else:
            log.warning("Unknown command: %s", action)
    except Exception as exc:
        handle_rate_limit(exc)
        log.warning("Command '%s' failed: %s", action, exc)


# ---------------------------------------------------------------------------
# Global Hotkeys
# ---------------------------------------------------------------------------

_last_hotkey_time: dict[str, float] = {}
HOTKEY_COOLDOWN = 1.0  # minimum seconds between presses of the same hotkey

def _hotkey_ready(name: str) -> bool:
    """Returns True if this hotkey hasn't been pressed too recently."""
    now = time.time()
    last = _last_hotkey_time.get(name, 0)
    if now - last < HOTKEY_COOLDOWN:
        return False
    _last_hotkey_time[name] = now
    return True


def register_hotkeys(sp: spotipy.Spotify) -> None:
    """Register global keyboard shortcuts for Spotify control."""

    def hotkey_next():
        if not _hotkey_ready("next"): return
        if is_rate_limited():
            log.warning("Hotkey: Rate limited, please wait")
            return
        log.info("Hotkey: Next track")
        try:
            sp.next_track()
        except Exception as exc:
            handle_rate_limit(exc)
            log.warning("Hotkey next failed: %s", exc)

    def hotkey_previous():
        if not _hotkey_ready("previous"): return
        if is_rate_limited():
            log.warning("Hotkey: Rate limited, please wait")
            return
        log.info("Hotkey: Previous track")
        try:
            sp.previous_track()
        except Exception as exc:
            handle_rate_limit(exc)
            log.warning("Hotkey previous failed: %s", exc)

    def hotkey_play_pause():
        if not _hotkey_ready("play_pause"): return
        if is_rate_limited():
            log.warning("Hotkey: Rate limited, please wait")
            return
        log.info("Hotkey: Play/Pause")
        try:
            pb = sp.current_playback()
            if pb and pb.get("is_playing"):
                sp.pause_playback()
            else:
                sp.start_playback()
        except Exception as exc:
            handle_rate_limit(exc)
            log.warning("Hotkey play/pause failed: %s", exc)

    def hotkey_volume_up():
        if not _hotkey_ready("volume_up"): return
        if is_rate_limited():
            log.warning("Hotkey: Rate limited, please wait")
            return
        log.info("Hotkey: Volume up")
        try:
            pb = sp.current_playback()
            if pb and pb.get("device"):
                vol = pb["device"].get("volume_percent", 50)
                sp.volume(min(100, vol + 10))
        except Exception as exc:
            handle_rate_limit(exc)
            log.warning("Hotkey volume up failed: %s", exc)

    def hotkey_volume_down():
        if not _hotkey_ready("volume_down"): return
        if is_rate_limited():
            log.warning("Hotkey: Rate limited, please wait")
            return
        log.info("Hotkey: Volume down")
        try:
            pb = sp.current_playback()
            if pb and pb.get("device"):
                vol = pb["device"].get("volume_percent", 50)
                sp.volume(max(0, vol - 10))
        except Exception as exc:
            handle_rate_limit(exc)
            log.warning("Hotkey volume down failed: %s", exc)

    keyboard.add_hotkey("ctrl+alt+right", hotkey_next, suppress=True)
    keyboard.add_hotkey("ctrl+alt+left", hotkey_previous, suppress=True)
    keyboard.add_hotkey("ctrl+alt+space", hotkey_play_pause, suppress=True)
    keyboard.add_hotkey("ctrl+alt+up", hotkey_volume_up, suppress=True)
    keyboard.add_hotkey("ctrl+alt+down", hotkey_volume_down, suppress=True)

    log.info("Global hotkeys registered")


# ---------------------------------------------------------------------------
# System tray icon
# ---------------------------------------------------------------------------

def create_icon_image() -> Image.Image:
    size = 64
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    draw.ellipse([4, 4, size - 4, size - 4], fill=(30, 215, 96, 255))
    draw.ellipse([16, 36, 30, 48], fill=(255, 255, 255, 255))
    draw.rectangle([28, 14, 31, 40], fill=(255, 255, 255, 255))
    draw.rectangle([31, 14, 44, 18], fill=(255, 255, 255, 255))
    draw.rectangle([40, 18, 44, 28], fill=(255, 255, 255, 255))
    return img


def run_tray(stop_event: threading.Event) -> None:
    def on_quit(icon, item):
        keyboard.unhook_all()
        stop_event.set()
        icon.stop()

    icon = pystray.Icon(
        "SpotiBridge",
        create_icon_image(),
        "SpotiBridge — Spotify ↔ LOTRO",
        menu=pystray.Menu(pystray.MenuItem("Quit SpotiBridge", on_quit)),
    )
    icon.run()


# ---------------------------------------------------------------------------
# Main loops
# ---------------------------------------------------------------------------

_cached_playlists: list[dict] = []
_playlists_lock = threading.Lock()


_state_seq = 0

def state_loop(sp: spotipy.Spotify, stop_event: threading.Event) -> None:
    global _state_seq
    while not stop_event.is_set():
        with _playlists_lock:
            pl_copy = list(_cached_playlists)
        state = get_playback_state(sp, pl_copy)
        try:
            key = f"SBS{_state_seq}.plugindata"
            write_to_all_accounts(key, state)
            write_to_all_accounts("SBSync.plugindata", {"seq": _state_seq})
            if _state_seq >= 600:
                old_key = f"SBS{_state_seq - 600}.plugindata"
                for account_dir in get_account_dirs():
                    old_file = account_dir / old_key
                    if old_file.exists():
                        try:
                            old_file.unlink()
                        except Exception:
                            pass
            _state_seq += 1
        except Exception as exc:
            log.warning("Failed to write state: %s", exc)
        stop_event.wait(1.0)


def command_loop(sp: spotipy.Spotify, stop_event: threading.Event) -> None:
    while not stop_event.is_set():
        try:
            cmd = read_from_any_account("SpotiBardCommand.plugindata")
            if cmd is not None:
                handle_command(sp, cmd)
        except Exception as exc:
            log.warning("Command loop error: %s", exc)
        stop_event.wait(0.5)


def playlist_loop(sp: spotipy.Spotify, stop_event: threading.Event) -> None:
    global _cached_playlists
    while not stop_event.is_set():
        playlists = fetch_playlists(sp)
        with _playlists_lock:
            _cached_playlists = playlists
        try:
            write_to_all_accounts("SpotiBardPlaylists.plugindata", playlists)
            log.info("Updated playlists (%d playlists)", len(playlists))
        except Exception as exc:
            log.warning("Failed to write playlists: %s", exc)
        stop_event.wait(60.0)


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main() -> None:
    setup_mode = "--setup" in sys.argv

    # Load saved credentials or prompt for them
    config = load_config()
    if config is None:
        prompt_credentials_friendly()

    config = load_config()
    client_id = config["client_id"]
    client_secret = config["client_secret"]

    # Authenticate with Spotify
    print("Authenticating with Spotify (a browser window may open)...")
    try:
        sp = build_spotify(client_id, client_secret)
        sp.current_user()
        print("Authenticated successfully!")
    except Exception as exc:
        print(f"ERROR: Spotify authentication failed: {exc}")
        print("Try deleting config.json and .spotify_cache, then run again.")
        sys.exit(1)

    # In setup mode, just do creds + auth then exit
    if setup_mode:
        print()
        print("Setup complete! SpotiBridge will now launch in the background.")
        return

    # Check that PluginData directories exist
    account_dirs = get_account_dirs()
    if not account_dirs:
        print()
        print("WARNING: No LOTRO PluginData account folders found.")
        print(f"Expected to find folders in: {PLUGIN_DATA_DIR}")
        print("Make sure you've logged into LOTRO at least once.")
        print("The bridge will keep trying...")
    else:
        print(f"Found {len(account_dirs)} LOTRO account(s)")

    # Register global hotkeys
    try:
        register_hotkeys(sp)
    except Exception as exc:
        print(f"WARNING: Could not register hotkeys: {exc}")
        print("Hotkeys will not be available. Try running as administrator.")

    print()
    print("============================================================")
    print("  SpotiBridge is running!")
    print("============================================================")
    print()
    print("  Global Hotkeys (work anytime, even in-game):")
    print("    Ctrl+Alt+Right    Next track")
    print("    Ctrl+Alt+Left     Previous track")
    print("    Ctrl+Alt+Space    Play / Pause")
    print("    Ctrl+Alt+Up       Volume up")
    print("    Ctrl+Alt+Down     Volume down")
    print()
    print("  In LOTRO: /plugins load SpotiBard")
    print("  System tray: right-click green icon to quit")
    print("============================================================")
    print()

    stop_event = threading.Event()

    threads = [
        threading.Thread(target=state_loop, args=(sp, stop_event), daemon=True),
        threading.Thread(target=command_loop, args=(sp, stop_event), daemon=True),
        threading.Thread(target=playlist_loop, args=(sp, stop_event), daemon=True),
    ]
    for t in threads:
        t.start()

    try:
        run_tray(stop_event)
    except KeyboardInterrupt:
        stop_event.set()

    keyboard.unhook_all()
    stop_event.set()
    for t in threads:
        t.join(timeout=2)
    log.info("SpotiBridge stopped.")


if __name__ == "__main__":
    main()
