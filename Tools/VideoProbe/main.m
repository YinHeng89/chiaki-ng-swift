#import <CoreVideo/CoreVideo.h>
#import <Foundation/Foundation.h>
#import <IOSurface/IOSurface.h>
#import <Metal/Metal.h>
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libavutil/hwcontext.h>
#include <libavutil/time.h>
#include <math.h>
#include <stdatomic.h>

typedef struct {
  uint32_t tenBit, fullRange, bt2020, pq, toneMap;
  float referenceWhiteNits;
} ColourConfig;
static NSUInteger expectedFrames = 60;

static enum AVPixelFormat hardwareFormat(AVCodecContext *context,
                                         const enum AVPixelFormat *formats) {
  for (; *formats != AV_PIX_FMT_NONE; formats++) {
    if (*formats == AV_PIX_FMT_VIDEOTOOLBOX) {
      return *formats;
    }
  }
  return AV_PIX_FMT_NONE;
}
static void require(BOOL condition, const char *message) {
  if (!condition) {
    fprintf(stderr, "FAIL: %s\n", message);
    exit(1);
  }
}

static double decodeMilliseconds[10000];
static unsigned decodeSamples;
static int compareDouble(const void *a, const void *b) {
  double left = *(const double *)a, right = *(const double *)b;
  return (left > right) - (left < right);
}
static void printTimings(const char *name, double *values, NSUInteger count) {
  require(count > 0 && count <= 10000, "Invalid timing sample count");
  qsort(values, count, sizeof(double), compareDouble);
  printf("%s ms: p50 %.3f, p95 %.3f, p99 %.3f, max %.3f (%lu samples)\n", name,
         values[(NSUInteger)ceil(count * .50) - 1], values[(NSUInteger)ceil(count * .95) - 1],
         values[(NSUInteger)ceil(count * .99) - 1], values[count - 1], (unsigned long)count);
}
static int timedSend(AVCodecContext *decoder, const AVPacket *packet) {
  int64_t start = av_gettime_relative();
  int result = avcodec_send_packet(decoder, packet);
  require(decodeSamples < 10000, "Decode timing budget exceeded");
  decodeMilliseconds[decodeSamples++] = (av_gettime_relative() - start) / 1000.0;
  return result;
}

