# CrankScribe Implementation Plan

## Overview
Build a voice-powered note-taking app for Playdate that records audio, transcribes via OpenAI, and offers AI-powered post-processing.

**Serverless Architecture** - No server required. Playdate calls OpenAI APIs directly.

## User Flow

```
Record Audio → Transcribe → View/Process
                              ├── View Transcript
                              ├── Meeting Minutes
                              ├── Summarize Thoughts
                              └── Make To-Do List
```

## Architecture

```
Playdate Device
├── Record audio (C extension)
├── POST to OpenAI Whisper API → Transcription
├── POST to OpenAI Chat API → AI processing (minutes/summary/todos)
└── Store notes locally
```

**No server needed.** User enters OpenAI API key in device settings.

---

## Project Structure

```
CrankScribe/
├── Source/
│   ├── main.lua                # Entry point, screen manager
│   ├── pdxinfo                 # App metadata
│   ├── screens/
│   │   ├── MainMenu.lua        # Home screen
│   │   ├── Recording.lua       # Recording screen
│   │   ├── Processing.lua      # "Transcribing..." / "Thinking..." screen
│   │   ├── PostRecording.lua   # Action menu after recording
│   │   ├── NotesList.lua       # Saved notes browser
│   │   ├── NoteView.lua        # View transcript/processed content
│   │   └── Settings.lua        # API key + preferences
│   └── lib/
│       ├── AudioRecorder.lua   # Manages C extension, saves audio
│       ├── OpenAI.lua          # Whisper + Chat API calls
│       ├── NotesStore.lua      # Note CRUD operations
│       └── SettingsStore.lua   # Settings persistence
├── extension/                  # C extension for mic
│   ├── mic_capture.c           # Mic callback + buffer
│   └── Makefile
├── Makefile                    # Build orchestration
├── CLAUDE.md                   # Spec (existing)
└── README.md
```

**Note:** No server directory - all API calls go directly to OpenAI.

---

## Phase 1: Core Infrastructure

### 1.1 C Extension for Mic Capture
**File**: `extension/mic_capture.c`

```c
// Functions exposed to Lua:
startRecording()     // Begin capturing mic audio
stopRecording()      // Stop and return audio data
getLevel()           // Current mic level (for UI meter)
isRecording()        // Check recording state

// Internal:
- Use pd->sound->setMicCallback() for audio capture
- Accumulate samples in growing buffer (malloc/realloc)
- Downsample 44.1kHz → 16kHz for Whisper compatibility
- Return audio as WAV or raw PCM bytes
```

**Technical details**:
- Playdate records at 44.1kHz, Whisper needs 16kHz
- Downsample factor: 44100/16000 ≈ 2.76
- **Auto-chunking**: Every 5 minutes, export chunk + clear buffer
- Supports recordings up to 2+ hours (unlimited chunks)

### 1.2 Playdate Project Setup
**Files**: `Source/pdxinfo`, `Source/main.lua`

- Bundle ID: `com.crankscribe.app`
- Import CoreLibs: graphics, timer
- Screen manager pattern for navigation
- Global state for current note and settings

---

## Phase 2: Recording & Transcription

### 2.1 Recording Screen
**File**: `Source/screens/Recording.lua`

- Timer display with pulsing "REC" indicator
- Audio level meter (dithered bar from C extension)
- **Live transcript**: Shows text as chunks are transcribed
- Controls: A=Pause, B=Stop recording
- Crank to scroll through transcript history

**Auto-chunking behavior**:
- Every 5 minutes, C extension exports audio chunk
- Chunk sent to OpenAI Whisper in background
- Transcript appended to display as it arrives
- User sees continuous transcription during long recordings

### 2.2 OpenAI Integration
**File**: `Source/lib/OpenAI.lua`

```lua
-- Transcription (Whisper API)
function OpenAI.transcribe(audioData, callback)
    -- POST to https://api.openai.com/v1/audio/transcriptions
    -- model: "whisper-1"
    -- file: audio data as WAV
    -- Returns: { text = "transcription..." }
end

-- AI Processing (Chat API)
function OpenAI.process(transcript, mode, callback)
    -- POST to https://api.openai.com/v1/chat/completions
    -- model: "gpt-4o-mini" (fast + cheap)
    -- Modes: "minutes" | "summary" | "todos"
    -- Returns: { content = "processed text..." }
end
```

### 2.3 Processing Screen
**File**: `Source/screens/Processing.lua`

- Animated "thinking" indicator
- Progress text: "Transcribing..." or "Generating..."
- Cancel button (B)
- On complete → PostRecording or NoteView

---

## Phase 3: Post-Recording & AI Features

### 3.1 PostRecording Screen
**File**: `Source/screens/PostRecording.lua`

After transcription completes, show action menu:
```
┌────────────────────────────────────────┐
│  Recording saved! (2:34)               │
├────────────────────────────────────────┤
│    ▶ View Transcript                   │
│      Meeting Minutes                   │
│      Summarize Thoughts                │
│      Make To-Do List                   │
│      Delete                            │
├────────────────────────────────────────┤
│  ⟳ Crank to scroll    Ⓐ Select        │
└────────────────────────────────────────┘
```

