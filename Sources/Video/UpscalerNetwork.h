#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <MetalPerformanceShaders/MetalPerformanceShaders.h>

NS_ASSUME_NONNULL_BEGIN

@interface CNUpscalerNetwork : NSObject
+ (nullable MPSNNGraph *)graphOnDevice:(id<MTLDevice>)device weights:(NSData *)weights;
- (instancetype)init NS_UNAVAILABLE;
@end

NS_ASSUME_NONNULL_END
