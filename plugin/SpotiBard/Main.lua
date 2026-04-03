-- SpotiBard Main.lua
-- LOTRO plugin: Spotify control panel with LOTRO-native look.
-- Uses rotating PluginData keys for bridge communication.

import "Turbine";
import "Turbine.Gameplay";
import "Turbine.UI";
import "Turbine.UI.Lotro";

-- =========================================================================
-- Constants
-- =========================================================================
local DATA_SCOPE = Turbine.DataScope.Account
local DEFAULT_WIDTH = 300
local DEFAULT_HEIGHT = 225
local MIN_WIDTH = 240
local MIN_HEIGHT = 190
local BTN_SIZE = 28
local PADDING = 10
local PLAYLIST_PANEL_HEIGHT = 200
local ACTION_HOLD_TIME = 4.0  -- seconds to keep action message visible

-- Colors (warm LOTRO-friendly palette)
local COLOR_BTN = Turbine.UI.Color(0.9, 0.15, 0.13, 0.11)
local COLOR_BTN_HOVER = Turbine.UI.Color(0.9, 0.25, 0.22, 0.18)
local COLOR_TEXT = Turbine.UI.Color(1.0, 0.85, 0.78, 0.65)
local COLOR_TEXT_DIM = Turbine.UI.Color(0.7, 0.65, 0.60, 0.50)
local COLOR_TEXT_ACTION = Turbine.UI.Color(1.0, 0.95, 0.80, 0.40)
local COLOR_PROGRESS_BG = Turbine.UI.Color(0.5, 0.15, 0.13, 0.11)
local COLOR_PROGRESS_FG = Turbine.UI.Color(1.0, 0.72, 0.58, 0.28)
local COLOR_PLAYLIST_BG = Turbine.UI.Color(0.95, 0.10, 0.09, 0.08)
local COLOR_PLAYLIST_ITEM = Turbine.UI.Color(0.9, 0.15, 0.13, 0.11)
local COLOR_PLAYLIST_HOVER = Turbine.UI.Color(0.95, 0.28, 0.24, 0.18)
local COLOR_RESIZE = Turbine.UI.Color(0.6, 0.55, 0.48, 0.35)

-- =========================================================================
-- State
-- =========================================================================
local currentState = {
    track = "Waiting for bridge...",
    artist = "",
    album = "",
    is_playing = false,
    shuffle = false,
    playlist_name = "",
    playlist_id = "",
    progress_ms = 0,
    duration_ms = 0,
}
local playlists = {}
local playlistPanelOpen = false
local stateSeq = -1
local synced = false
local pollCount = 0
local callbackCount = 0
local lastFoundSeq = -1
local actionMessage = nil
local actionTime = 0  -- game time when action was triggered

-- =========================================================================
-- Persist settings
-- =========================================================================
local settings = { x = 200, y = 200, w = DEFAULT_WIDTH, h = DEFAULT_HEIGHT }

local function loadSettings()
    local data = Turbine.PluginData.Load(DATA_SCOPE, "SpotiBardSettings")
    if data then
        settings.x = data.x or 200
        settings.y = data.y or 200
        settings.w = data.w or DEFAULT_WIDTH
        settings.h = data.h or DEFAULT_HEIGHT
    end
end

local function saveSettings()
    Turbine.PluginData.Save(DATA_SCOPE, "SpotiBardSettings", settings)
end

-- =========================================================================
-- Commands with instant feedback
-- =========================================================================
local function sendCommand(cmd)
    Turbine.PluginData.Save(DATA_SCOPE, "SpotiBardCommand", cmd)
end

-- updateUI forward declaration
local updateUI

-- Snapshot of state at time of action (used to detect when change arrives)
local actionSnapshot = nil  -- { track, is_playing, playlist_id }

local function setAction(msg, snapshot)
    actionMessage = msg
    actionTime = Turbine.Engine.GetGameTime()
    actionSnapshot = snapshot
    if updateUI then updateUI() end
end

