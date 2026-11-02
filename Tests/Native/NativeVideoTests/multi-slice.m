#include <assert.h>
#include <stdio.h>
#import "LiveEncodedVideo.h"

static size_t prefix(const uint8_t *bytes, size_t length) {
  if (length >= 4 && !bytes[0] && !bytes[1] && !bytes[2] && bytes[3] == 1) {
    return 4;
  }
  if (length >= 3 && !bytes[0] && !bytes[1] && bytes[2] == 1) {
    return 3;
  }
  return 0;
}

static NSArray<NSData *> *accessUnits(NSData *encoded, NSMutableData *header, size_t *maximumNals) {
  NSMutableArray<NSData *> *units = [NSMutableArray array];
  NSMutableData *current = nil;
  BOOL picture = NO, headerDone = NO;
  size_t nals = 0;
  *maximumNals = 0;
  const uint8_t *bytes = encoded.bytes;
  for (size_t offset = 0; offset < encoded.length;) {
    size_t pre = prefix(bytes + offset, encoded.length - offset);
    assert(pre);
    size_t end = offset + pre;
    while (end < encoded.length && !prefix(bytes + end, encoded.length - end)) {
      end++;
    }
    unsigned type = bytes[offset + pre] & 31;
    BOOL slice = type == 1 || type == 5;
    BOOL firstSlice = slice && (bytes[offset + pre + 1] & 0x80);
    if (!current || (picture && ((type >= 6 && type <= 9) || firstSlice))) {
      current = [NSMutableData data];
      [units addObject:current];
      picture = NO;
      nals = 0;
    }
    if (!headerDone && (type == 7 || type == 8)) {
      [header appendBytes:bytes + offset length:end - offset];
    }
    if (slice) {
      picture = YES;
      headerDone = header.length > 0;
    }
    [current appendBytes:bytes + offset length:end - offset];
    *maximumNals = MAX(*maximumNals, ++nals);
    offset = end;
  }
  return units;
}

int main(int argc, const char **argv) {
  @autoreleasepool {
    assert(argc == 5);
    NSData *encoded = [NSData dataWithContentsOfFile:@(argv[1])];
    size_t minimumNals = (size_t)atol(argv[2]);
    size_t lastWidth = (size_t)atol(argv[3]);
    size_t lastHeight = (size_t)atol(argv[4]);
    assert(encoded.length);
    NSMutableData *header = [NSMutableData data];
    size_t maximumNals = 0;
    NSArray<NSData *> *units = accessUnits(encoded, header, &maximumNals);
    assert(units.count > 1 && header.length && maximumNals >= minimumNals);

    CNLiveEncodedVideo *decoder = [[CNLiveEncodedVideo alloc] initWithHEVC:NO];
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    __block NSUInteger decoded = 0, failed = 0, callbacks = 0;
    __block size_t width = 0, height = 0;
    CNVideoOutput output = ^(OSStatus status, CVPixelBufferRef surface, CMTime pts) {
      (void)pts;
      callbacks++;
      if (status || !surface) {
        failed++;
      } else {
        decoded++;
        width = CVPixelBufferGetWidth(surface);
        height = CVPixelBufferGetHeight(surface);
      }
      dispatch_semaphore_signal(done);
    };
    CNEncodedVideoSubmission submitted = [decoder submit:header.bytes
                                                  length:header.length
                                                  header:header.bytes
                                            headerLength:header.length
                                                  output:output];
    assert(submitted.result == CNVideoSubmitAccepted && submitted.status == noErr &&
           !submitted.configuring);
    assert(dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 200 * NSEC_PER_MSEC)) !=
           0);
    assert(callbacks == 0);
    for (NSData *unit in units) {
      submitted = [decoder submit:unit.bytes
                           length:unit.length
                           header:NULL
                     headerLength:0
                           output:output];
      if (submitted.result != CNVideoSubmitAccepted) {
        fprintf(stderr, "FAIL: access unit %lu of %lu rejected: result=%ld status=%d\n",
                (unsigned long)[units indexOfObject:unit], (unsigned long)units.count,
                (long)submitted.result, (int)submitted.status);
        return 1;
      }
      assert(dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) ==
             0);
    }
    [decoder stop];
    NSUInteger streamDecoded = decoded;
    size_t streamWidth = width, streamHeight = height;
    CNLiveEncodedVideo *recovering = [[CNLiveEncodedVideo alloc] initWithHEVC:NO];
    submitted = [recovering submit:header.bytes
                            length:header.length
                            header:header.bytes
                      headerLength:header.length
                            output:output];
    assert(submitted.result == CNVideoSubmitAccepted);
    NSMutableData *corrupt = [NSMutableData dataWithData:units[1]];
    for (NSUInteger i = 0; i < corrupt.length; i++) {
      uint8_t *byte = (uint8_t *)corrupt.mutableBytes + i;
      if (i > 8 && *byte > 3) {
        *byte ^= 0x5a;
      }
    }
    NSUInteger failedBefore = failed;
    for (NSUInteger i = 0; i < 8; i++) {
      submitted = [recovering submit:corrupt.bytes
                              length:corrupt.length
                              header:NULL
                        headerLength:0
                              output:output];
      assert(submitted.result == CNVideoSubmitAccepted);
      assert(dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) ==
             0);
    }
    assert(failed - failedBefore == 8 && recovering.rebuilds == 0);
    failed = failedBefore;
    decoded = 0;
    submitted = [recovering submit:units[0].bytes
                            length:units[0].length
                            header:NULL
                      headerLength:0
                            output:output];
    assert(submitted.result == CNVideoSubmitAccepted);
    assert(dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) == 0);
    assert(recovering.rebuilds == 1 && decoded == 1);
    [recovering stop];
    decoded = streamDecoded;
    width = streamWidth;
    height = streamHeight;
    if (decoded != units.count || failed || width != lastWidth || height != lastHeight) {
      fprintf(stderr, "FAIL: decoded %lu of %lu, failed %lu, last %zux%zu\n",
              (unsigned long)decoded, (unsigned long)units.count, (unsigned long)failed, width,
              height);
      return 1;
    }
    printf(
        "PASS: %s decoded %lu H.264 access units with up to %zu NAL units, ending at %zux%zu, and "
        "rebuilt the session after 8 decode errors\n",
        argv[1], (unsigned long)decoded, maximumNals, width, height);
  }
  return 0;
}
