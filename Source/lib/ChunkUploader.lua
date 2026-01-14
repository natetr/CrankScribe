-- ChunkUploader: Manages progressive upload of compressed audio chunks
-- Uploads chunks in background while recording continues

ChunkUploader = {}

-- Configuration
local DEFAULT_SERVER_URL = "https://crankscribe-server.herokuapp.com"
local MAX_RETRIES = 3
local RETRY_DELAY_MS = 2000

-- State
local uploadQueue = {}        -- Queue of chunks waiting to upload
local currentUpload = nil     -- Currently uploading chunk
local sessionId = nil         -- Current session UUID
local serverUrl = nil         -- Configured server URL
local uploadedChunks = 0      -- Count of successfully uploaded chunks
local failedChunks = 0        -- Count of failed uploads
local totalBytesUploaded = 0  -- Total bytes sent
local isEnabled = false       -- Whether uploader is active
local callbacks = {}          -- Event callbacks

-- Generate a simple UUID
local function generateUUID()
    local template = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"
    return string.gsub(template, "[xy]", function(c)
        local v = (c == "x") and math.random(0, 15) or math.random(8, 11)
        return string.format("%x", v)
    end)
end

-- Initialize uploader with settings
function ChunkUploader.init(settings)
    serverUrl = settings and settings.serverUrl or DEFAULT_SERVER_URL
    isEnabled = serverUrl and serverUrl ~= ""
    return isEnabled
end

-- Start a new upload session
function ChunkUploader.startSession()
    if not isEnabled then
        return nil, "Uploader not enabled (no server URL)"
    end

    sessionId = generateUUID()
    uploadQueue = {}
    currentUpload = nil
    uploadedChunks = 0
    failedChunks = 0
    totalBytesUploaded = 0

    -- Enable WiFi for uploads
    if playdate.network and playdate.network.setEnabled then
        playdate.network.setEnabled(true)
    end

    return sessionId
end

-- Queue a chunk for upload
function ChunkUploader.queueChunk(compressedData, chunkSeq)
    if not isEnabled or not sessionId then
        return false
    end

    table.insert(uploadQueue, {
        data = compressedData,
        seq = chunkSeq,
        retries = 0,
        size = #compressedData
    })

    -- Start processing queue
    ChunkUploader.processQueue()
    return true
end

-- Process upload queue (called internally and from timer)
function ChunkUploader.processQueue()
    -- Skip if already uploading or queue empty
    if currentUpload or #uploadQueue == 0 then
        return
    end

    -- Skip if no network available
    if not playdate.network or not playdate.network.http then
        return
    end

    -- Get next chunk
    local chunk = table.remove(uploadQueue, 1)
    currentUpload = chunk

    -- Create HTTP request
    local url = serverUrl .. "/chunk"
    local http = playdate.network.http.new(serverUrl, 443, true)

    if not http then
        -- HTTP creation failed, requeue with retry
        chunk.retries = chunk.retries + 1
        if chunk.retries < MAX_RETRIES then
            table.insert(uploadQueue, 1, chunk)
        else
            failedChunks = failedChunks + 1
        end
        currentUpload = nil
        return
    end

    -- Set up request
    local headers = {
        ["X-Session-Id"] = sessionId,
        ["X-Chunk-Seq"] = tostring(chunk.seq),
        ["Content-Type"] = "audio/mulaw"
    }

    -- Make POST request
    http:post("/chunk", headers, chunk.data)

    -- Handle response
    http:setRequestCompleteCallback(function()
        local status = http:getResponseStatus()

        if status == 200 then
            -- Success
            uploadedChunks = uploadedChunks + 1
            totalBytesUploaded = totalBytesUploaded + chunk.size

            if callbacks.onChunkUploaded then
                callbacks.onChunkUploaded(chunk.seq, chunk.size)
            end
        else
            -- Failed - retry or give up
            chunk.retries = chunk.retries + 1
            if chunk.retries < MAX_RETRIES then
                -- Requeue for retry after delay
                playdate.timer.performAfterDelay(RETRY_DELAY_MS * chunk.retries, function()
                    table.insert(uploadQueue, 1, chunk)
                    ChunkUploader.processQueue()
                end)
            else
                failedChunks = failedChunks + 1
                if callbacks.onChunkFailed then
                    callbacks.onChunkFailed(chunk.seq, status)
                end
            end
        end

        http:close()
        currentUpload = nil

        -- Process next chunk
        ChunkUploader.processQueue()
    end)
end

-- Finalize session and get transcript
function ChunkUploader.finalize(callback)
    if not isEnabled or not sessionId then
        callback(nil, "No active session")
        return
    end

    -- Wait for queue to drain
    if #uploadQueue > 0 or currentUpload then
        playdate.timer.performAfterDelay(500, function()
            ChunkUploader.finalize(callback)
        end)
        return
    end

    -- Create finalize request
    local http = playdate.network.http.new(serverUrl, 443, true)
    if not http then
        callback(nil, "Failed to create HTTP connection")
        return
    end

    local headers = {
        ["X-Session-Id"] = sessionId,
        ["Content-Type"] = "application/json"
    }

    http:post("/finalize", headers, "")

    http:setRequestCompleteCallback(function()
        local status = http:getResponseStatus()
        local body = http:read(65536)

        http:close()
        sessionId = nil  -- Clear session

        if status == 200 then
            local success, data = pcall(json.decode, body)
            if success and data then
                callback(data.transcript, nil, data)
            else
                callback(nil, "Failed to parse response")
            end
        else
            callback(nil, "Server error: " .. tostring(status))
        end
    end)
end

-- Process transcript with LLM (summary, minutes, todos)
function ChunkUploader.process(transcript, action, callback)
    if not isEnabled then
        callback(nil, "Uploader not enabled")
        return
    end

    local http = playdate.network.http.new(serverUrl, 443, true)
    if not http then
        callback(nil, "Failed to create HTTP connection")
        return
    end

    local body = json.encode({
        action = action,
        text = transcript
    })

    local headers = {
        ["Content-Type"] = "application/json"
    }

    http:post("/process", headers, body)

    http:setRequestCompleteCallback(function()
        local status = http:getResponseStatus()
        local responseBody = http:read(65536)

        http:close()

        if status == 200 then
            local success, data = pcall(json.decode, responseBody)
            if success and data then
                callback(data.result, nil)
            else
                callback(nil, "Failed to parse response")
            end
        else
            callback(nil, "Server error: " .. tostring(status))
        end
    end)
end

-- Cancel current session
function ChunkUploader.cancel()
    sessionId = nil
    uploadQueue = {}
    currentUpload = nil
end

-- Get upload status
function ChunkUploader.getStatus()
    return {
        sessionId = sessionId,
        isUploading = currentUpload ~= nil,
        queueSize = #uploadQueue,
        uploadedChunks = uploadedChunks,
        failedChunks = failedChunks,
        totalBytesUploaded = totalBytesUploaded,
        isEnabled = isEnabled
    }
end

-- Check if uploader is enabled
function ChunkUploader.isEnabled()
    return isEnabled
end

-- Set event callbacks
function ChunkUploader.setCallbacks(cbs)
    callbacks = cbs or {}
end

-- Get progress percentage (0-100)
function ChunkUploader.getProgress()
    local total = uploadedChunks + failedChunks + #uploadQueue + (currentUpload and 1 or 0)
    if total == 0 then return 100 end
    return math.floor((uploadedChunks / total) * 100)
end
