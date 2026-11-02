#import "VideoSurface.h"

#import <IOSurface/IOSurfaceRef.h>
#import <Metal/Metal.h>
#if __has_include(<MetalFX/MetalFX.h>)
#import <MetalFX/MetalFX.h>
#define CN_METALFX 1
#else
#define CN_METALFX 0
#endif
#import <MetalPerformanceShaders/MetalPerformanceShaders.h>
#import <QuartzCore/CAMetalLayer.h>
#include <os/log.h>
#include <os/signpost.h>

#include <algorithm>
#include <array>
#include <atomic>
#include <cmath>
#include <cstdint>
#include <mutex>
#include <optional>
#include <utility>

#import "LightLevelWindow.hpp"
#import "Owned.hpp"
#import "PendingFrames.hpp"
#import "UpscalerNetwork.h"

namespace video {

struct ColourConfig {
  std::uint32_t tenBit;
  std::uint32_t fullRange;
  std::uint32_t bt2020;
  std::uint32_t pq;
  std::uint32_t toneMap;
  std::uint32_t diagnosticMode;
  float referenceWhiteNits;
  std::uint32_t adjust;
  float brightness;
  float contrast;
  float saturation;
  float gamma;
  std::uint32_t deband;
  std::uint32_t frame;
  float headroom;
  float contentPeak;
  float markerX;
  float markerY;
};

constexpr std::uint32_t lightLevelInterval = 6;
constexpr double lightSampleBudget = 262144;
constexpr std::size_t lightBufferCount = 3;

using MetalTexture = Owned<CVMetalTextureRef>;
using TextureCache = Owned<CVMetalTextureCacheRef>;

}  // namespace video

@interface CNDisplayLinkThread : NSObject
- (instancetype)initWithLink:(CAMetalDisplayLink *)link;
- (void)performWithLink:(void (^)(CAMetalDisplayLink *link))block;
- (void)close;
@end

@implementation CNDisplayLinkThread {
  CAMetalDisplayLink *_link;
  NSThread *_thread;
  std::mutex _lock;
  CFRunLoopRef _runLoop;
  BOOL _closed;
  BOOL _finished;
}

- (instancetype)initWithLink:(CAMetalDisplayLink *)link {
  self = [super init];
  if (!self) {
    return nil;
  }
  _link = link;
  _thread = [[NSThread alloc] initWithTarget:self selector:@selector(run) object:nil];
  _thread.name = @"io.github.chiaki-ng.display-link";
  _thread.qualityOfService = NSQualityOfServiceUserInteractive;
  [_thread start];
  return self;
}

- (BOOL)attachToCurrentRunLoop {
  const std::lock_guard lock(_lock);
  if (_closed) {
    _link.delegate = nil;
    [_link invalidate];
    return NO;
  }
  NSRunLoop *runLoop = NSRunLoop.currentRunLoop;
  [runLoop addPort:[NSMachPort port] forMode:NSDefaultRunLoopMode];
  [_link addToRunLoop:runLoop forMode:NSDefaultRunLoopMode];
  _runLoop = runLoop.getCFRunLoop;
  CFRetain(_runLoop);
  return YES;
}

- (void)run {
  @autoreleasepool {
    if (![self attachToCurrentRunLoop]) {
      return;
    }
  }
  while (!_finished) {
    @autoreleasepool {
      CFRunLoopRunInMode(kCFRunLoopDefaultMode, 1.0e10, false);
    }
  }
}

- (void)performWithLink:(void (^)(CAMetalDisplayLink *link))block {
  const std::lock_guard lock(_lock);
  if (_closed) {
    return;
  }
  CAMetalDisplayLink *link = _link;
  if (!_runLoop) {
    block(link);
    return;
  }
  CFRunLoopPerformBlock(_runLoop, kCFRunLoopDefaultMode, ^{
    block(link);
  });
  CFRunLoopWakeUp(_runLoop);
}

- (void)close {
  CFRunLoopRef runLoop = NULL;
  {
    const std::lock_guard lock(_lock);
    if (_closed) {
      return;
    }
    _closed = YES;
    runLoop = std::exchange(_runLoop, nullptr);
  }
  if (!runLoop) {
    return;
  }
  CFRunLoopPerformBlock(runLoop, kCFRunLoopDefaultMode, ^{
    [self finish];
  });
  CFRunLoopWakeUp(runLoop);
  CFRelease(runLoop);
}

- (void)finish {
  _link.delegate = nil;
  [_link invalidate];
  _finished = YES;
  CFRunLoopStop(CFRunLoopGetCurrent());
}

- (void)dealloc {
  if (_runLoop) {
    CFRelease(_runLoop);
  }
}

@end

