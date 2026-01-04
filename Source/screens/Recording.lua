-- Recording: Cassette tape recorder style audio capture

local gfx <const> = playdate.graphics

Recording = {}

-- State
local isRecording = false
local isPaused = false
local recordingStartTime = 0
local elapsedSeconds = 0
local liveTranscript = ""
local transcriptLines = {}
local scrollOffset = 0
local maxVisibleLines = 3
local animFrame = 0
local animTimer = nil
local levelUpdateTimer = nil
local currentLevel = 0
local reelAngle = 0

-- Screen lifecycle
function Recording:enter(data)
    isRecording = false
    isPaused = false
    recordingStartTime = 0
    elapsedSeconds = 0
    liveTranscript = ""
    transcriptLines = {}
    scrollOffset = 0
    currentLevel = 0
    animFrame = 0
    reelAngle = 0

    -- Start recording immediately
    self:startRecording()

    -- Animation timer
    animTimer = playdate.timer.new(50, function()
        animFrame = (animFrame + 1) % 20
        if isRecording and not isPaused then
            reelAngle = reelAngle + 8
        end
    end)
    animTimer.repeats = true

    -- Level meter update
    levelUpdateTimer = playdate.timer.new(50, function()
        if isRecording and not isPaused then
            currentLevel = AudioRecorder.getLevel()
        end
    end)
    levelUpdateTimer.repeats = true
end

function Recording:leave()
    if isRecording then
        AudioRecorder.stop()
    end

    if animTimer then
        animTimer:remove()
        animTimer = nil
    end

    if levelUpdateTimer then
        levelUpdateTimer:remove()
        levelUpdateTimer = nil
    end
end

function Recording:startRecording()
    local success, err = AudioRecorder.start()
    if success then
        isRecording = true
        isPaused = false
        recordingStartTime = playdate.getCurrentTimeMilliseconds()
    else
        print("Recording error: " .. tostring(err))
        ScreenManager:switchTo("mainMenu")
    end
end

function Recording:stopRecording()
    if not isRecording then return end

    local wavData, duration = AudioRecorder.stop()
    isRecording = false

    if wavData then
        App.currentNote = {
            wavData = wavData,
            duration = duration or elapsedSeconds,
            transcript = liveTranscript,
        }

        ScreenManager:switchTo("processing", {
            mode = "transcribe",
            wavData = wavData,
        })
    else
        ScreenManager:switchTo("mainMenu")
    end
end

