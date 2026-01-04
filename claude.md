# CrankScribe: Playdate Voice Notes App
## Technical Specification & Development Framework

---

## Overview

**CrankScribe** is a voice-powered note-taking app for Playdate that streams audio to a cloud transcription service and displays results on the device's 1-bit screen. The app embraces Playdate's quirky personality while providing genuinely useful functionality.

### Core Concept
The Playdate becomes a dedicated "yellow box" voice recorder that captures meetings, thoughts, and ideas—then transcribes and processes them via streaming Whisper. The crank provides unique interactions for scrubbing through recordings and transcripts.

---

## Hardware Constraints & Capabilities

### What We Have
- **CPU**: 168 MHz ARM Cortex-M7 (too weak for local ML)
- **RAM**: 16 MB (insufficient for any speech models)
- **Storage**: 4 GB flash (plenty for compressed audio)
- **Display**: 400×240 pixels, 1-bit (black/white), no backlight
- **Audio Input**: Built-in condenser mic + TRRS headset mic input
- **Networking**: 802.11bgn 2.4GHz WiFi (SDK 3.0+ has HTTP/TCP APIs)
- **Battery**: ~8 hours active use

### What This Means
- All transcription MUST happen server-side
- Streaming architecture required for real-time feedback
- UI must be designed for 1-bit readability
- Battery-conscious networking patterns needed

---

## Architecture

### System Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                         PLAYDATE                                 │
│  ┌─────────────┐    ┌──────────────┐    ┌──────────────────┐   │
│  │ Mic Capture │───▶│ Audio Buffer │───▶│ HTTP/TCP Client  │   │
│  │ (16kHz mono)│    │ (ring buffer)│    │ (chunk sender)   │   │
│  └─────────────┘    └──────────────┘    └────────┬─────────┘   │
│                                                   │              │
│  ┌─────────────┐    ┌──────────────┐              │              │
│  │   Display   │◀───│ Text Buffer  │◀─────────────┘              │
│  │  (400×240)  │    │ (transcripts)│   (receive text)           │
│  └─────────────┘    └──────────────┘                            │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ WiFi (HTTP POST chunks / receive JSON)
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    USER'S SERVER / PROXY                         │
│  ┌──────────────┐    ┌───────────────┐    ┌─────────────────┐   │
│  │ Audio Buffer │───▶│ WhisperFlow   │───▶│ Response Queue  │   │
│  │ (accumulate) │    │ (transcribe)  │    │ (partial texts) │   │
│  └──────────────┘    └───────────────┘    └─────────────────┘   │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │ Optional: LLM Integration (summaries, minutes, actions)  │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

### Audio Pipeline