-- Check if incoming data differs from the snapshot (meaning our action took effect)
local function actionComplete(newState)
    if not actionSnapshot then return true end
    if actionSnapshot.type == "skip" then
        return newState.track ~= actionSnapshot.track
    elseif actionSnapshot.type == "playpause" then
        return newState.is_playing ~= actionSnapshot.is_playing
    elseif actionSnapshot.type == "playlist" then
        return newState.playlist_id ~= actionSnapshot.playlist_id
    end
    return true
end

local function doNext()
    sendCommand({ command = "next" })
    setAction("Skipping...", { type = "skip", track = currentState.track })
end

local function doPrevious()
    sendCommand({ command = "previous" })
    setAction("Going back...", { type = "skip", track = currentState.track })
end

local function doPlayPause()
    sendCommand({ command = "play_pause" })
    if currentState.is_playing then
        setAction("Pausing...", { type = "playpause", is_playing = currentState.is_playing })
    else
        setAction("Resuming...", { type = "playpause", is_playing = currentState.is_playing })
    end
end

local function doPlayPlaylist(name, id)
    sendCommand({ command = "play_playlist", playlist_id = id })
    setAction("Loading " .. (name or "playlist") .. "...", { type = "playlist", playlist_id = currentState.playlist_id })
end

-- =========================================================================
-- Button helper
-- =========================================================================
local function createButton(parent, x, y, w, h, text)
    local btn = Turbine.UI.Label()
    btn:SetParent(parent)
    btn:SetPosition(x, y)
    btn:SetSize(w, h)
    btn:SetBackColor(COLOR_BTN)
    btn:SetForeColor(COLOR_TEXT)
    btn:SetText(text)
    btn:SetTextAlignment(Turbine.UI.ContentAlignment.MiddleCenter)
    btn:SetMouseVisible(true)
    btn.MouseEnter = function(s, a) s:SetBackColor(COLOR_BTN_HOVER) end
    btn.MouseLeave = function(s, a) s:SetBackColor(COLOR_BTN) end
    return btn
end

-- =========================================================================
-- Main Window
-- =========================================================================
loadSettings()

mainWindow = Turbine.UI.Lotro.Window()
mainWindow:SetPosition(settings.x, settings.y)
mainWindow:SetSize(settings.w, settings.h)
mainWindow:SetText("  Spoti Bard  ")
mainWindow:SetVisible(true)
mainWindow:SetOpacity(0.95)
mainWindow:SetZOrder(100)
mainWindow:SetMinimumSize(MIN_WIDTH, MIN_HEIGHT)

mainWindow.PositionChanged = function()
    settings.x, settings.y = mainWindow:GetPosition()
    saveSettings()
end

local CONTENT_TOP = 37

-- Track info labels
local trackLabel = Turbine.UI.Label()
trackLabel:SetParent(mainWindow)
trackLabel:SetForeColor(COLOR_TEXT)
trackLabel:SetFont(Turbine.UI.Lotro.Font.Verdana16)
trackLabel:SetText("Waiting for bridge...")
trackLabel:SetTextAlignment(Turbine.UI.ContentAlignment.MiddleLeft)

local artistLabel = Turbine.UI.Label()
artistLabel:SetParent(mainWindow)
artistLabel:SetForeColor(COLOR_TEXT_DIM)
artistLabel:SetFont(Turbine.UI.Lotro.Font.Verdana14)
artistLabel:SetText("")
artistLabel:SetTextAlignment(Turbine.UI.ContentAlignment.MiddleLeft)

local albumLabel = Turbine.UI.Label()
albumLabel:SetParent(mainWindow)
albumLabel:SetForeColor(COLOR_TEXT_DIM)
albumLabel:SetFont(Turbine.UI.Lotro.Font.Verdana12)
albumLabel:SetText("")
albumLabel:SetTextAlignment(Turbine.UI.ContentAlignment.MiddleLeft)

local playlistLabel = Turbine.UI.Label()
playlistLabel:SetParent(mainWindow)
playlistLabel:SetForeColor(COLOR_TEXT_DIM)
playlistLabel:SetFont(Turbine.UI.Lotro.Font.Verdana10)
playlistLabel:SetText("")
playlistLabel:SetTextAlignment(Turbine.UI.ContentAlignment.MiddleLeft)

