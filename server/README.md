# CrankScribe Server

Flask server that receives μ-law compressed audio from Playdate and transcribes via OpenAI Whisper.

## Endpoints

- `POST /chunk` - Receive compressed audio chunk
- `POST /finalize` - Combine chunks and transcribe
- `POST /process` - LLM processing (summary/minutes/todos)
- `GET /health` - Health check

## Deploy to Heroku

```bash
cd server
heroku create crankscribe-server
heroku config:set OPENAI_API_KEY=your-api-key
git subtree push --prefix server heroku main
```

## Local Development

```bash
cd server
pip install -r requirements.txt
export OPENAI_API_KEY=your-api-key
python app.py
```

## Protocol

Playdate sends chunks as raw μ-law data (8kHz, 8-bit) with headers:
- `X-Session-Id`: UUID for the recording session
- `X-Chunk-Seq`: Sequence number (0, 1, 2, ...)

Server decodes μ-law → PCM, resamples 8kHz → 16kHz, then sends to Whisper.
