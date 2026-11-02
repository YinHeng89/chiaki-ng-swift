#import <Foundation/Foundation.h>
#import <VideoToolbox/VideoToolbox.h>
NS_ASSUME_NONNULL_BEGIN
typedef NS_ENUM(NSInteger, CNVideoSubmitResult) {
  CNVideoSubmitAccepted,
  CNVideoSubmitWouldBlock,
  CNVideoSubmitInvalidSample,
  CNVideoSubmitFailed
};

typedef void (^CNVideoOutput)(OSStatus status, CVPixelBufferRef _Nullable surface, CMTime pts);
@interface CNVideoDecoderClient : NSObject

- (OSStatus)configure:(CMVideoFormatDescriptionRef)format tenBit:(BOOL)tenBit;
- (CNVideoSubmitResult)submit:(CMSampleBufferRef)sample output:(CNVideoOutput)output;

- (OSStatus)drain;
- (void)stop;
@property(nonatomic, readonly) BOOL hardwareVerified;
@property(nonatomic, readonly) OSStatus lastError;
@end
NS_ASSUME_NONNULL_END
