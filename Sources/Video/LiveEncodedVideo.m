#import "LiveEncodedVideo.h"
#include <pthread.h>
#include <stdatomic.h>
#import "AnnexBSample.h"
#import "StatusCodes.h"

@interface CNCompressedFramePool : NSObject
- (NSData *)newLeaseWithBytes:(const uint8_t *)bytes length:(size_t)length;
@end

@implementation CNCompressedFramePool {
  uint8_t *_bytes[4];
  BOOL _leased[4];
  pthread_mutex_t _lock;
}
- (instancetype)init {
  self = [super init];
  if (!self) {
    return nil;
  }
  pthread_mutex_init(&_lock, NULL);
  for (NSUInteger i = 0; i < 4; i++) {
    _bytes[i] = malloc(4 * 1024 * 1024);
    if (!_bytes[i]) {
      return nil;
    }
  }
  return self;
}
- (NSData *)newLeaseWithBytes:(const uint8_t *)bytes length:(size_t)length {
  if (!bytes || !length || length > 4 * 1024 * 1024) {
    return nil;
  }
  pthread_mutex_lock(&_lock);
  NSUInteger slot = 0;
  while (slot < 4 && _leased[slot]) {
    slot++;
  }
  if (slot == 4) {
    pthread_mutex_unlock(&_lock);
    return nil;
  }
  _leased[slot] = YES;
  pthread_mutex_unlock(&_lock);
  memcpy(_bytes[slot], bytes, length);
  return [[NSData alloc] initWithBytesNoCopy:_bytes[slot]
                                      length:length
                                 deallocator:^(void *buffer, NSUInteger size) {
                                   (void)buffer;
                                   (void)size;
                                   pthread_mutex_lock(&self->_lock);
                                   self->_leased[slot] = NO;
                                   pthread_mutex_unlock(&self->_lock);
                                 }];
}
- (void)dealloc {
  for (NSUInteger i = 0; i < 4; i++) {
    free(_bytes[i]);
  }
  pthread_mutex_destroy(&_lock);
}
@end

static const uint32_t CNEncodedRebuildFailures = 8;
static const CFTimeInterval CNEncodedRebuildInterval = 1.0;

