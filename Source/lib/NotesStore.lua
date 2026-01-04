-- NotesStore: CRUD operations for notes

NotesStore = {}

local NOTES_DIR = "notes"

-- Generate a unique ID
local function generateId()
    local time = playdate.getTime()
    return string.format("%04d%02d%02d_%02d%02d%02d",
        time.year, time.month, time.day,
        time.hour, time.minute, time.second)
end

-- Create a new note
function NotesStore.create(transcript, duration)
    local time = playdate.getTime()

    local note = {
        id = generateId(),
        created_at = string.format("%04d-%02d-%02dT%02d:%02d:%02dZ",
            time.year, time.month, time.day,
            time.hour, time.minute, time.second),
        duration_seconds = duration or 0,
        transcript = transcript or "",
        summary = nil,
        minutes = nil,
        todos = nil,
    }

    NotesStore.save(note)
    return note
end

-- Save a note
function NotesStore.save(note)
    if not note or not note.id then
        return false
    end

    -- Ensure notes directory exists
    if not playdate.file.isdir(NOTES_DIR) then
        playdate.file.mkdir(NOTES_DIR)
    end

    local path = NOTES_DIR .. "/" .. note.id
    playdate.datastore.write(note, path)
    return true
end

-- Load a note by ID
function NotesStore.load(id)
    local path = NOTES_DIR .. "/" .. id
    return playdate.datastore.read(path)
end

-- List all notes (returns array sorted by date, newest first)
function NotesStore.list()
    local notes = {}

    if not playdate.file.isdir(NOTES_DIR) then
        return notes
    end

    local files = playdate.file.listFiles(NOTES_DIR)
    if not files then
        return notes
    end

    for _, filename in ipairs(files) do
        -- Skip directories and hidden files
        if not string.match(filename, "^%.") and not string.match(filename, "/$") then
            local id = string.gsub(filename, "%.json$", "")
            local note = NotesStore.load(id)
            if note then
                table.insert(notes, note)
            end
        end
    end

    -- Sort by created_at descending (newest first)
    table.sort(notes, function(a, b)
        return a.created_at > b.created_at
    end)

    return notes
end

-- Delete a note by ID
function NotesStore.delete(id)
    local path = NOTES_DIR .. "/" .. id .. ".json"
    playdate.datastore.delete(NOTES_DIR .. "/" .. id)
    return true
end

-- Update specific fields of a note
function NotesStore.update(id, fields)
    local note = NotesStore.load(id)
    if not note then
        return nil
    end

    for key, value in pairs(fields) do
        note[key] = value
    end

    NotesStore.save(note)
    return note
end

-- Get note count
function NotesStore.count()
    local notes = NotesStore.list()
    return #notes
end

-- Format duration for display (e.g., "2:34")
function NotesStore.formatDuration(seconds)
    if not seconds or seconds < 0 then
        return "0:00"
    end

    local minutes = math.floor(seconds / 60)
    local secs = math.floor(seconds % 60)
    return string.format("%d:%02d", minutes, secs)
end

-- Get a short preview of transcript
function NotesStore.getPreview(note, maxLen)
    maxLen = maxLen or 50
    if not note or not note.transcript then
        return ""
    end

    local text = note.transcript
    if #text <= maxLen then
        return text
    end

    return string.sub(text, 1, maxLen - 3) .. "..."
end

-- Format date for display (e.g., "Jan 3, 2026")
function NotesStore.formatDate(isoDate)
    if not isoDate then
        return ""
    end

    local months = {
        "Jan", "Feb", "Mar", "Apr", "May", "Jun",
        "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
    }

    local year, month, day = string.match(isoDate, "(%d+)-(%d+)-(%d+)")
    if year and month and day then
        month = tonumber(month)
        return string.format("%s %d, %s", months[month], tonumber(day), year)
    end

    return isoDate
end
