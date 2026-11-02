#import <CoreVideo/CoreVideo.h>
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <math.h>
#import "FrameInterpolationClient.h"

typedef struct {
  uint32_t tenBit;
  uint32_t fullRange;
  uint32_t bt2020;
  uint32_t pq;
  uint32_t toneMap;
  uint32_t diagnosticMode;
  float referenceWhiteNits;
  uint32_t adjust;
  float brightness;
  float contrast;
  float saturation;
  float gamma;
  uint32_t deband;
  uint32_t frame;
  float headroom;
  float contentPeak;
} ColourConfig;

static ColourConfig sdrConfig(void) {
  return (ColourConfig){0, 1, 0, 0, 0, 0, 203.0f, 0, 0.0f, 1.0f, 1.0f, 1.0f, 0, 0, 0, 0};
}

static CVPixelBufferRef makeFrame(OSType format) {
  NSDictionary *attributes = @{
    (NSString *)kCVPixelBufferIOSurfacePropertiesKey : @{},
    (NSString *)kCVPixelBufferMetalCompatibilityKey : @YES,
    (NSString *)kCVPixelBufferPixelFormatTypeKey : @(format),
    (NSString *)kCVPixelBufferWidthKey : @1920,
    (NSString *)kCVPixelBufferHeightKey : @1080
  };
  CVPixelBufferRef frame = NULL;
  CVReturn result =
      CVPixelBufferCreate(NULL, 1920, 1080, format, (__bridge CFDictionaryRef)attributes, &frame);
  if (result != kCVReturnSuccess) {
    return NULL;
  }
  CVPixelBufferLockBaseAddress(frame, 0);
  memset(CVPixelBufferGetBaseAddressOfPlane(frame, 0), 96,
         CVPixelBufferGetBytesPerRowOfPlane(frame, 0) * CVPixelBufferGetHeightOfPlane(frame, 0));
  memset(CVPixelBufferGetBaseAddressOfPlane(frame, 1), 128,
         CVPixelBufferGetBytesPerRowOfPlane(frame, 1) * CVPixelBufferGetHeightOfPlane(frame, 1));
  CVPixelBufferUnlockBaseAddress(frame, 0);
  return frame;
}

static BOOL testInterpolation(CVPixelBufferRef first, CVPixelBufferRef second,
                              NSUInteger expectedGenerated) {
  CNFrameInterpolationClient *client = [CNFrameInterpolationClient new];
  [client setEnabled:YES];
  dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
  __block NSUInteger outputs = 0;
  __block NSUInteger generated = 0;
  CNInterpolatedFrameHandler handler = ^(CVPixelBufferRef frame, BOOL synthetic) {
    if (CVPixelBufferGetIOSurface(frame)) {
      outputs++;
      generated += synthetic ? 1 : 0;
    }
    dispatch_semaphore_signal(semaphore);
  };
  [client offer:first handler:handler];
  if (dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_SEC))) {
    [client stop];
    return NO;
  }
  [client offer:second handler:handler];
  NSUInteger expectedOutputs = 2 + expectedGenerated;
  for (NSUInteger index = 1; index < expectedOutputs; index++) {
    if (dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_SEC))) {
      [client stop];
      return NO;
    }
  }
  NSDictionary *statistics = client.statistics;
  [client stop];
  return outputs == expectedOutputs && generated == expectedGenerated &&
         [statistics[@"generated"] unsignedIntegerValue] == expectedGenerated;
}

