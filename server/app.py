"""
CrankScribe Transcription Server

Receives μ-law compressed audio chunks from Playdate, decodes them,
and forwards to OpenAI Whisper API for transcription.

Endpoints:
- POST /chunk: Receive a compressed audio chunk
- POST /finalize: Combine chunks and transcribe
- POST /process: LLM processing (summary, minutes, todos)
- GET /health: Health check
"""

import os
import uuid
import audioop
import tempfile
import struct
from datetime import datetime, timedelta
from flask import Flask, request, jsonify
from flask_cors import CORS
import openai

app = Flask(__name__)
CORS(app)

# Configuration
OPENAI_API_KEY = os.environ.get("OPENAI_API_KEY")
MAX_SESSION_AGE_MINUTES = 30
INPUT_SAMPLE_RATE = 8000
OUTPUT_SAMPLE_RATE = 16000

# In-memory session storage (for demo; use Redis in production)
sessions = {}

# Initialize OpenAI client
client = None
if OPENAI_API_KEY:
    client = openai.OpenAI(api_key=OPENAI_API_KEY)


def cleanup_old_sessions():
    """Remove sessions older than MAX_SESSION_AGE_MINUTES"""
    cutoff = datetime.utcnow() - timedelta(minutes=MAX_SESSION_AGE_MINUTES)
    expired = [sid for sid, data in sessions.items() if data["created"] < cutoff]
    for sid in expired:
        del sessions[sid]


def decode_mulaw_to_pcm(mulaw_data):
    """Decode μ-law audio to 16-bit PCM"""
    # audioop.ulaw2lin converts μ-law to linear PCM
    # width=2 means 16-bit output
    return audioop.ulaw2lin(mulaw_data, 2)


def resample_8k_to_16k(pcm_data):
    """Resample from 8kHz to 16kHz (Whisper's expected rate)"""
    # audioop.ratecv handles resampling
    # (data, width, nchannels, inrate, outrate, state)
    resampled, _ = audioop.ratecv(pcm_data, 2, 1, INPUT_SAMPLE_RATE, OUTPUT_SAMPLE_RATE, None)
    return resampled


def create_wav_header(data_size, sample_rate=16000, bits_per_sample=16, num_channels=1):
    """Create a WAV file header"""
    byte_rate = sample_rate * num_channels * bits_per_sample // 8
    block_align = num_channels * bits_per_sample // 8

    header = struct.pack(
        "<4sI4s4sIHHIIHH4sI",
        b"RIFF",
        36 + data_size,  # File size - 8
        b"WAVE",
        b"fmt ",
        16,  # fmt chunk size
        1,   # Audio format (PCM)
        num_channels,
        sample_rate,
        byte_rate,
        block_align,
        bits_per_sample,
        b"data",
        data_size
    )
    return header


def transcribe_audio(wav_data):
    """Send audio to OpenAI Whisper API"""
    if not client:
        return None, "OpenAI API key not configured"

    # Write to temp file (OpenAI API needs a file)
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
        f.write(wav_data)
        temp_path = f.name

    try:
        with open(temp_path, "rb") as audio_file:
            result = client.audio.transcriptions.create(
                model="whisper-1",
                file=audio_file,
                response_format="text",
                language="en"
            )
        return result, None
    except Exception as e:
        return None, str(e)
    finally:
        os.unlink(temp_path)


@app.route("/health", methods=["GET"])
def health():
    """Health check endpoint"""
    return jsonify({
        "status": "ok",
        "openai_configured": OPENAI_API_KEY is not None,
        "active_sessions": len(sessions)
    })


