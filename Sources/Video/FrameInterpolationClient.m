#import "FrameInterpolationClient.h"
#import <TargetConditionals.h>
#include <stdatomic.h>

#if TARGET_OS_SIMULATOR

@implementation CNFrameInterpolationClient {
  atomic_bool _enabled;
  atomic_bool _stopped;
  _Atomic NSUInteger _bypassed;
}

- (BOOL)supported {
  return NO;
}

- (void)setSourceFrameRate:(NSInteger)frameRate {
}

- (void)setEnabled:(BOOL)enabled {
  atomic_store_explicit(&_enabled, enabled, memory_order_relaxed);
}

- (void)offer:(CVPixelBufferRef)frame handler:(CNInterpolatedFrameHandler)handler {
  if (atomic_load_explicit(&_stopped, memory_order_relaxed)) {
    return;
  }
  atomic_fetch_add_explicit(&_bypassed, 1, memory_order_relaxed);
  handler(frame, NO);
}

- (NSDictionary<NSString *, NSNumber *> *)statistics {
  return @{
    @"supported" : @NO,
    @"enabled" : @(atomic_load_explicit(&_enabled, memory_order_relaxed)),
    @"generated" : @0,
    @"bypassed" : @(atomic_load_explicit(&_bypassed, memory_order_relaxed)),
    @"failures" : @0
  };
}

- (void)stop {
  atomic_store_explicit(&_stopped, true, memory_order_relaxed);
}

@end

#else

#import <CoreMedia/CoreMedia.h>
#import <IOSurface/IOSurfaceRef.h>
#import <VideoToolbox/VTFrameProcessor.h>
#import <VideoToolbox/VTFrameProcessor_LowLatencyFrameInterpolation.h>
#include <pthread.h>

@implementation CNFrameInterpolationClient {
  dispatch_queue_t _queue;
  VTFrameProcessor *_processor;
  VTLowLatencyFrameInterpolationConfiguration *_configuration;
  CVPixelBufferPoolRef _pool;
  CVPixelBufferRef _previous;
  atomic_bool _enabled;
  BOOL _stopped;
  pthread_mutex_t _deliveryLock;
  pthread_cond_t _delivered;
  NSUInteger _delivering;
  BOOL _busy;
  BOOL _stopRequested;
  uint64_t _generation;
  int32_t _sourceFrameRate;
  int64_t _sequence;
  _Atomic NSUInteger _generated;
  _Atomic NSUInteger _bypassed;
  _Atomic NSUInteger _failures;
}

- (instancetype)init {
  self = [super init];
  if (!self) {
    return nil;
  }
  _sourceFrameRate = 60;
  pthread_mutex_init(&_deliveryLock, NULL);
  pthread_cond_init(&_delivered, NULL);
  _queue = dispatch_queue_create("io.github.chiaki-ng.frame-interpolation", DISPATCH_QUEUE_SERIAL);
  return self;
}

- (BOOL)supported {
  if (!VTLowLatencyFrameInterpolationConfiguration.isSupported) {
    return NO;
  }
  if (@available(macOS 27.0, iOS 27.0, *)) {
    return [VTLowLatencyFrameInterpolationConfiguration maximumDimensionForSpatialScaleFactor:1] >=
               1920 &&
           [VTLowLatencyFrameInterpolationConfiguration maximumPixelCountForSpatialScaleFactor:1] >=
               1920 * 1080;
  }
  return YES;
}

- (void)setSourceFrameRate:(NSInteger)frameRate {
  dispatch_async(_queue, ^{
    int32_t bounded = frameRate == 30 ? 30 : 60;
    if (self->_sourceFrameRate != bounded) {
      self->_sourceFrameRate = bounded;
      [self resetSession];
    }
  });
}

- (void)setEnabled:(BOOL)enabled {
  dispatch_async(_queue, ^{
    pthread_mutex_lock(&self->_deliveryLock);
    BOOL stopped = self->_stopRequested;
    pthread_mutex_unlock(&self->_deliveryLock);
    if (stopped) {
      return;
    }
    if (atomic_load_explicit(&self->_enabled, memory_order_relaxed) == enabled && !self->_stopped) {
      return;
    }
    atomic_store_explicit(&self->_enabled, enabled, memory_order_relaxed);
    self->_stopped = NO;
    [self resetSession];
  });
}

- (BOOL)beginDelivery:(uint64_t)ticket {
  pthread_mutex_lock(&_deliveryLock);
  BOOL current = !_stopRequested && ticket == _generation;
  if (current) {
    _delivering++;
  }
  pthread_mutex_unlock(&_deliveryLock);
  return current;
}