1. **Capture**: Mic callback fires every audio cycle, provides mono samples
2. **Buffer**: Accumulate samples in circular buffer (~500ms chunks)
3. **Encode**: Convert to 16-bit PCM, 16kHz (Whisper's expected format)
4. **Transmit**: HTTP POST chunks to configured server endpoint
5. **Receive**: Poll or receive pushed transcript fragments
6. **Display**: Append text to scrollable transcript view

### Network Protocol

Since Playdate SDK 3.0+ supports HTTP and TCP but WebSocket support is unclear, use a simple HTTP-based streaming protocol:

```
POST /audio
Content-Type: audio/pcm
X-Session-Id: {uuid}
X-Chunk-Seq: {number}
X-API-Key: {user_api_key}

[raw PCM bytes]

Response:
{
  "transcript": "partial text...",
  "is_final": false,
  "chunk_id": 123
}
```

---

## User Configuration

### Settings File
Store user configuration in the game's data directory:

```json
// Data/com.yourname.crankscribe/settings.json
{
  "server_url": "https://your-whisperflow-server.com",
  "api_key": "user_whisperflow_api_key_here",
  "email": "user@example.com",
  "email_smtp_relay": "https://your-email-relay.com",
  "mic_gain": 1.0,
  "auto_save": true,
  "font_size": "medium"
}
```

### First-Run Setup Flow
1. Display QR code linking to web-based configuration page
2. User enters settings on phone/computer
3. Settings sync via Playdate's USB or WiFi sync
4. Alternative: Manual entry via d-pad text input (tedious but possible)

### API Key Security
- Keys stored locally on device only
- Never displayed in full on screen (show last 4 chars only)
- Option to clear/reset in settings menu

---

## Features & Screens

### Main Menu (Home Screen)

```
┌────────────────────────────────────────┐
│                                        │
│      ╔═══════════════════════════╗     │
│      ║     ♪ CRANKSCRIBE ♪       ║     │
│      ╚═══════════════════════════╝     │
│                                        │
│         ┌─────────────────┐            │
│     ▶   │  🎙️ RECORD      │            │
│         └─────────────────┘            │
│         ┌─────────────────┐            │
│         │  📋 MY NOTES    │            │
│         └─────────────────┘            │
│         ┌─────────────────┐            │
│         │  ⚙️ SETTINGS    │            │
│         └─────────────────┘            │
│                                        │
│    ⟳ Crank to scroll    Ⓐ Select      │
└────────────────────────────────────────┘
```

Design notes:
- Big, chunky UI elements (easy to read on 1-bit)
- Crank scrolls menu (satisfying click-per-item)
- Playful iconography using dithered patterns
- Animated idle state (microphone icon pulses)

### Recording Screen

```
┌────────────────────────────────────────┐
│ ● REC  00:01:23          [MEETING]     │
├────────────────────────────────────────┤
│                                        │
│  "...and I think we should focus on    │
│  the Q2 deliverables before moving     │
│  forward with the new feature set.     │
│  Sarah mentioned that the timeline     │
│  might need to shift by two weeks..."  │
│                                        │
│  ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░    │
│  ▲ Live transcription                  │
│                                        │
├────────────────────────────────────────┤
│  Ⓐ Pause  Ⓑ Stop  ⟳ Scroll transcript │
└────────────────────────────────────────┘
```

Features:
- Real-time scrolling transcript
- Recording timer with visual pulse
- Mode indicator (Meeting/Quick Note/etc.)
- Crank scrolls through transcript history
- Audio level meter (optional, uses dithering)

### Recording Modes

**1. Meeting Mode** 🎙️
- Continuous recording until stopped
- Optimized for longer sessions
- Auto-saves every 5 minutes
- Full transcript stored

**2. Quick Thought** 💭
- Press-and-hold to record
- Release to stop and save
- Perfect for fleeting ideas
- Shows last 3 thoughts on screen

**3. Voice Memo** 📝
- Fixed-length recordings (30s, 1m, 2m)
- Visual countdown timer
- Auto-stops at limit

### Post-Recording Actions Menu

```
┌────────────────────────────────────────┐
│  Recording saved! (2:34)               │
├────────────────────────────────────────┤
│                                        │
│    ┌─────────────────────────┐         │
│ ▶  │ 📄 View Transcript      │         │
│    └─────────────────────────┘         │
│    ┌─────────────────────────┐         │
│    │ 📋 Generate Summary     │         │
│    └─────────────────────────┘         │
│    ┌─────────────────────────┐         │
│    │ 📝 Write Minutes        │         │
│    └─────────────────────────┘         │
│    ┌─────────────────────────┐         │
│    │ ✅ Extract Action Items │         │
│    └─────────────────────────┘         │
│    ┌─────────────────────────┐         │
│    │ 📧 Email to Self        │         │
│    └─────────────────────────┘         │
│    ┌─────────────────────────┐         │
│    │ 🗑️ Delete               │         │
│    └─────────────────────────┘         │
│                                        │
└────────────────────────────────────────┘
```

### AI Processing Screen

```
┌────────────────────────────────────────┐
│  Generating Summary...                 │
├────────────────────────────────────────┤
│                                        │
│                                        │
│           ┌─────────┐                  │
│           │  ◐ ◓ ◑  │                  │
│           │ ╭─────╮ │                  │
│           │ │ ••• │ │  Thinking...     │
│           │ ╰─────╯ │                  │
│           └─────────┘                  │
│                                        │
│     ░░░░░░░░░░░░░░░▓▓▓░░░░░░░░░░      │
│                                        │
│                                        │
├────────────────────────────────────────┤
│            Ⓑ Cancel                    │
└────────────────────────────────────────┘
```

- Animated "thinking" robot/crank icon
- Progress bar for longer operations
- Cancel option always available

### Text Viewer

```
┌────────────────────────────────────────┐
│ Summary: Team Standup 1/3              │
├────────────────────────────────────────┤
│                                        │
│  KEY POINTS:                           │
│  • Q2 deliverables are priority        │
│  • Timeline may shift 2 weeks          │
│  • Sarah to follow up with design      │
│  • Budget review scheduled Friday      │
│                                        │
│  ACTION ITEMS:                         │
│  □ Review sprint backlog (John)        │
│  □ Send updated timeline (Sarah)       │
│  □ Schedule stakeholder call (Mike)    │
│                                        │
│  ░░░░░░░░▓▓▓▓░░░░░░░░░░░░░░░░░░░░░    │
├────────────────────────────────────────┤
│  ⟳ Scroll  Ⓐ Email  Ⓑ Back            │
└────────────────────────────────────────┘
```

- Crank scrolls through content (satisfying!)
- Clear visual hierarchy with dithered headers
- Scroll position indicator
- Quick actions via buttons

### Email Confirmation

```
┌────────────────────────────────────────┐
│  Send Email?                           │
├────────────────────────────────────────┤
│                                        │
│   To: nate@rendered.co                 │
│                                        │
│   Subject: CrankScribe: Team Standup   │
│                                        │
│   ┌────────────────────────────────┐   │
│   │ KEY POINTS:                    │   │
│   │ • Q2 deliverables are priority │   │
│   │ • Timeline may shift 2 weeks   │   │
│   │ ...                            │   │
│   └────────────────────────────────┘   │
│                                        │
│                                        │
├────────────────────────────────────────┤
│       Ⓐ Send         Ⓑ Cancel         │
└────────────────────────────────────────┘
```

### Settings Screen

```
┌────────────────────────────────────────┐
│  Settings                              │
├────────────────────────────────────────┤
│                                        │
│  Server                                │
│  └─ whisper.example.com     [Edit]     │
│                                        │
│  API Key                               │
│  └─ ••••••••••••ab12       [Edit]     │
│                                        │
│  Email                                 │
│  └─ nate@rendered.co       [Edit]     │
│                                        │
│  Mic Input                             │
│  └─ ◉ Internal  ○ Headset              │
│                                        │
│  Auto-Save                             │
│  └─ [✓] Every 5 minutes                │
│                                        │
│  Font Size                             │
│  └─ ◀ Medium ▶                         │
│                                        │
├────────────────────────────────────────┤
│  ⟳ Navigate  Ⓐ Select  Ⓑ Back         │
└────────────────────────────────────────┘
```

---

## Crank Interactions

The crank is what makes Playdate special—use it meaningfully:

| Context | Crank Action |
|---------|--------------|
| Main Menu | Scroll through options (with detents) |
| Recording | Scroll through live transcript |
| Text Viewer | Smooth scroll through content |
| Settings | Adjust numeric values, cycle options |
| Playback (future) | Scrub through audio timeline |
| Text Input | Cycle through alphabet |

### Crank Feel
- Use `getCrankTicks()` for menu navigation (discrete steps)
- Use `getCrankChange()` for smooth scrolling
- Add subtle audio feedback for crank detents
- Consider "crank momentum" for long documents

---

## Data Model

### Note Structure

```lua
-- Each note stored as JSON + optional raw audio
Note = {
    id = "uuid-here",
    created_at = "2026-01-03T10:30:00Z",
    updated_at = "2026-01-03T10:35:00Z",
    mode = "meeting",  -- meeting | thought | memo
    title = "Team Standup",  -- auto-generated or manual
    duration_seconds = 154,
    
    -- Core content
    transcript = "Full transcript text...",
    
    -- AI-generated content (optional, generated on demand)
    summary = nil,
    minutes = nil,
    action_items = nil,
    
    -- Metadata
    has_audio = true,  -- if raw audio preserved
    synced = false,    -- if emailed/exported
}
```

### File Storage

```
Data/com.yourname.crankscribe/
├── settings.json
├── notes/
│   ├── 2026-01-03_103000_meeting.json
│   ├── 2026-01-03_103000_meeting.wav  (optional)
│   ├── 2026-01-03_142500_thought.json
│   └── ...
└── cache/
    └── (temporary streaming data)
```

---

## Server Requirements

### Minimum Server Implementation

Users need to host or use a WhisperFlow-compatible endpoint:

```python
# Example minimal Flask server

from flask import Flask, request, jsonify
import whisper_streaming  # WhisperFlow/WhisperLive

app = Flask(__name__)
sessions = {}

@app.route('/audio', methods=['POST'])
def receive_audio():
    api_key = request.headers.get('X-API-Key')
    session_id = request.headers.get('X-Session-Id')
    chunk_seq = request.headers.get('X-Chunk-Seq')
    
    # Validate API key
    if not validate_key(api_key):
        return jsonify({"error": "Invalid API key"}), 401
    
    # Get or create session
    if session_id not in sessions:
        sessions[session_id] = WhisperStreamSession()
    
    # Feed audio chunk
    pcm_data = request.data
    partial_transcript = sessions[session_id].process_chunk(pcm_data)
    
    return jsonify({
        "transcript": partial_transcript,
        "is_final": False,
        "chunk_id": int(chunk_seq)
    })

@app.route('/session/<session_id>/end', methods=['POST'])
def end_session(session_id):
    if session_id in sessions:
        final_transcript = sessions[session_id].finalize()
        del sessions[session_id]
        return jsonify({
            "transcript": final_transcript,
            "is_final": True
        })
    return jsonify({"error": "Session not found"}), 404

@app.route('/process', methods=['POST'])
def process_text():
    """AI processing for summaries, minutes, etc."""
    data = request.json
    action = data.get('action')  # summary | minutes | actions
    text = data.get('text')
    
    result = run_llm_task(action, text)
    return jsonify({"result": result})

@app.route('/email', methods=['POST'])
def send_email():
    """Relay email to user"""
    data = request.json
    # Send via configured SMTP/API
    send_email_to_user(data['to'], data['subject'], data['body'])
    return jsonify({"sent": True})
```

### Recommended Server Stack
- **WhisperFlow** or **WhisperLive** for streaming transcription
- **faster-whisper** for efficient inference
- **LiteLLM** or direct OpenAI/Anthropic for AI processing
- **Resend** or **SendGrid** for email relay

---

## Implementation Notes

### Playdate SDK Specifics

**Microphone Access (Lua)**
```lua
-- Set up mic callback
function micCallback(buffer)
    -- buffer contains mono audio samples
    -- Accumulate into ring buffer
    audioBuffer:write(buffer)
end

playdate.sound.micinput.startListening()
playdate.sound.setMicCallback(micCallback)
```

**Networking (SDK 3.0+)**
```lua
-- HTTP request
local http = playdate.network.http

http.request("POST", serverUrl .. "/audio", {
    headers = {
        ["Content-Type"] = "audio/pcm",
        ["X-Session-Id"] = sessionId,
        ["X-API-Key"] = settings.apiKey
    },
    body = audioChunk,
    callback = function(response)
        if response.status == 200 then
            local data = json.decode(response.body)
            appendTranscript(data.transcript)
        end
    end
})
```

**File Storage**
```lua
-- Save note
local noteData = json.encode(note)
playdate.datastore.write(noteData, "notes/" .. note.id)

-- Load notes
local files = playdate.file.listFiles("notes/")
for _, filename in ipairs(files) do
    local note = playdate.datastore.read("notes/" .. filename)
    -- ...
end
```

### Performance Considerations

1. **Audio Buffering**: Use 500ms chunks (balance latency vs overhead)
2. **Network Throttling**: Don't spam requests; batch appropriately
3. **Display Updates**: Only redraw changed regions
4. **Memory**: Stream audio to storage, don't hold full recordings in RAM
5. **Battery**: Disable WiFi when not actively recording/syncing

### Error Handling

- **Network failures**: Queue chunks for retry, show status
- **Server errors**: Display friendly messages, offer retry
- **Storage full**: Warn user, offer to delete old notes
- **Mic unavailable**: Check headset vs internal, show guidance

---

## Visual Design Language

### Playdate Aesthetic
- **Chunky pixels**: Embrace the 1-bit limitation
- **Dithering patterns**: Use for grays, shadows, textures
- **Bold outlines**: 2-3px borders for clarity
- **Generous spacing**: Don't cram the small screen
- **Playful icons**: Hand-drawn feel, not corporate

### Typography
- Use Playdate's system fonts or custom bitmap fonts
- **Large text** for primary content (transcripts)
- **Small caps** for labels and headers
- Ensure readability in direct sunlight (high contrast)

### Animation
- **Subtle idle animations**: Breathing icons, blinking cursor
- **Recording pulse**: Visual heartbeat while capturing
- **Thinking animation**: Playful robot/crank while processing
- **Transitions**: Quick, snappy screen changes

### Sound Design
- **Crank clicks**: Subtle detent sounds
- **Recording start/stop**: Distinct audio cues
- **Success/error**: Clear but not annoying
- **Optional**: Disable all sounds in settings

---

## Future Enhancements

### Version 1.1
- [ ] Audio playback with crank-scrubbing
- [ ] Multiple speaker diarization
- [ ] Custom vocabulary/terms
- [ ] Export to Markdown files

### Version 1.2
- [ ] Companion desktop app for configuration
- [ ] Cloud sync between devices
- [ ] Shared note sessions
- [ ] Voice commands ("Hey Crank...")

### Version 2.0
- [ ] On-device audio storage with USB transfer
- [ ] Batch transcription mode
- [ ] Integration with calendar for meeting titles
- [ ] Widgets/complications for quick recording

---

## Development Checklist

### Phase 1: Core Recording
- [ ] Basic mic capture to buffer
- [ ] HTTP client for audio streaming
- [ ] Server endpoint (basic WhisperFlow wrapper)
- [ ] Real-time transcript display
- [ ] Start/stop recording flow

### Phase 2: Storage & Management
- [ ] Save transcripts to storage
- [ ] Note list view with crank scrolling
- [ ] View/delete individual notes
- [ ] Settings persistence

### Phase 3: AI Features
- [ ] Summary generation endpoint
- [ ] Minutes generation endpoint
- [ ] Action item extraction
- [ ] Email relay integration

### Phase 4: Polish
- [ ] Refined UI with dithered graphics
- [ ] Sound effects and haptics
- [ ] Error handling and edge cases
- [ ] Battery optimization
- [ ] User testing and iteration

---

## Resources

### Playdate SDK
- [Inside Playdate with Lua](https://sdk.play.date/inside-playdate)
- [SDK Changelog](https://sdk.play.date/changelog/)
- [Developer Forum](https://devforum.play.date/)

### Whisper Streaming
- [WhisperFlow](https://github.com/dimastatz/whisper-flow)
- [WhisperLive](https://github.com/collabora/WhisperLive)
- [whisper_streaming](https://github.com/ufal/whisper_streaming)
- [faster-whisper](https://github.com/guillaumekln/faster-whisper)

### Audio Specs for Whisper
- Format: 16-bit signed PCM
- Sample rate: 16000 Hz
- Channels: Mono
- Chunk size: ~8000-16000 samples (500ms-1s)

---

*CrankScribe: Because the best ideas deserve to be captured, even on a tiny yellow game console.* 🎮🎙️
