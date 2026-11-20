#include "Soundtrack.h"

#include <dlfcn.h>
#include <limits.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const double soundtrackRate = 48000.0;
static const float *soundtrack;
static size_t soundtrackFrames;

bool SilentMeetingLoadSoundtrack(void)
{
    if (soundtrack) return true;

    Dl_info info = { 0 };
    if (!dladdr((const void *)&SilentMeetingLoadSoundtrack, &info) || !info.dli_fname) return false;
    const char *lastSlash = strrchr(info.dli_fname, '/');
    if (!lastSlash) return false;

    char path[PATH_MAX];
    int length = snprintf(path, sizeof(path), "%.*s/../Resources/maple-leaf-rag.f32",
                          (int)(lastSlash - info.dli_fname), info.dli_fname);
    if (length < 0 || length >= (int)sizeof(path)) return false;

    FILE *file = fopen(path, "rb");
    if (!file) return false;
    long bytes = -1;
    if (fseek(file, 0, SEEK_END) == 0) bytes = ftell(file);
    float *samples = NULL;
    if (bytes > 0 && bytes <= 64 * 1024 * 1024 &&
        bytes % (long)sizeof(float) == 0 && fseek(file, 0, SEEK_SET) == 0) {
        samples = malloc((size_t)bytes);
        if (samples && fread(samples, 1, (size_t)bytes, file) != (size_t)bytes) {
            free(samples);
            samples = NULL;
        }
    }
    fclose(file);
    if (!samples) return false;
    soundtrackFrames = (size_t)bytes / sizeof(float);
    soundtrack = samples;
    return true;
}

void SilentMeetingReadSoundtrack(float *stereo, uint32_t frames, double sampleTime,
                                 double sampleRate, float volume, bool muted)
{
    if (!soundtrack || muted || volume <= 0 || sampleRate <= 0 || !isfinite(sampleTime)) {
        memset(stereo, 0, frames * 2 * sizeof(float));
        return;
    }
    // Core Audio supplies a shared hardware timeline for all clients reading the microphone.
    const double step = soundtrackRate / sampleRate;
    double cursor = fmod(fmax(0, sampleTime) * step, (double)soundtrackFrames);
    for (uint32_t i = 0; i < frames; ++i) {
        const size_t a = (size_t)cursor;
        const size_t b = a + 1 == soundtrackFrames ? 0 : a + 1;
        const float mix = (float)(cursor - (double)a);
        const float sample = (soundtrack[a] + mix * (soundtrack[b] - soundtrack[a])) * volume;
        stereo[2 * i] = sample;
        stereo[2 * i + 1] = sample;
        cursor += step;
        if (cursor >= (double)soundtrackFrames) cursor -= (double)soundtrackFrames;
    }
}
