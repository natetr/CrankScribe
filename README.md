# CrankScribe

A voice-powered note-taking app for Playdate that records audio and transcribes via cloud services.

## Status: Active Development

**Good news!** Playdate SDK 2.7.0 (April 2025) added HTTP networking APIs, enabling cloud transcription.

## Architecture

CrankScribe uses aggressive compression + progressive upload to work around Playdate's slow WiFi:

```
DURING RECORDING (30-second chunks)
┌──────────┐   ┌──────────────┐   ┌────────────┐   ┌────────────────┐
│   Mic    │──▶│ Downsample   │──▶│  μ-law     │──▶│  VAD Filter    │
│ (44.1kHz)│   │ to 8kHz      │   │  8-bit     │   │ (skip silence) │
└──────────┘   └──────────────┘   └────────────┘   └───────┬────────┘
                                                           │
                  Progressive upload ◀─────────────────────┘

AFTER RECORDING
┌────────────────────────────────────────────────────────────┐
│ Server combines chunks → Whisper API → Transcript returned │
└────────────────────────────────────────────────────────────┘
```

### Compression Chain

| Stage | Reduction |
|-------|-----------|
| 44.1kHz → 8kHz | 82% |
| μ-law 8-bit | 91% |
| VAD (skip silence) | 95% |

**Result:** 1 hour recording = ~17 MB (vs ~115 MB raw)

## Features

- Cassette tape recorder UI with animated reels and VU meter
- Real-time upload progress during recording
- AI processing: transcription, summaries, meeting minutes, to-do extraction
- Local note storage with tape spine visual style

## Setup

### 1. Deploy the Server

```bash
cd server
heroku create your-app-name
heroku config:set OPENAI_API_KEY=sk-your-key
git subtree push --prefix server heroku main
```

Or run locally:
```bash
cd server
pip install -r requirements.txt
export OPENAI_API_KEY=sk-your-key
python app.py
```

### 2. Configure Playdate

Create `api_key.txt` with your OpenAI API key and drop it onto the Playdate via USB. The app will import it on launch.

Set the server URL in Settings.

### 3. Build

```bash
# Requires Playdate SDK 3.0.2+
pdc Source CrankScribe.pdx

# Open in simulator
open CrankScribe.pdx
```

## Server Endpoints

| Endpoint | Description |
|----------|-------------|
| `POST /chunk` | Receive compressed audio chunk |
| `POST /finalize` | Combine chunks and transcribe |
| `POST /process` | LLM processing (summary/minutes/todos) |
| `GET /health` | Health check |

## Costs

- **OpenAI Whisper**: $0.006/min (~$0.36/hour)
- **Heroku**: Free tier works for personal use

## License

MIT
