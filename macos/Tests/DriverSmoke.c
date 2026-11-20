#include <CoreAudio/AudioServerPlugIn.h>
#include <assert.h>
#include <dlfcn.h>
#include <math.h>
#include <stdio.h>

static OSStatus readEmpty(AudioServerPlugInHostRef host, CFStringRef key, CFPropertyListRef *result)
{
    (void)host;
    (void)key;
    *result = NULL;
    return noErr;
}

int main(int argc, char **argv)
{
    assert(argc == 2);
    void *library = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
    if (!library) { fprintf(stderr, "%s\n", dlerror()); return 1; }
    AudioServerPlugInDriverRef (*factory)(CFAllocatorRef, CFUUIDRef) = dlsym(library, "NullAudio_Create");
    assert(factory);
    AudioServerPlugInDriverRef driver = factory(kCFAllocatorDefault, kAudioServerPlugInTypeUUID);
    assert(driver);
    AudioServerPlugInHostInterface host = { .CopyFromStorage = readEmpty };
    assert((*driver)->Initialize(driver, &host) == noErr);

    AudioObjectPropertyAddress property = {
        kAudioPlugInPropertyDeviceList, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain
    };
    AudioObjectID device = 0;
    UInt32 used = 0;
    assert((*driver)->GetPropertyData(driver, kAudioObjectPlugInObject, 0, &property, 0, NULL,
                                      sizeof(device), &used, &device) == noErr && device != 0);
    property.mSelector = kAudioDevicePropertyStreams;
    property.mScope = kAudioObjectPropertyScopeOutput;
    assert((*driver)->GetPropertyDataSize(driver, device, 0, &property, 0, NULL, &used) == noErr && used == 0);
    property.mScope = kAudioObjectPropertyScopeInput;
    AudioObjectID stream = 0;
    assert((*driver)->GetPropertyData(driver, device, 0, &property, 0, NULL,
                                      sizeof(stream), &used, &stream) == noErr && stream != 0);
    Boolean willDo = 0;
    Boolean inPlace = 0;
    assert((*driver)->WillDoIOOperation(driver, device, 1, kAudioServerPlugInIOOperationReadInput, &willDo, &inPlace) == noErr &&
           willDo && inPlace);
    AudioServerPlugInIOCycleInfo cycle = { .mInputTime = { .mSampleTime = 45000 } };
    float buffer[1024] = {0};
    assert((*driver)->DoIOOperation(driver, device, stream, 1, kAudioServerPlugInIOOperationReadInput, 512,
                                    &cycle, buffer, NULL) == noErr);
    float energy = 0;
    for (int i = 0; i < 1024; i += 2) {
        assert(isfinite(buffer[i]) && buffer[i] == buffer[i + 1]);
        energy += fabsf(buffer[i]);
    }
    assert(energy > 0.1);
    printf("Piano microphone HAL callbacks produced audio with one input stream and zero output streams.\n");
    return 0;
}
