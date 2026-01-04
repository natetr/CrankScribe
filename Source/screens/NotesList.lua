-- NotesList: Browse saved notes (cassette tape spine style)

local gfx <const> = playdate.graphics

NotesList = {}

local notes = {}
local selectedIndex = 1
local scrollOffset = 0
local maxVisibleItems = 5
local spineHeight = 38

-- Screen lifecycle
function NotesList:enter(data)
    selectedIndex = 1
    scrollOffset = 0
    notes = NotesStore.list()
end

function NotesList:leave()
end

function NotesList:update()
    local ticks = playdate.getCrankTicks(4)
    if ticks ~= 0 and #notes > 0 then
        selectedIndex = selectedIndex + ticks
        if selectedIndex < 1 then
            selectedIndex = #notes
        elseif selectedIndex > #notes then
            selectedIndex = 1
        end

        -- Adjust scroll to keep selection visible
        if selectedIndex <= scrollOffset then
            scrollOffset = selectedIndex - 1
        elseif selectedIndex > scrollOffset + maxVisibleItems then
            scrollOffset = selectedIndex - maxVisibleItems
        end
    end
end

function NotesList:draw()
    gfx.clear(gfx.kColorWhite)

    self:drawHeader()

    if #notes == 0 then
        self:drawEmpty()
    else
        self:drawTapeSpines()
    end

    self:drawFooter()
end

function NotesList:drawHeader()
    local screenWidth = 400

    gfx.setColor(gfx.kColorBlack)
    gfx.fillRoundRect(15, 8, screenWidth - 30, 34, 6)

    gfx.setImageDrawMode(gfx.kDrawModeInverted)
    if Fonts.asheville then
        gfx.setFont(Fonts.asheville)
    else
        gfx.setFont(gfx.getSystemFont(gfx.kFontBold))
    end
    local title = "MY NOTES"
    if #notes > 0 then
        title = title .. " (" .. #notes .. ")"
    end
    local titleWidth = gfx.getTextSize(title)
    gfx.drawText(title, (screenWidth - titleWidth) / 2, 16)
    gfx.setImageDrawMode(gfx.kDrawModeCopy)
end

function NotesList:drawEmpty()
    local screenWidth = 400
    local centerY = 120

    gfx.setColor(gfx.kColorBlack)
    gfx.setFont(gfx.getSystemFont(gfx.kFontBold))

    local text1 = "No tapes yet!"
    local text1Width = gfx.getTextSize(text1)
    gfx.drawText(text1, (screenWidth - text1Width) / 2, centerY - 10)

    local text2 = "Record your first note."
    local text2Width = gfx.getTextSize(text2)
    gfx.drawText(text2, (screenWidth - text2Width) / 2, centerY + 15)
end

function NotesList:drawTapeSpines()
    local screenWidth = 400
    local startY = 48
    local spineWidth = screenWidth - 40

    gfx.setFont(gfx.getSystemFont(gfx.kFontBold))

    for i = 1, maxVisibleItems do
        local noteIndex = scrollOffset + i
        if noteIndex <= #notes then
            local note = notes[noteIndex]
            local y = startY + (i - 1) * spineHeight
            local isSelected = (noteIndex == selectedIndex)

            self:drawTapeSpine(note, 20, y, spineWidth, spineHeight - 4, isSelected)
        end
    end

    -- Scroll indicators
    if #notes > maxVisibleItems then
        gfx.setColor(gfx.kColorBlack)
        if scrollOffset > 0 then
            -- Up arrow
            gfx.fillTriangle(screenWidth - 15, startY + 5, screenWidth - 10, startY - 5, screenWidth - 5, startY + 5)
        end
        if scrollOffset + maxVisibleItems < #notes then
            -- Down arrow
            local bottomY = startY + maxVisibleItems * spineHeight - 10
            gfx.fillTriangle(screenWidth - 15, bottomY - 5, screenWidth - 10, bottomY + 5, screenWidth - 5, bottomY - 5)
        end
    end
end

function NotesList:drawTapeSpine(note, x, y, width, height, isSelected)
    gfx.setColor(gfx.kColorBlack)

    if isSelected then
        -- Selected spine - filled with white text
        gfx.fillRoundRect(x, y, width, height, 4)
        gfx.setImageDrawMode(gfx.kDrawModeInverted)
    else
        -- Unselected spine - outlined
        gfx.setLineWidth(2)
        gfx.drawRoundRect(x, y, width, height, 4)
    end

    -- Left decorative stripe (like tape spine edge)
    local stripeWidth = 8
    if isSelected then
        gfx.setColor(gfx.kColorWhite)
        gfx.fillRect(x + 3, y + 3, stripeWidth, height - 6)
    else
        gfx.setColor(gfx.kColorBlack)
        gfx.fillRect(x + 3, y + 3, stripeWidth, height - 6)
    end

    -- Date/time label
    gfx.setFont(gfx.getSystemFont(gfx.kFontBold))
    local date = NotesStore.formatDate(note.created_at)
    local duration = NotesStore.formatDuration(note.duration_seconds)
    local label = date .. "  " .. duration

    gfx.drawText(label, x + stripeWidth + 12, y + 8)

    -- Preview text (smaller, if there's room)
    local preview = NotesStore.getPreview(note, 25)
    if preview ~= "" then
        gfx.setFont(gfx.getSystemFont())
        gfx.drawText(preview, x + stripeWidth + 12, y + 22)
    end

    gfx.setImageDrawMode(gfx.kDrawModeCopy)
end

function NotesList:drawFooter()
    local screenWidth = 400
    local screenHeight = 240
    local y = screenHeight - 22

    gfx.setColor(gfx.kColorBlack)
    gfx.setFont(gfx.getSystemFont(gfx.kFontBold))
    local text = #notes > 0 and "CRANK: Scroll   A: Open   B: Back" or "B: Back"
    local textWidth = gfx.getTextSize(text)
    gfx.drawText(text, (screenWidth - textWidth) / 2, y)
end

-- Input handlers
function NotesList:AButtonDown()
    if #notes == 0 then return end

    local note = notes[selectedIndex]
    if note then
        App.currentNote = note
        ScreenManager:switchTo("postRecording", { note = note })
    end
end

function NotesList:BButtonDown()
    ScreenManager:switchTo("mainMenu")
end

function NotesList:upButtonDown()
    if #notes == 0 then return end
    selectedIndex = selectedIndex - 1
    if selectedIndex < 1 then
        selectedIndex = #notes
        scrollOffset = math.max(0, #notes - maxVisibleItems)
    end
    if selectedIndex <= scrollOffset then
        scrollOffset = selectedIndex - 1
    end
end

function NotesList:downButtonDown()
    if #notes == 0 then return end
    selectedIndex = selectedIndex + 1
    if selectedIndex > #notes then
        selectedIndex = 1
        scrollOffset = 0
    end
    if selectedIndex > scrollOffset + maxVisibleItems then
        scrollOffset = selectedIndex - maxVisibleItems
    end
end