@implementation CNVideoSurface {
  CAMetalLayer *_metal;
  CNDisplayLinkThread *_displayLink;
  std::atomic<NSInteger> _presentationFrameRate;
  os_log_t _signposts;
  id<MTLCommandQueue> _queue;
  id<MTLComputePipelineState> _pipeline;
  id<MTLComputePipelineState> _nativePipeline;
  id<MTLComputePipelineState> _fsrcnnColourPipeline;
  id<MTLComputePipelineState> _clampPipeline;
  id<MTLComputePipelineState> _lightPipeline;
  MPSNNGraph *_fsrcnnGraph;
#if CN_METALFX
  id<MTLFXSpatialScaler> _spatialScaler;
#endif
  id<MTLTexture> _spatialInput;
  id<MTLDevice> _device;
  video::TextureCache _cache;
  dispatch_queue_t _renderQueue;
  std::mutex _lock;
  video::PendingFrames _pending;
  BOOL _rendering;
  BOOL _closed;
  BOOL _didPresent;
  std::atomic<NSUInteger> _submitted;
  std::atomic<NSUInteger> _completed;
  std::atomic<NSUInteger> _rejected;
  std::atomic<NSUInteger> _noDrawable;
  std::atomic<NSUInteger> _generatedDrops;
  std::atomic<NSUInteger> _replacedFrames;
  std::atomic<NSUInteger> _idleTicks;
  std::atomic<NSUInteger> _deadlineMisses;
  NSInteger _gpuError;
  NSUInteger _spatialInputWidth;
  NSUInteger _spatialInputHeight;
  NSUInteger _spatialOutputWidth;
  NSUInteger _spatialOutputHeight;
  BOOL _spatialHDR;
  BOOL _layerHDR;
  CNToneMapSource _toneMapSource;
  double _contentPeakNits;
  double _screenHeadroom;
  BOOL _usedFSRCNN;
  BOOL _fsrcnnAllowed;
  BOOL _fsrcnnBudgetFallback;
  CNVideoDiagnosticMode _videoDiagnosticMode;
  CNPictureAdjustment _pictureAdjustment;
  std::uint32_t _frameCounter;
  NSUInteger _sourceWidth;
  NSUInteger _sourceHeight;
  NSUInteger _outputWidth;
  NSUInteger _outputHeight;
  BOOL _inputTenBit;
  BOOL _inputPQ;
  BOOL _inputBT2020;
  BOOL _colourKnown;
  OSType _colourPixel;
  size_t _colourWidth;
  size_t _colourHeight;
  video::Owned<CFTypeRef> _colourTransfer;
  BOOL _colourPQ;
  BOOL _colourBT2020;
  double _gpuMilliseconds;
  CGPoint _marker;
  BOOL _markerFollowsPointer;
  BOOL _markerShown;
  BOOL _measuresLight;
  video::LightLevelWindow _light;
  std::array<id<MTLBuffer>, video::lightBufferCount> _lightBuffers;
  std::array<bool, video::lightBufferCount> _lightBufferBusy;
  std::size_t _lightBufferIndex;
#if TARGET_OS_OSX
  NSTrackingArea *_markerTracking;
#endif
}

#if !TARGET_OS_OSX
+ (Class)layerClass {
  return CAMetalLayer.class;
}
#endif

- (void)readColourOf:(CVPixelBufferRef)surface pixel:(OSType)pixel {
  auto transfer = video::Owned<CFTypeRef>::adopting(
      CVBufferCopyAttachment(surface, kCVImageBufferTransferFunctionKey, nullptr));
  const size_t width = CVPixelBufferGetWidth(surface);
  const size_t height = CVPixelBufferGetHeight(surface);
  const BOOL sameTransfer =
      transfer.get() == _colourTransfer.get() ||
      (transfer && _colourTransfer && CFEqual(transfer.get(), _colourTransfer.get()));
  if (_colourKnown && sameTransfer && pixel == _colourPixel && width == _colourWidth &&
      height == _colourHeight) {
    return;
  }
  const auto primaries = video::Owned<CFTypeRef>::adopting(
      CVBufferCopyAttachment(surface, kCVImageBufferColorPrimariesKey, nullptr));
  _colourBT2020 = primaries && CFEqual(primaries.get(), kCVImageBufferColorPrimaries_ITU_R_2020);
  _colourPQ = transfer && CFEqual(transfer.get(), kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ);
  _colourTransfer = std::move(transfer);
  _colourPixel = pixel;
  _colourWidth = width;
  _colourHeight = height;
  _colourKnown = YES;
  [self applyToneMappingFor:surface pq:_colourPQ];
}

- (void)applyToneMappingFor:(CVPixelBufferRef)surface pq:(BOOL)pq {
  if (!pq) {
    if (_toneMapSource != CNToneMapSourceNone) {
      [self noteToneMapSource:CNToneMapSourceNone peak:0];
    }
    return;
  }
  NSData *mastering = CFBridgingRelease(
      CVBufferCopyAttachment(surface, kCVImageBufferMasteringDisplayColorVolumeKey, nullptr));
  NSData *light = CFBridgingRelease(
      CVBufferCopyAttachment(surface, kCVImageBufferContentLightLevelInfoKey, nullptr));
  CNToneMapSource source =
      mastering.length > 0 || light.length > 0 ? CNToneMapSourceStream : CNToneMapSourceDefault;
  [self noteToneMapSource:source peak:[self contentPeakFromMastering:mastering light:light]];
}

- (void)refreshScreenHeadroom {
  dispatch_async(dispatch_get_main_queue(), ^{
#if TARGET_OS_OSX
    NSScreen *screen = self.window.screen ?: NSScreen.mainScreen;
    double headroom = screen ? screen.maximumExtendedDynamicRangeColorComponentValue : 1;
#else
    double headroom = self.window.screen ? self.window.screen.currentEDRHeadroom : 1;
#endif
    const std::lock_guard lock(self->_lock);
    self->_screenHeadroom = std::max(1.0, headroom);
  });
}

