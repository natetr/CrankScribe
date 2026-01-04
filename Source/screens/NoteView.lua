-- NoteView: View transcript or processed content

local gfx <const> = playdate.graphics

NoteView = {}

local note = nil
local viewMode = "transcript"  -- "transcript" | "minutes" | "summary" | "todos"
local contentLines = {}
local scrollOffset = 0
local maxVisibleLines = 8
local lineHeight = 20

local modeTitles = {
    transcript = "Transcript",
    minutes = "Meeting Minutes",
    summary = "Summary",
    todos = "To-Do List",
}

-- Screen lifecycle
function NoteView:enter(data)
    note = data and data.note or App.currentNote
    viewMode = data and data.viewMode or "transcript"
    scrollOffset = 0
    contentLines = {}

    self:wrapContent()
end

function NoteView:leave()
    -- Nothing to clean up
end

function NoteView:wrapContent()
    contentLines = {}

    if not note then return end

    -- Get content based on view mode
    local content = ""
    if viewMode == "transcript" then
        content = note.transcript or ""
    elseif viewMode == "minutes" then
        content = note.minutes or ""
    elseif viewMode == "summary" then
        content = note.summary or ""
    elseif viewMode == "todos" then
        content = note.todos or ""
    end

    if content == "" then
        table.insert(contentLines, "No content available.")
        return
    end

    -- Wrap text into lines
    local maxWidth = 370

    gfx.setFont(gfx.getSystemFont())

    -- Split by newlines first, then wrap each paragraph
    for paragraph in content:gmatch("[^\n]+") do
        local words = {}
        for word in paragraph:gmatch("%S+") do
            table.insert(words, word)
        end

        local currentLine = ""
        for _, word in ipairs(words) do
            local testLine = currentLine == "" and word or (currentLine .. " " .. word)
            local testWidth = gfx.getTextSize(testLine)

            if testWidth > maxWidth then
                if currentLine ~= "" then
                    table.insert(contentLines, currentLine)
                end
                currentLine = word
            else
                currentLine = testLine
            end
        end

        if currentLine ~= "" then
            table.insert(contentLines, currentLine)
        end

        -- Add blank line between paragraphs
        table.insert(contentLines, "")
    end

    -- Remove trailing blank line
    if #contentLines > 0 and contentLines[#contentLines] == "" then
        table.remove(contentLines)
    end
end

function NoteView:update()
    -- Handle crank for scrolling
    local change = playdate.getCrankChange()
    if change ~= 0 then
        scrollOffset = scrollOffset + change / 10
        local maxScroll = math.max(0, #contentLines - maxVisibleLines)
        scrollOffset = math.max(0, math.min(scrollOffset, maxScroll))
    end
end

function NoteView:draw()
    gfx.clear(gfx.kColorWhite)

    self:drawHeader()
    self:drawContent()
    self:drawFooter()
end

function NoteView:drawHeader()
    local screenWidth = 400
    local y = 5

    gfx.setColor(gfx.kColorBlack)
    gfx.setFont(gfx.getSystemFont(gfx.kFontBold))

    local title = modeTitles[viewMode] or "Note"
    gfx.drawText(title, 15, y)

    -- Date
    if note then
        gfx.setFont(gfx.getSystemFont())
        local date = NotesStore.formatDate(note.created_at)
        local dateWidth = gfx.getTextSize(date)
        gfx.drawText(date, screenWidth - dateWidth - 15, y)
    end

    gfx.drawLine(0, 25, screenWidth, 25)
end

function NoteView:drawContent()
    local screenWidth = 400
    local x = 15
    local startY = 35

    gfx.setFont(gfx.getSystemFont())
    gfx.setColor(gfx.kColorBlack)

    local scrollInt = math.floor(scrollOffset)
    local scrollFrac = scrollOffset - scrollInt

    for i = 1, maxVisibleLines + 1 do
        local lineIndex = scrollInt + i
        if lineIndex <= #contentLines then
            local y = startY + (i - 1) * lineHeight - scrollFrac * lineHeight
            if y >= startY - lineHeight and y < startY + maxVisibleLines * lineHeight then
                gfx.drawText(contentLines[lineIndex], x, y)
            end
        end
    end

    -- Scroll indicator
    if #contentLines > maxVisibleLines then
        local scrollBarHeight = maxVisibleLines * lineHeight
        local scrollBarY = startY
        local scrollBarX = screenWidth - 8

        local maxScroll = #contentLines - maxVisibleLines
        local scrollPercent = maxScroll > 0 and (scrollOffset / maxScroll) or 0
        local indicatorHeight = math.max(15, scrollBarHeight / #contentLines * maxVisibleLines)
        local indicatorY = scrollBarY + (scrollBarHeight - indicatorHeight) * scrollPercent

        gfx.setColor(gfx.kColorBlack)
        gfx.drawRect(scrollBarX, scrollBarY, 4, scrollBarHeight)
        gfx.fillRect(scrollBarX, indicatorY, 4, indicatorHeight)
    end
end

function NoteView:drawFooter()
    local screenWidth = 400
    local screenHeight = 240
    local y = screenHeight - 25

    gfx.setColor(gfx.kColorBlack)
    gfx.drawLine(0, y - 5, screenWidth, y - 5)

    gfx.setFont(gfx.getSystemFont())
    local text = "Crank: scroll   B: back"
    local textWidth = gfx.getTextSize(text)
    gfx.drawText(text, (screenWidth - textWidth) / 2, y)
end

-- Input handlers
function NoteView:BButtonDown()
    ScreenManager:switchTo("postRecording", { note = note })
end

function NoteView:upButtonDown()
    scrollOffset = scrollOffset - 1
    if scrollOffset < 0 then
        scrollOffset = 0
    end
end

function NoteView:downButtonDown()
    local maxScroll = math.max(0, #contentLines - maxVisibleLines)
    scrollOffset = scrollOffset + 1
    if scrollOffset > maxScroll then
        scrollOffset = maxScroll
    end
end

function NoteView:cranked(change, acceleratedChange)
    -- Handled in update via getCrankChange for smooth scrolling
end