- (void)endDelivery {
  pthread_mutex_lock(&_deliveryLock);
  _delivering--;
  if (_delivering == 0) {
    pthread_cond_broadcast(&_delivered);
  }
  pthread_mutex_unlock(&_deliveryLock);
}

- (void)deliver:(CVPixelBufferRef)frame
      generated:(BOOL)generated
         ticket:(uint64_t)ticket
        handler:(CNInterpolatedFrameHandler)handler {
  if (![self beginDelivery:ticket]) {
    return;
  }
  handler(frame, generated);
  [self endDelivery];
}

- (void)finishOffer {
  pthread_mutex_lock(&_deliveryLock);
  _busy = NO;
  pthread_mutex_unlock(&_deliveryLock);
}

- (void)offer:(CVPixelBufferRef)frame handler:(CNInterpolatedFrameHandler)handler {
  pthread_mutex_lock(&_deliveryLock);
  if (_stopRequested) {
    pthread_mutex_unlock(&_deliveryLock);
    return;
  }
  uint64_t ticket = ++_generation;
  if (_busy) {
    _delivering++;
    pthread_mutex_unlock(&_deliveryLock);
    atomic_fetch_add_explicit(&_bypassed, 1, memory_order_relaxed);
    handler(frame, NO);
    [self endDelivery];
    return;
  }
  _busy = YES;
  pthread_mutex_unlock(&_deliveryLock);
  CVPixelBufferRetain(frame);
  dispatch_async(_queue, ^{
    if (self->_stopped || !atomic_load_explicit(&self->_enabled, memory_order_relaxed) ||
        !self.supported || ![self accepts:frame]) {
      atomic_fetch_add_explicit(&self->_bypassed, 1, memory_order_relaxed);
      [self deliver:frame generated:NO ticket:ticket handler:handler];
      CVPixelBufferRelease(frame);
      [self finishOffer];
      return;
    }
    if (![self prepareFor:frame]) {
      atomic_fetch_add_explicit(&self->_failures, 1, memory_order_relaxed);
      [self deliver:frame generated:NO ticket:ticket handler:handler];
      CVPixelBufferRelease(frame);
      [self finishOffer];
      return;
    }
    if (!self->_previous) {
      self->_previous = CVPixelBufferRetain(frame);
      [self deliver:frame generated:NO ticket:ticket handler:handler];
      CVPixelBufferRelease(frame);
      [self finishOffer];
      return;
    }
    CVPixelBufferRef generated = NULL;
    CVReturn allocation = CVPixelBufferPoolCreatePixelBuffer(NULL, self->_pool, &generated);
    if (allocation != kCVReturnSuccess || !generated) {
      atomic_fetch_add_explicit(&self->_failures, 1, memory_order_relaxed);
      [self replacePrevious:frame];
      [self deliver:frame generated:NO ticket:ticket handler:handler];
      CVPixelBufferRelease(frame);
      [self finishOffer];
      return;
    }
    CVBufferPropagateAttachments(frame, generated);
    CMTime previousTime = CMTimeMake(self->_sequence, self->_sourceFrameRate);
    CMTime generatedTime = CMTimeMake(self->_sequence * 2 + 1, self->_sourceFrameRate * 2);
    CMTime currentTime = CMTimeMake(self->_sequence + 1, self->_sourceFrameRate);
    self->_sequence++;
    VTFrameProcessorFrame *previous = [[VTFrameProcessorFrame alloc] initWithBuffer:self->_previous
                                                              presentationTimeStamp:previousTime];
    VTFrameProcessorFrame *current = [[VTFrameProcessorFrame alloc] initWithBuffer:frame
                                                             presentationTimeStamp:currentTime];
    VTFrameProcessorFrame *destination =
        [[VTFrameProcessorFrame alloc] initWithBuffer:generated
                                presentationTimeStamp:generatedTime];
    VTLowLatencyFrameInterpolationParameters *parameters =
        [[VTLowLatencyFrameInterpolationParameters alloc] initWithSourceFrame:current
                                                                previousFrame:previous
                                                           interpolationPhase:@[ @0.5 ]
                                                            destinationFrames:@[ destination ]];
    NSError *error = nil;
    BOOL success = parameters && [self->_processor processWithParameters:parameters error:&error];
    [self replacePrevious:frame];
    if (success) {
      atomic_fetch_add_explicit(&self->_generated, 1, memory_order_relaxed);
      [self deliver:generated generated:YES ticket:ticket handler:handler];
    } else {
      atomic_fetch_add_explicit(&self->_failures, 1, memory_order_relaxed);
    }
    [self deliver:frame generated:NO ticket:ticket handler:handler];
    CVPixelBufferRelease(generated);
    CVPixelBufferRelease(frame);
    [self finishOffer];
  });
}

