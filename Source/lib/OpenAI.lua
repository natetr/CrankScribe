-- OpenAI: API integration for Whisper transcription and Chat completions
-- NOTE: Playdate SDK doesn't have HTTP networking, so this uses mock responses
-- in simulator mode. For device use, audio files must be transferred via USB.

OpenAI = {}

local WHISPER_URL = "https://api.openai.com/v1/audio/transcriptions"
local CHAT_URL = "https://api.openai.com/v1/chat/completions"

-- AI processing prompts
local PROMPTS = {
    minutes = [[Convert this transcript into formal meeting minutes with the following sections:
- **Attendees** (if mentioned)
- **Discussion Points**
- **Decisions Made**
- **Action Items**

Be concise and professional. Format for easy reading on a small screen.]],

    summary = [[Summarize the key points from this transcript in 3-5 bullet points.
Be concise - each point should be one line.
Focus on the most important information.]],

    todos = [[Extract actionable to-do items from this transcript.
Format as a checklist with [ ] for each item.
Include who is responsible if mentioned.
Only include clear, actionable tasks.]],
}

-- Current request state
local currentRequest = nil
local mockTimer = nil

-- Check if we're in simulator (no real networking available)
local function isSimulator()
    -- Playdate SDK doesn't have HTTP networking, always use mock for now
    return true
end

-- Mock transcription response for testing
local function getMockTranscript()
    local mockTranscripts = {
        "This is a test recording from CrankScribe. The voice transcription feature is working correctly. We discussed the project timeline and agreed to meet again next Tuesday.",
        "Meeting notes: We reviewed the quarterly results which showed a 15% increase in productivity. Action items include preparing the budget report and scheduling team reviews.",
        "Quick thought: Remember to pick up groceries on the way home. Also need to call the dentist to reschedule the appointment for next week.",
    }
    return mockTranscripts[math.random(1, #mockTranscripts)]
end

-- Mock AI processing responses
local function getMockProcessed(mode, transcript)
    if mode == "minutes" then
        return [[**Meeting Minutes**

**Discussion Points**
- Reviewed project timeline
- Discussed next steps

**Decisions Made**
- Will meet again next Tuesday

**Action Items**
[ ] Prepare follow-up materials
[ ] Send calendar invite]]
    elseif mode == "summary" then
        return [[**Summary**

- Test recording captured successfully
- Voice transcription feature working
- Project timeline was discussed
- Follow-up meeting scheduled]]
    elseif mode == "todos" then
        return [[**To-Do List**

[ ] Prepare follow-up materials
[ ] Send calendar invite for Tuesday
[ ] Review meeting notes]]
    end
    return transcript
end

-- Transcribe audio using Whisper API (mock in simulator)
function OpenAI.transcribe(wavData, callback)
    local apiKey = App.settings and App.settings.apiKey

    if not apiKey or apiKey == "" then
        callback(nil, "No API key configured")
        return
    end

    if not wavData then
        callback(nil, "No audio data provided")
        return
    end

    if isSimulator() then
        -- Simulate network delay then return mock response
        print("OpenAI: Using mock transcription (no networking in Playdate SDK)")
        mockTimer = playdate.timer.performAfterDelay(1500, function()
            mockTimer = nil
            callback(getMockTranscript(), nil)
        end)
        currentRequest = true
        return
    end

    -- Real implementation would go here if networking existed
    callback(nil, "HTTP networking not available on Playdate")
end

-- Process transcript with Chat API (mock in simulator)
function OpenAI.process(transcript, mode, callback)
    local apiKey = App.settings and App.settings.apiKey

    if not apiKey or apiKey == "" then
        callback(nil, "No API key configured")
        return
    end

    local prompt = PROMPTS[mode]
    if not prompt then
        callback(nil, "Unknown processing mode: " .. tostring(mode))
        return
    end

    if isSimulator() then
        -- Simulate network delay then return mock response
        print("OpenAI: Using mock processing (no networking in Playdate SDK)")
        mockTimer = playdate.timer.performAfterDelay(1000, function()
            mockTimer = nil
            callback(getMockProcessed(mode, transcript), nil)
        end)
        currentRequest = true
        return
    end

    -- Real implementation would go here if networking existed
    callback(nil, "HTTP networking not available on Playdate")
end

-- Cancel current request
function OpenAI.cancel()
    if mockTimer then
        mockTimer:remove()
        mockTimer = nil
    end
    currentRequest = nil
end

-- Check if a request is in progress
function OpenAI.isBusy()
    return currentRequest ~= nil or mockTimer ~= nil
end

-- Get available processing modes
function OpenAI.getModes()
    return {
        { id = "minutes", label = "Meeting Minutes" },
        { id = "summary", label = "Summarize" },
        { id = "todos", label = "To-Do List" },
    }
end
