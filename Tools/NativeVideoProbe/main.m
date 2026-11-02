#import <AVFoundation/AVFoundation.h>
#import <Foundation/Foundation.h>
#import <IOSurface/IOSurface.h>
#import <Metal/Metal.h>
#include <math.h>
#include <stdatomic.h>
#import "AnnexBSample.h"
#import "VideoDecoderClient.h"
typedef struct {
  uint32_t tenBit, fullRange, bt2020, pq, toneMap;
  float referenceWhiteNits;
} ColourConfig;
static NSUInteger expectedFrames;
static void require(BOOL condition, const char *message) {
  if (!condition) {
    fprintf(stderr, "FAIL: %s\n", message);
    exit(1);
  }
}
static int compareDouble(const void *a, const void *b) {
  double left = *(const double *)a, right = *(const double *)b;
  return (left > right) - (left < right);
}
static void printTimings(const char *name, double *values, NSUInteger count) {
  require(count > 0 && count <= 10000, "Invalid timing count");
  qsort(values, count, sizeof(double), compareDouble);
  printf("%s ms: p50 %.3f, p95 %.3f, p99 %.3f, max %.3f\n", name,
         values[(NSUInteger)ceil(count * .50) - 1], values[(NSUInteger)ceil(count * .95) - 1],
         values[(NSUInteger)ceil(count * .99) - 1], values[count - 1]);
}
@interface SurfaceProbe : NSObject
- (instancetype)initWithShader:(NSString *)path;
- (void)consume:(CVPixelBufferRef)surface;
- (void)finish;
@end
@implementation SurfaceProbe {
  id<MTLDevice> _device;
  id<MTLCommandQueue> _queue;
  id<MTLComputePipelineState> _pipeline;
  CVMetalTextureCacheRef _cache;
  dispatch_semaphore_t _slotReady[2];
  dispatch_group_t _group;
  atomic_int _failures;
  NSUInteger _frames;
  NSUInteger _tenBit;
  double _gpuMilliseconds[10000];
  id<MTLTexture> _outputs[2];
}
- (instancetype)initWithShader:(NSString *)path {
  self = [super init];
  if (!self) {
    return nil;
  }
  _device = MTLCreateSystemDefaultDevice();
  require(_device != nil, "Metal device unavailable");
  _queue = [_device newCommandQueue];
  NSError *error = nil;
  NSString *source = [NSString stringWithContentsOfFile:path
                                               encoding:NSUTF8StringEncoding
                                                  error:&error];
  require(source != nil, "Cannot read probe shader");
  id<MTLLibrary> library = [_device newLibraryWithSource:source options:nil error:&error];
  if (!library) {
    fprintf(stderr, "%s\n", error.localizedDescription.UTF8String);
  }
  require(library != nil, "Probe shader compilation failed");
  _pipeline =
      [_device newComputePipelineStateWithFunction:[library newFunctionWithName:@"colour_planes"]
                                             error:&error];
  require(_pipeline != nil && _queue != nil, "Metal setup failed");
  require(CVMetalTextureCacheCreate(NULL, NULL, _device, NULL, &_cache) == kCVReturnSuccess,
          "Texture cache creation failed");
  _slotReady[0] = dispatch_semaphore_create(1);
  _slotReady[1] = dispatch_semaphore_create(1);
  _group = dispatch_group_create();
  atomic_init(&_failures, 0);
  return self;
}
- (void)consume:(CVPixelBufferRef)surface {
  require(surface && CVPixelBufferGetIOSurface(surface), "Frame has no shareable IOSurface");
  require(CVPixelBufferGetPlaneCount(surface) == 2, "Unsupported plane layout");
  OSType format = CVPixelBufferGetPixelFormatType(surface);
  BOOL tenBit = format == kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange ||
                format == kCVPixelFormatType_420YpCbCr10BiPlanarFullRange;
  require(tenBit || format == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange ||
              format == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
          "Unsupported pixel format");
  CFTypeRef primaries = CVBufferGetAttachment(surface, kCVImageBufferColorPrimariesKey, NULL);
  CFTypeRef transfer = CVBufferGetAttachment(surface, kCVImageBufferTransferFunctionKey, NULL);
  CFTypeRef matrix = CVBufferGetAttachment(surface, kCVImageBufferYCbCrMatrixKey, NULL);
  BOOL bt2020 = primaries && CFEqual(primaries, kCVImageBufferColorPrimaries_ITU_R_2020);
  BOOL pq = transfer && CFEqual(transfer, kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ);
  require((bt2020 && matrix && CFEqual(matrix, kCVImageBufferYCbCrMatrix_ITU_R_2020)) ||
              (primaries && CFEqual(primaries, kCVImageBufferColorPrimaries_ITU_R_709_2) &&
               matrix && CFEqual(matrix, kCVImageBufferYCbCrMatrix_ITU_R_709_2)),
          "Unsupported colour primaries/matrix");
  require(pq || (transfer && CFEqual(transfer, kCVImageBufferTransferFunction_ITU_R_709_2)),
          "Unsupported transfer");
  ColourConfig config = {tenBit,
                         format == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange ||
                             format == kCVPixelFormatType_420YpCbCr10BiPlanarFullRange,
                         bt2020,
                         pq,
                         0,
                         100.0f};

  NSUInteger slot = _frames % 2;
  require(dispatch_semaphore_wait(_slotReady[slot],
                                  dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC)) == 0,
          "GPU slot deadline exceeded");
  NSUInteger width = CVPixelBufferGetWidth(surface), height = CVPixelBufferGetHeight(surface);
  require(width <= 8192 && height <= 8192, "Fixture dimensions exceed probe budget");
  if (!_outputs[slot] || _outputs[slot].width != width || _outputs[slot].height != height) {
    MTLTextureDescriptor *desc =
        [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA16Float
                                                           width:width
                                                          height:height
                                                       mipmapped:NO];
    desc.storageMode = MTLStorageModePrivate;
    desc.usage = MTLTextureUsageShaderWrite;
    _outputs[slot] = [_device newTextureWithDescriptor:desc];
    require(_outputs[slot] != nil, "Output allocation failed");
  }
  CVMetalTextureRef y = NULL, uv = NULL;
  require(CVMetalTextureCacheCreateTextureFromImage(
              NULL, _cache, surface, NULL, tenBit ? MTLPixelFormatR16Unorm : MTLPixelFormatR8Unorm,
              CVPixelBufferGetWidthOfPlane(surface, 0), CVPixelBufferGetHeightOfPlane(surface, 0),
              0, &y) == kCVReturnSuccess,
          "Luma plane import failed");
  require(
      CVMetalTextureCacheCreateTextureFromImage(
          NULL, _cache, surface, NULL, tenBit ? MTLPixelFormatRG16Unorm : MTLPixelFormatRG8Unorm,
          CVPixelBufferGetWidthOfPlane(surface, 1), CVPixelBufferGetHeightOfPlane(surface, 1), 1,
          &uv) == kCVReturnSuccess,
      "Chroma plane import failed");
  id<MTLTexture> yt = CVMetalTextureGetTexture(y), uvt = CVMetalTextureGetTexture(uv);
  require(yt && uvt, "Imported texture unavailable");
  require(yt.iosurface == CVPixelBufferGetIOSurface(surface) &&
              uvt.iosurface == CVPixelBufferGetIOSurface(surface),
          "Texture does not share decoded surface");
  CVPixelBufferRef lease = CVPixelBufferRetain(surface);
  id<MTLCommandBuffer> command = [_queue commandBuffer];
  id<MTLComputeCommandEncoder> encoder = [command computeCommandEncoder];
  require(command && encoder, "Command encoding unavailable");
  [encoder setComputePipelineState:_pipeline];
  [encoder setBytes:&config length:sizeof(config) atIndex:0];
  [encoder setTexture:yt atIndex:0];
  [encoder setTexture:uvt atIndex:1];
  [encoder setTexture:_outputs[slot] atIndex:2];
  [encoder dispatchThreads:MTLSizeMake(width, height, 1)
      threadsPerThreadgroup:MTLSizeMake(16, 16, 1)];
  [encoder endEncoding];
  require(_frames < 10000, "GPU timing budget exceeded");
  NSUInteger frameIndex = _frames;
  dispatch_group_enter(_group);
  [command addCompletedHandler:^(id<MTLCommandBuffer> completed) {
    if (completed.status != MTLCommandBufferStatusCompleted) {
      atomic_fetch_add(&self->_failures, 1);
    }
    self->_gpuMilliseconds[frameIndex] = (completed.GPUEndTime - completed.GPUStartTime) * 1000.0;
    if (!isfinite(self->_gpuMilliseconds[frameIndex]) || completed.GPUStartTime <= 0 ||
        completed.GPUEndTime < completed.GPUStartTime) {
      atomic_fetch_add(&self->_failures, 1);
    }
    CFRelease(y);
    CFRelease(uv);
    CVPixelBufferRelease(lease);
    dispatch_semaphore_signal(self->_slotReady[slot]);
    dispatch_group_leave(self->_group);
  }];
  [command commit];
  _frames++;
  if (tenBit) {
    _tenBit++;
  }
}
- (void)finish {
  require(dispatch_group_wait(_group, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC)) == 0,
          "GPU drain deadline exceeded");
  require(
      (!expectedFrames ? _frames > 0 : _frames == expectedFrames) && atomic_load(&_failures) == 0,
      "Unexpected frame count or GPU failure");
  printf("PASS: %lu frames, %lu ten-bit; decoded IOSurface identity preserved in Metal; GPU leases "
         "completed.\n",
         (unsigned long)_frames, (unsigned long)_tenBit);
  printTimings("GPU colour conversion", _gpuMilliseconds, _frames);

  printf("NOT a compressed-input zero-copy, pacing or HDR display certification.\n");
}
- (void)dealloc {
  if (_cache) {
    CFRelease(_cache);
  }
}
@end