static BOOL runColour(id<MTLDevice> device, id<MTLLibrary> library, ColourConfig config,
                      const float input[12], float output[12]) {
  NSError *error = nil;
  id<MTLComputePipelineState> pipeline =
      [device newComputePipelineStateWithFunction:[library newFunctionWithName:@"test_colour"]
                                            error:&error];
  if (!pipeline) {
    return NO;
  }
  size_t size = 12 * sizeof(float);
  id<MTLBuffer> inputBuffer = [device newBufferWithBytes:input
                                                  length:size
                                                 options:MTLResourceStorageModeShared];
  id<MTLBuffer> outputBuffer = [device newBufferWithLength:size
                                                   options:MTLResourceStorageModeShared];
  id<MTLCommandBuffer> command = [[device newCommandQueue] commandBuffer];
  id<MTLComputeCommandEncoder> encoder = [command computeCommandEncoder];
  [encoder setComputePipelineState:pipeline];
  [encoder setBuffer:inputBuffer offset:0 atIndex:0];
  [encoder setBuffer:outputBuffer offset:0 atIndex:1];
  [encoder setBytes:&config length:sizeof(config) atIndex:2];
  [encoder dispatchThreads:MTLSizeMake(3, 1, 1) threadsPerThreadgroup:MTLSizeMake(3, 1, 1)];
  [encoder endEncoding];
  [command commit];
  [command waitUntilCompleted];
  if (command.status != MTLCommandBufferStatusCompleted) {
    return NO;
  }
  memcpy(output, outputBuffer.contents, size);
  return YES;
}

static BOOL runColourDiagnostic(id<MTLDevice> device, id<MTLLibrary> library, uint32_t mode,
                                float output[12]) {
  const float input[12] = {
      0.30f, 0.50f, 0.50f, 1.0f, 0.60f, 0.50f, 0.50f, 1.0f, 0.80f, 0.50f, 0.50f, 1.0f,
  };
  ColourConfig config = {0, 1, 1, 1, 0, mode, 203.0f, 0, 0.0f, 1.0f, 1.0f, 1.0f, 0, 0, 0, 0};
  return runColour(device, library, config, input, output);
}

static BOOL testPictureAdjustments(id<MTLDevice> device, id<MTLLibrary> library) {
  const float input[12] = {
      0.30f, 0.50f, 0.50f, 1.0f, 0.55f, 0.35f, 0.70f, 1.0f, 0.70f, 0.60f, 0.40f, 1.0f,
  };
  ColourConfig plain = sdrConfig();
  ColourConfig neutral = sdrConfig();
  neutral.adjust = 1;
  ColourConfig brighter = neutral;
  brighter.brightness = 0.2f;
  ColourConfig grey = neutral;
  grey.saturation = 0.0f;
  float base[12] = {0};
  float same[12] = {0};
  float bright[12] = {0};
  float greyed[12] = {0};
  if (!runColour(device, library, plain, input, base) ||
      !runColour(device, library, neutral, input, same) ||
      !runColour(device, library, brighter, input, bright) ||
      !runColour(device, library, grey, input, greyed)) {
    return NO;
  }
  for (NSUInteger pixel = 0; pixel < 3; pixel++) {
    for (NSUInteger channel = 0; channel < 3; channel++) {
      NSUInteger index = pixel * 4 + channel;
      if (fabsf(base[index] - same[index]) > 0.002f || bright[index] <= base[index]) {
        return NO;
      }
    }
    NSUInteger red = pixel * 4;
    if (fabsf(greyed[red] - greyed[red + 1]) > 0.002f ||
        fabsf(greyed[red + 1] - greyed[red + 2]) > 0.002f) {
      return NO;
    }
  }
  return fabsf(base[4] - base[5]) > 0.05f;
}

static BOOL finiteColours(const float values[12]) {
  for (NSUInteger index = 0; index < 12; index++) {
    if (!isfinite(values[index])) {
      return NO;
    }
  }
  return YES;
}

static BOOL testWideGamutAndHighlights(id<MTLDevice> device, id<MTLLibrary> library,
                                       ColourConfig neutral) {
  const float input[12] = {
      0.6500f, 0.3000f, 0.9500f, 1.0f,    0.7040f, 0.4995f,
      0.4995f, 1.0f,    0.5586f, 0.4995f, 0.4995f, 1.0f,
  };
  ColourConfig plain = neutral;
  plain.adjust = 0;
  ColourConfig brighter = neutral;
  brighter.brightness = 0.05f;
  ColourConfig strong = neutral;
  strong.contrast = 1.5f;
  ColourConfig flat = neutral;
  flat.contrast = 0.5f;
  float base[12] = {0};
  float bright[12] = {0};
  float high[12] = {0};
  float low[12] = {0};
  if (!runColour(device, library, plain, input, base) ||
      !runColour(device, library, brighter, input, bright) ||
      !runColour(device, library, strong, input, high) ||
      !runColour(device, library, flat, input, low)) {
    return NO;
  }
  BOOL wideGamut = base[1] < -0.01f || base[2] < -0.01f;
  BOOL keepsGamut = (base[1] >= 0 || bright[1] < 0) && (base[2] >= 0 || bright[2] < 0);
  BOOL boundedContrast =
      high[4] > base[4] && high[4] < base[4] * 1.5f && low[4] < base[4] && low[4] > base[4] / 1.5f;
  return wideGamut && keepsGamut && boundedContrast;
}

