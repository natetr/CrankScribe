/*
 * CrankScribe Microphone Capture Extension
 *
 * Captures audio from Playdate's microphone, downsamples from 44.1kHz to 8kHz,
 * applies μ-law compression and VAD for efficient upload.
 *
 * Compression chain: 44.1kHz 16-bit → 8kHz 16-bit → 8kHz 8-bit μ-law → VAD filtered
 * Results in ~95% size reduction vs raw audio.
 */

#include <stdlib.h>
#include <string.h>
#include <math.h>
#include "pd_api.h"

static PlaydateAPI* pd = NULL;

// Audio configuration
#define SAMPLE_RATE_INPUT   44100   // Playdate native sample rate
#define SAMPLE_RATE_OUTPUT  8000    // 8kHz for aggressive compression (server resamples to 16kHz)
#define DOWNSAMPLE_FACTOR   5.5125f // 44100/8000

// Recording state
static int is_recording = 0;
static int16_t* audio_buffer = NULL;       // Raw 16-bit buffer (for WAV export/backup)
static uint8_t* compressed_buffer = NULL;  // μ-law compressed buffer (for upload)
static size_t buffer_size = 0;             // Allocated size in samples
static size_t buffer_position = 0;         // Current write position in samples
static size_t compressed_position = 0;     // Position in compressed buffer
static float current_level = 0.0f;

// Initial buffer size: 30 seconds at 8kHz (grows as needed)
#define INITIAL_BUFFER_SAMPLES (8000 * 30)
#define BUFFER_GROW_SAMPLES    (8000 * 30)  // Grow by 30 seconds

// Chunk tracking for progressive upload (30 second chunks)
#define CHUNK_DURATION_SECONDS 30   // 30 seconds per chunk for progressive upload
#define CHUNK_SAMPLES (8000 * CHUNK_DURATION_SECONDS)
static int chunk_ready = 0;
static uint8_t* chunk_buffer = NULL;  // Compressed chunk for upload
static size_t chunk_size = 0;
static int chunk_sequence = 0;        // Sequence number for ordering

// VAD (Voice Activity Detection) configuration
#define VAD_FRAME_SIZE 160           // 20ms at 8kHz
#define VAD_THRESHOLD 300            // Energy threshold (tunable)
#define VAD_HOLDOVER_FRAMES 25       // Keep ~500ms after speech ends
static int vad_holdover = 0;         // Frames remaining in holdover
static int vad_enabled = 1;          // Can be disabled for testing

// μ-law encoding lookup table (ITU G.711 standard)
static uint8_t mulaw_encode_table[65536];
static int mulaw_table_initialized = 0;

// Downsampling state
static float sample_accumulator = 0.0f;
static float accumulated_samples = 0.0f;
static int sample_count = 0;

// WAV header structure
typedef struct {
    char riff[4];           // "RIFF"
    uint32_t file_size;     // File size - 8
    char wave[4];           // "WAVE"
    char fmt[4];            // "fmt "
    uint32_t fmt_size;      // 16 for PCM
    uint16_t audio_format;  // 1 for PCM
    uint16_t num_channels;  // 1 for mono
    uint32_t sample_rate;   // Sample rate
    uint32_t byte_rate;     // sample_rate * num_channels * bits_per_sample/8
    uint16_t block_align;   // num_channels * bits_per_sample/8
    uint16_t bits_per_sample; // 16
    char data[4];           // "data"
    uint32_t data_size;     // num_samples * num_channels * bits_per_sample/8
} WavHeader;

// ============================================================================
// μ-law Compression (ITU G.711 standard)
// Reduces 16-bit samples to 8-bit with logarithmic compression
// Optimized for speech - maintains quality while halving size
// ============================================================================

// Initialize μ-law encoding lookup table
static void init_mulaw_table(void) {
    if (mulaw_table_initialized) return;

    // μ-law encoding formula: F(x) = sgn(x) * ln(1 + μ|x|) / ln(1 + μ)
    // where μ = 255 for standard G.711
    const int BIAS = 0x84;
    const int CLIP = 32635;

    for (int i = 0; i < 65536; i++) {
        int16_t sample = (int16_t)i;
        int sign = (sample >> 8) & 0x80;

        if (sign) sample = -sample;
        if (sample > CLIP) sample = CLIP;

        sample += BIAS;

        int exponent = 7;
        for (int exp_mask = 0x4000; exp_mask > 0x80; exp_mask >>= 1) {
            if (sample & exp_mask) break;
            exponent--;
        }

        int mantissa = (sample >> (exponent + 3)) & 0x0F;
        mulaw_encode_table[i] = ~(sign | (exponent << 4) | mantissa);
    }

    mulaw_table_initialized = 1;
}