### 3.2 AI Prompts
**File**: `Source/lib/OpenAI.lua` (prompts section)

```lua
PROMPTS = {
    minutes = "Convert this transcript into formal meeting minutes with attendees, discussion points, decisions made, and action items.",

    summary = "Summarize the key points from this transcript in 3-5 bullet points. Be concise.",

    todos = "Extract actionable to-do items from this transcript. Format as a checklist with [ ] for each item."
}
```

---

## Phase 4: Storage & Notes Management

### 4.1 NotesStore
**File**: `Source/lib/NotesStore.lua`

```lua
-- Note structure:
{
  id = "uuid",
  created_at = "2026-01-03T10:30:00Z",
  duration_seconds = 154,
  transcript = "Full transcript...",
  minutes = nil,      -- Generated on demand
  summary = nil,      -- Generated on demand
  todos = nil,        -- Generated on demand
}

-- Methods:
save(note), load(id), list(), delete(id), update(id, fields)
```

### 4.2 NotesList Screen
**File**: `Source/screens/NotesList.lua`

- Crank-scrollable list of saved notes
- Display: date, duration, preview of transcript
- A=View, B=Back to menu

### 4.3 NoteView Screen
**File**: `Source/screens/NoteView.lua`

- Display transcript or processed content (minutes/summary/todos)
- Crank to scroll through content
- Menu button for: Process again, Delete, Back

---

## Phase 5: Settings & Polish

### 5.1 Settings Screen
**File**: `Source/screens/Settings.lua`

Configurable:
- OpenAI API Key (masked input, stored locally)
- Mic input (Internal/Headset)

### 5.2 First-Run Setup
- Check for settings.json
- If no API key, show setup screen
- D-pad text input for API key (or QR code instructions)

### 5.3 UI Polish
- Dithered graphics for visual interest
- Recording pulse animation
- Animated "thinking" indicator
- Error dialogs with retry options

---

## Key Technical Decisions

### Audio Format
- Playdate native: 44.1kHz 16-bit mono
- OpenAI Whisper accepts: WAV, MP3, M4A, etc.
- C extension outputs WAV format (simple, well-supported)
- **Chunk size**: 5 minutes (~5MB at 16kHz mono)
- **Long recordings**: Auto-chunk every 5 min, combine transcripts

### OpenAI API Calls
```lua
-- Transcription
POST https://api.openai.com/v1/audio/transcriptions
Headers: Authorization: Bearer {api_key}
Body: multipart/form-data with audio file
Model: whisper-1

-- AI Processing
POST https://api.openai.com/v1/chat/completions
Headers: Authorization: Bearer {api_key}
Body: JSON with messages array
Model: gpt-4o-mini (fast + cheap)
```

### Error Handling
- Network timeout: Show error, offer retry
- API errors: Display message (rate limit, invalid key, etc.)
- Storage full: Warn and offer to delete old notes

---

## Build & Deployment

### Build Commands
```bash
cd CrankScribe
make          # Builds C extension + Lua into CrankScribe.pdx
make run      # Opens in Playdate Simulator
make device   # Sideload to connected Playdate
```

### User Setup
1. Install CrankScribe.pdx on Playdate
2. On first launch, enter OpenAI API key
3. Get API key from: https://platform.openai.com/api-keys

**No server required.** All processing happens via direct API calls.

---

## Implementation Order

1. **C Extension** - mic_capture.c with audio recording + WAV output
2. **Playdate Skeleton** - main.lua, screen manager, pdxinfo
3. **Recording Flow** - Recording screen + Processing screen
4. **OpenAI Integration** - Transcription + AI processing
5. **Post-Recording** - Action menu with AI options
6. **Storage** - NotesStore + NotesList + NoteView
7. **Settings** - API key input + preferences
8. **Polish** - Animations, error handling

---

## Files to Create

| Priority | File | Purpose |
|----------|------|---------|
| 1 | `extension/mic_capture.c` | C extension for mic recording |
| 1 | `extension/Makefile` | Build C extension |
| 1 | `Source/main.lua` | App entry point + screen manager |
| 1 | `Source/pdxinfo` | App metadata |
| 2 | `Source/screens/MainMenu.lua` | Home screen |
| 2 | `Source/screens/Recording.lua` | Recording UI |
| 2 | `Source/screens/Processing.lua` | Transcribing/Thinking screen |
| 2 | `Source/lib/OpenAI.lua` | API calls to OpenAI |
| 3 | `Source/screens/PostRecording.lua` | Action menu after recording |
| 3 | `Source/screens/NotesList.lua` | Saved notes browser |
| 3 | `Source/screens/NoteView.lua` | View transcript/processed |
| 3 | `Source/lib/NotesStore.lua` | Note CRUD operations |
| 4 | `Source/screens/Settings.lua` | API key + preferences |
| 4 | `Source/lib/SettingsStore.lua` | Settings persistence |
| 4 | `Source/lib/AudioRecorder.lua` | C extension wrapper |
| 4 | `Makefile` | Build orchestration |
