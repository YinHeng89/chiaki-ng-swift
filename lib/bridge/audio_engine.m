#import <AVFoundation/AVFoundation.h>
#include <TargetConditionals.h>
#if TARGET_OS_OSX
#import <CoreAudio/CoreAudio.h>
#endif

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "audio.h"

typedef struct {
  nx_audio* audio;
  uint32_t channels;
  uint32_t bed_channels;
  int16_t samples[NX_AUDIO_MAX_PULL_FRAMES * NX_AUDIO_MAX_CHANNELS];
} nx_audio_engine_render;

enum { NX_AUDIO_SPATIAL_BED_CHANNELS = 8 };

static AudioChannelLayoutTag layout_tag(uint32_t channels) {
  switch (channels) {
    case 1:
      return kAudioChannelLayoutTag_Mono;
    case 2:
      return kAudioChannelLayoutTag_Stereo;
    case 6:
      return kAudioChannelLayoutTag_WAVE_5_1_A;
    case 8:
      return kAudioChannelLayoutTag_WAVE_7_1;
    case 12:
      return kAudioChannelLayoutTag_Atmos_7_1_4;
    default:
      return kAudioChannelLayoutTag_DiscreteInOrder | channels;
  }
}

#if TARGET_OS_OSX
static AudioObjectID *output_device_ids(UInt32 *count) {
  AudioObjectPropertyAddress devices = {kAudioHardwarePropertyDevices,
                                        kAudioObjectPropertyScopeGlobal,
                                        kAudioObjectPropertyElementMain};
  UInt32 size = 0;
  *count = 0;
  if (AudioObjectGetPropertyDataSize(kAudioObjectSystemObject, &devices, 0,
                                     NULL, &size) != noErr ||
      !size) {
    return NULL;
  }
  AudioObjectID *ids = malloc(size);
  if (!ids) {
    return NULL;
  }
  if (AudioObjectGetPropertyData(kAudioObjectSystemObject, &devices, 0, NULL,
                                 &size, ids) != noErr) {
    free(ids);
    return NULL;
  }
  *count = size / sizeof(AudioObjectID);
  return ids;
}

static bool has_output(AudioObjectID device) {
  AudioObjectPropertyAddress streams = {kAudioDevicePropertyStreams,
                                        kAudioObjectPropertyScopeOutput,
                                        kAudioObjectPropertyElementMain};
  UInt32 size = 0;
  return AudioObjectGetPropertyDataSize(device, &streams, 0, NULL, &size) ==
             noErr &&
         size > 0;
}

static bool device_name(AudioObjectID device, char *name, size_t capacity) {
  AudioObjectPropertyAddress address = {kAudioObjectPropertyName,
                                        kAudioObjectPropertyScopeGlobal,
                                        kAudioObjectPropertyElementMain};
  CFStringRef value = NULL;
  UInt32 size = sizeof(value);
  if (AudioObjectGetPropertyData(device, &address, 0, NULL, &size, &value) !=
          noErr ||
      !value) {
    return false;
  }
  bool copied =
      CFStringGetCString(value, name, (CFIndex)capacity, kCFStringEncodingUTF8);
  CFRelease(value);
  return copied && name[0];
}

static AudioObjectID output_device_named(const char *wanted) {
  UInt32 count = 0;
  AudioObjectID *ids = output_device_ids(&count);
  AudioObjectID found = kAudioObjectUnknown;
  char name[NX_AUDIO_DEVICE_NAME_SIZE];
  for (UInt32 index = 0; ids && index < count; index++) {
    if (has_output(ids[index]) &&
        device_name(ids[index], name, sizeof(name)) && !strcmp(name, wanted)) {
      found = ids[index];
      break;
    }
  }
  free(ids);
  return found;
}
#endif

@interface CNAudioEngineOutput : NSObject
- (instancetype)initWithAudio:(nx_audio *)audio
                     channels:(uint32_t)channels
                   sampleRate:(uint32_t)sampleRate
                       device:(const char *)device
                      spatial:(BOOL)spatial
                          log:(nx_bridge_log *)log;
- (BOOL)start;
- (void)close;
- (void)setGain:(float)gain;
@end

@implementation CNAudioEngineOutput {
  AVAudioEngine *_engine;
  AVAudioSourceNode *_source;
  AVAudioEnvironmentNode *_spatial;
  AVAudioFormat *_format;
  nx_audio_engine_render *_render;
  nx_bridge_log *_log;
  NSString *_device;
  id _observer;
  dispatch_queue_t _queue;
  BOOL _closed;
}

