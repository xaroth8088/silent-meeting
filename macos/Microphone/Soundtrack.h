#ifndef SILENT_MEETING_SOUNDTRACK_H
#define SILENT_MEETING_SOUNDTRACK_H

#include <stdbool.h>
#include <stdint.h>

bool SilentMeetingLoadSoundtrack(void);
void SilentMeetingReadSoundtrack(float *stereo, uint32_t frames, double sampleTime,
                                 double sampleRate, float volume, bool muted);

#endif
