#include <assert.h>
#import "VideoDecoderClient.h"
int main(void) {
  @autoreleasepool {
    CNVideoDecoderClient *client = [CNVideoDecoderClient new];
    assert(!client.hardwareVerified);
    assert([client drain] == paramErr);
    CMVideoFormatDescriptionRef unsupported = NULL;
    assert(CMVideoFormatDescriptionCreate(NULL, kCMVideoCodecType_JPEG, 640, 360, NULL,
                                          &unsupported) == noErr);
    assert([client configure:unsupported tenBit:NO] == paramErr);
    assert(!client.hardwareVerified);
    CFRelease(unsupported);
    CMSampleBufferRef empty = NULL;
    assert(CMSampleBufferCreate(NULL, NULL, true, NULL, NULL, NULL, 0, 0, NULL, 0, NULL, &empty) ==
           noErr);
    assert([client submit:empty
                   output:^(OSStatus status, CVPixelBufferRef surface, CMTime pts) {
                     assert(!"invalid input must not invoke callback");
                   }] == CNVideoSubmitInvalidSample);
    CFRelease(empty);
    [client stop];
    [client stop];
    assert([client drain] == paramErr);
    puts("PASS: native Client rejects unsupported/unconfigured input; teardown is idempotent (no "
         "hardware required)");
  }
}