function Recording:update()
    if isRecording and not isPaused then
        elapsedSeconds = (playdate.getCurrentTimeMilliseconds() - recordingStartTime) / 1000
    end

    -- Check for completed chunks
    if isRecording and AudioRecorder.hasChunk() then
        local chunkData = AudioRecorder.getChunk()
        if chunkData then
            self:transcribeChunk(chunkData)
        end
    end

    -- Handle crank for transcript scrolling
    local ticks = playdate.getCrankTicks(6)
    if ticks ~= 0 then
        scrollOffset = scrollOffset + ticks
        local maxScroll = math.max(0, #transcriptLines - maxVisibleLines)
        scrollOffset = math.max(0, math.min(scrollOffset, maxScroll))
    end
end

function Recording:transcribeChunk(wavData)
    OpenAI.transcribe(wavData, function(text, err)
        if text then
            if liveTranscript ~= "" then
                liveTranscript = liveTranscript .. " " .. text
            else
                liveTranscript = text
            end
            self:wrapTranscript()
        end
    end)
end

function Recording:wrapTranscript()
    transcriptLines = {}
    local maxWidth = 360

    gfx.setFont(gfx.getSystemFont(gfx.kFontBold))

    local words = {}
    for word in liveTranscript:gmatch("%S+") do
        table.insert(words, word)
    end

    local currentLine = ""
    for _, word in ipairs(words) do
        local testLine = currentLine == "" and word or (currentLine .. " " .. word)
        local testWidth = gfx.getTextSize(testLine)

        if testWidth > maxWidth then
            if currentLine ~= "" then
                table.insert(transcriptLines, currentLine)
            end
            currentLine = word
        else
            currentLine = testLine
        end
    end

    if currentLine ~= "" then
        table.insert(transcriptLines, currentLine)
    end

    local maxScroll = math.max(0, #transcriptLines - maxVisibleLines)
    scrollOffset = maxScroll
end

function Recording:draw()
    gfx.clear(gfx.kColorWhite)

    -- Draw cassette tape deck
    self:drawTapeDeck()

    -- Draw transcript area
    self:drawTranscript()

    -- Draw footer
    self:drawFooter()
end

function Recording:drawTapeDeck()
    local screenWidth = 400

    -- Main cassette body
    gfx.setColor(gfx.kColorBlack)
    gfx.setLineWidth(3)
    gfx.drawRoundRect(15, 10, screenWidth - 30, 100, 8)

    -- Inner tape window
    gfx.setLineWidth(2)
    gfx.drawRoundRect(30, 25, screenWidth - 60, 55, 4)

    -- Draw spinning reels
    self:drawReel(90, 52, 22)
    self:drawReel(310, 52, 22)

    -- Tape between reels
    gfx.setLineWidth(1)
    gfx.drawLine(112, 52, 288, 52)
    gfx.drawLine(112, 56, 288, 56)

    -- Recording head area
    gfx.fillRect(185, 65, 30, 12)

    -- REC indicator with pulse
    local recX = 25
    local recY = 85
    if isRecording and not isPaused then
        if animFrame < 15 then
            gfx.fillCircleAtPoint(recX + 8, recY + 8, 6)
        else
            gfx.drawCircleAtPoint(recX + 8, recY + 8, 6)
        end
    else
        gfx.drawCircleAtPoint(recX + 8, recY + 8, 6)
    end

    gfx.setFont(gfx.getSystemFont(gfx.kFontBold))
    local statusText = isPaused and "PAUSE" or "REC"
    gfx.drawText(statusText, recX + 20, recY + 1)

    -- Timer display (digital clock style)
    local minutes = math.floor(elapsedSeconds / 60)
    local seconds = math.floor(elapsedSeconds % 60)
    local timeText = string.format("%02d:%02d", minutes, seconds)

    -- Timer box
    local timerX = screenWidth - 100
    gfx.fillRoundRect(timerX, 82, 75, 22, 4)
    gfx.setImageDrawMode(gfx.kDrawModeInverted)
    gfx.setFont(gfx.getSystemFont(gfx.kFontBold))
    local timeWidth = gfx.getTextSize(timeText)
    gfx.drawText(timeText, timerX + (75 - timeWidth) / 2, 85)
    gfx.setImageDrawMode(gfx.kDrawModeCopy)

    -- VU Meter
    self:drawVUMeter(140, 82, 120, 20)
end

function Recording:drawReel(cx, cy, radius)
    gfx.setColor(gfx.kColorBlack)

    -- Outer circle
    gfx.setLineWidth(2)
    gfx.drawCircleAtPoint(cx, cy, radius)

    -- Inner hub
    gfx.fillCircleAtPoint(cx, cy, 6)

    -- Spokes (rotating)
    local numSpokes = 3
    for i = 0, numSpokes - 1 do
        local angle = math.rad(reelAngle + i * (360 / numSpokes))
        local x1 = cx + math.cos(angle) * 8
        local y1 = cy + math.sin(angle) * 8
        local x2 = cx + math.cos(angle) * (radius - 4)
        local y2 = cy + math.sin(angle) * (radius - 4)
        gfx.setLineWidth(3)
        gfx.drawLine(x1, y1, x2, y2)
    end

    -- Tape amount (outer ring thickness varies)
    gfx.setLineWidth(1)
    gfx.drawCircleAtPoint(cx, cy, radius - 6)
end

function Recording:drawVUMeter(x, y, width, height)
    gfx.setColor(gfx.kColorBlack)
    gfx.setLineWidth(2)
    gfx.drawRect(x, y, width, height)

    -- VU meter segments
    local numSegments = 12
    local segmentWidth = (width - 10) / numSegments
    local activeSegments = math.floor(currentLevel * numSegments)

    for i = 0, numSegments - 1 do
        local segX = x + 5 + i * segmentWidth
        if i < activeSegments then
            -- Filled segment
            gfx.fillRect(segX, y + 4, segmentWidth - 2, height - 8)
        else
            -- Empty segment (dithered)
            local pattern = {0xAA, 0x55, 0xAA, 0x55, 0xAA, 0x55, 0xAA, 0x55}
            gfx.setPattern(pattern)
            gfx.fillRect(segX, y + 4, segmentWidth - 2, height - 8)
            gfx.setColor(gfx.kColorBlack)
        end
    end

    -- No VU label - cleaner look
end

function Recording:drawTranscript()
    local screenWidth = 400
    local startY = 120
    local lineHeight = 22

    gfx.setColor(gfx.kColorBlack)
    gfx.setLineWidth(1)
    gfx.drawLine(15, startY - 5, screenWidth - 15, startY - 5)

    gfx.setFont(gfx.getSystemFont(gfx.kFontBold))

    if #transcriptLines == 0 then
        local dots = string.rep(".", (animFrame // 5) % 4)
        gfx.drawText("Listening" .. dots, 20, startY + 15)
    else
        for i = 1, maxVisibleLines do
            local lineIndex = scrollOffset + i
            if lineIndex <= #transcriptLines then
                local y = startY + (i - 1) * lineHeight
                gfx.drawText(transcriptLines[lineIndex], 20, y)
            end
        end

        -- Scroll indicator
        if #transcriptLines > maxVisibleLines then
            local scrollBarHeight = maxVisibleLines * lineHeight
            local scrollBarY = startY
            local scrollBarX = screenWidth - 15

            local maxScroll = #transcriptLines - maxVisibleLines
            local scrollPercent = maxScroll > 0 and (scrollOffset / maxScroll) or 0
            local indicatorHeight = 15
            local indicatorY = scrollBarY + (scrollBarHeight - indicatorHeight) * scrollPercent

            gfx.drawRect(scrollBarX, scrollBarY, 4, scrollBarHeight)
            gfx.fillRect(scrollBarX, indicatorY, 4, indicatorHeight)
        end
    end
end

function Recording:drawFooter()
    local screenWidth = 400
    local screenHeight = 240
    local y = screenHeight - 30

    gfx.setColor(gfx.kColorBlack)
    gfx.setLineWidth(2)
    gfx.drawLine(15, y - 5, screenWidth - 15, y - 5)

    -- Transport controls style
    gfx.setFont(gfx.getSystemFont(gfx.kFontBold))

    -- Pause button
    gfx.drawRect(30, y, 24, 20)
    gfx.fillRect(36, y + 4, 4, 12)
    gfx.fillRect(44, y + 4, 4, 12)
    gfx.drawText("A", 58, y + 3)

    -- Stop button
    gfx.drawRect(100, y, 24, 20)
    gfx.fillRect(106, y + 4, 12, 12)
    gfx.drawText("B", 128, y + 3)

    -- Crank hint
    gfx.drawText("CRANK: Scroll", screenWidth - 130, y + 3)
end

-- Input handlers
function Recording:AButtonDown()
    if isRecording then
        isPaused = not isPaused
    end
end

function Recording:BButtonDown()
    self:stopRecording()
end