@interface SurfaceProbe : NSObject
- (instancetype)initWithShader:(NSString *)path;
- (void)consume:(AVFrame *)frame;
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
- (void)consume:(AVFrame *)frame {
  require(frame->format == AV_PIX_FMT_VIDEOTOOLBOX, "Decoder returned software pixels");
  CVPixelBufferRef surface = (CVPixelBufferRef)frame->data[3];
  require(surface && CVPixelBufferGetIOSurface(surface), "Frame has no shareable IOSurface");
  require(CVPixelBufferGetPlaneCount(surface) == 2, "Unsupported plane layout");
  OSType format = CVPixelBufferGetPixelFormatType(surface);
  BOOL tenBit = format == kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange ||
                format == kCVPixelFormatType_420YpCbCr10BiPlanarFullRange;
  require(tenBit || format == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange ||
              format == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
          "Unsupported pixel format");
  if (frame->color_primaries != AVCOL_PRI_BT709 && frame->color_primaries != AVCOL_PRI_BT2020) {
    fprintf(stderr, "Frame colour tags: matrix=%d primaries=%d transfer=%d\n", frame->colorspace,
            frame->color_primaries, frame->color_trc);
  }
  require(frame->colorspace == AVCOL_SPC_BT709 || frame->colorspace == AVCOL_SPC_BT2020_NCL,
          "Unsupported or missing YCbCr matrix");
  require(frame->color_primaries == AVCOL_PRI_BT709 || frame->color_primaries == AVCOL_PRI_BT2020,
          "Unsupported or missing colour primaries");
  require(
      (frame->colorspace == AVCOL_SPC_BT2020_NCL) == (frame->color_primaries == AVCOL_PRI_BT2020),
      "Mixed matrix/primaries require explicit support");
  require(frame->color_trc == AVCOL_TRC_BT709 || frame->color_trc == AVCOL_TRC_SMPTE2084,
          "Unsupported or missing transfer function (HLG pending)");
  ColourConfig config = {tenBit,
                         format == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange ||
                             format == kCVPixelFormatType_420YpCbCr10BiPlanarFullRange,
                         frame->color_primaries == AVCOL_PRI_BT2020,
                         frame->color_trc == AVCOL_TRC_SMPTE2084,
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
  AVFrame *lease = av_frame_clone(frame);
  require(lease != NULL, "Frame lease allocation failed");
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
    AVFrame *owned = lease;
    av_frame_free(&owned);
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
  printTimings("Packet submission (including synchronous backend work)", decodeMilliseconds,
               decodeSamples);
  printf("NOT a compressed-input zero-copy, pacing or HDR display certification.\n");
}
- (void)dealloc {
  if (_cache) {
    CFRelease(_cache);
  }
}
@end

static int drain(AVCodecContext *decoder, AVFrame *frame, SurfaceProbe *probe) {
  int status;
  while ((status = avcodec_receive_frame(decoder, frame)) == 0) {
    @autoreleasepool {
      [probe consume:frame];
    }
    av_frame_unref(frame);
  }
  require(status == AVERROR(EAGAIN) || status == AVERROR_EOF, "Decode failed");
  return status;
}
int main(int argc, char **argv) {
  @autoreleasepool {
    require(argc == 3 || argc == 4,
            "Usage: video-probe fixture.mp4 colour.metal [expected frames, 0 for variable]");
    if (argc == 4) {
      expectedFrames = strtoul(argv[3], NULL, 10);
    }
    printf("Diagnostic FFmpeg %s\n", av_version_info());
    require(avcodec_version() == LIBAVCODEC_VERSION_INT &&
                avformat_version() == LIBAVFORMAT_VERSION_INT &&
                avutil_version() == LIBAVUTIL_VERSION_INT,
            "Runtime FFmpeg libraries do not match the pinned build headers");
    av_log_set_level(AV_LOG_ERROR);
    AVFormatContext *input = NULL;
    require(avformat_open_input(&input, argv[1], NULL, NULL) == 0, "Cannot open fixture");
    require(avformat_find_stream_info(input, NULL) >= 0, "Cannot inspect fixture");
    const AVCodec *codec = NULL;
    int stream = av_find_best_stream(input, AVMEDIA_TYPE_VIDEO, -1, -1, &codec, 0);
    require(stream >= 0 && (codec->id == AV_CODEC_ID_H264 || codec->id == AV_CODEC_ID_HEVC),
            "Expected H264 or HEVC fixture");
    AVCodecContext *decoder = avcodec_alloc_context3(codec);
    require(decoder != NULL, "Decoder allocation failed");
    require(avcodec_parameters_to_context(decoder, input->streams[stream]->codecpar) >= 0,
            "Invalid codec parameters");
    decoder->get_format = hardwareFormat;
    decoder->thread_count = 1;
    require(av_hwdevice_ctx_create(&decoder->hw_device_ctx, AV_HWDEVICE_TYPE_VIDEOTOOLBOX, NULL,
                                   NULL, 0) == 0,
            "VideoToolbox device unavailable");
    require(avcodec_open2(decoder, codec, NULL) == 0, "Cannot open hardware backend");
    SurfaceProbe *probe = [[SurfaceProbe alloc] initWithShader:@(argv[2])];
    AVPacket *packet = av_packet_alloc();
    AVFrame *frame = av_frame_alloc();
    require(packet && frame, "Packet/frame allocation failed");
    int readStatus;
    unsigned packets = 0;
    while ((readStatus = av_read_frame(input, packet)) >= 0) {
      require(++packets <= 10000, "Fixture exceeds packet budget; use a short clip");
      if (packet->stream_index == stream) {
        int status = timedSend(decoder, packet);
        if (status == AVERROR(EAGAIN)) {
          drain(decoder, frame, probe);
          status = timedSend(decoder, packet);
        }
        require(status >= 0, "Packet submission failed");
        drain(decoder, frame, probe);
      }
      av_packet_unref(packet);
    }
    require(readStatus == AVERROR_EOF, "Fixture read failed");
    require(avcodec_send_packet(decoder, NULL) >= 0, "Decoder flush failed");
    require(drain(decoder, frame, probe) == AVERROR_EOF, "Decoder did not drain");
    [probe finish];
    av_frame_free(&frame);
    av_packet_free(&packet);
    avcodec_free_context(&decoder);
    avformat_close_input(&input);
  }
  return 0;
}
