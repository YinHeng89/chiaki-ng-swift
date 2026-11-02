#import <IOSurface/IOSurface.h>
#include <assert.h>
#import "LiveEncodedVideo.h"

@interface CNCompressedFramePool : NSObject
- (NSData *)newLeaseWithBytes:(const uint8_t *)bytes length:(size_t)length;
@end

static void pool_ownership(void) {
  CNCompressedFramePool *pool = [CNCompressedFramePool new];
  uint8_t input[] = {1, 2, 3, 4};
  NSData *leases[4];
  @autoreleasepool {
    for (NSUInteger i = 0; i < 4; i++) {
      leases[i] = [pool newLeaseWithBytes:input length:sizeof input];
      assert(leases[i] && leases[i].bytes != input);
    }
  }
  assert(![pool newLeaseWithBytes:input length:sizeof input]);
  const void *first;
  @autoreleasepool {
    first = leases[0].bytes;
    leases[0] = nil;
  }
  @autoreleasepool {
    NSData *reused = [pool newLeaseWithBytes:input length:sizeof input];
    assert(reused && reused.bytes == first);
  }
  pool = nil;
  input[0] = 9;
  for (NSUInteger i = 1; i < 4; i++) {
    assert(((const uint8_t *)leases[i].bytes)[0] == 1);
    leases[i] = nil;
  }
}

static size_t prefix(const uint8_t *bytes, size_t length) {
  if (length >= 4 && !bytes[0] && !bytes[1] && !bytes[2] && bytes[3] == 1) {
    return 4;
  }
  if (length >= 3 && !bytes[0] && !bytes[1] && bytes[2] == 1) {
    return 3;
  }
  return 0;
}

static BOOL attachment_is(CVPixelBufferRef surface, CFStringRef key, CFStringRef wanted) {
  CFTypeRef value = CVBufferCopyAttachment(surface, key, NULL);
  BOOL matches = value && CFEqual(value, wanted);
  if (value) {
    CFRelease(value);
  }
  return matches;
}

static BOOL pq_bt2020(CVPixelBufferRef surface) {
  return attachment_is(surface, kCVImageBufferTransferFunctionKey,
                       kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ) &&
         attachment_is(surface, kCVImageBufferColorPrimariesKey,
                       kCVImageBufferColorPrimaries_ITU_R_2020);
}

static unsigned pixel_error(CVPixelBufferRef surface, NSData *expected, BOOL tenBit) {
  assert(surface && CVPixelBufferGetIOSurface(surface));
  assert(CVPixelBufferGetWidth(surface) == 320 && CVPixelBufferGetHeight(surface) == 180);
  assert(CVPixelBufferGetPlaneCount(surface) == 2);
  const OSType type = CVPixelBufferGetPixelFormatType(surface);
  assert(type == (tenBit ? kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange
                         : kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange));
  assert(expected.length == 320 * 180 * 3 / 2 * (tenBit ? 2 : 1));
  assert(CVPixelBufferLockBaseAddress(surface, kCVPixelBufferLock_ReadOnly) == kCVReturnSuccess);
  const uint8_t *reference = expected.bytes;
  unsigned maximum = 0;
  for (unsigned plane = 0; plane < 3; plane++) {
    unsigned width = plane ? 160 : 320;
    unsigned height = plane ? 90 : 180;
    unsigned reference_offset = plane ? 320 * 180 + (plane - 1) * 160 * 90 : 0;
    const uint8_t *base = CVPixelBufferGetBaseAddressOfPlane(surface, plane ? 1 : 0);
    size_t stride = CVPixelBufferGetBytesPerRowOfPlane(surface, plane ? 1 : 0);
    for (unsigned y = 0; y < height; y++) {
      for (unsigned x = 0; x < width; x++) {
        unsigned index = plane ? x * 2 + plane - 1 : x;
        unsigned actual =
            tenBit ? ((const uint16_t *)(base + y * stride))[index] >> 6 : base[y * stride + index];
        unsigned wanted = tenBit ? ((const uint16_t *)reference)[reference_offset + y * width + x]
                                 : reference[reference_offset + y * width + x];
        unsigned difference = actual > wanted ? actual - wanted : wanted - actual;
        maximum = MAX(maximum, difference);
      }
    }
  }
  CVPixelBufferUnlockBaseAddress(surface, kCVPixelBufferLock_ReadOnly);
  return maximum;
}

