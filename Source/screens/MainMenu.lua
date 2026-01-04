-- MainMenu: Home screen with cassette recorder aesthetic

local gfx <const> = playdate.graphics

MainMenu = {}

local menuItems = {
    { id = "record", label = "RECORD" },
    { id = "notes", label = "MY NOTES" },
    { id = "settings", label = "SETTINGS" },
}

local selectedIndex = 1

-- Screen lifecycle
function MainMenu:enter(data)
    selectedIndex = 1
end

function MainMenu:leave()
end

function MainMenu:update()
    local ticks = playdate.getCrankTicks(4)
    if ticks ~= 0 then
        selectedIndex = selectedIndex + ticks
        if selectedIndex < 1 then
            selectedIndex = #menuItems
        elseif selectedIndex > #menuItems then
            selectedIndex = 1
        end
    end
end

function MainMenu:draw()
    gfx.clear(gfx.kColorWhite)

    self:drawHeader()
    self:drawMenu()
    self:drawFooter()
end

function MainMenu:drawHeader()
    local screenWidth = 400

    gfx.setColor(gfx.kColorBlack)

    -- Title banner
    local titleY = 12
    gfx.fillRoundRect(15, titleY, screenWidth - 30, 40, 6)

    gfx.setImageDrawMode(gfx.kDrawModeInverted)
    if Fonts.asheville then
        gfx.setFont(Fonts.asheville)
    else
        gfx.setFont(gfx.getSystemFont(gfx.kFontBold))
    end
    local title = "CRANKSCRIBE"
    local titleWidth = gfx.getTextSize(title)
    gfx.drawText(title, (screenWidth - titleWidth) / 2, titleY + 8)
    gfx.setImageDrawMode(gfx.kDrawModeCopy)
end

function MainMenu:drawMenu()
    local screenWidth = 400
    local startY = 70
    local itemHeight = 45
    local itemWidth = 220

    if Fonts.asheville then
        gfx.setFont(Fonts.asheville)
    else
        gfx.setFont(gfx.getSystemFont(gfx.kFontBold))
    end

    for i, item in ipairs(menuItems) do
        local y = startY + (i - 1) * itemHeight
        local x = (screenWidth - itemWidth) / 2
        local isSelected = (i == selectedIndex)

        if isSelected then
            -- Selected item - filled box
            gfx.setColor(gfx.kColorBlack)
            gfx.fillRoundRect(x, y, itemWidth, 38, 6)

            -- Selection arrow
            gfx.fillTriangle(x - 20, y + 13, x - 20, y + 25, x - 8, y + 19)

            gfx.setImageDrawMode(gfx.kDrawModeInverted)
            local labelWidth = gfx.getTextSize(item.label)
            gfx.drawText(item.label, x + (itemWidth - labelWidth) / 2, y + 8)
            gfx.setImageDrawMode(gfx.kDrawModeCopy)
        else
            -- Unselected item - outline
            gfx.setColor(gfx.kColorBlack)
            gfx.setLineWidth(3)
            gfx.drawRoundRect(x, y, itemWidth, 38, 6)

            local labelWidth = gfx.getTextSize(item.label)
            gfx.drawText(item.label, x + (itemWidth - labelWidth) / 2, y + 8)
        end
    end
end

function MainMenu:drawFooter()
    local screenWidth = 400
    local screenHeight = 240
    local y = screenHeight - 25

    gfx.setColor(gfx.kColorBlack)
    gfx.setFont(gfx.getSystemFont(gfx.kFontBold))
    local text = "CRANK: Select   A: Go"
    local textWidth = gfx.getTextSize(text)
    gfx.drawText(text, (screenWidth - textWidth) / 2, y)
end

-- Input handlers
function MainMenu:AButtonDown()
    local item = menuItems[selectedIndex]
    if not item then return end

    if item.id == "record" then
        ScreenManager:switchTo("recording")
    elseif item.id == "notes" then
        ScreenManager:switchTo("notesList")
    elseif item.id == "settings" then
        ScreenManager:switchTo("settings")
    end
end

function MainMenu:upButtonDown()
    selectedIndex = selectedIndex - 1
    if selectedIndex < 1 then
        selectedIndex = #menuItems
    end
end

function MainMenu:downButtonDown()
    selectedIndex = selectedIndex + 1
    if selectedIndex > #menuItems then
        selectedIndex = 1
    end
end
