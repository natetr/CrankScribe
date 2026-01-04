-- MicStub: Fallback mic module for simulator testing
-- This provides a stub implementation when the C extension isn't available

if mic == nil then
    mic = {}

    local _isRecording = false
    local _startTime = 0
    local _level = 0

    function mic.startRecording()
        _isRecording = true
        _startTime = playdate.getCurrentTimeMilliseconds()
        _level = 0
        return true
    end

    function mic.stopRecording()
        _isRecording = false
        -- Return dummy WAV data (just a header for testing)
        local duration = (playdate.getCurrentTimeMilliseconds() - _startTime) / 1000
        return "RIFF....WAVEfmt ................data....", duration
    end

    function mic.getLevel()
        if _isRecording then
            -- Simulate varying mic level
            _level = math.abs(math.sin(playdate.getCurrentTimeMilliseconds() / 200)) * 0.7
        end
        return _level
    end

    function mic.isRecording()
        return _isRecording
    end

    function mic.hasChunk()
        return false
    end

    function mic.getChunk()
        return nil
    end

    function mic.getDuration()
        if _isRecording then
            return (playdate.getCurrentTimeMilliseconds() - _startTime) / 1000
        end
        return 0
    end

    print("MicStub: Using Lua stub for mic module (simulator mode)")
end