@implementation CNLiveEncodedVideo {
  CNVideoDecoderClient *_decoder;
  CNCompressedFramePool *_pool;
  CMVideoFormatDescriptionRef _format;
  NSData *_parameterSets;
  _Atomic(uint32_t) _failureStreak;
  CFAbsoluteTime _rebuiltAt;
  enum { EncodedIdle, EncodedReady, EncodedFailed, EncodedStopped } _phase;
}
- (instancetype)initWithHEVC:(BOOL)hevc {
  self = [super init];
  if (self) {
    _hevc = hevc;
    _decoder = [CNVideoDecoderClient new];
    _pool = [CNCompressedFramePool new];
    if (!_decoder || !_pool) {
      return nil;
    }
  }
  return self;
}
- (OSStatus)configureWithFormat:(CMVideoFormatDescriptionRef)format sets:(NSData *)sets {
  OSStatus status = [_decoder configure:format tenBit:_hevc];
  if (status) {
    CFRelease(format);
    return status;
  }
  if (_format) {
    CFRelease(_format);
  }
  _format = format;
  _parameterSets = sets;
  atomic_store(&_failureStreak, 0);
  return noErr;
}
- (OSStatus)rebuild {
  _rebuiltAt = CFAbsoluteTimeGetCurrent();
  _rebuilds++;
  atomic_store(&_failureStreak, 0);
  return [_decoder configure:_format tenBit:_hevc];
}
- (CNVideoSubmitResult)decode:(const uint8_t *)bytes
                       length:(size_t)length
                       output:(CNVideoOutput)output
                       status:(OSStatus *)status {
  CNVideoSubmitResult result = CNVideoSubmitWouldBlock;
  @autoreleasepool {
    NSData *lease = [_pool newLeaseWithBytes:bytes length:length];
    if (lease) {
      CMSampleBufferRef sample = NULL;
      *status =
          CNCreateAnnexBSample(lease.bytes, lease.length, lease, _format, kCMTimeInvalid, &sample);
      if (*status) {
        return CNVideoSubmitInvalidSample;
      }
      result = [_decoder submit:sample output:output];
      CFRelease(sample);
    }
  }
  *status = result == CNVideoSubmitFailed ? _decoder.lastError : noErr;
  return result;
}
- (CNEncodedVideoSubmission)submit:(const uint8_t *)bytes
                            length:(size_t)length
                            header:(const uint8_t *)header
                      headerLength:(size_t)headerLength
                            output:(CNVideoOutput)output {
  if (_phase == EncodedStopped || _phase == EncodedFailed || !output) {
    return (CNEncodedVideoSubmission){CNVideoSubmitFailed, CNStatusInvalidParameter, YES};
  }
  if (headerLength) {
    NSData *sets = CNCopyAnnexBParameterSets(header, headerLength, _hevc);
    CMVideoFormatDescriptionRef format = NULL;
    OSStatus status = sets ? CNCreateAnnexBFormat(sets.bytes, sets.length, _hevc, &format)
                           : CNStatusInvalidParameter;
    if (!status) {
      status = [self configureWithFormat:format sets:sets];
    }
    if (status) {
      _phase = EncodedFailed;
      return (CNEncodedVideoSubmission){CNVideoSubmitFailed, status, YES};
    }
    _phase = EncodedReady;
  }
  if (_phase != EncodedReady) {
    return (CNEncodedVideoSubmission){CNVideoSubmitFailed, CNStatusInvalidParameter, YES};
  }
  if (!bytes || !length || length > 4 * 1024 * 1024) {
    return (CNEncodedVideoSubmission){CNVideoSubmitInvalidSample, CNStatusInvalidParameter, NO};
  }
  NSData *inband = CNCopyAnnexBParameterSets(bytes, length, _hevc);
  if (inband) {
    if (!CNAnnexBHasPicture(bytes, length, _hevc)) {
      return (CNEncodedVideoSubmission){CNVideoSubmitAccepted, noErr, NO};
    }
    CMVideoFormatDescriptionRef format = NULL;
    if (![inband isEqualToData:_parameterSets] &&
        !CNCreateAnnexBFormat(inband.bytes, inband.length, _hevc, &format)) {
      OSStatus status = [self configureWithFormat:format sets:inband];
      if (status) {
        _phase = EncodedFailed;
        return (CNEncodedVideoSubmission){CNVideoSubmitFailed, status, YES};
      }
    }
  }
  if (atomic_load(&_failureStreak) >= CNEncodedRebuildFailures &&
      CFAbsoluteTimeGetCurrent() - _rebuiltAt >= CNEncodedRebuildInterval) {
    OSStatus status = [self rebuild];
    if (status) {
      _phase = EncodedFailed;
      return (CNEncodedVideoSubmission){CNVideoSubmitFailed, status, YES};
    }
  }
  CNVideoOutput tracked = ^(OSStatus status, CVPixelBufferRef surface, CMTime pts) {
    if (status || !surface) {
      atomic_fetch_add(&self->_failureStreak, 1);
    } else {
      atomic_store(&self->_failureStreak, 0);
    }
    output(status, surface, pts);
  };
  OSStatus status = noErr;
  CNVideoSubmitResult result = [self decode:bytes length:length output:tracked status:&status];
  if (result == CNVideoSubmitFailed &&
      (status == kVTInvalidSessionErr || status == kVTVideoDecoderMalfunctionErr)) {
    OSStatus rebuiltStatus = [self rebuild];
    if (rebuiltStatus) {
      _phase = EncodedFailed;
      return (CNEncodedVideoSubmission){CNVideoSubmitFailed, rebuiltStatus, YES};
    }
    result = [self decode:bytes length:length output:tracked status:&status];
  }
  return (CNEncodedVideoSubmission){result, status, NO};
}
- (void)stop {
  if (_phase == EncodedStopped) {
    return;
  }
  _phase = EncodedStopped;
  [_decoder stop];
  _parameterSets = nil;
  if (_format) {
    CFRelease(_format);
    _format = NULL;
  }
}
- (void)dealloc {
  [self stop];
}
@end