// Encode single 16-bit sample to 8-bit μ-law
static inline uint8_t mulaw_encode(int16_t sample) {
    return mulaw_encode_table[(uint16_t)sample];
}

// ============================================================================
// Voice Activity Detection (VAD)
// Simple energy-based detector to skip silence and reduce upload size
// ============================================================================

// VAD frame buffer for energy calculation
static int16_t vad_frame[VAD_FRAME_SIZE];
static int vad_frame_pos = 0;

// Calculate frame energy and determine if speech is present
static int frame_has_speech(void) {
    if (vad_frame_pos < VAD_FRAME_SIZE) return 1;  // Not enough samples yet

    // Calculate mean absolute energy (simpler than RMS, good enough for VAD)
    int32_t energy = 0;
    for (int i = 0; i < VAD_FRAME_SIZE; i++) {
        energy += abs(vad_frame[i]);
    }
    energy /= VAD_FRAME_SIZE;

    if (energy > VAD_THRESHOLD) {
        vad_holdover = VAD_HOLDOVER_FRAMES;  // Reset holdover when speech detected
        return 1;
    }

    // During holdover period, still output (prevents cutting off word endings)
    if (vad_holdover > 0) {
        vad_holdover--;
        return 1;
    }

    return 0;  // Silence - skip this frame
}

// ============================================================================
// Forward declarations
// ============================================================================

static int micCallback(void* context, int16_t* data, int len);
static void createWavHeader(WavHeader* header, size_t num_samples);

// Lua function: mic.startRecording()
static int mic_startRecording(lua_State* L) {
    if (is_recording) {
        pd->lua->pushBool(0);
        pd->lua->pushString("Already recording");
        return 2;
    }

    // Initialize μ-law encoding table (once)
    init_mulaw_table();

    // Allocate raw audio buffer (for backup/WAV export)
    buffer_size = INITIAL_BUFFER_SAMPLES;
    audio_buffer = (int16_t*)pd->system->realloc(NULL, buffer_size * sizeof(int16_t));
    if (!audio_buffer) {
        pd->lua->pushBool(0);
        pd->lua->pushString("Failed to allocate audio buffer");
        return 2;
    }

    // Allocate compressed buffer (same size in samples, but 1 byte each)
    compressed_buffer = (uint8_t*)pd->system->realloc(NULL, buffer_size);
    if (!compressed_buffer) {
        pd->system->realloc(audio_buffer, 0);
        audio_buffer = NULL;
        pd->lua->pushBool(0);
        pd->lua->pushString("Failed to allocate compressed buffer");
        return 2;
    }

    buffer_position = 0;
    compressed_position = 0;
    sample_accumulator = 0.0f;
    accumulated_samples = 0.0f;
    sample_count = 0;
    current_level = 0.0f;
    chunk_ready = 0;
    chunk_sequence = 0;
    vad_holdover = 0;
    vad_frame_pos = 0;

    // Clear any previous chunk
    if (chunk_buffer) {
        pd->system->realloc(chunk_buffer, 0);
        chunk_buffer = NULL;
        chunk_size = 0;
    }

    // Start mic capture
    pd->sound->setMicCallback(micCallback, NULL, kMicInputAutodetect);
    is_recording = 1;

    pd->lua->pushBool(1);
    return 1;
}