- (double)contentPeakFromMastering:(NSData *)mastering light:(NSData *)light {
  const auto *cll = static_cast<const std::uint8_t *>(light.bytes);
  if (light.length >= 2) {
    const auto maxCLL = static_cast<std::uint16_t>(cll[0] << 8 | cll[1]);
    if (maxCLL > 0) {
      return maxCLL;
    }
  }
  const auto *volume = static_cast<const std::uint8_t *>(mastering.bytes);
  if (mastering.length >= 20) {
    const std::uint32_t peak = static_cast<std::uint32_t>(volume[16]) << 24 |
                               static_cast<std::uint32_t>(volume[17]) << 16 |
                               static_cast<std::uint32_t>(volume[18]) << 8 | volume[19];
    if (peak > 0) {
      return peak / 10000.0;
    }
  }
  return 1000;
}

- (void)noteToneMapSource:(CNToneMapSource)source peak:(double)peak {
  const std::lock_guard lock(_lock);
  _toneMapSource = source;
  _contentPeakNits = peak;
}

- (nullable instancetype)initWithShader:(NSString *)shader fsrcnnWeights:(NSData *)fsrcnnWeights {
  self = [super initWithFrame:CGRectMake(0, 0, 1280, 720)];
  if (!self) {
    return nil;
  }
  id<MTLDevice> device = MTLCreateSystemDefaultDevice();
  _device = device;
  _fsrcnnAllowed = YES;
  _pictureAdjustment = CNPictureAdjustment{0, 1, 1, 1, NO};
  NSError *error = nil;
  id<MTLLibrary> library = [device newLibraryWithSource:shader options:nil error:&error];
  _pipeline =
      [device newComputePipelineStateWithFunction:[library newFunctionWithName:@"colour_planes"]
                                            error:&error];
  _nativePipeline = [device
      newComputePipelineStateWithFunction:[library newFunctionWithName:@"colour_planes_native"]
                                    error:&error];
  _fsrcnnGraph = [CNUpscalerNetwork graphOnDevice:device weights:fsrcnnWeights];
  _fsrcnnColourPipeline =
      [device newComputePipelineStateWithFunction:[library newFunctionWithName:@"fsrcnn_colour"]
                                            error:&error];
  _clampPipeline =
      [device newComputePipelineStateWithFunction:[library newFunctionWithName:@"clamp_highlights"]
                                            error:&error];
  if ([device supportsFamily:MTLGPUFamilyApple7] || [device supportsFamily:MTLGPUFamilyMac2]) {
    _lightPipeline =
        [device newComputePipelineStateWithFunction:[library newFunctionWithName:@"light_levels"]
                                              error:&error];
  }
  _marker = CGPointMake(0.5, 0.5);
  _queue = [device newCommandQueue];
  if (!_pipeline || !_nativePipeline || !_fsrcnnGraph || !_fsrcnnColourPipeline ||
      !_clampPipeline || !_queue ||
      CVMetalTextureCacheCreate(nullptr, nullptr, device, nullptr, _cache.out()) !=
          kCVReturnSuccess) {
    return nil;
  }
  _renderQueue = dispatch_queue_create("io.github.chiaki-ng.video-render",
                                       dispatch_queue_attr_make_with_qos_class(
                                           DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INTERACTIVE, 0));
  _signposts = os_log_create("io.github.chiaki-ng.video", "Render");
#if TARGET_OS_OSX
  _metal = [CAMetalLayer layer];
#else
  _metal = (CAMetalLayer *)self.layer;
#endif
  _metal.device = device;
  _metal.pixelFormat = MTLPixelFormatRGBA16Float;
  _metal.framebufferOnly = NO;
  _metal.maximumDrawableCount = 2;
  _metal.allowsNextDrawableTimeout = YES;
#if TARGET_OS_OSX
  _metal.displaySyncEnabled = YES;
#endif
  const auto space = video::Owned<CGColorSpaceRef>::adopting(
      CGColorSpaceCreateWithName(kCGColorSpaceExtendedLinearSRGB));
  _metal.colorspace = space.get();
#if TARGET_OS_OSX
  self.wantsLayer = YES;
  self.layer = _metal;
#endif
  CAMetalDisplayLink *link = [[CAMetalDisplayLink alloc] initWithMetalLayer:_metal];
  link.delegate = self;
  link.preferredFrameLatency = 1;
  link.preferredFrameRateRange = CAFrameRateRangeMake(60, 60, 60);
  _presentationFrameRate.store(60, std::memory_order_relaxed);
  _displayLink = [[CNDisplayLinkThread alloc] initWithLink:link];
  return self;
}

- (void)setPresentationFrameRate:(NSInteger)frameRate {
  NSInteger bounded = frameRate >= 120 ? 120 : (frameRate >= 60 ? 60 : 30);
  _presentationFrameRate.store(bounded, std::memory_order_relaxed);
  [_displayLink performWithLink:^(CAMetalDisplayLink *link) {
    link.preferredFrameRateRange = CAFrameRateRangeMake(bounded, bounded, bounded);
  }];
}

- (NSInteger)presentationFrameRate {
  return _presentationFrameRate.load(std::memory_order_relaxed);
}

- (void)setVideoDiagnosticMode:(CNVideoDiagnosticMode)mode {
  const std::lock_guard lock(_lock);
  _videoDiagnosticMode = mode;
}

