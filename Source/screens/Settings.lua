-- Settings: API key and preferences

local gfx <const> = playdate.graphics

Settings = {}

local settingsItems = {
    { id = "apiKey", label = "OpenAI API Key", type = "text" },
    { id = "micInput", label = "Mic Input", type = "toggle", options = { "internal", "headset" } },
}

local selectedIndex = 1
local isFirstRun = false
local isEditing = false
local showSetupInstructions = false
local editText = ""
local keyboardChars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
local charIndex = 1

-- Screen lifecycle
function Settings:enter(data)
    selectedIndex = 1
    isFirstRun = data and data.firstRun or false
    isEditing = false
    editText = ""
    charIndex = 1

    -- Show setup instructions if first run (no API key)
    if isFirstRun then
        showSetupInstructions = true
    else
        showSetupInstructions = false
    end
end

function Settings:leave()
    SettingsStore.save(App.settings)
end

function Settings:startEditing()
    local item = settingsItems[selectedIndex]
    if item.type == "text" then
        isEditing = true
        showSetupInstructions = false
        editText = App.settings[item.id] or ""
        charIndex = 1
    end
end

function Settings:stopEditing(save)
    if save then
        local item = settingsItems[selectedIndex]
        App.settings[item.id] = editText
        SettingsStore.save(App.settings)
    end
    isEditing = false
    editText = ""
end

function Settings:checkForApiKey()
    -- Re-check for api_key.txt file
    if SettingsStore.checkForApiKeyFile() then
        App.settings = SettingsStore.load()
        showSetupInstructions = false
        ScreenManager:switchTo("mainMenu")
    end
end

function Settings:update()
    if isEditing then
        local ticks = playdate.getCrankTicks(8)
        if ticks ~= 0 then
            charIndex = charIndex + ticks
            if charIndex < 1 then
                charIndex = #keyboardChars
            elseif charIndex > #keyboardChars then
                charIndex = 1
            end
        end
    elseif not showSetupInstructions then
        local ticks = playdate.getCrankTicks(4)
        if ticks ~= 0 then
            selectedIndex = selectedIndex + ticks
            if selectedIndex < 1 then
                selectedIndex = #settingsItems
            elseif selectedIndex > #settingsItems then
                selectedIndex = 1
            end
        end
    end
end

function Settings:draw()
    gfx.clear(gfx.kColorWhite)

    if showSetupInstructions then
        self:drawSetupInstructions()
    elseif isEditing then
        self:drawKeyboardMode()
    else
        self:drawSettingsMode()
    end
end

function Settings:drawSetupInstructions()
    local screenWidth = 400
    local screenHeight = 240

    -- Header
    gfx.setColor(gfx.kColorBlack)
    gfx.fillRoundRect(15, 5, screenWidth - 30, 28, 6)

    gfx.setImageDrawMode(gfx.kDrawModeInverted)
    if Fonts.asheville then
        gfx.setFont(Fonts.asheville)
    else
        gfx.setFont(gfx.getSystemFont(gfx.kFontBold))
    end
    local title = "SETUP REQUIRED"
    local titleWidth = gfx.getTextSize(title)
    gfx.drawText(title, (screenWidth - titleWidth) / 2, 10)
    gfx.setImageDrawMode(gfx.kDrawModeCopy)

    -- Instructions - compact layout
    gfx.setFont(gfx.getSystemFont(gfx.kFontBold))
    local startY = 38

    gfx.drawText("Add your OpenAI API key:", 20, startY)

    gfx.setFont(gfx.getSystemFont())
    gfx.drawText("1. Connect Playdate to computer", 25, startY + 16)
    gfx.drawText("2. Open Data > com.crankscribe.app", 25, startY + 32)

    -- Filename bold
    gfx.setFont(gfx.getSystemFont(gfx.kFontBold))
    gfx.drawText("3. Create file: api_key.txt", 25, startY + 48)

    gfx.setFont(gfx.getSystemFont())
    gfx.drawText("4. Paste your key, save, press A", 25, startY + 64)

    -- Get key hint - in a box
    local boxY = startY + 85
    gfx.setColor(gfx.kColorBlack)
    gfx.setLineWidth(2)
    gfx.drawRoundRect(15, boxY, screenWidth - 30, 38, 4)

    gfx.setFont(gfx.getSystemFont(gfx.kFontBold))
    gfx.drawText("Get a key: platform.openai.com/api-keys", 25, boxY + 12)

    -- Footer
    gfx.setColor(gfx.kColorBlack)
    gfx.drawLine(15, screenHeight - 28, screenWidth - 15, screenHeight - 28)

    gfx.setFont(gfx.getSystemFont(gfx.kFontBold))
    local footerText = "A: Check Again   B: Enter Manually"
    local footerWidth = gfx.getTextSize(footerText)
    gfx.drawText(footerText, (screenWidth - footerWidth) / 2, screenHeight - 20)
