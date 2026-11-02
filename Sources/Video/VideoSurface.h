#import <CoreVideo/CoreVideo.h>
#import <QuartzCore/CAMetalDisplayLink.h>
#import <TargetConditionals.h>
#if TARGET_OS_OSX
#import <AppKit/AppKit.h>
#else
#import <UIKit/UIKit.h>
#endif

#import "RenderStatistics.h"
#import "VideoOptions.h"

NS_ASSUME_NONNULL_BEGIN

typedef struct {
  float brightness;
  float contrast;
  float saturation;
  float gamma;
  BOOL deband;
} CNPictureAdjustment;

#if TARGET_OS_OSX
@interface CNVideoSurface : NSView <CAMetalDisplayLinkDelegate>
#else
@interface CNVideoSurface : UIView <CAMetalDisplayLinkDelegate>
#endif
@property(nonatomic, copy, nullable) void (^firstFramePresentedHandler)(void);
@property(nonatomic) CNVideoUpscaler videoUpscaler;
@property(nonatomic) NSInteger targetOutputHeight;
@property(nonatomic) NSInteger presentationFrameRate;
@property(nonatomic) CNVideoDiagnosticMode videoDiagnosticMode;
@property(nonatomic) CNPictureAdjustment pictureAdjustment;
@property(nonatomic, readonly) CGPoint lightMarker;
@property(nonatomic) BOOL lightMarkerShown;
@property(nonatomic) BOOL measuresLight;
- (void)setLightMarkerX:(double)x y:(double)y;
- (nullable instancetype)initWithShader:(NSString *)shader fsrcnnWeights:(NSData *)fsrcnnWeights;
- (void)offer:(CVPixelBufferRef)surface generated:(BOOL)generated;
- (void)presentWithoutVideo;
- (void)close;
- (CNSurfaceStatistics)statistics;
@end

NS_ASSUME_NONNULL_END