- (CNVideoDiagnosticMode)videoDiagnosticMode {
  const std::lock_guard lock(_lock);
  return _videoDiagnosticMode;
}

- (void)setPictureAdjustment:(CNPictureAdjustment)adjustment {
  const std::lock_guard lock(_lock);
  _pictureAdjustment = adjustment;
}

- (CNPictureAdjustment)pictureAdjustment {
  const std::lock_guard lock(_lock);
  return _pictureAdjustment;
}

- (void)setLightMarkerShown:(BOOL)shown {
  const std::lock_guard lock(_lock);
  _markerShown = shown;
}

- (BOOL)lightMarkerShown {
  const std::lock_guard lock(_lock);
  return _markerShown;
}

- (CGPoint)lightMarker {
  const std::lock_guard lock(_lock);
  return _marker;
}

- (void)setMeasuresLight:(BOOL)measures {
  const std::lock_guard lock(_lock);
  if (measures && !_measuresLight) {
    _light.reset(CFAbsoluteTimeGetCurrent());
  }
  _measuresLight = measures;
}

- (BOOL)measuresLight {
  const std::lock_guard lock(_lock);
  return _measuresLight;
}

- (void)setLightMarkerX:(double)x y:(double)y {
  const std::lock_guard lock(_lock);
  _marker = CGPointMake(std::clamp(x, 0.0, 1.0), std::clamp(y, 0.0, 1.0));
  _markerFollowsPointer = NO;
}

#if TARGET_OS_OSX
- (void)viewDidMoveToWindow {
  [super viewDidMoveToWindow];
  self.window.acceptsMouseMovedEvents = YES;
}

- (void)updateTrackingAreas {
  [super updateTrackingAreas];
  if (_markerTracking) {
    [self removeTrackingArea:_markerTracking];
  }
  _markerTracking =
      [[NSTrackingArea alloc] initWithRect:NSZeroRect
                                   options:NSTrackingMouseMoved | NSTrackingMouseEnteredAndExited |
                                           NSTrackingActiveAlways | NSTrackingInVisibleRect
                                     owner:self
                                  userInfo:nil];
  [self addTrackingArea:_markerTracking];
}

- (void)mouseMoved:(NSEvent *)event {
  [super mouseMoved:event];
  NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
  NSSize size = self.bounds.size;
  if (size.width <= 0 || size.height <= 0) {
    return;
  }
  double x = std::clamp(point.x / size.width, 0.0, 1.0);
  double y =
      std::clamp(self.isFlipped ? point.y / size.height : 1 - point.y / size.height, 0.0, 1.0);
  const std::lock_guard lock(_lock);
  _marker = CGPointMake(x, y);
  _markerFollowsPointer = YES;
}

- (void)mouseExited:(NSEvent *)event {
  [super mouseExited:event];
  const std::lock_guard lock(_lock);
  _marker = CGPointMake(0.5, 0.5);
  _markerFollowsPointer = NO;
}
#endif

- (void)notePresented {
  BOOL first = NO;
  {
    const std::lock_guard lock(_lock);
    first = !_didPresent && !_closed;
    _didPresent = YES;
  }
  if (first) {
    dispatch_async(dispatch_get_main_queue(), ^{
      if (self.firstFramePresentedHandler) {
        self.firstFramePresentedHandler();
      }
    });
  }
}

- (void)presentWithoutVideo {
  [self notePresented];
}

- (void)encodeFSRCNNFromLuma:(id<MTLTexture>)luma
                      chroma:(id<MTLTexture>)chroma
                      output:(id<MTLTexture>)output
                      config:(const video::ColourConfig &)config
                     command:(id<MTLCommandBuffer>)command {
  MPSImage *input = [[MPSImage alloc] initWithTexture:luma featureChannels:1];
  MPSImage *subconv = [_fsrcnnGraph encodeToCommandBuffer:command
                                             sourceImages:@[ input ]
                                             sourceStates:nil
                                       intermediateImages:nil
                                        destinationStates:nil];
  id<MTLComputeCommandEncoder> encoder = [command computeCommandEncoder];
  [encoder setComputePipelineState:_fsrcnnColourPipeline];
  [encoder setBytes:&config length:sizeof config atIndex:0];
  [encoder setTexture:subconv.texture atIndex:0];
  [encoder setTexture:chroma atIndex:1];
  [encoder setTexture:luma atIndex:3];
  [encoder setTexture:output atIndex:2];
  [encoder dispatchThreads:MTLSizeMake(output.width, output.height, 1)
      threadsPerThreadgroup:MTLSizeMake(16, 16, 1)];
  [encoder endEncoding];
}