-- Progress bar
local progressBg = Turbine.UI.Label()
progressBg:SetParent(mainWindow)
progressBg:SetBackColor(COLOR_PROGRESS_BG)

local progressFg = Turbine.UI.Label()
progressFg:SetParent(mainWindow)
progressFg:SetBackColor(COLOR_PROGRESS_FG)

local timeLabel = Turbine.UI.Label()
timeLabel:SetParent(mainWindow)
timeLabel:SetForeColor(COLOR_TEXT_DIM)
timeLabel:SetFont(Turbine.UI.Lotro.Font.Verdana10)
timeLabel:SetText("")
timeLabel:SetTextAlignment(Turbine.UI.ContentAlignment.MiddleCenter)

-- Control buttons
local prevBtn = createButton(mainWindow, 0, 0, BTN_SIZE, BTN_SIZE, "<<")
prevBtn.MouseClick = function(s, a) doPrevious() end

local playBtn = createButton(mainWindow, 0, 0, BTN_SIZE, BTN_SIZE, "||")
playBtn.MouseClick = function(s, a) doPlayPause() end

local nextBtn = createButton(mainWindow, 0, 0, BTN_SIZE, BTN_SIZE, ">>")
nextBtn.MouseClick = function(s, a) doNext() end

-- Playlist button
local playlistBtn = createButton(mainWindow, 0, 0, 100, 22, "= Playlists")
playlistBtn:SetFont(Turbine.UI.Lotro.Font.Verdana12)

-- Playlist panel
local playlistPanel = Turbine.UI.Window()
playlistPanel:SetVisible(false)
playlistPanel:SetBackColor(COLOR_PLAYLIST_BG)
playlistPanel:SetOpacity(0.95)
playlistPanel:SetZOrder(101)

local playlistListBox = Turbine.UI.ListBox()
playlistListBox:SetParent(playlistPanel)
playlistListBox:SetPosition(4, 4)

local playlistScrollBar = Turbine.UI.Lotro.ScrollBar()
playlistScrollBar:SetParent(playlistPanel)
playlistScrollBar:SetOrientation(Turbine.UI.Orientation.Vertical)
playlistListBox:SetVerticalScrollBar(playlistScrollBar)

playlistBtn.MouseClick = function(s, a)
    playlistPanelOpen = not playlistPanelOpen
    if playlistPanelOpen then
        local wx, wy = mainWindow:GetPosition()
        local ww, wh = mainWindow:GetSize()
        playlistPanel:SetPosition(wx, wy + wh)
        playlistPanel:SetSize(ww, PLAYLIST_PANEL_HEIGHT)
        playlistListBox:SetSize(ww - 24, PLAYLIST_PANEL_HEIGHT - 8)
        playlistScrollBar:SetPosition(ww - 18, 4)
        playlistScrollBar:SetSize(14, PLAYLIST_PANEL_HEIGHT - 8)
        playlistPanel:SetVisible(true)
    else
        playlistPanel:SetVisible(false)
    end
end

-- =========================================================================
-- Resize handle (bottom-right corner)
-- =========================================================================
local resizeHandle = Turbine.UI.Label()
resizeHandle:SetParent(mainWindow)
resizeHandle:SetSize(18, 18)
resizeHandle:SetBackColor(COLOR_RESIZE)
resizeHandle:SetText("///")
resizeHandle:SetForeColor(COLOR_TEXT)
resizeHandle:SetFont(Turbine.UI.Lotro.Font.Verdana10)
resizeHandle:SetTextAlignment(Turbine.UI.ContentAlignment.MiddleCenter)
resizeHandle:SetMouseVisible(true)

local resizing = false
local resizeStartX, resizeStartY = 0, 0
local resizeStartW, resizeStartH = 0, 0

resizeHandle.MouseDown = function(s, a)
    resizing = true
    resizeStartX = a.X
    resizeStartY = a.Y
    resizeStartW, resizeStartH = mainWindow:GetSize()
end