- (BOOL)accepts:(CVPixelBufferRef)frame {
  size_t width = CVPixelBufferGetWidth(frame);
  size_t height = CVPixelBufferGetHeight(frame);
  if (!((width == 1920 && height == 1080) || (width == 1280 && height == 720)) ||
      !CVPixelBufferGetIOSurface(frame)) {
    return NO;
  }
  OSType format = CVPixelBufferGetPixelFormatType(frame);
  return format == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange ||
         format == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange ||
         format == kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange ||
         format == kCVPixelFormatType_420YpCbCr10BiPlanarFullRange;
}

- (BOOL)prepareFor:(CVPixelBufferRef)frame {
  if (_previous &&
      (CVPixelBufferGetWidth(_previous) != CVPixelBufferGetWidth(frame) ||
       CVPixelBufferGetHeight(_previous) != CVPixelBufferGetHeight(frame) ||
       CVPixelBufferGetPixelFormatType(_previous) != CVPixelBufferGetPixelFormatType(frame))) {
    [self resetSession];
  }
  if (_processor && _pool) {
    return YES;
  }
  _configuration = [[VTLowLatencyFrameInterpolationConfiguration alloc]
              initWithFrameWidth:CVPixelBufferGetWidth(frame)
                     frameHeight:CVPixelBufferGetHeight(frame)
      numberOfInterpolatedFrames:1];
  if (!_configuration) {
    return NO;
  }
  if (![_configuration.frameSupportedPixelFormats
          containsObject:@(CVPixelBufferGetPixelFormatType(frame))]) {
    _configuration = nil;
    return NO;
  }
  _processor = [VTFrameProcessor new];
  NSError *error = nil;
  if (![_processor startSessionWithConfiguration:_configuration error:&error]) {
    _processor = nil;
    _configuration = nil;
    return NO;
  }
  NSMutableDictionary *attributes = [_configuration.destinationPixelBufferAttributes mutableCopy];
  attributes[(NSString *)kCVPixelBufferIOSurfacePropertiesKey] = @{};
  attributes[(NSString *)kCVPixelBufferMetalCompatibilityKey] = @YES;
  NSDictionary *poolAttributes = @{(NSString *)kCVPixelBufferPoolMinimumBufferCountKey : @2};
  CVReturn result = CVPixelBufferPoolCreate(NULL, (__bridge CFDictionaryRef)poolAttributes,
                                            (__bridge CFDictionaryRef)attributes, &_pool);
  if (result != kCVReturnSuccess) {
    [_processor endSession];
    _processor = nil;
    _configuration = nil;
    return NO;
  }
  return YES;
}

- (void)replacePrevious:(CVPixelBufferRef)frame {
  if (_previous) {
    CVPixelBufferRelease(_previous);
  }
  _previous = CVPixelBufferRetain(frame);
}

- (void)resetSession {
  if (_processor) {
    [_processor endSession];
    _processor = nil;
  }
  _configuration = nil;
  if (_pool) {
    CFRelease(_pool);
    _pool = NULL;
  }
  if (_previous) {
    CVPixelBufferRelease(_previous);
    _previous = NULL;
  }
  _sequence = 0;
}

- (NSDictionary<NSString *, NSNumber *> *)statistics {
  return @{
    @"supported" : @(self.supported),
    @"enabled" : @(atomic_load_explicit(&_enabled, memory_order_relaxed)),
    @"generated" : @(atomic_load_explicit(&_generated, memory_order_relaxed)),
    @"bypassed" : @(atomic_load_explicit(&_bypassed, memory_order_relaxed)),
    @"failures" : @(atomic_load_explicit(&_failures, memory_order_relaxed))
  };
}

- (void)stop {
  pthread_mutex_lock(&_deliveryLock);
  if (_stopRequested) {
    pthread_mutex_unlock(&_deliveryLock);
    return;
  }
  _stopRequested = YES;
  ++_generation;
  while (_delivering > 0) {
    pthread_cond_wait(&_delivered, &_deliveryLock);
  }
  pthread_mutex_unlock(&_deliveryLock);
  dispatch_async(_queue, ^{
    self->_stopped = YES;
    [self resetSession];
  });
}

- (void)dealloc {
  [self resetSession];
  pthread_cond_destroy(&_delivered);
  pthread_mutex_destroy(&_deliveryLock);
}

@end

#endif