// Lua function: mic.stopRecording() -> returns WAV data as string (backup format)
static int mic_stopRecording(lua_State* L) {
    if (!is_recording) {
        pd->lua->pushNil();
        pd->lua->pushString("Not recording");
        return 2;
    }

    // Stop mic capture
    pd->sound->setMicCallback(NULL, NULL, kMicInputAutodetect);
    is_recording = 0;

    if (!audio_buffer || buffer_position == 0) {
        if (audio_buffer) {
            pd->system->realloc(audio_buffer, 0);
            audio_buffer = NULL;
        }
        if (compressed_buffer) {
            pd->system->realloc(compressed_buffer, 0);
            compressed_buffer = NULL;
        }
        pd->lua->pushNil();
        pd->lua->pushString("No audio recorded");
        return 2;
    }

    // Create WAV data (8kHz, 16-bit for backup/local storage)
    WavHeader header;
    createWavHeader(&header, buffer_position);

    size_t wav_size = sizeof(WavHeader) + (buffer_position * sizeof(int16_t));
    char* wav_data = (char*)pd->system->realloc(NULL, wav_size);
    if (!wav_data) {
        pd->system->realloc(audio_buffer, 0);
        audio_buffer = NULL;
        pd->system->realloc(compressed_buffer, 0);
        compressed_buffer = NULL;
        pd->lua->pushNil();
        pd->lua->pushString("Failed to allocate WAV buffer");
        return 2;
    }

    memcpy(wav_data, &header, sizeof(WavHeader));
    memcpy(wav_data + sizeof(WavHeader), audio_buffer, buffer_position * sizeof(int16_t));

    // Push as Lua string (binary data)
    pd->lua->pushBytes(wav_data, wav_size);

    // Cleanup
    pd->system->realloc(wav_data, 0);
    pd->system->realloc(audio_buffer, 0);
    audio_buffer = NULL;
    pd->system->realloc(compressed_buffer, 0);
    compressed_buffer = NULL;
    buffer_size = 0;
    buffer_position = 0;
    compressed_position = 0;

    // Clear chunk if any
    if (chunk_buffer) {
        pd->system->realloc(chunk_buffer, 0);
        chunk_buffer = NULL;
        chunk_size = 0;
    }

    return 1;
}

// Lua function: mic.getLevel() -> returns current mic level 0.0-1.0
static int mic_getLevel(lua_State* L) {
    pd->lua->pushFloat(current_level);
    return 1;
}

// Lua function: mic.isRecording() -> returns boolean
static int mic_isRecording(lua_State* L) {
    pd->lua->pushBool(is_recording);
    return 1;
}

// Lua function: mic.hasChunk() -> returns boolean (true if 30s compressed chunk ready)
static int mic_hasChunk(lua_State* L) {
    pd->lua->pushBool(chunk_ready);
    return 1;
}

// Lua function: mic.getChunk() -> returns μ-law compressed data for upload, clears chunk
static int mic_getChunk(lua_State* L) {
    if (!chunk_ready || !chunk_buffer || chunk_size == 0) {
        pd->lua->pushNil();
        return 1;
    }

    // Return raw μ-law compressed data (no WAV header - server handles decoding)
    pd->lua->pushBytes((char*)chunk_buffer, chunk_size);

    // Cleanup chunk
    pd->system->realloc(chunk_buffer, 0);
    chunk_buffer = NULL;
    chunk_size = 0;
    chunk_ready = 0;

    return 1;
}

// Lua function: mic.getChunkSequence() -> returns current chunk sequence number
static int mic_getChunkSequence(lua_State* L) {
    pd->lua->pushInt(chunk_sequence);
    return 1;
}

// Lua function: mic.setVADEnabled(enabled) -> enable/disable VAD for testing
static int mic_setVADEnabled(lua_State* L) {
    vad_enabled = pd->lua->getArgBool(1);
    pd->lua->pushBool(1);
    return 1;
}

// Lua function: mic.getDuration() -> returns recording duration in seconds
static int mic_getDuration(lua_State* L) {
    if (!is_recording || !audio_buffer) {
        pd->lua->pushFloat(0.0f);
        return 1;
    }
    pd->lua->pushFloat((float)buffer_position / (float)SAMPLE_RATE_OUTPUT);
    return 1;
}

