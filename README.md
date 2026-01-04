# CrankScribe

A voice-powered note-taking app for Playdate that records audio and transcribes via OpenAI's Whisper API.

## Status: Tabled

This project has been **tabled** due to a fundamental platform limitation: **the Playdate SDK does not expose HTTP networking APIs to developers**.

While the Playdate hardware has WiFi capability, Panic has not made networking available in the SDK. This has been a [highly requested feature](https://devforum.play.date/t/networking-functionality/4881) in the developer community for years, but as of SDK 2.6 (January 2025), it remains unavailable.

Without HTTP networking, the core value proposition of CrankScribe—on-device voice recording with real-time cloud transcription—is not possible.

### Potential Workarounds (not implemented)

- **Companion App**: A macOS/Windows app that watches for new audio files when the Playdate syncs, transcribes them, and writes results back
- **Serial Bridge**: Stream audio over USB serial connection to a host computer (requires being tethered)
- **Manual Workflow**: Export WAV files via USB, transcribe externally

If Panic adds HTTP networking to the SDK in the future, this project could be revived.

## What's Here

The codebase includes a fully functional UI with:

- Cassette tape recorder aesthetic
- Recording screen with animated VU meter and spinning reels
- Settings screen with USB file drop for API key configuration
- Notes list with tape spine visual style
- Post-recording actions menu (transcribe, summarize, meeting minutes, to-dos)
- Mock API responses for testing the UI flow in the simulator

## Building

```bash
# Requires Playdate SDK
pdc Source CrankScribe.pdx

# Open in simulator
open CrankScribe.pdx
```

## Screenshots

The app runs in the simulator with mock transcription responses, allowing you to explore the full UI.

## License

MIT
