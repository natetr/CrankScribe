-- SettingsStore: Persistence for user settings

SettingsStore = {}

local SETTINGS_FILE = "settings"

-- Default settings
local defaults = {
    apiKey = "",
    serverUrl = "",  -- CrankScribe transcription server URL
    micInput = "internal",  -- "internal" or "headset"
    autoSave = true,
}

-- Load settings from disk
function SettingsStore.load()
    local data = playdate.datastore.read(SETTINGS_FILE)
    if data then
        -- Merge with defaults to ensure all keys exist
        for key, value in pairs(defaults) do
            if data[key] == nil then
                data[key] = value
            end
        end
        return data
    else
        return SettingsStore.copyDefaults()
    end
end

-- Save settings to disk
function SettingsStore.save(settings)
    playdate.datastore.write(settings, SETTINGS_FILE)
end

-- Get a copy of default settings
function SettingsStore.copyDefaults()
    local copy = {}
    for key, value in pairs(defaults) do
        copy[key] = value
    end
    return copy
end

-- Clear all settings
function SettingsStore.clear()
    playdate.datastore.delete(SETTINGS_FILE)
end

-- Mask API key for display (show last 4 chars)
function SettingsStore.maskApiKey(apiKey)
    if not apiKey or #apiKey < 8 then
        return "Not set"
    end
    return string.rep("*", 12) .. string.sub(apiKey, -4)
end

-- Check for api_key.txt file and import if found
function SettingsStore.checkForApiKeyFile()
    local path = "api_key.txt"
    local file = playdate.file.open(path, playdate.file.kFileRead)
    if file then
        local key = file:read(200)  -- API keys are ~51 chars
        file:close()

        -- Clean up the key (trim whitespace/newlines)
        if key then
            key = key:match("^%s*(.-)%s*$")
            if key and #key > 20 then  -- Valid key length check
                -- Save to settings and delete the file
                local settings = SettingsStore.load()
                settings.apiKey = key
                SettingsStore.save(settings)
                playdate.file.delete(path)
                return true
            end
        end
    end
    return false
end
