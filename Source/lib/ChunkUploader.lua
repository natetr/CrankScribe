-- ChunkUploader: Manages progressive upload of compressed audio chunks
-- Uses polling-based HTTP (Playdate SDK 3.0.2 API)

ChunkUploader = {}

-- Configuration
local MAX_RETRIES = 3
local TIMEOUT_MS = 30000  -- 30 second timeout

-- State
local uploadQueue = {}        -- Queue of chunks waiting to upload
local sessionId = nil         -- Current session UUID
local serverUrl = nil         -- Configured server URL
local uploadedChunks = 0      -- Count of successfully uploaded chunks
local failedChunks = 0        -- Count of failed uploads
local totalBytesUploaded = 0  -- Total bytes sent
local isEnabled = false       -- Whether uploader is active

-- HTTP state machine
local httpConnection = nil    -- Current HTTP connection
local httpState = "idle"      -- "idle" | "uploading" | "finalizing"
local currentChunk = nil      -- Chunk being uploaded
local requestStartTime = 0    -- For timeout tracking
local finalizeCallback = nil  -- Callback for finalize completion

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
    serverUrl = settings and settings.serverUrl
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
    httpConnection = nil
    httpState = "idle"
    currentChunk = nil
    uploadedChunks = 0
    failedChunks = 0
    totalBytesUploaded = 0
    finalizeCallback = nil

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

    return true
end

-- Start uploading the next chunk in queue
local function startNextUpload()
    if #uploadQueue == 0 or httpConnection then
        return
    end

    -- Check network availability
    if not playdate.network or not playdate.network.http then
        print("ChunkUploader: Network not available")
        return
    end

    currentChunk = table.remove(uploadQueue, 1)

    -- Parse server URL for host
    local host = serverUrl:match("https?://([^/]+)")
    if not host then
        print("ChunkUploader: Invalid server URL: " .. tostring(serverUrl))
        failedChunks = failedChunks + 1
        currentChunk = nil
        return
    end

    -- Create HTTP connection
    httpConnection = playdate.network.http.new(host, 443, true)
    if not httpConnection then
        print("ChunkUploader: Failed to create HTTP connection")
        -- Retry
        currentChunk.retries = currentChunk.retries + 1
        if currentChunk.retries < MAX_RETRIES then
            table.insert(uploadQueue, 1, currentChunk)
        else
            failedChunks = failedChunks + 1
        end
        currentChunk = nil
        return
    end

    -- Set up headers
    local headers = {
        ["X-Session-Id"] = sessionId,
        ["X-Chunk-Seq"] = tostring(currentChunk.seq),
        ["Content-Type"] = "audio/mulaw"
    }

    -- Make POST request
    print("ChunkUploader: Uploading chunk " .. currentChunk.seq .. " (" .. currentChunk.size .. " bytes)")
    httpConnection:post("/chunk", headers, currentChunk.data)

    httpState = "uploading"
    requestStartTime = playdate.getCurrentTimeMilliseconds()
end

-- Start finalize request
local function startFinalizeRequest()
    if httpConnection then
        return  -- Already have a connection in progress
    end

    -- Check network availability
    if not playdate.network or not playdate.network.http then
        if finalizeCallback then
            finalizeCallback(nil, "Network not available")
            finalizeCallback = nil
        end
        return
    end

    -- Parse server URL for host
    local host = serverUrl:match("https?://([^/]+)")
    if not host then
        if finalizeCallback then
            finalizeCallback(nil, "Invalid server URL")
            finalizeCallback = nil
        end
        return
    end

    -- Create HTTP connection
    httpConnection = playdate.network.http.new(host, 443, true)
    if not httpConnection then
        if finalizeCallback then
            finalizeCallback(nil, "Failed to create HTTP connection")
            finalizeCallback = nil
        end
        return
    end

    -- Set up headers
    local headers = {
        ["X-Session-Id"] = sessionId,
        ["Content-Type"] = "application/json"
    }

    -- Make POST request
    print("ChunkUploader: Calling /finalize for session " .. sessionId)
    httpConnection:post("/finalize", headers, "")

    httpState = "finalizing"
    requestStartTime = playdate.getCurrentTimeMilliseconds()
end

