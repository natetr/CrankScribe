-- Processing: Shows progress during transcription or AI processing

local gfx <const> = playdate.graphics

Processing = {}

-- State
local mode = "transcribe"  -- "transcribe" | "finalize" | "minutes" | "summary" | "todos"
local statusText = "Processing..."
local animFrame = 0
local animTimer = nil
local isComplete = false
local hasError = false
local errorMessage = ""
local resultText = ""

-- Upload finalization state
local uploadPhase = "waiting"  -- "waiting" | "finalizing" | "done"
local chunksQueued = 0
local sessionId = nil
local backupWavData = nil

local modeLabels = {
    transcribe = "Transcribing...",
    finalize = "Uploading...",
    minutes = "Generating Minutes...",
    summary = "Summarizing...",
    todos = "Extracting To-Dos...",
}

-- Screen lifecycle
function Processing:enter(data)
    mode = data and data.mode or "transcribe"
    statusText = modeLabels[mode] or "Processing..."
    animFrame = 0
    isComplete = false
    hasError = false
    errorMessage = ""
    resultText = ""
    uploadPhase = "waiting"
    chunksQueued = data and data.chunksQueued or 0
    sessionId = data and data.sessionId
    backupWavData = data and data.wavData

    -- Animation timer
    animTimer = playdate.timer.new(80, function()
        animFrame = (animFrame + 1) % 12
    end)
    animTimer.repeats = true

    -- Start the appropriate processing
    if mode == "finalize" then
        self:startFinalization()
    elseif mode == "transcribe" then
        self:startTranscription(data.wavData)
    else
        self:startAIProcessing(data.transcript, mode)
    end
end

function Processing:leave()
    if animTimer then
        animTimer:remove()
        animTimer = nil
    end
end

function Processing:startTranscription(wavData)
    if not wavData then
        hasError = true
        errorMessage = "No audio data"
        return
    end

    OpenAI.transcribe(wavData, function(text, err)
        if err then
            hasError = true
            errorMessage = err
        else
            isComplete = true
            resultText = text

            -- Create note and go to post-recording
            local note = NotesStore.create(text, App.currentNote and App.currentNote.duration or 0)
            App.currentNote = note

            ScreenManager:switchTo("postRecording", { note = note })
        end
    end)
end

function Processing:startAIProcessing(transcript, processingMode)
    if not transcript then
        hasError = true
        errorMessage = "No transcript"
        return
    end

    OpenAI.process(transcript, processingMode, function(result, err)
        if err then
            hasError = true
            errorMessage = err
        else
            isComplete = true
            resultText = result

            -- Update note with processed content
            if App.currentNote then
                local updateField = processingMode  -- "minutes", "summary", or "todos"
                NotesStore.update(App.currentNote.id, { [updateField] = result })
                App.currentNote[updateField] = result
            end

            -- Go to note view with processed content
            ScreenManager:switchTo("noteView", {
                note = App.currentNote,
                viewMode = processingMode
            })
        end
    end)
end

-- Start progressive upload finalization
function Processing:startFinalization()
    if not sessionId then
        hasError = true
        errorMessage = "No upload session"
        return
    end

    uploadPhase = "waiting"
    statusText = "Finishing upload..."

    -- Call finalize (will wait for queue to drain)
    ChunkUploader.finalize(function(transcript, err, metadata)
        if err then
            hasError = true
            errorMessage = err
            return
        end

        uploadPhase = "done"
        isComplete = true
        resultText = transcript

        -- Create note with transcript
        local duration = metadata and metadata.audio_duration_seconds or (App.currentNote and App.currentNote.duration or 0)
        local note = NotesStore.create(transcript, duration)
        App.currentNote = note

        -- Go to post-recording screen
        ScreenManager:switchTo("postRecording", { note = note })
    end)
end

function Processing:update()
    -- Update chunk uploader (polls HTTP state) - critical for finalize mode
    if mode == "finalize" then
        ChunkUploader.update()
    end
end

function Processing:draw()
    gfx.clear(gfx.kColorWhite)

    -- Draw header
    self:drawHeader()

    if hasError then
        self:drawError()
    else
        self:drawProgress()
    end

    -- Draw footer
    self:drawFooter()
end

function Processing:drawHeader()
    local screenWidth = 400
    local y = 10

    gfx.setColor(gfx.kColorBlack)
    gfx.setFont(gfx.getSystemFont(gfx.kFontBold))
    gfx.drawText(statusText, 15, y)

    gfx.drawLine(0, 30, screenWidth, 30)
end