- (instancetype)initWithAudio:(nx_audio *)audio
                     channels:(uint32_t)channels
                   sampleRate:(uint32_t)sampleRate
                       device:(const char *)device
                      spatial:(BOOL)spatial
                          log:(nx_bridge_log *)log {
  self = [super init];
  if (!self) {
    return nil;
  }
  _log = log;
  _device = device ? [NSString stringWithUTF8String:device] : nil;
  _queue = dispatch_queue_create("dev.chiaki-ng.audio-output",
                                 DISPATCH_QUEUE_SERIAL);
  _render = calloc(1, sizeof(*_render));
  if (!_render) {
    return nil;
  }
  _render->audio = audio;
  _render->channels = channels;
  BOOL stereoBed = spatial && channels == 2;
  _render->bed_channels =
      stereoBed ? NX_AUDIO_SPATIAL_BED_CHANNELS : channels;
  AVAudioChannelLayout *layout = [[AVAudioChannelLayout alloc]
      initWithLayoutTag:layout_tag(_render->bed_channels)];
  _format = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:sampleRate
                                                      channelLayout:layout];
  if (!_format) {
    free(_render);
    _render = NULL;
    return nil;
  }
  nx_audio_engine_render *render = _render;
  _source = [[AVAudioSourceNode alloc]
      initWithFormat:_format
         renderBlock:^OSStatus(BOOL *isSilence,
                               const AudioTimeStamp *timestamp,
                               AVAudioFrameCount frameCount,
                               AudioBufferList *outputData) {
           (void)timestamp;
           uint32_t channels = render->channels;
           uint32_t bed = render->bed_channels;
           AVAudioFrameCount done = 0;
           size_t supplied = 0;
           while (done < frameCount) {
             AVAudioFrameCount chunk = frameCount - done;
             if (chunk > NX_AUDIO_MAX_PULL_FRAMES) {
               chunk = NX_AUDIO_MAX_PULL_FRAMES;
             }
             supplied += nx_audio_pull(render->audio, render->samples, chunk);
             for (UInt32 buffer = 0;
                  buffer < outputData->mNumberBuffers && buffer < bed;
                  buffer++) {
               float *destination = (float *)outputData->mBuffers[buffer].mData;
               if (buffer >= channels) {
                 memset(destination + done, 0, chunk * sizeof(float));
                 continue;
               }
               for (AVAudioFrameCount frame = 0; frame < chunk; frame++) {
                 destination[done + frame] =
                     (float)render->samples[frame * channels + buffer] /
                     32768.0f;
               }
             }
             done += chunk;
           }
           *isSilence = supplied == 0;
           return noErr;
         }];
  _engine = [[AVAudioEngine alloc] init];
  [_engine attachNode:_source];
  if (stereoBed) {
    _spatial = [[AVAudioEnvironmentNode alloc] init];
    _spatial.outputType = AVAudioEnvironmentOutputTypeAuto;
    _spatial.listenerHeadTrackingEnabled = YES;
    _source.sourceMode = AVAudio3DMixingSourceModeAmbienceBed;
    _source.renderingAlgorithm = AVAudio3DMixingRenderingAlgorithmAuto;
    [_engine attachNode:_spatial];
    [_engine connect:_source to:_spatial format:_format];
    [_engine connect:_spatial to:_engine.mainMixerNode format:nil];
  } else {
    [_engine connect:_source to:_engine.mainMixerNode format:_format];
  }
  return self;
}

- (void)dealloc {
  free(_render);
}

- (void)log:(int)level message:(NSString *)message {
  nx_bridge_log_write(_log, level, "%s", message.UTF8String);
}

- (void)selectDevice {
#if TARGET_OS_OSX
  if (!_device.length) {
    return;
  }
  AudioObjectID device = output_device_named(_device.UTF8String);
  if (device == kAudioObjectUnknown) {
    [self log:NX_LOG_WARNING
        message:[NSString stringWithFormat:@"Audio output \"%@\" is not "
                                           @"connected; using the system "
                                           @"default output",
                                           _device]];
    return;
  }
  OSStatus status = AudioUnitSetProperty(
      _engine.outputNode.audioUnit, kAudioOutputUnitProperty_CurrentDevice,
      kAudioUnitScope_Global, 0, &device, sizeof(device));
  if (status != noErr) {
    [self log:NX_LOG_WARNING
        message:[NSString stringWithFormat:@"Audio output \"%@\" could not be "
                                           @"selected (%d); using the system "
                                           @"default output",
                                           _device, (int)status]];
  }
#endif
}