resizeHandle.MouseMove = function(s, a)
    if resizing then
        local newW = resizeStartW + (a.X - resizeStartX)
        local newH = resizeStartH + (a.Y - resizeStartY)
        if newW < MIN_WIDTH then newW = MIN_WIDTH end
        if newH < MIN_HEIGHT then newH = MIN_HEIGHT end
        mainWindow:SetSize(newW, newH)
    end
end

resizeHandle.MouseUp = function(s, a)
    resizing = false
    settings.w, settings.h = mainWindow:GetSize()
    saveSettings()
end

-- =========================================================================
-- Layout function (called on resize and startup)
-- =========================================================================
local function layoutUI()
    local w, h = mainWindow:GetSize()
    local innerW = w - PADDING * 2

    trackLabel:SetPosition(PADDING, CONTENT_TOP)
    trackLabel:SetSize(innerW, 22)

    artistLabel:SetPosition(PADDING, CONTENT_TOP + 23)
    artistLabel:SetSize(innerW, 16)

    albumLabel:SetPosition(PADDING, CONTENT_TOP + 40)
    albumLabel:SetSize(innerW, 14)

    playlistLabel:SetPosition(PADDING, CONTENT_TOP + 55)
    playlistLabel:SetSize(innerW, 14)

    local progressY = CONTENT_TOP + 72
    progressBg:SetPosition(PADDING, progressY)
    progressBg:SetSize(innerW, 5)
    progressFg:SetPosition(PADDING, progressY)

    timeLabel:SetPosition(PADDING, progressY + 7)
    timeLabel:SetSize(innerW, 14)

    local btnY = progressY + 25
    local totalBtnWidth = BTN_SIZE * 3 + PADDING * 2
    local btnStartX = math.floor((w - totalBtnWidth) / 2)
    prevBtn:SetPosition(btnStartX, btnY)
    prevBtn:SetSize(BTN_SIZE, BTN_SIZE)
    playBtn:SetPosition(btnStartX + BTN_SIZE + PADDING, btnY)
    playBtn:SetSize(BTN_SIZE, BTN_SIZE)
    nextBtn:SetPosition(btnStartX + (BTN_SIZE + PADDING) * 2, btnY)
    nextBtn:SetSize(BTN_SIZE, BTN_SIZE)

    local plBtnY = btnY + BTN_SIZE + PADDING
    playlistBtn:SetPosition(PADDING, plBtnY)
    playlistBtn:SetSize(innerW, 22)

    -- Resize handle in bottom-right
    resizeHandle:SetPosition(w - 22, h - 22)
end

mainWindow.SizeChanged = function()
    settings.w, settings.h = mainWindow:GetSize()
    saveSettings()
    layoutUI()
end

layoutUI()

-- =========================================================================
-- Minimized icon (shows when main window is closed)
-- =========================================================================
local COLOR_MINI_BG = Turbine.UI.Color(0.85, 0.12, 0.10, 0.08)
local COLOR_MINI_HOVER = Turbine.UI.Color(0.9, 0.22, 0.18, 0.14)
local COLOR_MINI_TEXT = Turbine.UI.Color(1.0, 0.72, 0.58, 0.28)

SpotiBardMiniIcon = Turbine.UI.Window()
SpotiBardMiniIcon:SetSize(32, 32)
SpotiBardMiniIcon:SetVisible(false)
SpotiBardMiniIcon:SetOpacity(0.9)
SpotiBardMiniIcon:SetZOrder(100)

-- Bard icon image (non-interactive, just displays the icon)
local miniIconImg = Turbine.UI.Control()
miniIconImg:SetParent(SpotiBardMiniIcon)
miniIconImg:SetPosition(0, 0)
miniIconImg:SetSize(32, 32)
miniIconImg:SetBackground(0x41005e6a) -- LOTRO bard NPC icon
miniIconImg:SetMouseVisible(false) -- clicks pass through to the overlay below

-- Invisible click overlay on top (handles mouse events without affecting the icon)
local miniClickArea = Turbine.UI.Control()
miniClickArea:SetParent(SpotiBardMiniIcon)
miniClickArea:SetPosition(0, 0)
miniClickArea:SetSize(32, 32)
miniClickArea:SetMouseVisible(true)