static BOOL testHDRPictureAdjustments(id<MTLDevice> device, id<MTLLibrary> library) {
  const float input[12] = {
      0.5586f, 0.4995f, 0.4995f, 1.0f,    0.7040f, 0.4995f,
      0.4995f, 1.0f,    0.6000f, 0.4300f, 0.5800f, 1.0f,
  };
  ColourConfig plain = {1, 0, 1, 1, 0, 0, 203.0f, 0, 0.0f, 1.0f, 1.0f, 1.0f, 0, 0, 0, 0};
  ColourConfig neutral = plain;
  neutral.adjust = 1;
  float base[12] = {0};
  float same[12] = {0};
  if (!runColour(device, library, plain, input, base) ||
      !runColour(device, library, neutral, input, same)) {
    return NO;
  }
  if (base[4] <= 1.5f || fabsf(base[0] - 1.0f) > 0.15f) {
    return NO;
  }
  for (NSUInteger index = 0; index < 12; index++) {
    if (fabsf(base[index] - same[index]) > 0.002f * fmaxf(1.0f, base[index])) {
      return NO;
    }
  }
  const float extremes[8][4] = {
      {0.25f, 1.0f, 1.0f, 1.0f}, {-0.25f, 1.0f, 1.0f, 1.0f}, {0.0f, 1.5f, 1.0f, 1.0f},
      {0.0f, 0.5f, 1.0f, 1.0f},  {0.0f, 1.0f, 2.0f, 1.0f},   {0.0f, 1.0f, 0.0f, 1.0f},
      {0.0f, 1.0f, 1.0f, 2.0f},  {0.0f, 1.0f, 1.0f, 0.5f},
  };
  float results[8][12] = {{0}};
  for (NSUInteger index = 0; index < 8; index++) {
    ColourConfig config = neutral;
    config.brightness = extremes[index][0];
    config.contrast = extremes[index][1];
    config.saturation = extremes[index][2];
    config.gamma = extremes[index][3];
    if (!runColour(device, library, config, input, results[index]) ||
        !finiteColours(results[index])) {
      return NO;
    }
  }
  BOOL brighter = results[0][0] > base[0] && results[0][4] > base[4];
  BOOL darker = results[1][0] < base[0] && results[1][4] < base[4];
  BOOL grey = fabsf(results[5][8] - results[5][9]) < 0.01f * fmaxf(1.0f, results[5][9]);
  BOOL highlightsKept = fabsf(results[6][4] - base[4]) < 0.01f * base[4] &&
                        fabsf(results[7][4] - base[4]) < 0.01f * base[4];
  BOOL gammaShapesMidtones = results[6][0] > base[0] && results[7][0] < base[0];
  return brighter && darker && grey && highlightsKept && gammaShapesMidtones &&
         testWideGamutAndHighlights(device, library, neutral);
}

static id<MTLTexture> planeTexture(id<MTLDevice> device, MTLPixelFormat format, NSUInteger width,
                                   NSUInteger height, const uint8_t *bytes,
                                   NSUInteger bytesPerRow) {
  MTLTextureDescriptor *descriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:format
                                                                                        width:width
                                                                                       height:height
                                                                                    mipmapped:NO];
  descriptor.usage = MTLTextureUsageShaderRead;
  id<MTLTexture> texture = [device newTextureWithDescriptor:descriptor];
  [texture replaceRegion:MTLRegionMake2D(0, 0, width, height)
             mipmapLevel:0
               withBytes:bytes
             bytesPerRow:bytesPerRow];
  return texture;
}

typedef struct {
  BOOL tenBit;
  BOOL deband;
} DebandCase;

