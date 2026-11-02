#import <CoreVideo/CoreVideo.h>
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^CNInterpolatedFrameHandler)(CVPixelBufferRef frame, BOOL generated);

@interface CNFrameInterpolationClient : NSObject
@property(nonatomic, readonly) BOOL supported;
@property(nonatomic, readonly) NSDictionary<NSString *, NSNumber *> *statistics;
- (void)setSourceFrameRate:(NSInteger)frameRate;
- (void)setEnabled:(BOOL)enabled;
- (void)offer:(CVPixelBufferRef)frame handler:(CNInterpolatedFrameHandler)handler;
- (void)stop;
@end

NS_ASSUME_NONNULL_END