- (std::optional<std::size_t>)encodeLightLevelsFromLuma:(id<MTLTexture>)luma
                                                 chroma:(id<MTLTexture>)chroma
                                                 config:(const video::ColourConfig &)config
                                                command:(id<MTLCommandBuffer>)command {
  if (!_lightPipeline) {
    return std::nullopt;
  }
  std::size_t slot = 0;
  {
    const std::lock_guard lock(_lock);
    slot = _lightBufferIndex % video::lightBufferCount;
    if (_lightBufferBusy[slot]) {
      return std::nullopt;
    }
    _lightBufferBusy[slot] = true;
    _lightBufferIndex++;
  }
  if (!_lightBuffers[slot]) {
    _lightBuffers[slot] = [_device newBufferWithLength:sizeof(video::LightSample)
                                               options:MTLResourceStorageModeShared];
  }
  id<MTLBuffer> levels = _lightBuffers[slot];
  if (!levels) {
    const std::lock_guard lock(_lock);
    _lightBufferBusy[slot] = false;
    return std::nullopt;
  }
  *static_cast<video::LightSample *>(levels.contents) = video::LightSample{};
  const auto step = static_cast<std::uint32_t>(
      std::max(1.0, std::ceil(std::sqrt(static_cast<double>(luma.width * luma.height) /
                                        video::lightSampleBudget))));
  id<MTLComputeCommandEncoder> encoder = [command computeCommandEncoder];
  [encoder setComputePipelineState:_lightPipeline];
  [encoder setBytes:&config length:sizeof config atIndex:0];
  [encoder setBuffer:levels offset:0 atIndex:1];
  [encoder setBytes:&step length:sizeof step atIndex:2];
  [encoder setTexture:luma atIndex:0];
  [encoder setTexture:chroma atIndex:1];
  [encoder dispatchThreads:MTLSizeMake((luma.width + step - 1) / step,
                                       (luma.height + step - 1) / step, 1)
      threadsPerThreadgroup:MTLSizeMake(16, 16, 1)];
  [encoder endEncoding];
  return slot;
}

- (BOOL)prepareSpatialScalerWithInputWidth:(NSUInteger)inputWidth
                               inputHeight:(NSUInteger)inputHeight
                               outputWidth:(NSUInteger)outputWidth
                              outputHeight:(NSUInteger)outputHeight
                                       hdr:(BOOL)hdr {
#if !CN_METALFX
  return NO;
#else
  if (_spatialScaler && _spatialInputWidth == inputWidth && _spatialInputHeight == inputHeight &&
      _spatialOutputWidth == outputWidth && _spatialOutputHeight == outputHeight &&
      _spatialHDR == hdr) {
    return YES;
  }
  if (![MTLFXSpatialScalerDescriptor supportsDevice:_device]) {
    return NO;
  }
  MTLFXSpatialScalerDescriptor *descriptor = [MTLFXSpatialScalerDescriptor new];
  descriptor.colorTextureFormat = MTLPixelFormatRGBA16Float;
  descriptor.outputTextureFormat = MTLPixelFormatRGBA16Float;
  descriptor.inputWidth = inputWidth;
  descriptor.inputHeight = inputHeight;
  descriptor.outputWidth = outputWidth;
  descriptor.outputHeight = outputHeight;
  descriptor.colorProcessingMode =
      hdr ? MTLFXSpatialScalerColorProcessingModeHDR : MTLFXSpatialScalerColorProcessingModeLinear;
  id<MTLFXSpatialScaler> scaler = [descriptor newSpatialScalerWithDevice:_device];
  if (!scaler) {
    return NO;
  }
  MTLTextureDescriptor *texture =
      [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA16Float
                                                         width:inputWidth
                                                        height:inputHeight
                                                     mipmapped:NO];
  texture.storageMode = MTLStorageModePrivate;
  texture.usage = MTLTextureUsageShaderWrite | scaler.colorTextureUsage;
  id<MTLTexture> input = [_device newTextureWithDescriptor:texture];
  if (!input) {
    return NO;
  }
  _spatialScaler = scaler;
  _spatialInput = input;
  _spatialInputWidth = inputWidth;
  _spatialInputHeight = inputHeight;
  _spatialOutputWidth = outputWidth;
  _spatialOutputHeight = outputHeight;
  _spatialHDR = hdr;
  return YES;
#endif
}