static uint16_t debandCode(BOOL tenBit, NSUInteger x) {
  if (tenBit) {
    if (x < 160) {
      return (uint16_t)(400 + x / 16);
    }
    if (x < 192) {
      return (uint16_t)(500 + ((x / 2) % 2) * 4);
    }
    return x < 224 ? 380 : 600;
  }
  if (x < 192) {
    return (uint16_t)(64 + x / 16);
  }
  return x < 224 ? 60 : 110;
}

static BOOL runDeband(id<MTLDevice> device, id<MTLLibrary> library, DebandCase kind,
                      float *output) {
  enum { width = 256, height = 16 };
  static uint16_t wide[width * height];
  static uint16_t wideChroma[(width / 2) * (height / 2) * 2];
  static uint8_t narrow[width * height];
  static uint8_t narrowChroma[(width / 2) * (height / 2) * 2];
  for (NSUInteger y = 0; y < height; y++) {
    for (NSUInteger x = 0; x < width; x++) {
      uint16_t code = debandCode(kind.tenBit, x);
      wide[y * width + x] = (uint16_t)(code * 64);
      narrow[y * width + x] = (uint8_t)code;
    }
  }
  for (NSUInteger index = 0; index < (width / 2) * (height / 2) * 2; index++) {
    wideChroma[index] = 512 * 64;
    narrowChroma[index] = 128;
  }
  NSError *error = nil;
  id<MTLComputePipelineState> pipeline =
      [device newComputePipelineStateWithFunction:[library newFunctionWithName:@"test_deband"]
                                            error:&error];
  if (!pipeline) {
    return NO;
  }
  id<MTLTexture> y =
      kind.tenBit ? planeTexture(device, MTLPixelFormatR16Unorm, width, height,
                                 (const uint8_t *)wide, width * 2)
                  : planeTexture(device, MTLPixelFormatR8Unorm, width, height, narrow, width);
  id<MTLTexture> uv = kind.tenBit ? planeTexture(device, MTLPixelFormatRG16Unorm, width / 2,
                                                 height / 2, (const uint8_t *)wideChroma, width * 2)
                                  : planeTexture(device, MTLPixelFormatRG8Unorm, width / 2,
                                                 height / 2, narrowChroma, width);
  id<MTLBuffer> buffer = [device newBufferWithLength:sizeof(float) * 4 * width * height
                                             options:MTLResourceStorageModeShared];
  ColourConfig config = {kind.tenBit ? 1 : 0,
                         0,
                         kind.tenBit ? 1 : 0,
                         kind.tenBit ? 1 : 0,
                         0,
                         0,
                         203.0f,
                         0,
                         0.0f,
                         1.0f,
                         1.0f,
                         1.0f,
                         kind.deband ? 1 : 0,
                         3,
                         0,
                         0};
  id<MTLCommandBuffer> command = [[device newCommandQueue] commandBuffer];
  id<MTLComputeCommandEncoder> encoder = [command computeCommandEncoder];
  [encoder setComputePipelineState:pipeline];
  [encoder setTexture:y atIndex:0];
  [encoder setTexture:uv atIndex:1];
  [encoder setBuffer:buffer offset:0 atIndex:0];
  [encoder setBytes:&config length:sizeof(config) atIndex:1];
  [encoder dispatchThreads:MTLSizeMake(width, height, 1)
      threadsPerThreadgroup:MTLSizeMake(16, 16, 1)];
  [encoder endEncoding];
  [command commit];
  [command waitUntilCompleted];
  if (command.status != MTLCommandBufferStatusCompleted) {
    return NO;
  }
  memcpy(output, buffer.contents, sizeof(float) * 4 * width * height);
  return YES;
}

