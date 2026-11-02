#import "VideoDecoderClient.h"
#include <pthread.h>
#include "DecoderState.h"
#import "StatusCodes.h"

@implementation CNVideoDecoderClient {
  VTDecompressionSessionRef _session;
  CMVideoFormatDescriptionRef _format;
  pthread_mutex_t _mutex;
  CNDecoderState _state;
  BOOL _hardwareVerified;
  OSStatus _lastError;
}
- (instancetype)init {
  if ((self = [super init])) {
    pthread_mutex_init(&_mutex, NULL);
  }
  return self;
}
- (BOOL)hardwareVerified {
  return _hardwareVerified;
}
- (OSStatus)lastError {
  return _lastError;
}
- (OSStatus)configure:(CMVideoFormatDescriptionRef)format tenBit:(BOOL)tenBit {
  [self stop];
  if (!format) {
    return _lastError = CNStatusInvalidParameter;
  }
  FourCharCode codec = CMFormatDescriptionGetMediaSubType(format);
  CMVideoDimensions dimensions = CMVideoFormatDescriptionGetDimensions(format);
  if ((codec != kCMVideoCodecType_H264 && codec != kCMVideoCodecType_HEVC) ||
      dimensions.width <= 0 || dimensions.height <= 0 || dimensions.width > 8192 ||
      dimensions.height > 8192) {
    return _lastError = CNStatusInvalidParameter;
  }
  NSDictionary *spec = @{
    (__bridge NSString *)kVTVideoDecoderSpecification_RequireHardwareAcceleratedVideoDecoder : @YES
  };
  NSDictionary *attributes = @{
    (__bridge NSString *)
    kCVPixelBufferPixelFormatTypeKey : @(tenBit ? kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange
                                                : kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange),
    (__bridge NSString *)kCVPixelBufferMetalCompatibilityKey : @YES,
    (__bridge NSString *)kCVPixelBufferIOSurfacePropertiesKey : @{}
  };
  OSStatus status =
      VTDecompressionSessionCreate(NULL, format, (__bridge CFDictionaryRef)spec,
                                   (__bridge CFDictionaryRef)attributes, NULL, &_session);
  if (status) {
    return _lastError = status;
  }
  CFTypeRef hardware = NULL;
  status = VTSessionCopyProperty(
      _session, kVTDecompressionPropertyKey_UsingHardwareAcceleratedVideoDecoder, NULL, &hardware);
  _hardwareVerified = !status && hardware && CFEqual(hardware, kCFBooleanTrue);
  if (hardware) {
    CFRelease(hardware);
  }
  if (!_hardwareVerified) {
    [self stop];
    return _lastError = status ?: kVTVideoDecoderNotAvailableNowErr;
  }
  status = VTSessionSetProperty(_session, kVTDecompressionPropertyKey_RealTime, kCFBooleanTrue);
  if (status) {
    [self stop];
    return _lastError = status;
  }
  _format = (CMVideoFormatDescriptionRef)CFRetain(format);
  pthread_mutex_lock(&_mutex);
  BOOL started = cn_decoder_start(&_state);
  pthread_mutex_unlock(&_mutex);
  if (!started) {
    [self stop];
    return _lastError = CNStatusInvalidParameter;
  }
  return _lastError = noErr;
}
- (CNVideoSubmitResult)submit:(CMSampleBufferRef)sample output:(CNVideoOutput)output {
  if (!_session || !sample || !CMSampleBufferDataIsReady(sample) ||
      CMSampleBufferGetNumSamples(sample) != 1 || !CMSampleBufferGetFormatDescription(sample) ||
      !CMFormatDescriptionEqual(_format, CMSampleBufferGetFormatDescription(sample))) {
    return CNVideoSubmitInvalidSample;
  }
  CMBlockBufferRef block = CMSampleBufferGetDataBuffer(sample);
  if (!block || !CMBlockBufferGetDataLength(block) ||
      CMBlockBufferGetDataLength(block) > 32 * 1024 * 1024) {
    return CNVideoSubmitInvalidSample;
  }
  pthread_mutex_lock(&_mutex);
  uint64_t ticket = cn_decoder_reserve(&_state), generation = _state.generation;
  pthread_mutex_unlock(&_mutex);
  if (!ticket) {
    return CNVideoSubmitWouldBlock;
  }

  id inputLease = (__bridge id)sample;
  OSStatus status = VTDecompressionSessionDecodeFrameWithOutputHandler(
      _session, sample, kVTDecodeFrame_EnableAsynchronousDecompression, NULL,
      ^(OSStatus result, VTDecodeInfoFlags flags, CVImageBufferRef image, CMTime pts,
        CMTime duration) {
        (void)CMSampleBufferGetDataBuffer((__bridge CMSampleBufferRef)inputLease);
        pthread_mutex_lock(&self->_mutex);
        BOOL active =
            self->_state.phase == CNDecoderRunning && self->_state.generation == generation;
        pthread_mutex_unlock(&self->_mutex);
        if (active) {
          output(result ?: (image ? noErr : kVTVideoDecoderBadDataErr), image, pts);
        }
        pthread_mutex_lock(&self->_mutex);
        cn_decoder_complete(&self->_state, generation, ticket);
        pthread_mutex_unlock(&self->_mutex);
      });
  if (status) {
    pthread_mutex_lock(&_mutex);
    cn_decoder_complete(&_state, generation, ticket);
    pthread_mutex_unlock(&_mutex);
    _lastError = status;
    return CNVideoSubmitFailed;
  }
  return CNVideoSubmitAccepted;
}
- (OSStatus)drain {
  if (!_session) {
    return CNStatusInvalidParameter;
  }
  OSStatus status = VTDecompressionSessionFinishDelayedFrames(_session);
  OSStatus waited = VTDecompressionSessionWaitForAsynchronousFrames(_session);
  return _lastError = status ?: waited;
}
- (void)stop {
  pthread_mutex_lock(&_mutex);
  cn_decoder_begin_stop(&_state);
  pthread_mutex_unlock(&_mutex);
  if (_session) {
    VTDecompressionSessionWaitForAsynchronousFrames(_session);
    VTDecompressionSessionInvalidate(_session);
    CFRelease(_session);
    _session = NULL;
  }
  pthread_mutex_lock(&_mutex);
  cn_decoder_finish_stop(&_state);
  pthread_mutex_unlock(&_mutex);
  if (_format) {
    CFRelease(_format);
    _format = NULL;
  }
  _hardwareVerified = NO;
}
- (void)dealloc {
  [self stop];
  pthread_mutex_destroy(&_mutex);
}
@end
