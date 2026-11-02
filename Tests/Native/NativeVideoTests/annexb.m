#include <assert.h>
#import "AnnexBSample.h"
int main(void) {
  @autoreleasepool {
    CMVideoFormatDescriptionRef format = NULL;
    assert(CMVideoFormatDescriptionCreate(NULL, kCMVideoCodecType_H264, 640, 360, NULL, &format) ==
           noErr);
    CMSampleBufferRef sample = NULL;
    __weak id weakOwner;
    @autoreleasepool {
      const uint8_t fixture[] = {0, 0, 0, 1, 0x65, 0xab, 0xcd, 0, 0, 1, 0x41, 0xef};
      NSData *owner = [NSData dataWithBytes:fixture length:sizeof(fixture)];
      weakOwner = owner;
      assert(CNCreateAnnexBSample(owner.bytes, owner.length, owner, format, CMTimeMake(1, 60),
                                  &sample) == noErr);
      CMBlockBufferRef block = CMSampleBufferGetDataBuffer(sample);
      char *pointer = NULL;
      assert(CMBlockBufferGetDataPointer(block, 4, NULL, NULL, &pointer) == noErr);
      assert(pointer == (char *)owner.bytes + 4);
      assert(CMBlockBufferGetDataPointer(block, 11, NULL, NULL, &pointer) == noErr);
      assert(pointer == (char *)owner.bytes + 10);
      uint8_t actual[13];
      const uint8_t expected[] = {0, 0, 0, 3, 0x65, 0xab, 0xcd, 0, 0, 0, 2, 0x41, 0xef};
      assert(CMBlockBufferCopyDataBytes(block, 0, sizeof(actual), actual) == noErr);
      assert(memcmp(actual, expected, sizeof(actual)) == 0);
    }
    @autoreleasepool {
      assert(weakOwner != nil);
    }
    CFRelease(sample);
    sample = NULL;
    assert(weakOwner == nil);
    NSData *owner = [NSData data];
    const uint8_t empty[] = {0, 0, 1};
    assert(CNCreateAnnexBSample(empty, sizeof(empty), owner, format, kCMTimeZero, &sample) !=
               noErr &&
           !sample);
    const uint8_t noPrefix[] = {0x65, 0xab};
    assert(CNCreateAnnexBSample(noPrefix, sizeof(noPrefix), owner, format, kCMTimeZero, &sample) !=
               noErr &&
           !sample);
    NSMutableData *sliced = [NSMutableData data];
    const uint8_t aud[] = {0, 0, 0, 1, 0x09, 0xf0};
    const uint8_t sei[] = {0, 0, 1, 0x06, 0x05, 0x01, 0xaa, 0x80};
    [sliced appendBytes:aud length:sizeof aud];
    [sliced appendBytes:sei length:sizeof sei];
    for (int i = 0; i < 200; i++) {
      const uint8_t slice[] = {0, 0, 1, 0x65, (uint8_t)(0x80 | i), 0x11};
      [sliced appendBytes:slice length:sizeof slice];
    }
    assert(CNCreateAnnexBSample(sliced.bytes, sliced.length, sliced, format, kCMTimeZero,
                                &sample) == noErr &&
           sample);
    CMBlockBufferRef slicedBlock = CMSampleBufferGetDataBuffer(sample);
    assert(CMBlockBufferGetDataLength(slicedBlock) == 4 + 2 + 4 + 5 + 200 * (4 + 3));
    uint8_t lastSlice[7];
    assert(CMBlockBufferCopyDataBytes(slicedBlock, CMBlockBufferGetDataLength(slicedBlock) - 7, 7,
                                      lastSlice) == noErr);
    const uint8_t expectedLast[] = {0, 0, 0, 3, 0x65, 0x80 | 199, 0x11};
    assert(memcmp(lastSlice, expectedLast, sizeof expectedLast) == 0);
    char *slicePointer = NULL;
    assert(CMBlockBufferGetDataPointer(slicedBlock, CMBlockBufferGetDataLength(slicedBlock) - 3,
                                       NULL, NULL, &slicePointer) == noErr);
    assert(slicePointer == (char *)sliced.bytes + sliced.length - 3);
    CFRelease(sample);
    sample = NULL;
    assert(CNAnnexBHasPicture(sliced.bytes, sliced.length, NO));
    assert(!CNCopyAnnexBParameterSets(sliced.bytes, sliced.length, NO));
    const uint8_t parameters[] = {0,    0,    0,    1,    0x09, 0x10, 0,    0,    0,    1,    0x67,
                                  0x42, 0xc0, 0x2a, 0xda, 0x01, 0xe0, 0x08, 0x9f, 0x97, 0x01, 0x10,
                                  0x00, 0x00, 0x03, 0x00, 0x10, 0x00, 0x00, 0x07, 0x80, 0xf1, 0x83,
                                  0x2a, 0,    0,    1,    0x06, 0x05, 0x01, 0xaa, 0x80, 0,    0,
                                  0,    1,    0x68, 0xce, 0x0f, 0xc8, 0,    0,    0};
    assert(!CNAnnexBHasPicture(parameters, sizeof parameters, NO));
    NSData *sets = CNCopyAnnexBParameterSets(parameters, sizeof parameters, NO);
    assert(sets.length == 4 + 24 + 4 + 4);
    CMVideoFormatDescriptionRef withExtras = NULL;
    assert(CNCreateAnnexBFormat(parameters, sizeof parameters, NO, &withExtras) == noErr &&
           withExtras);
    CMVideoDimensions dimensions = CMVideoFormatDescriptionGetDimensions(withExtras);
    assert(dimensions.width == 1920 && dimensions.height == 1080);
    CFRelease(withExtras);
    CFRelease(format);
    puts("PASS: Annex-B payload pointer identity, mixed prefixes, owner lifetime, malformed input, "
         "AUD/SEI and "
         "multi-slice access units");
  }
}