static BOOL testDebandCase(id<MTLDevice> device, id<MTLLibrary> library, BOOL tenBit) {
  enum { width = 256, height = 16 };
  static float off[width * height * 4];
  static float on[width * height * 4];
  if (!runDeband(device, library, (DebandCase){tenBit, NO}, off) ||
      !runDeband(device, library, (DebandCase){tenBit, YES}, on)) {
    return NO;
  }
  double unit = tenBit ? 64.0 / 65535.0 : 1.0 / 255.0;
  double base = tenBit ? 400.0 : 64.0;
  NSUInteger rampEnd = tenBit ? 152 : 168;
  double plainError = 0;
  double smoothError = 0;
  for (NSUInteger y = 4; y < height - 4; y++) {
    for (NSUInteger x = 24; x < rampEnd; x++) {
      NSUInteger index = (y * width + x) * 4;
      double ideal = (base + ((double)x - 7.5) / 16.0) * unit;
      if (fabs(off[index] - debandCode(tenBit, x) * unit) > unit * 0.05) {
        return NO;
      }
      plainError += fabs(off[index] - ideal);
      smoothError += fabs(on[index] - ideal);
    }
  }
  NSUInteger row = 8 * width * 4;
  double edge = (on[row + 230 * 4] - on[row + 218 * 4]) / unit;
  BOOL edgeKept = tenBit ? edge > 200 : edge > 40;
  BOOL detailKept = YES;
  if (tenBit) {
    double low = (on[row + 168 * 4] + on[row + 169 * 4]) / 2;
    double high = (on[row + 170 * 4] + on[row + 171 * 4]) / 2;
    detailKept = (high - low) / unit > 3.0;
  }
  return smoothError < plainError * 0.8 && edgeKept && detailKept;
}

static BOOL testDeband(id<MTLDevice> device, id<MTLLibrary> library) {
  return testDebandCase(device, library, NO) && testDebandCase(device, library, YES);
}

enum { rollOffSamples = 34 };

static BOOL runRollOff(id<MTLDevice> device, id<MTLLibrary> library, float headroom,
                       const float *input, float *output) {
  NSError *error = nil;
  id<MTLComputePipelineState> pipeline =
      [device newComputePipelineStateWithFunction:[library newFunctionWithName:@"test_roll_off"]
                                            error:&error];
  if (!pipeline) {
    return NO;
  }
  size_t size = rollOffSamples * 4 * sizeof(float);
  id<MTLBuffer> inputBuffer = [device newBufferWithBytes:input
                                                  length:size
                                                 options:MTLResourceStorageModeShared];
  id<MTLBuffer> outputBuffer = [device newBufferWithLength:size
                                                   options:MTLResourceStorageModeShared];
  ColourConfig config = {0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, headroom, 1000.0f / 203.0f};
  id<MTLCommandBuffer> command = [[device newCommandQueue] commandBuffer];
  id<MTLComputeCommandEncoder> encoder = [command computeCommandEncoder];
  [encoder setComputePipelineState:pipeline];
  [encoder setBuffer:inputBuffer offset:0 atIndex:0];
  [encoder setBuffer:outputBuffer offset:0 atIndex:1];
  [encoder setBytes:&config length:sizeof(config) atIndex:2];
  [encoder dispatchThreads:MTLSizeMake(rollOffSamples, 1, 1)
      threadsPerThreadgroup:MTLSizeMake(rollOffSamples, 1, 1)];
  [encoder endEncoding];
  [command commit];
  [command waitUntilCompleted];
  if (command.status != MTLCommandBufferStatusCompleted) {
    return NO;
  }
  memcpy(output, outputBuffer.contents, size);
  return YES;
}