- (BOOL)prepareSession {
#if TARGET_OS_IOS || TARGET_OS_TV || TARGET_OS_VISION
  AVAudioSession *session = AVAudioSession.sharedInstance;
  NSError *error = nil;
  AVAudioSessionCategoryOptions options =
      AVAudioSessionCategoryOptionMixWithOthers |
      AVAudioSessionCategoryOptionDuckOthers;
  if (![session setCategory:AVAudioSessionCategoryPlayback
                       mode:AVAudioSessionModeDefault
                    options:options
                      error:&error]) {
    [self log:NX_LOG_ERROR
        message:[NSString stringWithFormat:@"Audio session category failed: %@",
                                           error.localizedDescription]];
    return NO;
  }
  [session setSupportsMultichannelContent:YES error:nil];
  if (![session setActive:YES error:&error]) {
    [self log:NX_LOG_ERROR
        message:[NSString stringWithFormat:@"Audio session activation failed: %@",
                                           error.localizedDescription]];
    return NO;
  }
  NSInteger wanted = MIN((NSInteger)_render->channels,
                         session.maximumOutputNumberOfChannels);
  if (wanted > session.outputNumberOfChannels) {
    [session setPreferredOutputNumberOfChannels:wanted error:nil];
  }
#endif
  return YES;
}

- (BOOL)startEngine {
  [self selectDevice];
  AVAudioFormat *hardware = [_engine.outputNode outputFormatForBus:0];
  [_engine connect:_engine.mainMixerNode to:_engine.outputNode format:hardware];
  [_engine prepare];
  NSError *error = nil;
  if (![_engine startAndReturnError:&error]) {
    [self log:NX_LOG_ERROR
        message:[NSString stringWithFormat:@"AVAudioEngine failed to start: %@",
                                           error.localizedDescription]];
    return NO;
  }
  [self log:NX_LOG_INFO
      message:[NSString
                  stringWithFormat:@"AVAudioEngine playing %u channels on a "
                                   @"%u-channel output at %.0f Hz",
                                   _render->channels,
                                   (unsigned)hardware.channelCount,
                                   hardware.sampleRate]];
  if (_spatial) {
    [self log:NX_LOG_INFO
        message:[NSString stringWithFormat:@"Spatial audio rendering stereo "
                                           @"through a 7.1 bed for output type "
                                           @"%ld",
                                           (long)_spatial.outputType]];
  }
  return YES;
}

- (BOOL)start {
  if (![self prepareSession]) {
    return NO;
  }
  __weak CNAudioEngineOutput *weakSelf = self;
  _observer = [NSNotificationCenter.defaultCenter
      addObserverForName:AVAudioEngineConfigurationChangeNotification
                  object:_engine
                   queue:nil
              usingBlock:^(NSNotification *note) {
                (void)note;
                CNAudioEngineOutput *strongSelf = weakSelf;
                if (strongSelf) {
                  dispatch_async(strongSelf->_queue, ^{
                    [strongSelf restart];
                  });
                }
              }];
  __block BOOL started = NO;
  dispatch_sync(_queue, ^{
    started = [self startEngine];
  });
  return started;
}

- (void)restart {
  if (_closed) {
    return;
  }
  [self log:NX_LOG_INFO message:@"Audio output changed; restarting playback"];
  [_engine stop];
  [self startEngine];
}

- (void)close {
  if (_observer) {
    [NSNotificationCenter.defaultCenter removeObserver:_observer];
    _observer = nil;
  }
  dispatch_sync(_queue, ^{
    self->_closed = YES;
    [self->_engine stop];
  });
#if TARGET_OS_IOS || TARGET_OS_TV || TARGET_OS_VISION
  [AVAudioSession.sharedInstance
        setActive:NO
      withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation
            error:nil];
#endif
}

- (void)setGain:(float)gain {
  _engine.mainMixerNode.outputVolume = gain;
}

@end

static void *engine_open(nx_audio *audio, uint32_t channels,
                         uint32_t sample_rate, const char *device, float gain,
                         bool spatial, nx_bridge_log *log) {
  @autoreleasepool {
    CNAudioEngineOutput *output =
        [[CNAudioEngineOutput alloc] initWithAudio:audio
                                          channels:channels
                                        sampleRate:sample_rate
                                            device:device
                                           spatial:spatial
                                               log:log];
    if (!output) {
      nx_bridge_log_write(log, NX_LOG_ERROR,
                          "Audio output has no format for %u channels",
                          channels);
      return NULL;
    }
    [output setGain:gain];
    if (![output start]) {
      [output close];
      return NULL;
    }
    return (__bridge_retained void *)output;
  }
}

static void engine_close(void *handle) {
  @autoreleasepool {
    CNAudioEngineOutput *output = (__bridge_transfer CNAudioEngineOutput *)handle;
    [output close];
  }
}