#if TARGET_OS_OSX
- (void)layout {
  [super layout];
  CGFloat scale = self.window.backingScaleFactor ?: 1;
#else
- (void)layoutSubviews {
  [super layoutSubviews];
  CGFloat scale = self.window.screen.nativeScale ?: self.contentScaleFactor;
#endif
  _metal.contentsScale = scale;
  if (self.targetOutputHeight > 0) {
    _metal.drawableSize = CGSizeMake(self.targetOutputHeight * 16 / 9, self.targetOutputHeight);
  } else {
    _metal.drawableSize = CGSizeMake(std::max<CGFloat>(1, self.bounds.size.width * scale),
                                     std::max<CGFloat>(1, self.bounds.size.height * scale));
  }
}

- (void)offer:(CVPixelBufferRef)surface generated:(BOOL)generated {
  video::PixelBuffer retained = video::PixelBuffer::retaining(surface);
  video::PendingFrames::Offer outcome = video::PendingFrames::Offer::queued;
  {
    const std::lock_guard lock(_lock);
    if (_closed) {
      return;
    }
    outcome = _pending.offer(std::move(retained), generated);
  }
  switch (outcome) {
    case video::PendingFrames::Offer::queued:
      break;
    case video::PendingFrames::Offer::generated_refused:
    case video::PendingFrames::Offer::generated_replaced:
      _generatedDrops.fetch_add(1, std::memory_order_relaxed);
      break;
    case video::PendingFrames::Offer::decoded_replaced:
      _replacedFrames.fetch_add(1, std::memory_order_relaxed);
      break;
  }
}

- (void)metalDisplayLink:(CAMetalDisplayLink *)link needsUpdate:(CAMetalDisplayLinkUpdate *)update {
  BOOL idle = NO;
  BOOL missed = NO;
  BOOL render = NO;
  {
    const std::lock_guard lock(_lock);
    idle = !_closed && _pending.empty() && _didPresent;
    if (!_closed && !_pending.empty()) {
      missed = _rendering;
      render = !_rendering;
    }
    if (render) {
      _rendering = YES;
    }
  }
  if (idle) {
    _idleTicks.fetch_add(1, std::memory_order_relaxed);
  }
  if (missed) {
    _deadlineMisses.fetch_add(1, std::memory_order_relaxed);
  }
  if (!render) {
    return;
  }
  id<CAMetalDrawable> drawable = update.drawable;
  dispatch_async(_renderQueue, ^{
    [self renderDrawable:drawable];
  });
}

- (void)finishRender {
  const std::lock_guard lock(_lock);
  _rendering = NO;
}

- (void)countRejected {
  _rejected.fetch_add(1, std::memory_order_relaxed);
}

- (void)renderDrawable:(id<CAMetalDrawable>)drawable {
  @autoreleasepool {
    std::optional<video::PixelBuffer> taken;
    BOOL closed = NO;
    {
      const std::lock_guard lock(_lock);
      taken = _pending.take();
      closed = _closed;
    }
    if (!taken || closed) {
      [self finishRender];
      return;
    }
    if (!drawable) {
      _noDrawable.fetch_add(1, std::memory_order_relaxed);
    }
    os_signpost_id_t signpost = os_signpost_id_generate(_signposts);
    os_signpost_interval_begin(_signposts, signpost, "Encode");
    [self render:std::move(*taken) into:drawable];
    os_signpost_interval_end(_signposts, signpost, "Encode");
  }
}

- (void)render:(video::PixelBuffer)owned into:(id<CAMetalDrawable>)drawable {
  CVPixelBufferRef surface = owned.get();
  OSType pixel = CVPixelBufferGetPixelFormatType(surface);
  BOOL ten = pixel == kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange ||
             pixel == kCVPixelFormatType_420YpCbCr10BiPlanarFullRange;
  video::MetalTexture y;
  video::MetalTexture uv;
  BOOL valid =
      drawable && CVPixelBufferGetIOSurface(surface) && CVPixelBufferGetPlaneCount(surface) == 2;
  if (valid) {
    valid = CVMetalTextureCacheCreateTextureFromImage(
                nullptr, _cache.get(), surface, nullptr,
                ten ? MTLPixelFormatR16Unorm : MTLPixelFormatR8Unorm,
                CVPixelBufferGetWidthOfPlane(surface, 0), CVPixelBufferGetHeightOfPlane(surface, 0),
                0, y.out()) == kCVReturnSuccess;
  }
  if (valid) {
    valid = CVMetalTextureCacheCreateTextureFromImage(
                nullptr, _cache.get(), surface, nullptr,
                ten ? MTLPixelFormatRG16Unorm : MTLPixelFormatRG8Unorm,
                CVPixelBufferGetWidthOfPlane(surface, 1), CVPixelBufferGetHeightOfPlane(surface, 1),
                1, uv.out()) == kCVReturnSuccess;
  }
  if (!valid) {
    [self countRejected];
    [self finishRender];
    return;
  }
  id<MTLTexture> yt = CVMetalTextureGetTexture(y.get());
  id<MTLTexture> uvt = CVMetalTextureGetTexture(uv.get());
  if (yt.iosurface != CVPixelBufferGetIOSurface(surface) ||
      uvt.iosurface != CVPixelBufferGetIOSurface(surface)) {
    [self countRejected];
    [self finishRender];
    return;
  }
  [self readColourOf:surface pixel:pixel];
  BOOL bt2020 = _colourBT2020;
  BOOL pq = _colourPQ;
  if (_layerHDR != pq) {
    _layerHDR = pq;
    {
      const std::lock_guard lock(_lock);
      _light.reset(CFAbsoluteTimeGetCurrent());
    }
    CAMetalLayer *metal = _metal;
    dispatch_async(dispatch_get_main_queue(), ^{
      metal.wantsExtendedDynamicRangeContent = pq;
    });
  }
  CNVideoDiagnosticMode diagnosticMode = CNVideoDiagnosticModeOff;
  CNPictureAdjustment adjustment{};
  std::uint32_t frame = 0;
  double headroom = 0;
  double contentPeak = 0;
  CGPoint marker = CGPointMake(-1, 0);
  BOOL measuresLight = NO;
  {
    const std::lock_guard lock(_lock);
    diagnosticMode = _videoDiagnosticMode;
    adjustment = _pictureAdjustment;
    frame = _frameCounter++;
    headroom = _screenHeadroom * 0.95;
    contentPeak = _contentPeakNits / 203;
    if (_markerShown || _markerFollowsPointer) {
      marker = _marker;
    } else {
      marker.y = _marker.y;
    }
    measuresLight = _measuresLight;
  }
  if (pq && frame % 30 == 0) {
    [self refreshScreenHeadroom];
  }
  BOOL toneMap = pq && headroom >= 0.95 && contentPeak > headroom;
  BOOL adjust = adjustment.brightness != 0 || adjustment.contrast != 1 ||
                adjustment.saturation != 1 || adjustment.gamma != 1;
  const video::ColourConfig config{
      .tenBit = ten,
      .fullRange = pixel == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange ||
                   pixel == kCVPixelFormatType_420YpCbCr10BiPlanarFullRange,
      .bt2020 = bt2020,
      .pq = pq,
      .toneMap = toneMap,
      .diagnosticMode = static_cast<std::uint32_t>(diagnosticMode),
      .referenceWhiteNits = 203,
      .adjust = adjust,
      .brightness = adjustment.brightness,
      .contrast = adjustment.contrast,
      .saturation = adjustment.saturation,
      .gamma = adjustment.gamma,
      .deband = adjustment.deband,
      .frame = frame,
      .headroom = static_cast<float>(headroom),
      .contentPeak = static_cast<float>(contentPeak),
      .markerX = static_cast<float>(marker.x),
      .markerY = static_cast<float>(marker.y),
  };
  NSUInteger sourceWidth = CVPixelBufferGetWidthOfPlane(surface, 0);
  NSUInteger sourceHeight = CVPixelBufferGetHeightOfPlane(surface, 0);
  NSUInteger outputWidth = drawable.texture.width;
  NSUInteger outputHeight = drawable.texture.height;
  BOOL fsrcnnAllowed = NO;
  {
    const std::lock_guard lock(_lock);
    _sourceWidth = sourceWidth;
    _sourceHeight = sourceHeight;
    _outputWidth = outputWidth;
    _outputHeight = outputHeight;
    _inputTenBit = ten;
    _inputPQ = pq;
    _inputBT2020 = bt2020;
    fsrcnnAllowed = _fsrcnnAllowed;
  }
  BOOL upscale = outputWidth > sourceWidth && outputHeight > sourceHeight;
  BOOL exactDouble = outputWidth == sourceWidth * 2 && outputHeight == sourceHeight * 2;
  BOOL useFSRCNN = self.videoUpscaler == CNVideoUpscalerAdvancedSpatial && exactDouble &&
                   _fsrcnnGraph != nil && fsrcnnAllowed;
  if (useFSRCNN) {
    const std::lock_guard lock(_lock);
    _usedFSRCNN = YES;
  }
  BOOL useSpatial = NO;
  BOOL spatialRequested = self.videoUpscaler != CNVideoUpscalerDisabled;
  if (upscale && spatialRequested && !useFSRCNN) {
    useSpatial = [self prepareSpatialScalerWithInputWidth:sourceWidth
                                              inputHeight:sourceHeight
                                              outputWidth:outputWidth
                                             outputHeight:outputHeight
                                                      hdr:pq];
  }
  id<MTLTexture> finalOutput = drawable.texture;
  id<MTLTexture> conversionOutput = useSpatial ? _spatialInput : finalOutput;
  id<MTLCommandBuffer> command = [_queue commandBuffer];
  if (useFSRCNN) {
    [self encodeFSRCNNFromLuma:yt chroma:uvt output:finalOutput config:config command:command];
  } else {
    id<MTLComputeCommandEncoder> encoder = [command computeCommandEncoder];
    [encoder setComputePipelineState:useSpatial ? _nativePipeline : _pipeline];
    [encoder setBytes:&config length:sizeof config atIndex:0];
    [encoder setTexture:yt atIndex:0];
    [encoder setTexture:uvt atIndex:1];
    [encoder setTexture:conversionOutput atIndex:2];
    [encoder dispatchThreads:MTLSizeMake(conversionOutput.width, conversionOutput.height, 1)
        threadsPerThreadgroup:MTLSizeMake(16, 16, 1)];
    [encoder endEncoding];
  }
  std::optional<std::size_t> lightSlot;
  if (measuresLight && frame % video::lightLevelInterval == 0) {
    lightSlot = [self encodeLightLevelsFromLuma:yt chroma:uvt config:config command:command];
  }
#if CN_METALFX
  if (useSpatial && !useFSRCNN) {
    _spatialScaler.colorTexture = _spatialInput;
    _spatialScaler.inputContentWidth = sourceWidth;
    _spatialScaler.inputContentHeight = sourceHeight;
    _spatialScaler.outputTexture = finalOutput;
    [_spatialScaler encodeToCommandBuffer:command];
    if (toneMap) {
      float limit = static_cast<float>(headroom / 0.95);
      id<MTLComputeCommandEncoder> clamp = [command computeCommandEncoder];
      [clamp setComputePipelineState:_clampPipeline];
      [clamp setTexture:finalOutput atIndex:0];
      [clamp setBytes:&limit length:sizeof limit atIndex:0];
      [clamp dispatchThreads:MTLSizeMake(finalOutput.width, finalOutput.height, 1)
          threadsPerThreadgroup:MTLSizeMake(16, 16, 1)];
      [clamp endEncoding];
    }
  }
#endif
#if TARGET_OS_SIMULATOR
  [command addScheduledHandler:^(id<MTLCommandBuffer> scheduled) {
    [self notePresented];
  }];
#else
  [drawable addPresentedHandler:^(id<MTLDrawable> presented) {
    [self notePresented];
  }];
#endif
  [command presentDrawable:drawable];
  _submitted.fetch_add(1, std::memory_order_relaxed);
  __block video::PixelBuffer heldSurface = std::move(owned);
  __block video::MetalTexture heldLuma = std::move(y);
  __block video::MetalTexture heldChroma = std::move(uv);
  os_log_t signposts = _signposts;
  os_signpost_id_t gpu = os_signpost_id_generate(signposts);
  os_signpost_interval_begin(signposts, gpu, "GPU");
  [command addCompletedHandler:^(id<MTLCommandBuffer> finished) {
    os_signpost_interval_end(signposts, gpu, "GPU");
    [self completed:finished fsrcnn:useFSRCNN lightSlot:lightSlot];
    heldSurface = video::PixelBuffer{};
    heldLuma = video::MetalTexture{};
    heldChroma = video::MetalTexture{};
    [self finishRender];
  }];
  [command commit];
}

- (void)completed:(id<MTLCommandBuffer>)finished
           fsrcnn:(BOOL)useFSRCNN
        lightSlot:(std::optional<std::size_t>)lightSlot {
  if (finished.status == MTLCommandBufferStatusCompleted) {
    _completed.fetch_add(1, std::memory_order_relaxed);
  }
  const std::lock_guard lock(_lock);
  if (lightSlot) {
    _lightBufferBusy[*lightSlot] = false;
  }
  if (finished.status != MTLCommandBufferStatusCompleted) {
    _gpuError = finished.error.code;
    return;
  }
  if (finished.GPUEndTime > finished.GPUStartTime) {
    double elapsed = (finished.GPUEndTime - finished.GPUStartTime) * 1000;
    _gpuMilliseconds = _gpuMilliseconds == 0 ? elapsed : _gpuMilliseconds * 0.9 + elapsed * 0.1;
  }
  if (lightSlot) {
    _light.note(*static_cast<const video::LightSample *>(_lightBuffers[*lightSlot].contents));
  }
  if (useFSRCNN && finished.GPUEndTime > finished.GPUStartTime &&
      finished.GPUEndTime - finished.GPUStartTime > 0.008) {
    _fsrcnnAllowed = NO;
    _fsrcnnBudgetFallback = YES;
  }
}

- (CNSurfaceStatistics)statistics {
  CNSurfaceStatistics result{};
  result.submitted = _submitted.load(std::memory_order_relaxed);
  result.completed = _completed.load(std::memory_order_relaxed);
  result.rejected = _rejected.load(std::memory_order_relaxed);
  result.noDrawable = _noDrawable.load(std::memory_order_relaxed);
  result.generatedDrops = _generatedDrops.load(std::memory_order_relaxed);
  result.replacedFrames = _replacedFrames.load(std::memory_order_relaxed);
  result.idleTicks = _idleTicks.load(std::memory_order_relaxed);
  result.deadlineMisses = _deadlineMisses.load(std::memory_order_relaxed);
  {
    const std::lock_guard lock(_lock);
    result.gpuError = _gpuError;
    result.spatialUpscaling = _spatialInput != nil;
    result.advancedSpatial = _usedFSRCNN;
    result.advancedBudgetFallback = _fsrcnnBudgetFallback;
    result.sourceWidth = _sourceWidth;
    result.sourceHeight = _sourceHeight;
    result.outputWidth = _outputWidth;
    result.outputHeight = _outputHeight;
    result.tenBit = _inputTenBit;
    result.pq = _inputPQ;
    result.bt2020 = _inputBT2020;
    result.layerHDR = _layerHDR;
    result.toneMapSource = _toneMapSource;
    result.contentPeakNits = _contentPeakNits;
    result.gpuMilliseconds = _gpuMilliseconds;
    result.diagnosticMode = _videoDiagnosticMode;
    result.lightMeasurements = _light.measurements();
    result.lightSeconds = _light.seconds(CFAbsoluteTimeGetCurrent());
    result.lightPeakNits = _light.peak();
    result.lightAverageNits = _light.average();
    result.lightAbovePercent = _light.above();
    result.maxCLL = _light.maxCLL();
    result.maxFALL = _light.maxFALL();
    result.sessionAbovePercent = _light.sessionAbove();
    result.sessionNearWhitePercent = _light.sessionNearWhite();
    result.markerNits = _light.marker();
    result.markerFollowsPointer = _markerFollowsPointer;
    result.markerVisible = _markerShown || _markerFollowsPointer;
  }
  result.presentationFrameRate = self.presentationFrameRate;
  result.width = self.bounds.size.width;
  result.height = self.bounds.size.height;
  result.attached = self.window != nil;
#if TARGET_OS_OSX
  NSScreen *screen = self.window.screen ?: NSScreen.mainScreen;
  if (screen) {
    result.displayMaximumFPS = screen.maximumFramesPerSecond;
    result.displayMaximumEDR = screen.maximumExtendedDynamicRangeColorComponentValue;
    result.displayPotentialEDR = screen.maximumPotentialExtendedDynamicRangeColorComponentValue;
  }
#else
  UIScreen *screen = self.window.screen;
  if (screen) {
    result.displayMaximumFPS = screen.maximumFramesPerSecond;
    result.displayMaximumEDR = screen.currentEDRHeadroom;
    result.displayPotentialEDR = screen.potentialEDRHeadroom;
  }
#endif
  return result;
}

- (void)close {
  [_displayLink close];
  const std::lock_guard lock(_lock);
  _closed = YES;
  _pending.clear();
}

- (void)dealloc {
  [_displayLink close];
}

@end