static BOOL testRollOff(id<MTLDevice> device, id<MTLLibrary> library) {
  float input[rollOffSamples * 4];
  for (NSUInteger index = 0; index < rollOffSamples - 1; index++) {
    float value = 0.25f * (float)index;
    input[index * 4] = value;
    input[index * 4 + 1] = value;
    input[index * 4 + 2] = value;
    input[index * 4 + 3] = 1;
  }
  const float colour[4] = {6.0f, 3.0f, 1.5f, 1.0f};
  memcpy(&input[(rollOffSamples - 1) * 4], colour, sizeof(colour));
  float bright[rollOffSamples * 4];
  float dim[rollOffSamples * 4];
  if (!runRollOff(device, library, 4.0f, input, bright) ||
      !runRollOff(device, library, 16.0f, input, dim)) {
    return NO;
  }
  float previous = -1;
  for (NSUInteger index = 0; index < rollOffSamples - 1; index++) {
    float in = input[index * 4];
    float out = bright[index * 4];
    if (getenv("CN_ROLL_OFF_TABLE")) {
      printf("roll-off %5.2f -> %5.3f at 4x, %5.3f at 16x\n", in, out, dim[index * 4]);
    }
    if (out < previous - 1e-4f || out > 4.0f + 1e-4f || fabsf(dim[index * 4] - in) > 1e-4f) {
      return NO;
    }
    if (in <= 3.0f && fabsf(out - in) > 1e-4f) {
      return NO;
    }
    previous = out;
  }
  float peak = 1000.0f / 203.0f;
  float atPeak[rollOffSamples * 4];
  for (NSUInteger index = 0; index < rollOffSamples; index++) {
    input[index * 4] = peak;
    input[index * 4 + 1] = peak;
    input[index * 4 + 2] = peak;
  }
  if (!runRollOff(device, library, 4.0f, input, atPeak)) {
    return NO;
  }
  const float *hue = &bright[(rollOffSamples - 1) * 4];
  BOOL hueKept = fabsf(hue[1] / hue[0] - 0.5f) < 1e-3f && fabsf(hue[2] / hue[0] - 0.25f) < 1e-3f;
  return fabsf(atPeak[0] - 4.0f) < 1e-3f && hueKept && hue[0] <= 4.0f + 1e-4f;
}

static BOOL testColourDiagnostics(NSString *shaderPath) {
  id<MTLDevice> device = MTLCreateSystemDefaultDevice();
  NSError *error = nil;
  NSString *source = [NSString stringWithContentsOfFile:shaderPath
                                               encoding:NSUTF8StringEncoding
                                                  error:&error];
  id<MTLLibrary> library = [device newLibraryWithSource:source options:nil error:&error];
  if (!library) {
    return NO;
  }
  float heatmap[12] = {0};
  float clipping[12] = {0};
  if (!runColourDiagnostic(device, library, 1, heatmap) ||
      !runColourDiagnostic(device, library, 2, clipping) ||
      !testPictureAdjustments(device, library) || !testHDRPictureAdjustments(device, library) ||
      !testDeband(device, library) || !testRollOff(device, library)) {
    return NO;
  }
  for (NSUInteger index = 0; index < 12; index++) {
    if (!isfinite(heatmap[index]) || !isfinite(clipping[index])) {
      return NO;
    }
  }
  BOOL heatmapSeparatesLuminance = fabsf(heatmap[0] - heatmap[8]) > 0.1f ||
                                   fabsf(heatmap[1] - heatmap[9]) > 0.1f ||
                                   fabsf(heatmap[2] - heatmap[10]) > 0.1f;
  BOOL modesDiffer = fabsf(heatmap[4] - clipping[4]) > 0.1f ||
                     fabsf(heatmap[5] - clipping[5]) > 0.1f ||
                     fabsf(heatmap[6] - clipping[6]) > 0.1f;
  return heatmapSeparatesLuminance && modesDiffer;
}

int main(int argc, const char *argv[]) {
  @autoreleasepool {
    if (argc != 2) {
      return 2;
    }
    CVPixelBufferRef first = makeFrame(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange);
    CVPixelBufferRef second = makeFrame(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange);
    CVPixelBufferRef tenBitFirst = makeFrame(kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange);
    CVPixelBufferRef tenBitSecond = makeFrame(kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange);
    if (!first || !second || !tenBitFirst || !tenBitSecond) {
      return 3;
    }
    BOOL interpolation = testInterpolation(first, second, 1);
    BOOL tenBitFallback = testInterpolation(tenBitFirst, tenBitSecond, 0);
    BOOL diagnostics = testColourDiagnostics(@(argv[1]));
    CVPixelBufferRelease(first);
    CVPixelBufferRelease(second);
    CVPixelBufferRelease(tenBitFirst);
    CVPixelBufferRelease(tenBitSecond);
    if (!interpolation || !tenBitFallback || !diagnostics) {
      fprintf(stderr, "FAIL: interpolation=%d tenBitFallback=%d diagnostics=%d\n", interpolation,
              tenBitFallback, diagnostics);
      return 1;
    }
    printf("PASS: frame generation, Main10 fallback, HDR diagnostics, picture adjustments, "
           "debanding and highlight roll-off\n");
    return 0;
  }
}