-- Click to reopen
miniClickArea.MouseClick = function(s, a)
    mainWindow:SetVisible(true)
    SpotiBardMiniIcon:SetVisible(false)
end

-- Make mini icon draggable
local miniDragging = false
local miniDragX, miniDragY = 0, 0

miniClickArea.MouseDown = function(s, a)
    miniDragging = true
    miniDragX = a.X
    miniDragY = a.Y
end

miniClickArea.MouseMove = function(s, a)
    if miniDragging then
        local x, y = SpotiBardMiniIcon:GetPosition()
        SpotiBardMiniIcon:SetPosition(x + a.X - miniDragX, y + a.Y - miniDragY)
    end
end

miniClickArea.MouseUp = function(s, a)
    if miniDragging then
        miniDragging = false
        settings.mx, settings.my = SpotiBardMiniIcon:GetPosition()
        saveSettings()
    end
end

-- Restore mini icon position from settings
if settings.mx and settings.my then
    SpotiBardMiniIcon:SetPosition(settings.mx, settings.my)
else
    SpotiBardMiniIcon:SetPosition(settings.x, settings.y)
end

-- Block the default close — minimize to icon instead
mainWindow.Closing = function()
    mainWindow:SetVisible(false)
    playlistPanelOpen = false
    playlistPanel:SetVisible(false)
    if not settings.mx then
        settings.mx, settings.my = mainWindow:GetPosition()
    end
    SpotiBardMiniIcon:SetPosition(settings.mx or settings.x, settings.my or settings.y)
    miniIconImg:SetBackground(0x41005e6a) -- refresh bard icon
    SpotiBardMiniIcon:SetVisible(true)
end

-- =========================================================================
-- Slash command
-- =========================================================================
SpotiBardCmd = Turbine.ShellCommand()
function SpotiBardCmd:Execute(command, argStr)
    local a = ""
    if argStr then a = argStr end
    if a == "status" then
        Turbine.Shell.WriteLine("SpotiBard Status:")
        Turbine.Shell.WriteLine("  synced=" .. tostring(synced) .. " seq=" .. tostring(stateSeq))
        Turbine.Shell.WriteLine("  polls=" .. tostring(pollCount) .. " callbacks=" .. tostring(callbackCount))
        Turbine.Shell.WriteLine("  lastFound=" .. tostring(lastFoundSeq))
        Turbine.Shell.WriteLine("  track=" .. tostring(currentState.track))
    else
        if mainWindow:IsVisible() then
            mainWindow:SetVisible(false)
            playlistPanel:SetVisible(false)
            SpotiBardMiniIcon:SetVisible(true)
        else
            mainWindow:SetVisible(true)
            SpotiBardMiniIcon:SetVisible(false)
        end
    end
end
Turbine.Shell.AddCommand("spotibard", SpotiBardCmd)

-- =========================================================================
-- Populate playlist list
-- =========================================================================
local function refreshPlaylistUI()
    playlistListBox:ClearItems()
    local pw = settings.w or DEFAULT_WIDTH
    for i, pl in ipairs(playlists) do
        local item = Turbine.UI.Label()
        item:SetSize(pw - 28, 26)
        item:SetBackColor(COLOR_PLAYLIST_ITEM)
        item:SetForeColor(COLOR_TEXT)
        item:SetFont(Turbine.UI.Lotro.Font.Verdana14)
        item:SetText("   " .. (pl.name or ""))
        item:SetTextAlignment(Turbine.UI.ContentAlignment.MiddleLeft)
        item:SetMouseVisible(true)
        item.MouseEnter = function(s, a) s:SetBackColor(COLOR_PLAYLIST_HOVER) end
        item.MouseLeave = function(s, a) s:SetBackColor(COLOR_PLAYLIST_ITEM) end
        item.MouseClick = function(s, a)
            doPlayPlaylist(pl.name, pl.id)
            playlistPanelOpen = false
            playlistPanel:SetVisible(false)
        end
        playlistListBox:AddItem(item)
    end