function Processing:drawProgress()
    local screenWidth = 400
    local screenHeight = 240
    local centerX = screenWidth / 2
    local centerY = screenHeight / 2 - 20

    -- Animated spinner
    self:drawSpinner(centerX, centerY)

    -- Status text based on mode
    gfx.setFont(gfx.getSystemFont())
    local statusTextDisplay
    if mode == "finalize" then
        local status = ChunkUploader.getStatus()
        if status.isUploading or status.queueSize > 0 then
            statusTextDisplay = string.format("Uploading chunk %d...", status.uploadedChunks + 1)
        else
            statusTextDisplay = "Transcribing..."
        end
    else
        statusTextDisplay = "Thinking"
    end
    local dots = string.rep(".", (animFrame // 3) % 4)
    local fullText = statusTextDisplay .. dots
    local textWidth = gfx.getTextSize(fullText)
    gfx.drawText(fullText, centerX - textWidth / 2, centerY + 50)

    -- Progress bar
    local barWidth = 200
    local barHeight = 8
    local barX = (screenWidth - barWidth) / 2
    local barY = centerY + 80

    gfx.setColor(gfx.kColorBlack)
    gfx.drawRect(barX, barY, barWidth, barHeight)

    -- For finalize mode, show actual progress; otherwise indeterminate
    if mode == "finalize" then
        local status = ChunkUploader.getStatus()
        local progressPercent = ChunkUploader.getProgress() / 100
        local fillWidth = math.floor((barWidth - 4) * progressPercent)
        gfx.fillRect(barX + 2, barY + 2, fillWidth, barHeight - 4)

        -- Show upload stats
        gfx.setFont(gfx.getSystemFont())
        local statsText = string.format("Uploaded: %d chunks (%.1f KB)",
            status.uploadedChunks,
            status.totalBytesUploaded / 1024)
        local statsWidth = gfx.getTextSize(statsText)
        gfx.drawText(statsText, centerX - statsWidth / 2, barY + 15)
    else
        -- Indeterminate progress (moving indicator)
        local indicatorWidth = 40
        local progress = (animFrame / 12) * (barWidth - indicatorWidth)
        local pattern = {0xAA, 0x55, 0xAA, 0x55, 0xAA, 0x55, 0xAA, 0x55}
        gfx.setPattern(pattern)
        gfx.fillRect(barX + 2 + progress, barY + 2, indicatorWidth, barHeight - 4)
        gfx.setColor(gfx.kColorBlack)
    end
end

function Processing:drawSpinner(x, y)
    local radius = 30

    -- Draw spinning dots
    for i = 0, 7 do
        local angle = (i / 8) * 2 * math.pi - (animFrame / 12) * 2 * math.pi
        local dotX = x + math.cos(angle) * radius
        local dotY = y + math.sin(angle) * radius

        -- Fade based on position in rotation
        local alpha = ((i + animFrame) % 8) / 8
        local dotSize = 3 + alpha * 4

        gfx.setColor(gfx.kColorBlack)
        gfx.fillCircleAtPoint(dotX, dotY, dotSize)
    end

    -- Center icon (simplified robot face)
    gfx.drawRect(x - 15, y - 12, 30, 24)
    gfx.fillRect(x - 8, y - 5, 5, 5)  -- Left eye
    gfx.fillRect(x + 3, y - 5, 5, 5)  -- Right eye
    gfx.drawLine(x - 6, y + 6, x + 6, y + 6)  -- Mouth
end

function Processing:drawError()
    local screenWidth = 400
    local screenHeight = 240
    local centerY = screenHeight / 2 - 20

    gfx.setColor(gfx.kColorBlack)

    -- Error icon (X in circle)
    local iconX = screenWidth / 2
    local iconY = centerY - 10
    gfx.drawCircleAtPoint(iconX, iconY, 25)
    gfx.setLineWidth(3)
    gfx.drawLine(iconX - 12, iconY - 12, iconX + 12, iconY + 12)
    gfx.drawLine(iconX - 12, iconY + 12, iconX + 12, iconY - 12)
    gfx.setLineWidth(1)

    -- Error message
    gfx.setFont(gfx.getSystemFont(gfx.kFontBold))
    local errorTitle = "Error"
    local titleWidth = gfx.getTextSize(errorTitle)
    gfx.drawText(errorTitle, (screenWidth - titleWidth) / 2, centerY + 30)

    gfx.setFont(gfx.getSystemFont())
    -- Wrap error message if too long
    local maxWidth = 350
    local msgWidth = gfx.getTextSize(errorMessage)
    if msgWidth > maxWidth then
        -- Simple truncation for now
        errorMessage = string.sub(errorMessage, 1, 45) .. "..."
    end
    local msgWidth2 = gfx.getTextSize(errorMessage)
    gfx.drawText(errorMessage, (screenWidth - msgWidth2) / 2, centerY + 55)
end

function Processing:drawFooter()
    local screenWidth = 400
    local screenHeight = 240
    local y = screenHeight - 25

    gfx.setColor(gfx.kColorBlack)
    gfx.drawLine(0, y - 5, screenWidth, y - 5)

    gfx.setFont(gfx.getSystemFont())
    local text = hasError and "B: Back" or "B: Cancel"
    local textWidth = gfx.getTextSize(text)
    gfx.drawText(text, (screenWidth - textWidth) / 2, y)
end

-- Input handlers
function Processing:BButtonDown()
    -- Cancel/back
    OpenAI.cancel()

    -- Also cancel upload if in finalize mode
    if mode == "finalize" then
        ChunkUploader.cancel()
    end

    if hasError then
        -- Go back to previous screen
        if mode == "transcribe" or mode == "finalize" then
            ScreenManager:switchTo("mainMenu")
        else
            ScreenManager:switchTo("postRecording", { note = App.currentNote })
        end
    else
        -- Cancel in progress
        if mode == "transcribe" or mode == "finalize" then
            ScreenManager:switchTo("mainMenu")
        else
            ScreenManager:switchTo("postRecording", { note = App.currentNote })
        end
    end
end