// Microphone callback - called by Playdate audio system
// Processes: 44.1kHz input → 8kHz downsample → VAD filter → μ-law encode
static int micCallback(void* context, int16_t* data, int len) {
    (void)context;

    if (!is_recording || !audio_buffer || !compressed_buffer) {
        return 0;
    }

    // Calculate level from this buffer (RMS)
    float sum = 0;
    for (int i = 0; i < len; i++) {
        float sample = data[i] / 32768.0f;
        sum += sample * sample;
    }
    current_level = sqrtf(sum / (float)len);

    // Downsample from 44.1kHz to 8kHz
    for (int i = 0; i < len; i++) {
        accumulated_samples += data[i];
        sample_count++;
        sample_accumulator += 1.0f;

        // Output a sample when we've accumulated enough
        if (sample_accumulator >= DOWNSAMPLE_FACTOR) {
            // Check if we need to grow the buffers
            if (buffer_position >= buffer_size) {
                size_t new_size = buffer_size + BUFFER_GROW_SAMPLES;

                int16_t* new_buffer = (int16_t*)pd->system->realloc(audio_buffer, new_size * sizeof(int16_t));
                if (!new_buffer) {
                    return 0;  // Out of memory
                }
                audio_buffer = new_buffer;

                uint8_t* new_compressed = (uint8_t*)pd->system->realloc(compressed_buffer, new_size);
                if (!new_compressed) {
                    return 0;  // Out of memory
                }
                compressed_buffer = new_compressed;

                buffer_size = new_size;
            }

            // Average the accumulated samples
            int16_t output_sample = (int16_t)(accumulated_samples / sample_count);

            // Store raw sample (for backup WAV)
            audio_buffer[buffer_position] = output_sample;

            // VAD: Add sample to frame buffer
            vad_frame[vad_frame_pos % VAD_FRAME_SIZE] = output_sample;
            vad_frame_pos++;

            // Apply VAD and μ-law encoding
            if (!vad_enabled || frame_has_speech()) {
                // Encode to μ-law and store in compressed buffer
                compressed_buffer[compressed_position++] = mulaw_encode(output_sample);
            }
            // If VAD says silence, skip adding to compressed buffer (saves space!)

            buffer_position++;
            accumulated_samples = 0.0f;
            sample_count = 0;
            sample_accumulator -= DOWNSAMPLE_FACTOR;
        }

        // Check for chunk boundary (30 seconds of raw samples = time to create compressed chunk)
        if (buffer_position > 0 && buffer_position % CHUNK_SAMPLES == 0 && !chunk_ready) {
            // Create compressed chunk from the accumulated compressed data
            // Note: compressed_position may be less than CHUNK_SAMPLES due to VAD filtering

            chunk_size = compressed_position;
            if (chunk_size > 0) {
                chunk_buffer = (uint8_t*)pd->system->realloc(NULL, chunk_size);
                if (chunk_buffer) {
                    memcpy(chunk_buffer, compressed_buffer, chunk_size);
                    chunk_ready = 1;
                    chunk_sequence++;
                }
            }

            // Reset compressed buffer for next chunk
            compressed_position = 0;
        }
    }

    return 1;
}

// Create WAV header for given number of samples
static void createWavHeader(WavHeader* header, size_t num_samples) {
    size_t data_size = num_samples * sizeof(int16_t);

    memcpy(header->riff, "RIFF", 4);
    header->file_size = (uint32_t)(sizeof(WavHeader) - 8 + data_size);
    memcpy(header->wave, "WAVE", 4);
    memcpy(header->fmt, "fmt ", 4);
    header->fmt_size = 16;
    header->audio_format = 1;  // PCM
    header->num_channels = 1;  // Mono
    header->sample_rate = SAMPLE_RATE_OUTPUT;
    header->bits_per_sample = 16;
    header->byte_rate = SAMPLE_RATE_OUTPUT * 1 * 2;  // sample_rate * channels * bytes_per_sample
    header->block_align = 1 * 2;  // channels * bytes_per_sample
    memcpy(header->data, "data", 4);
    header->data_size = (uint32_t)data_size;
}

// Lua binding registration table
static const lua_reg mic_lib[] = {
    { "startRecording", mic_startRecording },
    { "stopRecording", mic_stopRecording },
    { "getLevel", mic_getLevel },
    { "isRecording", mic_isRecording },
    { "hasChunk", mic_hasChunk },
    { "getChunk", mic_getChunk },
    { "getChunkSequence", mic_getChunkSequence },
    { "getDuration", mic_getDuration },
    { "setVADEnabled", mic_setVADEnabled },
    { NULL, NULL }
};

// Extension event handler
#ifdef _WINDLL
__declspec(dllexport)
#endif
int eventHandler(PlaydateAPI* playdate, PDSystemEvent event, uint32_t arg) {
    (void)arg;

    if (event == kEventInitLua) {
        pd = playdate;

        const char* err;
        if (!pd->lua->registerClass("mic", mic_lib, NULL, 0, &err)) {
            pd->system->logToConsole("Failed to register mic class: %s", err);
            return -1;
        }
    }

    return 0;
}