end

function Settings:drawSettingsMode()
    local screenWidth = 400
    local screenHeight = 240

    -- Header
    gfx.setColor(gfx.kColorBlack)
    gfx.fillRoundRect(15, 8, screenWidth - 30, 32, 6)

    gfx.setImageDrawMode(gfx.kDrawModeInverted)
    if Fonts.asheville then
        gfx.setFont(Fonts.asheville)
    else
        gfx.setFont(gfx.getSystemFont(gfx.kFontBold))
    end
    gfx.drawText("SETTINGS", (screenWidth - gfx.getTextSize("SETTINGS")) / 2, 15)
    gfx.setImageDrawMode(gfx.kDrawModeCopy)

    -- Settings items
    local startY = 50
    local itemHeight = 70

    for i, item in ipairs(settingsItems) do
        local y = startY + (i - 1) * itemHeight
        local isSelected = (i == selectedIndex)

        -- Label
        gfx.setFont(gfx.getSystemFont(gfx.kFontBold))
        gfx.drawText(item.label, 20, y)

        -- Value box
        local valueY = y + 25
        local valueWidth = screenWidth - 50
        local valueHeight = 28

        if isSelected then
            gfx.setColor(gfx.kColorBlack)
            gfx.fillRoundRect(20, valueY, valueWidth, valueHeight, 4)
            gfx.setImageDrawMode(gfx.kDrawModeInverted)
        else
            gfx.setColor(gfx.kColorBlack)
            gfx.setLineWidth(2)
            gfx.drawRoundRect(20, valueY, valueWidth, valueHeight, 4)
        end

        -- Value text
        gfx.setFont(gfx.getSystemFont(gfx.kFontBold))
        local value = ""
        if item.type == "text" then
            if item.id == "apiKey" then
                value = SettingsStore.maskApiKey(App.settings[item.id])
            else
                value = App.settings[item.id] or "Not set"
            end
        elseif item.type == "toggle" then
            local current = App.settings[item.id] or item.options[1]
            value = "< " .. current .. " >"
        end

        gfx.drawText(value, 30, valueY + 6)
        gfx.setImageDrawMode(gfx.kDrawModeCopy)
    end

    -- Footer
    gfx.setColor(gfx.kColorBlack)
    gfx.setLineWidth(1)
    gfx.drawLine(15, screenHeight - 35, screenWidth - 15, screenHeight - 35)

    gfx.setFont(gfx.getSystemFont(gfx.kFontBold))
    local footerText = "A: Edit   B: Back"
    local footerWidth = gfx.getTextSize(footerText)
    gfx.drawText(footerText, (screenWidth - footerWidth) / 2, screenHeight - 25)
end

