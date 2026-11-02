#import "VideoDecoderClient.h"

typedef struct {
  CNVideoSubmitResult result;
  OSStatus status;
  BOOL configuring;
} CNEncodedVideoSubmission;

@interface CNLiveEncodedVideo : NSObject
- (instancetype)initWithHEVC:(BOOL)hevc;
@property(nonatomic) BOOL hevc;
@property(nonatomic, readonly) NSUInteger rebuilds;
- (CNEncodedVideoSubmission)submit:(const uint8_t *)bytes
                            length:(size_t)length
                            header:(const uint8_t *)header
                      headerLength:(size_t)headerLength
                            output:(CNVideoOutput)output;
- (void)stop;
@end