-- Update function - MUST be called every frame
function ChunkUploader.update()
    if not isEnabled then return end

    local now = playdate.getCurrentTimeMilliseconds()

    if httpState == "idle" then
        -- Start next upload if queue not empty
        if #uploadQueue > 0 then
            startNextUpload()
        end

    elseif httpState == "uploading" then
        -- Check for timeout
        if now - requestStartTime > TIMEOUT_MS then
            print("ChunkUploader: Upload timeout")
            if httpConnection then
                httpConnection:close()
                httpConnection = nil
            end
            -- Retry
            if currentChunk then
                currentChunk.retries = currentChunk.retries + 1
                if currentChunk.retries < MAX_RETRIES then
                    table.insert(uploadQueue, 1, currentChunk)
                else
                    failedChunks = failedChunks + 1
                end
                currentChunk = nil
            end
            httpState = "idle"
            return
        end

        -- Check if response received
        local status = httpConnection:getResponseStatus()
        if status then
            if status == 200 then
                -- Success
                print("ChunkUploader: Chunk " .. currentChunk.seq .. " uploaded successfully")
                uploadedChunks = uploadedChunks + 1
                totalBytesUploaded = totalBytesUploaded + currentChunk.size
            else
                -- Error
                print("ChunkUploader: Chunk upload failed with status " .. status)
                currentChunk.retries = currentChunk.retries + 1
                if currentChunk.retries < MAX_RETRIES then
                    table.insert(uploadQueue, 1, currentChunk)
                else
                    failedChunks = failedChunks + 1
                end
            end

            -- Clean up
            httpConnection:close()
            httpConnection = nil
            currentChunk = nil
            httpState = "idle"
        end

    elseif httpState == "finalizing" then
        -- Check for timeout
        if now - requestStartTime > TIMEOUT_MS then
            print("ChunkUploader: Finalize timeout")
            if httpConnection then
                httpConnection:close()
                httpConnection = nil
            end
            httpState = "idle"
            if finalizeCallback then
                finalizeCallback(nil, "Request timeout")
                finalizeCallback = nil
            end
            return
        end

        -- Check if response received
        local status = httpConnection:getResponseStatus()
        if status then
            local body = ""
            local available = httpConnection:getBytesAvailable()
            if available > 0 then
                body = httpConnection:read(available) or ""
            end

            httpConnection:close()
            httpConnection = nil
            httpState = "idle"

            if status == 200 then
                -- Parse response
                local success, data = pcall(json.decode, body)
                if success and data then
                    print("ChunkUploader: Finalize successful, got transcript")
                    if finalizeCallback then
                        finalizeCallback(data.transcript, nil, data)
                        finalizeCallback = nil
                    end
                else
                    print("ChunkUploader: Failed to parse response: " .. tostring(body))
                    if finalizeCallback then
                        finalizeCallback(nil, "Failed to parse response")
                        finalizeCallback = nil
                    end
                end
            else
                print("ChunkUploader: Finalize failed with status " .. status .. ": " .. body)
                if finalizeCallback then
                    finalizeCallback(nil, "Server error: " .. status .. " - " .. body)
                    finalizeCallback = nil
                end
            end

            sessionId = nil  -- Clear session after finalize
        end
    end
end

-- Finalize session and get transcript
function ChunkUploader.finalize(callback)
    if not isEnabled then
        callback(nil, "Uploader not enabled")
        return
    end

    if not sessionId then
        callback(nil, "No active session")
        return
    end

    -- Wait for upload queue to drain
    if #uploadQueue > 0 or httpState == "uploading" then
        -- Queue is not empty, wait and retry
        finalizeCallback = callback
        playdate.timer.performAfterDelay(100, function()
            ChunkUploader.finalize(callback)
        end)
        return
    end

    -- Ready to finalize
    finalizeCallback = callback
    startFinalizeRequest()
end

-- Process transcript with LLM (summary, minutes, todos)
function ChunkUploader.process(transcript, action, callback)
    if not isEnabled then
        callback(nil, "Uploader not enabled")
        return
    end

    -- This still uses the old approach - could be converted to polling too
    -- For now, use a simple synchronous-style approach

    local host = serverUrl:match("https?://([^/]+)")
    if not host then
        callback(nil, "Invalid server URL")
        return
    end

    local http = playdate.network.http.new(host, 443, true)
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

    -- For process, we'll use a timer-based polling approach
    local checkResponse
    local startTime = playdate.getCurrentTimeMilliseconds()

    checkResponse = function()
        local status = http:getResponseStatus()
        if status then
            local responseBody = ""
            local available = http:getBytesAvailable()
            if available > 0 then
                responseBody = http:read(available) or ""
            end
            http:close()

            if status == 200 then
                local success, data = pcall(json.decode, responseBody)
                if success and data then
                    callback(data.result, nil)
                else
                    callback(nil, "Failed to parse response")
                end
            else
                callback(nil, "Server error: " .. status)
            end
        elseif playdate.getCurrentTimeMilliseconds() - startTime > 60000 then
            -- 60 second timeout for processing
            http:close()
            callback(nil, "Request timeout")
        else
            -- Keep polling
            playdate.timer.performAfterDelay(100, checkResponse)
        end
    end

    playdate.timer.performAfterDelay(100, checkResponse)
end

-- Cancel current session
function ChunkUploader.cancel()
    if httpConnection then
        httpConnection:close()
        httpConnection = nil
    end
    sessionId = nil
    uploadQueue = {}
    currentChunk = nil
    httpState = "idle"
    finalizeCallback = nil
end

-- Get upload status
function ChunkUploader.getStatus()
    return {
        sessionId = sessionId,
        isUploading = httpState == "uploading",
        queueSize = #uploadQueue,
        uploadedChunks = uploadedChunks,
        failedChunks = failedChunks,
        totalBytesUploaded = totalBytesUploaded,
        isEnabled = isEnabled,
        httpState = httpState
    }
end

-- Check if uploader is enabled
function ChunkUploader.isEnabled()
    return isEnabled
end

-- Get progress percentage (0-100)
function ChunkUploader.getProgress()
    local total = uploadedChunks + failedChunks + #uploadQueue + (currentChunk and 1 or 0)
    if total == 0 then return 100 end
    return math.floor((uploadedChunks / total) * 100)
end
