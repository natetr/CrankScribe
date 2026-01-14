-- CrankScribe: Voice-powered note-taking for Playdate
-- Main entry point and screen manager

import "CoreLibs/graphics"
import "CoreLibs/timer"
import "CoreLibs/crank"

-- Screen imports
import "screens/MainMenu"
import "screens/Recording"
import "screens/Processing"
import "screens/PostRecording"
import "screens/NotesList"
import "screens/NoteView"
import "screens/Settings"

-- Library imports
import "lib/SettingsStore"
import "lib/NotesStore"
import "lib/OpenAI"
import "lib/MicStub"        -- Provides fallback if C extension not available
import "lib/AudioRecorder"
import "lib/ChunkUploader"  -- Progressive upload manager

local gfx <const> = playdate.graphics

-- Load custom fonts
Fonts = {
    asheville = gfx.font.new("fonts/Asheville-Sans-14-Bold"),
    rains = gfx.font.new("fonts/font-rains-2x"),
}

-- Screen Manager
ScreenManager = {}
ScreenManager.screens = {}
ScreenManager.currentScreen = nil
ScreenManager.currentScreenName = nil

function ScreenManager:register(name, screen)
    self.screens[name] = screen
end

function ScreenManager:switchTo(name, data)
    if self.currentScreen and self.currentScreen.leave then
        self.currentScreen:leave()
    end

    self.currentScreenName = name
    self.currentScreen = self.screens[name]

    if self.currentScreen then
        if self.currentScreen.enter then
            self.currentScreen:enter(data)
        end
    else
        print("Warning: Screen '" .. name .. "' not found")
    end
end

function ScreenManager:getCurrentName()
    return self.currentScreenName
end

-- Global state
App = {
    currentNote = nil,      -- Note being recorded or viewed
    settings = nil,         -- User settings (loaded on init)
}

-- Initialize the app
local function init()
    -- Set up display
    gfx.setBackgroundColor(gfx.kColorWhite)
    gfx.clear()

    -- Check for api_key.txt file drop, then load settings
    SettingsStore.checkForApiKeyFile()
    App.settings = SettingsStore.load()

    -- Register all screens
    ScreenManager:register("mainMenu", MainMenu)
    ScreenManager:register("recording", Recording)
    ScreenManager:register("processing", Processing)
    ScreenManager:register("postRecording", PostRecording)
    ScreenManager:register("notesList", NotesList)
    ScreenManager:register("noteView", NoteView)
    ScreenManager:register("settings", Settings)

    -- Check if first run (no API key)
    if not App.settings.apiKey or App.settings.apiKey == "" then
        ScreenManager:switchTo("settings", { firstRun = true })
    else
        ScreenManager:switchTo("mainMenu")
    end
end

-- Main update loop
function playdate.update()
    -- Update timers
    playdate.timer.updateTimers()

    -- Update current screen
    if ScreenManager.currentScreen and ScreenManager.currentScreen.update then
        ScreenManager.currentScreen:update()
    end

    -- Draw current screen
    if ScreenManager.currentScreen and ScreenManager.currentScreen.draw then
        ScreenManager.currentScreen:draw()
    end
end

-- Input handlers - delegate to current screen
function playdate.AButtonDown()
    if ScreenManager.currentScreen and ScreenManager.currentScreen.AButtonDown then
        ScreenManager.currentScreen:AButtonDown()
    end
end

function playdate.AButtonUp()
    if ScreenManager.currentScreen and ScreenManager.currentScreen.AButtonUp then
        ScreenManager.currentScreen:AButtonUp()
    end
end

function playdate.BButtonDown()
    if ScreenManager.currentScreen and ScreenManager.currentScreen.BButtonDown then
        ScreenManager.currentScreen:BButtonDown()
    end
end

function playdate.BButtonUp()
    if ScreenManager.currentScreen and ScreenManager.currentScreen.BButtonUp then
        ScreenManager.currentScreen:BButtonUp()
    end
end

function playdate.upButtonDown()
    if ScreenManager.currentScreen and ScreenManager.currentScreen.upButtonDown then
        ScreenManager.currentScreen:upButtonDown()
    end
end

function playdate.downButtonDown()
    if ScreenManager.currentScreen and ScreenManager.currentScreen.downButtonDown then
        ScreenManager.currentScreen:downButtonDown()
    end
end

function playdate.leftButtonDown()
    if ScreenManager.currentScreen and ScreenManager.currentScreen.leftButtonDown then
        ScreenManager.currentScreen:leftButtonDown()
    end
end

function playdate.rightButtonDown()
    if ScreenManager.currentScreen and ScreenManager.currentScreen.rightButtonDown then
        ScreenManager.currentScreen:rightButtonDown()
    end
end

function playdate.cranked(change, acceleratedChange)
    if ScreenManager.currentScreen and ScreenManager.currentScreen.cranked then
        ScreenManager.currentScreen:cranked(change, acceleratedChange)
    end
end

function playdate.crankDocked()
    if ScreenManager.currentScreen and ScreenManager.currentScreen.crankDocked then
        ScreenManager.currentScreen:crankDocked()
    end
end

function playdate.crankUndocked()
    if ScreenManager.currentScreen and ScreenManager.currentScreen.crankUndocked then
        ScreenManager.currentScreen:crankUndocked()
    end
end

-- System menu
local menu = playdate.getSystemMenu()

menu:addMenuItem("Settings", function()
    ScreenManager:switchTo("settings")
end)

menu:addMenuItem("My Notes", function()
    ScreenManager:switchTo("notesList")
end)

-- Initialize on load
init()