static void engine_set_gain(void *handle, float gain) {
  @autoreleasepool {
    [(__bridge CNAudioEngineOutput *)handle setGain:gain];
  }
}

nx_audio *nx_audio_create(nx_bridge_log *log) {
  return nx_audio_create_with_output(log, nx_audio_engine_output());
}

const nx_audio_output_ops *nx_audio_engine_output(void) {
  static const nx_audio_output_ops ops = {
      .open = engine_open, .close = engine_close, .set_gain = engine_set_gain};
  return &ops;
}

#if TARGET_OS_OSX
static AudioObjectID default_output_device(void) {
  AudioObjectPropertyAddress address = {
      kAudioHardwarePropertyDefaultOutputDevice,
      kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain};
  AudioObjectID device = kAudioObjectUnknown;
  UInt32 size = sizeof(device);
  if (AudioObjectGetPropertyData(kAudioObjectSystemObject, &address, 0, NULL,
                                 &size, &device) != noErr) {
    return kAudioObjectUnknown;
  }
  return device;
}

static UInt32 device_property(AudioObjectID device, AudioObjectPropertySelector
                                                        selector,
                              AudioObjectPropertyScope scope) {
  AudioObjectPropertyAddress address = {selector, scope,
                                        kAudioObjectPropertyElementMain};
  UInt32 value = 0;
  UInt32 size = sizeof(value);
  if (!AudioObjectHasProperty(device, &address) ||
      AudioObjectGetPropertyData(device, &address, 0, NULL, &size, &value) !=
          noErr) {
    return 0;
  }
  return value;
}

static bool device_is_dualsense(AudioObjectID device) {
  char name[NX_AUDIO_DEVICE_NAME_SIZE] = {0};
  return device_name(device, name, sizeof(name)) &&
         (strstr(name, "DualSense") || strstr(name, "Wireless Controller"));
}

static bool device_is_playing(AudioObjectID device) {
  AudioObjectPropertyAddress address = {kAudioDevicePropertyNominalSampleRate,
                                        kAudioObjectPropertyScopeGlobal,
                                        kAudioObjectPropertyElementMain};
  Float64 rate = 0;
  UInt32 size = sizeof(rate);
  return device_property(device, kAudioDevicePropertyDeviceIsAlive,
                         kAudioObjectPropertyScopeGlobal) &&
         AudioObjectGetPropertyData(device, &address, 0, NULL, &size, &rate) ==
             noErr &&
         rate > 0 && has_output(device);
}
#endif

bool nx_audio_output_dualsense_ready(void) {
#if TARGET_OS_OSX
  UInt32 count = 0;
  AudioObjectID *ids = output_device_ids(&count);
  bool ready = false;
  for (UInt32 index = 0; ids && index < count && !ready; index++) {
    ready = device_is_dualsense(ids[index]) && device_is_playing(ids[index]);
  }
  free(ids);
  return ready;
#else
  return false;
#endif
}

bool nx_audio_output_is_headphones(const char *device) {
#if TARGET_OS_OSX
  AudioObjectID output = kAudioObjectUnknown;
  if (device && device[0]) {
    output = output_device_named(device);
  }
  if (output == kAudioObjectUnknown) {
    output = default_output_device();
  }
  if (output == kAudioObjectUnknown) {
    return false;
  }
  char name[NX_AUDIO_DEVICE_NAME_SIZE] = {0};
  device_name(output, name, sizeof(name));
  return nx_audio_output_looks_like_headphones(
      device_property(output, kAudioDevicePropertyTransportType,
                      kAudioObjectPropertyScopeGlobal),
      device_property(output, kAudioDevicePropertyDataSource,
                      kAudioObjectPropertyScopeOutput),
      name);
#else
  (void)device;
  for (AVAudioSessionPortDescription *port in
       AVAudioSession.sharedInstance.currentRoute.outputs) {
    if ([port.portType isEqualToString:AVAudioSessionPortHeadphones] ||
        [port.portType isEqualToString:AVAudioSessionPortBluetoothA2DP] ||
        [port.portType isEqualToString:AVAudioSessionPortBluetoothLE] ||
        [port.portType isEqualToString:AVAudioSessionPortBluetoothHFP]) {
      return true;
    }
  }
  return false;
#endif
}

@interface CNAudioOutputWatch : NSObject
- (instancetype)initWithChange:(void (*)(void *))changed
                       context:(void *)context;
- (void)stop;
@end

@implementation CNAudioOutputWatch {
  void (*_changed)(void *);
  void *_context;
#if TARGET_OS_OSX
  AudioObjectID _device;
  AudioObjectPropertyListenerBlock _defaultListener;
  AudioObjectPropertyListenerBlock _sourceListener;
#else
  id _observer;
#endif
}

