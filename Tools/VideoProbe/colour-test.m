#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <math.h>
#import <simd/simd.h>
typedef struct {
  uint32_t tenBit, fullRange, bt2020, pq, toneMap;
  float referenceWhiteNits;
} ColourConfig;
static void check(BOOL ok, const char *message) {
  if (!ok) {
    fprintf(stderr, "FAIL: %s\n", message);
    exit(1);
  }
}
int main(int argc, char **argv) {
  @autoreleasepool {
    check(argc == 2, "Shader path required");
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    check(device != nil, "Metal unavailable");
    NSError *error = nil;
    NSString *source = [NSString stringWithContentsOfFile:@(argv[1])
                                                 encoding:NSUTF8StringEncoding
                                                    error:&error];
    id<MTLLibrary> lib = [device newLibraryWithSource:source options:nil error:&error];
    if (!lib) {
      fprintf(stderr, "%s\n", error.localizedDescription.UTF8String);
    }
    check(lib != nil, "Shader failed");
    id<MTLComputePipelineState> pipeline =
        [device newComputePipelineStateWithFunction:[lib newFunctionWithName:@"test_colour"]
                                              error:&error];
    check(pipeline != nil, "Pipeline failed");
    id<MTLCommandQueue> queue = [device newCommandQueue];

    const float pq[] = {0, 0.50807842f, 0.75182710f, 1};
    vector_float4 input[4];
    for (int i = 0; i < 4; i++) {
      input[i] = (vector_float4){roundf(64 + 876 * pq[i]) * 64 / 65535.0f, 512 * 64 / 65535.0f,
                                 512 * 64 / 65535.0f, 0};
    }
    id<MTLBuffer> in = [device newBufferWithBytes:input
                                           length:sizeof(input)
                                          options:MTLResourceStorageModeShared];
    id<MTLBuffer> out = [device newBufferWithLength:sizeof(input)
                                            options:MTLResourceStorageModeShared];
    for (int mapped = 0; mapped < 2; mapped++) {
      ColourConfig config = {1, 0, 1, 1, (uint32_t)mapped, 100};
      id<MTLCommandBuffer> cmd = [queue commandBuffer];
      id<MTLComputeCommandEncoder> enc = [cmd computeCommandEncoder];
      [enc setComputePipelineState:pipeline];
      [enc setBuffer:in offset:0 atIndex:0];
      [enc setBuffer:out offset:0 atIndex:1];
      [enc setBytes:&config length:sizeof(config) atIndex:2];
      [enc dispatchThreads:MTLSizeMake(4, 1, 1) threadsPerThreadgroup:MTLSizeMake(4, 1, 1)];
      [enc endEncoding];
      [cmd commit];
      [cmd waitUntilCompleted];
      check(cmd.status == MTLCommandBufferStatusCompleted, "GPU failed");
      vector_float4 *result = out.contents;
      const float expected[] = {0, 1, 10, 100};
      for (int i = 0; i < 4; i++) {
        float target = mapped ? expected[i] / (1 + expected[i]) : expected[i];
        check(isfinite(result[i].x) && fabsf(result[i].x - target) < fmaxf(0.015f, target * 0.015f),
              "PQ luminance mismatch");
        check(
            fabsf(result[i].x - result[i].y) < 0.002f && fabsf(result[i].x - result[i].z) < 0.002f,
            "Neutral colour shifted");
        if (i) {
          check(result[i].x > result[i - 1].x, "Highlights collapsed");
        }
      }
    }
    puts(
        "PASS: GPU PQ black/100/1000/10000 nit vectors, preserved HDR highlights and monotonic SDR "
        "mapping.");
  }
  return 0;
}