end

-- =========================================================================
-- Format milliseconds as M:SS
-- =========================================================================
local function formatTime(ms)
    if ms == nil or ms <= 0 then return "0:00" end
    local totalSeconds = math.floor(ms / 1000)
    local minutes = math.floor(totalSeconds / 60)
    local seconds = totalSeconds % 60
    return string.format("%d:%02d", minutes, seconds)
end

-- =========================================================================
-- Update UI from state
-- =========================================================================
updateUI = function()
    -- Show action message until the actual data changes
    if actionMessage and not actionComplete(currentState) then
        trackLabel:SetText(actionMessage)
        trackLabel:SetForeColor(COLOR_TEXT_ACTION)
        artistLabel:SetText("")
        albumLabel:SetText("")
        playlistLabel:SetText("")
    else
        -- Action is complete (or no action), show real data
        if actionMessage then
            actionMessage = nil
            actionSnapshot = nil
        end
        trackLabel:SetText(currentState.track or "")
        trackLabel:SetForeColor(COLOR_TEXT)
        artistLabel:SetText(currentState.artist or "")
        albumLabel:SetText(currentState.album or "")

        local plName = currentState.playlist_name or ""
        if plName ~= "" then
            local indicator = currentState.is_playing and "> " or "|| "
            playlistLabel:SetText(indicator .. plName)
        else
            playlistLabel:SetText("")
        end
    end

    if currentState.is_playing then
        playBtn:SetText("||")
    else
        playBtn:SetText(">")
    end

    local progress = 0
    local dur = currentState.duration_ms or 0
    local prog = currentState.progress_ms or 0
    if dur > 0 then progress = prog / dur end
    local barWidth = (settings.w or DEFAULT_WIDTH) - PADDING * 2
    progressFg:SetSize(math.floor(barWidth * progress), 5)
    timeLabel:SetText(formatTime(prog) .. " / " .. formatTime(dur))
end

-- =========================================================================
-- Initial sync
-- =========================================================================
local syncData = Turbine.PluginData.Load(DATA_SCOPE, "SBSync")
if syncData and syncData.seq then
    stateSeq = syncData.seq
    synced = true
    Turbine.Shell.WriteLine("SpotiBard: Synced at seq " .. tostring(stateSeq))
    local key = "SBS" .. tostring(stateSeq)
    local data = Turbine.PluginData.Load(DATA_SCOPE, key)
    if data then
        currentState = data
        Turbine.Shell.WriteLine("SpotiBard: Now playing: " .. tostring(data.track))
    end
else
    Turbine.Shell.WriteLine("SpotiBard: Bridge not detected. Run run_spotibridge.bat first.")
end
updateUI()

local initPl = Turbine.PluginData.Load(DATA_SCOPE, "SpotiBardPlaylists")
if initPl then
    playlists = initPl
    refreshPlaylistUI()
end

-- =========================================================================
-- Timer
-- =========================================================================
SpotiBardTimer = Turbine.UI.Control()
SpotiBardTimer:SetWantsUpdates(true)
local lastPollTime = Turbine.Engine.GetGameTime()
local pollElapsed = 0

SpotiBardTimer.Update = function()
    pollCount = pollCount + 1

    local now = Turbine.Engine.GetGameTime()
    local dt = now - lastPollTime
    lastPollTime = now
    pollElapsed = pollElapsed + dt

    if pollElapsed >= 1.0 and synced then
        pollElapsed = 0
        for offset = 1, 20 do
            local trySeq = stateSeq + offset
            local key = "SBS" .. tostring(trySeq)
            Turbine.PluginData.Load(DATA_SCOPE, key, function(data)
                callbackCount = callbackCount + 1
                if data then
                    if trySeq > lastFoundSeq then
                        lastFoundSeq = trySeq
                        currentState = data
                        updateUI()
                    end
                    if trySeq > stateSeq then
                        stateSeq = trySeq
                    end
                end
            end)
        end
    end
end

Turbine.Shell.WriteLine("SpotiBard loaded. Type /spotibard to toggle.")