@app.route("/chunk", methods=["POST"])
def receive_chunk():
    """Receive a compressed audio chunk from Playdate"""
    cleanup_old_sessions()

    session_id = request.headers.get("X-Session-Id")
    chunk_seq = request.headers.get("X-Chunk-Seq")

    if not session_id:
        return jsonify({"error": "Missing X-Session-Id header"}), 400

    try:
        chunk_seq = int(chunk_seq) if chunk_seq else 0
    except ValueError:
        return jsonify({"error": "Invalid X-Chunk-Seq"}), 400

    # Get μ-law compressed data
    mulaw_data = request.data
    if not mulaw_data:
        return jsonify({"error": "No audio data received"}), 400

    # Decode μ-law to PCM
    pcm_data = decode_mulaw_to_pcm(mulaw_data)

    # Resample 8kHz → 16kHz
    pcm_16k = resample_8k_to_16k(pcm_data)

    # Store in session
    if session_id not in sessions:
        sessions[session_id] = {
            "chunks": {},
            "created": datetime.utcnow()
        }

    sessions[session_id]["chunks"][chunk_seq] = pcm_16k

    return jsonify({
        "received": chunk_seq,
        "size_bytes": len(mulaw_data),
        "decoded_bytes": len(pcm_16k)
    })


@app.route("/finalize", methods=["POST"])
def finalize_session():
    """Combine all chunks and transcribe"""
    session_id = request.headers.get("X-Session-Id")

    if not session_id:
        return jsonify({"error": "Missing X-Session-Id header"}), 400

    if session_id not in sessions:
        return jsonify({"error": "Session not found"}), 404

    session = sessions[session_id]
    chunks = session["chunks"]

    if not chunks:
        del sessions[session_id]
        return jsonify({"error": "No chunks in session"}), 400

    # Combine chunks in order
    ordered_keys = sorted(chunks.keys())
    full_audio = b"".join(chunks[k] for k in ordered_keys)

    # Create WAV file
    wav_header = create_wav_header(len(full_audio))
    wav_data = wav_header + full_audio

    # Transcribe
    transcript, error = transcribe_audio(wav_data)

    # Cleanup session
    del sessions[session_id]

    if error:
        return jsonify({"error": error}), 500

    return jsonify({
        "transcript": transcript,
        "chunks_combined": len(ordered_keys),
        "audio_duration_seconds": len(full_audio) / (OUTPUT_SAMPLE_RATE * 2)
    })


@app.route("/process", methods=["POST"])
def process_transcript():
    """Process transcript with LLM (summary, minutes, todos)"""
    if not client:
        return jsonify({"error": "OpenAI API key not configured"}), 500

    data = request.json
    if not data:
        return jsonify({"error": "No JSON data"}), 400

    action = data.get("action")
    text = data.get("text")

    if not action or not text:
        return jsonify({"error": "Missing action or text"}), 400

    prompts = {
        "summary": """Summarize the key points from this transcript in 3-5 bullet points.
Be concise - each point should be one line.
Focus on the most important information.""",

        "minutes": """Convert this transcript into formal meeting minutes with the following sections:
- **Attendees** (if mentioned)
- **Discussion Points**
- **Decisions Made**
- **Action Items**

Be concise and professional. Format for easy reading on a small screen.""",

        "todos": """Extract actionable to-do items from this transcript.
Format as a checklist with [ ] for each item.
Include who is responsible if mentioned.
Only include clear, actionable tasks."""
    }

    if action not in prompts:
        return jsonify({"error": f"Unknown action: {action}"}), 400

    try:
        response = client.chat.completions.create(
            model="gpt-4o-mini",
            messages=[
                {"role": "system", "content": "You are a concise note-taking assistant for a tiny screen device."},
                {"role": "user", "content": prompts[action] + "\n\nTranscript:\n" + text}
            ],
            max_tokens=500
        )
        result = response.choices[0].message.content
        return jsonify({"result": result})
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route("/email", methods=["POST"])
def send_email():
    """Email relay endpoint (placeholder - needs SMTP/SendGrid config)"""
    # This would need actual email service configuration
    # For now, just acknowledge the request
    data = request.json
    return jsonify({
        "status": "not_implemented",
        "message": "Email relay requires SMTP configuration"
    }), 501


if __name__ == "__main__":
    port = int(os.environ.get("PORT", 5000))
    app.run(host="0.0.0.0", port=port, debug=True)
