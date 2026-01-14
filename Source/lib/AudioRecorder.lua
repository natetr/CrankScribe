-- AudioRecorder: Wrapper for the C mic extension
-- Provides μ-law compressed audio chunks for progressive upload

AudioRecorder = {}

-- Recording state
local currentRecording = nil
local recordingStartTime = nil
local chunks = {}  -- Array of compressed μ-law chunks for progressive upload

-- Start recording
function AudioRecorder.start()
    if AudioRecorder.isRecording() then
        return false, "Already recording"
    end

    -- Clear previous data
    chunks = {}
    currentRecording = nil
    recordingStartTime = playdate.getCurrentTimeMilliseconds()

    -- Start the C extension
    local success, err = mic.startRecording()
    if not success then
        return false, err or "Failed to start recording"
    end

    return true
end

-- Stop recording and get WAV data (8kHz, 16-bit for local backup)
function AudioRecorder.stop()
    if not AudioRecorder.isRecording() then
        return nil, "Not recording"
    end

    -- Get any remaining audio from C extension (returns WAV for backup)
    local wavData, err = mic.stopRecording()

    -- Calculate total duration
    local duration = 0
    if recordingStartTime then
        duration = (playdate.getCurrentTimeMilliseconds() - recordingStartTime) / 1000
    end

    recordingStartTime = nil

    if wavData then
        return wavData, duration
    else
        return nil, err or "No audio recorded"
    end
end

-- Check if currently recording
function AudioRecorder.isRecording()
    return mic.isRecording()
end

-- Get current mic level (0.0 - 1.0)
function AudioRecorder.getLevel()
    return mic.getLevel()
end

-- Get current recording duration in seconds
function AudioRecorder.getDuration()
    return mic.getDuration()
end

-- Check if a compressed chunk is ready (30 seconds)
function AudioRecorder.hasChunk()
    return mic.hasChunk()
end

-- Get the ready chunk (returns μ-law compressed data, or nil if no chunk ready)
-- This data should be uploaded directly to the server
function AudioRecorder.getChunk()
    local compressedData = mic.getChunk()
    if compressedData then
        table.insert(chunks, compressedData)
        return compressedData
    end
    return nil
end

-- Get current chunk sequence number (for ordering on server)
function AudioRecorder.getChunkSequence()
    return mic.getChunkSequence()
end

-- Get number of completed chunks
function AudioRecorder.getChunkCount()
    return #chunks
end

-- Enable/disable Voice Activity Detection (VAD)
-- When enabled, silence is stripped from compressed output
function AudioRecorder.setVADEnabled(enabled)
    return mic.setVADEnabled(enabled)
end

-- Save audio data to file (WAV format for backup)
function AudioRecorder.saveToFile(wavData, filename)
    if not wavData then
        return false
    end

    local file = playdate.file.open(filename, playdate.file.kFileWrite)
    if not file then
        return false
    end

    file:write(wavData)
    file:close()

    return true
end

-- Load audio data from file
function AudioRecorder.loadFromFile(filename)
    local file = playdate.file.open(filename, playdate.file.kFileRead)
    if not file then
        return nil
    end

    local data = file:read(file:getSize())
    file:close()

    return data
end

-- Get compression stats for debugging
function AudioRecorder.getCompressionInfo()
    local rawSamplesExpected = AudioRecorder.getDuration() * 8000  -- 8kHz
    local rawBytes = rawSamplesExpected * 2  -- 16-bit
    local compressedBytes = 0
    for _, chunk in ipairs(chunks) do
        compressedBytes = compressedBytes + #chunk
    end

    return {
        rawBytes = rawBytes,
        compressedBytes = compressedBytes,
        ratio = rawBytes > 0 and (compressedBytes / rawBytes) or 0,
        chunkCount = #chunks
    }
end