function Settings:drawKeyboardMode()
    local screenWidth = 400
    local screenHeight = 240

    -- Header
    gfx.setColor(gfx.kColorBlack)
    gfx.fillRoundRect(15, 8, screenWidth - 30, 32, 6)

    gfx.setImageDrawMode(gfx.kDrawModeInverted)
    if Fonts.asheville then
        gfx.setFont(Fonts.asheville)
    else
        gfx.setFont(gfx.getSystemFont(gfx.kFontBold))
    end
    gfx.drawText("ENTER API KEY", (screenWidth - gfx.getTextSize("ENTER API KEY")) / 2, 15)
    gfx.setImageDrawMode(gfx.kDrawModeCopy)

    -- Input field
    local fieldX = 20
    local fieldY = 50
    local fieldWidth = screenWidth - 40
    local fieldHeight = 35

    gfx.setLineWidth(2)
    gfx.drawRoundRect(fieldX, fieldY, fieldWidth, fieldHeight, 4)

    -- Display text (truncated if too long)
    gfx.setFont(gfx.getSystemFont(gfx.kFontBold))
    local displayText = editText
    local maxChars = 30
    if #displayText > maxChars then
        displayText = "..." .. string.sub(displayText, -(maxChars - 3))
    end
    gfx.drawText(displayText, fieldX + 10, fieldY + 9)

    -- Blinking cursor
    if (playdate.getCurrentTimeMilliseconds() // 400) % 2 == 0 then
        local cursorX = fieldX + 10 + gfx.getTextSize(displayText)
        gfx.fillRect(cursorX + 2, fieldY + 8, 3, 18)
    end

    -- Character length indicator
    gfx.setFont(gfx.getSystemFont())
    gfx.drawText(#editText .. " chars", fieldX + fieldWidth - 70, fieldY + 12)

    -- Character selector
    local selectorY = 110
    gfx.setFont(gfx.getSystemFont(gfx.kFontBold))
    gfx.drawText("SELECT CHARACTER:", 20, selectorY)

    -- Big character display
    local charBoxY = selectorY + 30
    local charBoxSize = 50
    local charBoxX = screenWidth / 2 - charBoxSize / 2

    -- Previous char
    local prevIndex = charIndex > 1 and charIndex - 1 or #keyboardChars
    local prevChar = string.sub(keyboardChars, prevIndex, prevIndex)
    gfx.setFont(gfx.getSystemFont(gfx.kFontBold))
    gfx.drawText(prevChar, charBoxX - 50, charBoxY + 15)
    gfx.drawText("<", charBoxX - 70, charBoxY + 15)

    -- Current char (highlighted)
    gfx.setColor(gfx.kColorBlack)
    gfx.fillRoundRect(charBoxX, charBoxY, charBoxSize, charBoxSize, 6)
    gfx.setImageDrawMode(gfx.kDrawModeInverted)
    local currentChar = string.sub(keyboardChars, charIndex, charIndex)
    local charWidth = gfx.getTextSize(currentChar)
    gfx.drawText(currentChar, charBoxX + (charBoxSize - charWidth) / 2, charBoxY + 15)
    gfx.setImageDrawMode(gfx.kDrawModeCopy)

    -- Next char
    local nextIndex = charIndex < #keyboardChars and charIndex + 1 or 1
    local nextChar = string.sub(keyboardChars, nextIndex, nextIndex)
    gfx.drawText(nextChar, charBoxX + charBoxSize + 30, charBoxY + 15)
    gfx.drawText(">", charBoxX + charBoxSize + 55, charBoxY + 15)

    -- Footer
    gfx.setColor(gfx.kColorBlack)
    gfx.drawLine(15, screenHeight - 35, screenWidth - 15, screenHeight - 35)

    gfx.setFont(gfx.getSystemFont(gfx.kFontBold))
    local footerText = "A: Add   LEFT: Delete   B: Save"
    local footerWidth = gfx.getTextSize(footerText)
    gfx.drawText(footerText, (screenWidth - footerWidth) / 2, screenHeight - 25)
end

-- Input handlers
function Settings:AButtonDown()
    if showSetupInstructions then
        -- Check again for api_key.txt
        self:checkForApiKey()
    elseif isEditing then
        local char = string.sub(keyboardChars, charIndex, charIndex)
        editText = editText .. char
    else
        local item = settingsItems[selectedIndex]
        if item.type == "text" then
            self:startEditing()
        elseif item.type == "toggle" then
            local current = App.settings[item.id] or item.options[1]
            local currentIdx = 1
            for i, opt in ipairs(item.options) do
                if opt == current then
                    currentIdx = i
                    break
                end
            end
            currentIdx = currentIdx + 1
            if currentIdx > #item.options then
                currentIdx = 1
            end
            App.settings[item.id] = item.options[currentIdx]
            SettingsStore.save(App.settings)
        end
    end
end

function Settings:BButtonDown()
    if showSetupInstructions then
        -- Enter manually
        showSetupInstructions = false
        selectedIndex = 1
        self:startEditing()
    elseif isEditing then
        self:stopEditing(true)
        if isFirstRun and App.settings.apiKey and #App.settings.apiKey > 0 then
            isFirstRun = false
            ScreenManager:switchTo("mainMenu")
        end
    else
        ScreenManager:switchTo("mainMenu")
    end
end

function Settings:leftButtonDown()
    if isEditing then
        if #editText > 0 then
            editText = string.sub(editText, 1, -2)
        end
    else
        local item = settingsItems[selectedIndex]
        if item.type == "toggle" then
            self:AButtonDown()
        end
    end
end

function Settings:rightButtonDown()
    if not isEditing and not showSetupInstructions then
        local item = settingsItems[selectedIndex]
        if item.type == "toggle" then
            self:AButtonDown()
        end
    end
end

function Settings:upButtonDown()
    if not isEditing and not showSetupInstructions then
        selectedIndex = selectedIndex - 1
        if selectedIndex < 1 then
            selectedIndex = #settingsItems
        end
    end
end

function Settings:downButtonDown()
    if not isEditing and not showSetupInstructions then
        selectedIndex = selectedIndex + 1
        if selectedIndex > #settingsItems then
            selectedIndex = 1
        end
    end
end