- (instancetype)initWithChange:(void (*)(void *))changed
                       context:(void *)context {
  self = [super init];
  if (!self) {
    return nil;
  }
  _changed = changed;
  _context = context;
  __weak CNAudioOutputWatch *weakSelf = self;
#if TARGET_OS_OSX
  _device = kAudioObjectUnknown;
  _sourceListener = ^(UInt32 count,
                      const AudioObjectPropertyAddress *addresses) {
    (void)count;
    (void)addresses;
    [weakSelf notify];
  };
  _defaultListener = ^(UInt32 count,
                       const AudioObjectPropertyAddress *addresses) {
    (void)count;
    (void)addresses;
    [weakSelf follow];
    [weakSelf notify];
  };
  AudioObjectPropertyAddress address = {
      kAudioHardwarePropertyDefaultOutputDevice,
      kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain};
  AudioObjectAddPropertyListenerBlock(kAudioObjectSystemObject, &address,
                                      dispatch_get_main_queue(),
                                      _defaultListener);
  [self follow];
#else
  _observer = [NSNotificationCenter.defaultCenter
      addObserverForName:AVAudioSessionRouteChangeNotification
                  object:nil
                   queue:NSOperationQueue.mainQueue
              usingBlock:^(NSNotification *note) {
                (void)note;
                [weakSelf notify];
              }];
#endif
  return self;
}

- (void)notify {
  if (_changed) {
    _changed(_context);
  }
}

#if TARGET_OS_OSX
- (void)follow {
  AudioObjectPropertyAddress source = {kAudioDevicePropertyDataSource,
                                       kAudioObjectPropertyScopeOutput,
                                       kAudioObjectPropertyElementMain};
  if (_device != kAudioObjectUnknown) {
    AudioObjectRemovePropertyListenerBlock(_device, &source,
                                           dispatch_get_main_queue(),
                                           _sourceListener);
  }
  _device = default_output_device();
  if (_device != kAudioObjectUnknown &&
      AudioObjectHasProperty(_device, &source)) {
    AudioObjectAddPropertyListenerBlock(_device, &source,
                                        dispatch_get_main_queue(),
                                        _sourceListener);
  } else {
    _device = kAudioObjectUnknown;
  }
}
#endif

- (void)stop {
  _changed = NULL;
#if TARGET_OS_OSX
  AudioObjectPropertyAddress address = {
      kAudioHardwarePropertyDefaultOutputDevice,
      kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain};
  AudioObjectRemovePropertyListenerBlock(kAudioObjectSystemObject, &address,
                                         dispatch_get_main_queue(),
                                         _defaultListener);
  if (_device != kAudioObjectUnknown) {
    AudioObjectPropertyAddress source = {kAudioDevicePropertyDataSource,
                                         kAudioObjectPropertyScopeOutput,
                                         kAudioObjectPropertyElementMain};
    AudioObjectRemovePropertyListenerBlock(_device, &source,
                                           dispatch_get_main_queue(),
                                           _sourceListener);
    _device = kAudioObjectUnknown;
  }
#else
  if (_observer) {
    [NSNotificationCenter.defaultCenter removeObserver:_observer];
    _observer = nil;
  }
#endif
}

@end

nx_audio_output_watch *nx_audio_output_watch_start(void (*changed)(void *),
                                                   void *context) {
  @autoreleasepool {
    CNAudioOutputWatch *watch =
        [[CNAudioOutputWatch alloc] initWithChange:changed context:context];
    return watch ? (__bridge_retained nx_audio_output_watch *)watch : NULL;
  }
}

void nx_audio_output_watch_stop(nx_audio_output_watch *handle) {
  if (!handle) {
    return;
  }
  @autoreleasepool {
    CNAudioOutputWatch *watch = (__bridge_transfer CNAudioOutputWatch *)handle;
    [watch stop];
  }
}

size_t nx_audio_output_devices(char names[][NX_AUDIO_DEVICE_NAME_SIZE],
                               size_t capacity) {
  if (!names) {
    return 0;
  }
  size_t written = 0;
#if TARGET_OS_OSX
  UInt32 count = 0;
  AudioObjectID *ids = output_device_ids(&count);
  for (UInt32 index = 0; ids && index < count && written < capacity;
       index++) {
    if (has_output(ids[index]) &&
        device_name(ids[index], names[written], NX_AUDIO_DEVICE_NAME_SIZE)) {
      written++;
    }
  }
  free(ids);
#else
  (void)capacity;
#endif
  return written;
}