int main(int argc, const char **argv) {
  @autoreleasepool {
    assert(argc == 4);
    pool_ownership();
    int mode = atoi(argv[3]);
    BOOL hevc = mode != 0;
    BOOL pq = mode == 2;
    NSData *encoded = [NSData dataWithContentsOfFile:@(argv[1])];
    NSData *expected = [NSData dataWithContentsOfFile:@(argv[2])];
    assert(encoded.length && expected.length);
    NSMutableData *header = [NSMutableData data];
    NSMutableData *frame = [NSMutableData data];
    const uint8_t *bytes = encoded.bytes;
    const uint8_t start[] = {0, 0, 0, 1};
    for (size_t offset = 0; offset < encoded.length;) {
      size_t pre = prefix(bytes + offset, encoded.length - offset);
      assert(pre);
      size_t end = offset + pre;
      while (end < encoded.length && !prefix(bytes + end, encoded.length - end)) {
        end++;
      }
      unsigned type = hevc ? (bytes[offset + pre] >> 1) & 63 : bytes[offset + pre] & 31;
      BOOL parameter = hevc ? type >= 32 && type <= 34 : type == 7 || type == 8;
      NSMutableData *target = parameter ? header : frame;
      [target appendBytes:start length:sizeof start];
      [target appendBytes:bytes + offset + pre length:end - offset - pre];
      offset = end;
    }
    assert(header.length && frame.length);
    NSData *originalFrame = [frame copy];
    CNLiveEncodedVideo *decoder = [[CNLiveEncodedVideo alloc] initWithHEVC:hevc];
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    __block OSStatus decode_status = 0;
    __block unsigned difference = UINT_MAX;
    __block BOOL colour_matches = NO;
    CNVideoOutput output = ^(OSStatus status, CVPixelBufferRef surface, CMTime pts) {
      (void)pts;
      decode_status = status;
      if (!status) {
        difference = pixel_error(surface, expected, hevc);
        colour_matches = pq_bt2020(surface) == pq;
      }
      dispatch_semaphore_signal(done);
    };
    CNEncodedVideoSubmission submitted = [decoder submit:frame.bytes
                                                  length:frame.length
                                                  header:header.bytes
                                            headerLength:header.length
                                                  output:output];
    assert(submitted.result == CNVideoSubmitAccepted && submitted.status == 0);
    memset(frame.mutableBytes, 0, frame.length);
    memset(header.mutableBytes, 0, header.length);
    assert(dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) == 0);
    assert(decode_status == 0 && difference <= 2 && colour_matches);
    for (unsigned i = 0; i < 16; i++) {
      submitted = [decoder submit:originalFrame.bytes
                           length:originalFrame.length
                           header:NULL
                     headerLength:0
                           output:output];
      assert(submitted.result == CNVideoSubmitAccepted);
      assert(dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) ==
             0);
      assert(decode_status == 0 && difference <= 2 && colour_matches);
    }
    uint8_t invalid[] = {1, 2, 3};
    submitted = [decoder submit:invalid
                         length:sizeof invalid
                         header:NULL
                   headerLength:0
                         output:output];
    assert(submitted.result == CNVideoSubmitInvalidSample && !submitted.configuring);
    [decoder stop];
    [decoder stop];
    submitted = [decoder submit:invalid
                         length:sizeof invalid
                         header:NULL
                   headerLength:0
                         output:output];
    assert(submitted.result == CNVideoSubmitFailed);
    CNLiveEncodedVideo *bad = [[CNLiveEncodedVideo alloc] initWithHEVC:hevc];
    submitted = [bad submit:invalid
                     length:sizeof invalid
                     header:invalid
               headerLength:sizeof invalid
                     output:output];
    assert(submitted.result == CNVideoSubmitFailed && submitted.configuring && submitted.status);
    [bad stop];
    printf(
        "PASS: live %s Annex-B adapter, borrowed input overwrite, hardware pixels match software "
        "within %u, bounded leases and stop.\n",
        pq ? "HEVC Main10 PQ BT.2020" : (hevc ? "HEVC Main10" : "H.264"), difference);
  }
  return 0;
}
