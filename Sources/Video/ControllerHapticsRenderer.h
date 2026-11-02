#import <Foundation/Foundation.h>
#import <GameController/GameController.h>

NS_ASSUME_NONNULL_BEGIN

@interface CNControllerHapticsRenderer : NSObject
@property(nonatomic, readonly) NSUInteger submittedBuffers;
@property(nonatomic, readonly) NSUInteger renderedBuffers;
@property(nonatomic, readonly) NSUInteger failedBuffers;
@property(nonatomic, readonly) NSUInteger droppedBuffers;
- (nullable instancetype)initWithController:(GCController *)controller;
- (void)submitPCM:(const uint8_t *)pcm length:(size_t)length gain:(float)gain;
- (void)stop;
@end

NS_ASSUME_NONNULL_END
