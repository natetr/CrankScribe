/*
 * CrankScribe Microphone Capture Extension
 *
 * Captures audio from Playdate's microphone, downsamples from 44.1kHz to 16kHz
 * for Whisper compatibility, and provides WAV export functionality.
 */

#include <stdlib.h>
#include <string.h>
#include <math.h>
#include "pd_api.h"

static PlaydateAPI* pd = NULL;

// Audio configuration
#define SAMPLE_RATE_INPUT   44100   // Playdate native sample rate
#define SAMPLE_RATE_OUTPUT  16000   // Whisper expected sample rate
#define DOWNSAMPLE_FACTOR   2.75625f // 44100/16000

// Recording state
static int is_recording = 0;
static int16_t* audio_buffer = NULL;
static size_t buffer_size = 0;         // Allocated size in samples
static size_t buffer_position = 0;     // Current write position in samples
static float current_level = 0.0f;

// Initial buffer size: 30 seconds at 16kHz (grows as needed)
#define INITIAL_BUFFER_SAMPLES (16000 * 30)
#define BUFFER_GROW_SAMPLES    (16000 * 30)  // Grow by 30 seconds

// Chunk tracking for long recordings
#define CHUNK_DURATION_SECONDS 300  // 5 minutes per chunk
#define CHUNK_SAMPLES (16000 * CHUNK_DURATION_SECONDS)
static int chunk_ready = 0;
static int16_t* chunk_buffer = NULL;
static size_t chunk_size = 0;

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
    uint32_t sample_rate;   // 16000
    uint32_t byte_rate;     // sample_rate * num_channels * bits_per_sample/8
    uint16_t block_align;   // num_channels * bits_per_sample/8
    uint16_t bits_per_sample; // 16
    char data[4];           // "data"
    uint32_t data_size;     // num_samples * num_channels * bits_per_sample/8
} WavHeader;

// Forward declarations
static int micCallback(void* context, int16_t* data, int len);
static void createWavHeader(WavHeader* header, size_t num_samples);

// Lua function: mic.startRecording()
static int mic_startRecording(lua_State* L) {
    if (is_recording) {
        pd->lua->pushBool(0);
        pd->lua->pushString("Already recording");
        return 2;
    }

    // Allocate initial buffer
    buffer_size = INITIAL_BUFFER_SAMPLES;
    audio_buffer = (int16_t*)pd->system->realloc(NULL, buffer_size * sizeof(int16_t));
    if (!audio_buffer) {
        pd->lua->pushBool(0);
        pd->lua->pushString("Failed to allocate audio buffer");
        return 2;
    }

    buffer_position = 0;
    sample_accumulator = 0.0f;
    accumulated_samples = 0.0f;
    sample_count = 0;
    current_level = 0.0f;
    chunk_ready = 0;

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

// Lua function: mic.stopRecording() -> returns WAV data as string
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
        pd->lua->pushNil();
        pd->lua->pushString("No audio recorded");
        return 2;
    }

    // Create WAV data
    WavHeader header;
    createWavHeader(&header, buffer_position);

    size_t wav_size = sizeof(WavHeader) + (buffer_position * sizeof(int16_t));
    char* wav_data = (char*)pd->system->realloc(NULL, wav_size);
    if (!wav_data) {
        pd->system->realloc(audio_buffer, 0);
        audio_buffer = NULL;
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
    buffer_size = 0;
    buffer_position = 0;

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

// Lua function: mic.hasChunk() -> returns boolean (true if 5-min chunk ready)
static int mic_hasChunk(lua_State* L) {
    pd->lua->pushBool(chunk_ready);
    return 1;
}

// Lua function: mic.getChunk() -> returns WAV data for the chunk, clears chunk
static int mic_getChunk(lua_State* L) {
    if (!chunk_ready || !chunk_buffer || chunk_size == 0) {
        pd->lua->pushNil();
        return 1;
    }

    // Create WAV data for chunk
    WavHeader header;
    createWavHeader(&header, chunk_size);

    size_t wav_size = sizeof(WavHeader) + (chunk_size * sizeof(int16_t));
    char* wav_data = (char*)pd->system->realloc(NULL, wav_size);
    if (!wav_data) {
        pd->lua->pushNil();
        return 1;
    }

    memcpy(wav_data, &header, sizeof(WavHeader));
    memcpy(wav_data + sizeof(WavHeader), chunk_buffer, chunk_size * sizeof(int16_t));

    pd->lua->pushBytes(wav_data, wav_size);

    // Cleanup chunk
    pd->system->realloc(wav_data, 0);
    pd->system->realloc(chunk_buffer, 0);
    chunk_buffer = NULL;
    chunk_size = 0;
    chunk_ready = 0;

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
static int micCallback(void* context, int16_t* data, int len) {
    (void)context;

    if (!is_recording || !audio_buffer) {
        return 0;
    }

    // Calculate level from this buffer (RMS)
    float sum = 0;
    for (int i = 0; i < len; i++) {
        float sample = data[i] / 32768.0f;
        sum += sample * sample;
    }
    current_level = sqrtf(sum / (float)len);

    // Downsample from 44.1kHz to 16kHz
    for (int i = 0; i < len; i++) {
        accumulated_samples += data[i];
        sample_count++;
        sample_accumulator += 1.0f;

        // Output a sample when we've accumulated enough
        if (sample_accumulator >= DOWNSAMPLE_FACTOR) {
            // Check if we need to grow the buffer
            if (buffer_position >= buffer_size) {
                size_t new_size = buffer_size + BUFFER_GROW_SAMPLES;
                int16_t* new_buffer = (int16_t*)pd->system->realloc(audio_buffer, new_size * sizeof(int16_t));
                if (!new_buffer) {
                    // Out of memory - stop recording
                    return 0;
                }
                audio_buffer = new_buffer;
                buffer_size = new_size;
            }

            // Average the accumulated samples
            audio_buffer[buffer_position++] = (int16_t)(accumulated_samples / sample_count);

            accumulated_samples = 0.0f;
            sample_count = 0;
            sample_accumulator -= DOWNSAMPLE_FACTOR;
        }

        // Check for chunk boundary (5 minutes)
        if (buffer_position > 0 && buffer_position % CHUNK_SAMPLES == 0 && !chunk_ready) {
            // Copy last CHUNK_SAMPLES to chunk buffer
            size_t chunk_start = buffer_position - CHUNK_SAMPLES;
            chunk_size = CHUNK_SAMPLES;
            chunk_buffer = (int16_t*)pd->system->realloc(NULL, chunk_size * sizeof(int16_t));
            if (chunk_buffer) {
                memcpy(chunk_buffer, audio_buffer + chunk_start, chunk_size * sizeof(int16_t));
                chunk_ready = 1;
            }
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
    { "getDuration", mic_getDuration },
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
