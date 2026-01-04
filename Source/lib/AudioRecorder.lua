-- AudioRecorder: Wrapper for the C mic extension

AudioRecorder = {}

-- Recording state
local currentRecording = nil
local recordingStartTime = nil
local chunks = {}  -- Array of WAV data chunks for long recordings

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

-- Stop recording and get WAV data
function AudioRecorder.stop()
    if not AudioRecorder.isRecording() then
        return nil, "Not recording"
    end

    -- Get any remaining audio from C extension
    local wavData, err = mic.stopRecording()

    -- Calculate total duration
    local duration = 0
    if recordingStartTime then
        duration = (playdate.getCurrentTimeMilliseconds() - recordingStartTime) / 1000
    end

    recordingStartTime = nil

    -- If we have chunks from long recording, we'd need to combine them
    -- For now, just return the final chunk
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

-- Check if a 5-minute chunk is ready
function AudioRecorder.hasChunk()
    return mic.hasChunk()
end

-- Get the ready chunk (returns WAV data, or nil if no chunk ready)
function AudioRecorder.getChunk()
    local wavData = mic.getChunk()
    if wavData then
        table.insert(chunks, wavData)
        return wavData
    end
    return nil
end

-- Get number of completed chunks
function AudioRecorder.getChunkCount()
    return #chunks
end

-- Save audio data to file
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