static CMSampleBufferRef annexFixture(CMSampleBufferRef original) {
  CMBlockBufferRef source = CMSampleBufferGetDataBuffer(original);
  size_t size = CMBlockBufferGetDataLength(source);
  NSMutableData *owner = [NSMutableData dataWithLength:size];
  require(CMBlockBufferCopyDataBytes(source, 0, size, owner.mutableBytes) == noErr,
          "Fixture packet extraction failed");
  uint8_t *bytes = owner.mutableBytes;
  size_t offset = 0;
  while (offset < size) {
    require(size - offset >= 4, "Short fixture NAL prefix");
    uint32_t length = ((uint32_t)bytes[offset] << 24) | ((uint32_t)bytes[offset + 1] << 16) |
                      ((uint32_t)bytes[offset + 2] << 8) | bytes[offset + 3];
    require(length && length <= size - offset - 4, "Invalid fixture NAL length");
    bytes[offset] = bytes[offset + 1] = bytes[offset + 2] = 0;
    bytes[offset + 3] = 1;
    offset += 4 + length;
  }
  CMSampleBufferRef result = NULL;
  require(CNCreateAnnexBSample(bytes, size, owner, CMSampleBufferGetFormatDescription(original),
                               CMSampleBufferGetPresentationTimeStamp(original), &result) == noErr,
          "Owned Annex-B sample construction failed");
  return result;
}
int main(int argc, char **argv) {
  @autoreleasepool {
    require(argc == 3 || argc == 4,
            "Usage: native-video-probe fixture.mp4 colour.metal [expected frames]");
    if (argc == 4) {
      expectedFrames = strtoul(argv[3], NULL, 10);
    }
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:@(argv[1])] options:nil];
    AVAssetTrack *track = [[asset tracksWithMediaType:AVMediaTypeVideo] firstObject];
    require(track != nil, "Video track missing");
    CNVideoDecoderClient *decoder = [CNVideoDecoderClient new];
    SurfaceProbe *probe = [[SurfaceProbe alloc] initWithShader:@(argv[2])];
    NSUInteger totalSubmitted = 0;
    NSUInteger passes = getenv("CN_VIDEO_RESTART") ? 2 : 1;
    if (expectedFrames) {
      expectedFrames *= passes;
    }
    for (NSUInteger pass = 0; pass < passes; pass++) {
      NSError *error = nil;
      AVAssetReader *reader = [[AVAssetReader alloc] initWithAsset:asset error:&error];
      AVAssetReaderTrackOutput *source = [[AVAssetReaderTrackOutput alloc] initWithTrack:track
                                                                          outputSettings:nil];
      source.alwaysCopiesSampleData = NO;
      require([reader canAddOutput:source], "Cannot attach compressed fixture reader");
      [reader addOutput:source];
      require([reader startReading], "Cannot read fixture");
      NSUInteger submitted = 0;
      CMSampleBufferRef sample;
      while ((sample = [source copyNextSampleBuffer])) {
        @autoreleasepool {
          if (CMSampleBufferGetNumSamples(sample) == 0 && !CMSampleBufferGetDataBuffer(sample)) {
            CFRelease(sample);
            continue;
          }
          require(++submitted <= 10000, "Fixture exceeds packet budget");
          if (submitted == 1) {
            CMVideoFormatDescriptionRef format = CMSampleBufferGetFormatDescription(sample);
            CFTypeRef bits = CMFormatDescriptionGetExtension(format, CFSTR("BitsPerComponent"));
            CFTypeRef transfer = CMFormatDescriptionGetExtension(
                format, kCMFormatDescriptionExtension_TransferFunction);
            BOOL tenBit =
                (bits && [(__bridge NSNumber *)bits intValue] > 8) ||
                (transfer &&
                 CFEqual(transfer, kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ));
            OSStatus status = [decoder configure:format tenBit:tenBit];
            if (status) {
              fprintf(stderr, "Configure status %d\n", (int)status);
            }
            require(status == noErr && decoder.hardwareVerified,
                    "Hardware decoder configuration failed");
          }
          if (getenv("CN_VIDEO_ANNEXB")) {
            CMSampleBufferRef framed = annexFixture(sample);
            CFRelease(sample);
            sample = framed;
          }
          CNVideoOutput output = ^(OSStatus status, CVPixelBufferRef surface, CMTime pts) {
            require(status == noErr && surface != NULL, "Native decode callback failed");

            @synchronized(probe) {
              @autoreleasepool {
                [probe consume:surface];
              }
            }
          };
          CNVideoSubmitResult result = [decoder submit:sample output:output];
          if (result == CNVideoSubmitWouldBlock) {
            require([decoder drain] == noErr, "Offline batch drain failed");
            result = [decoder submit:sample output:output];
          }
          require(result == CNVideoSubmitAccepted, "Native sample submission failed");
          CFRelease(sample);
        }
      }
      require(reader.status == AVAssetReaderStatusCompleted, "Fixture read failed");
      require([decoder drain] == noErr, "Final decoder drain failed");
      totalSubmitted += submitted;
    }
    if (!expectedFrames) {
      expectedFrames = totalSubmitted;
    }
    [probe finish];
    require(decoder.hardwareVerified, "Hardware verification lost");
    [decoder stop];
    printf(
        "PASS: direct VideoToolbox hardware decoder, %lu compressed samples; no FFmpeg linked.\n",
        (unsigned long)totalSubmitted);
  }
  return 0;
}
