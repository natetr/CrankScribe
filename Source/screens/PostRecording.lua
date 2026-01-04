-- PostRecording: Action menu after recording is complete

local gfx <const> = playdate.graphics

PostRecording = {}

local menuItems = {
    { id = "view", label = "View Transcript" },
    { id = "minutes", label = "Meeting Minutes" },
    { id = "summary", label = "Summarize" },
    { id = "todos", label = "Make To-Do List" },
    { id = "delete", label = "Delete" },
}

local selectedIndex = 1
local note = nil
local showDeleteConfirm = false

-- Screen lifecycle
function PostRecording:enter(data)
    selectedIndex = 1
    showDeleteConfirm = false
    note = data and data.note or App.currentNote
end

function PostRecording:leave()
    -- Nothing to clean up
end

function PostRecording:update()
    -- Handle crank for menu navigation
    if not showDeleteConfirm then
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
end

function PostRecording:draw()
    gfx.clear(gfx.kColorWhite)

    if showDeleteConfirm then
        self:drawDeleteConfirm()
    else
        self:drawHeader()
        self:drawMenu()
        self:drawFooter()
    end
end

function PostRecording:drawHeader()
    local screenWidth = 400
    local y = 10

    gfx.setColor(gfx.kColorBlack)
    gfx.setFont(gfx.getSystemFont(gfx.kFontBold))

    local headerText = "Recording saved!"
    gfx.drawText(headerText, 15, y)

    -- Duration
    if note and note.duration_seconds then
        local duration = NotesStore.formatDuration(note.duration_seconds)
        gfx.setFont(gfx.getSystemFont())
        local durationText = "(" .. duration .. ")"
        local textWidth = gfx.getTextSize(durationText)
        gfx.drawText(durationText, screenWidth - textWidth - 15, y)
    end

    gfx.drawLine(0, 30, screenWidth, 30)
end

function PostRecording:drawMenu()
    local screenWidth = 400
    local startY = 45
    local itemHeight = 36
    local itemWidth = 250

    gfx.setFont(gfx.getSystemFont())

    for i, item in ipairs(menuItems) do
        local y = startY + (i - 1) * itemHeight
        local x = (screenWidth - itemWidth) / 2

        local isSelected = (i == selectedIndex)

        -- Draw item background
        if isSelected then
            gfx.setColor(gfx.kColorBlack)
            gfx.fillRoundRect(x, y, itemWidth, 30, 4)
            gfx.setImageDrawMode(gfx.kDrawModeInverted)
        else
            gfx.setColor(gfx.kColorBlack)
            gfx.setLineWidth(2)
            gfx.drawRoundRect(x, y, itemWidth, 30, 4)
            gfx.setImageDrawMode(gfx.kDrawModeCopy)
        end

        -- Draw label
        local labelWidth = gfx.getTextSize(item.label)
        local labelX = x + (itemWidth - labelWidth) / 2
        local labelY = y + 7
        gfx.drawText(item.label, labelX, labelY)

        -- Draw selection indicator
        if isSelected then
            local indicatorX = x - 20
            gfx.setImageDrawMode(gfx.kDrawModeCopy)
            gfx.drawText(">", indicatorX, labelY)
        end

        gfx.setImageDrawMode(gfx.kDrawModeCopy)
    end
end

function PostRecording:drawDeleteConfirm()
    local screenWidth = 400
    local screenHeight = 240

    -- Darken background with pattern
    local pattern = {0xAA, 0x55, 0xAA, 0x55, 0xAA, 0x55, 0xAA, 0x55}
    gfx.setPattern(pattern)
    gfx.fillRect(0, 0, screenWidth, screenHeight)

    -- Dialog box
    local dialogWidth = 280
    local dialogHeight = 120
    local dialogX = (screenWidth - dialogWidth) / 2
    local dialogY = (screenHeight - dialogHeight) / 2

    gfx.setColor(gfx.kColorWhite)
    gfx.fillRect(dialogX, dialogY, dialogWidth, dialogHeight)
    gfx.setColor(gfx.kColorBlack)
    gfx.setLineWidth(3)
    gfx.drawRect(dialogX, dialogY, dialogWidth, dialogHeight)

    -- Warning text
    gfx.setFont(gfx.getSystemFont(gfx.kFontBold))
    local title = "Delete Recording?"
    local titleWidth = gfx.getTextSize(title)
    gfx.drawText(title, (screenWidth - titleWidth) / 2, dialogY + 20)

    gfx.setFont(gfx.getSystemFont())
    local msg = "This cannot be undone."
    local msgWidth = gfx.getTextSize(msg)
    gfx.drawText(msg, (screenWidth - msgWidth) / 2, dialogY + 45)

    -- Buttons
    local buttonY = dialogY + 80
    local buttonWidth = 100
    local buttonHeight = 28

    -- Delete button
    local deleteX = dialogX + 30
    gfx.setColor(gfx.kColorBlack)
    gfx.fillRoundRect(deleteX, buttonY, buttonWidth, buttonHeight, 4)
    gfx.setImageDrawMode(gfx.kDrawModeInverted)
    gfx.drawText("A: Delete", deleteX + 12, buttonY + 6)
    gfx.setImageDrawMode(gfx.kDrawModeCopy)

    -- Cancel button
    local cancelX = dialogX + dialogWidth - buttonWidth - 30
    gfx.drawRoundRect(cancelX, buttonY, buttonWidth, buttonHeight, 4)
    gfx.drawText("B: Cancel", cancelX + 10, buttonY + 6)
end

function PostRecording:drawFooter()
    local screenWidth = 400
    local screenHeight = 240
    local y = screenHeight - 25

    gfx.setColor(gfx.kColorBlack)
    gfx.drawLine(0, y - 5, screenWidth, y - 5)

    gfx.setFont(gfx.getSystemFont())
    local text = "Crank: scroll   A: select   B: home"
    local textWidth = gfx.getTextSize(text)
    gfx.drawText(text, (screenWidth - textWidth) / 2, y)
end

-- Input handlers
function PostRecording:AButtonDown()
    if showDeleteConfirm then
        -- Confirm delete
        if note then
            NotesStore.delete(note.id)
        end
        App.currentNote = nil
        ScreenManager:switchTo("mainMenu")
        return
    end

    local item = menuItems[selectedIndex]
    if not item or not note then return end

    if item.id == "view" then
        ScreenManager:switchTo("noteView", {
            note = note,
            viewMode = "transcript"
        })
    elseif item.id == "minutes" then
        ScreenManager:switchTo("processing", {
            mode = "minutes",
            transcript = note.transcript
        })
    elseif item.id == "summary" then
        ScreenManager:switchTo("processing", {
            mode = "summary",
            transcript = note.transcript
        })
    elseif item.id == "todos" then
        ScreenManager:switchTo("processing", {
            mode = "todos",
            transcript = note.transcript
        })
    elseif item.id == "delete" then
        showDeleteConfirm = true
    end
end

function PostRecording:BButtonDown()
    if showDeleteConfirm then
        showDeleteConfirm = false
    else
        ScreenManager:switchTo("mainMenu")
    end
end

function PostRecording:upButtonDown()
    if showDeleteConfirm then return end
    selectedIndex = selectedIndex - 1
    if selectedIndex < 1 then
        selectedIndex = #menuItems
    end
end

function PostRecording:downButtonDown()
    if showDeleteConfirm then return end
    selectedIndex = selectedIndex + 1
    if selectedIndex > #menuItems then
        selectedIndex = 1
    end
end

function PostRecording:cranked(change, acceleratedChange)
    -- Handled in update via getCrankTicks
end
