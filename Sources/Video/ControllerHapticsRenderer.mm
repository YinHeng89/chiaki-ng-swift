#import "ControllerHapticsRenderer.h"

#import <CoreHaptics/CoreHaptics.h>

#include <time.h>
#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <mutex>
#include <optional>
#include <span>

#import "HapticShaper.h"

namespace video {

struct HapticBlock {
  static constexpr std::size_t largest = 512;

  std::array<std::int16_t, largest / sizeof(std::int16_t)> samples{};
  std::size_t count = 0;
  float gain = 0;
  std::uint64_t arrival = 0;
};

template <std::size_t Capacity>
class HapticBlockRing {
 public:
  auto push(std::span<const std::uint8_t> pcm, float gain, std::uint64_t arrival) -> bool {
    const bool full = count_ == Capacity;
    if (full) {
      head_ = (head_ + 1) % Capacity;
      --count_;
    }
    HapticBlock &slot = blocks_[(head_ + count_) % Capacity];
    slot.count = pcm.size() / sizeof(std::int16_t);
    std::memcpy(slot.samples.data(), pcm.data(), pcm.size());
    slot.gain = gain;
    slot.arrival = arrival;
    ++count_;
    return full;
  }

  auto pop() -> std::optional<HapticBlock> {
    if (count_ == 0) {
      return std::nullopt;
    }
    const HapticBlock &front = blocks_[head_];
    head_ = (head_ + 1) % Capacity;
    --count_;
    return front;
  }

  void clear() {
    head_ = 0;
    count_ = 0;
  }

 private:
  std::array<HapticBlock, Capacity> blocks_{};
  std::size_t head_ = 0;
  std::size_t count_ = 0;
};

}  // namespace video

typedef NS_ENUM(NSInteger, CNHapticRendererPhase) {
  CNHapticRendererIdle,
  CNHapticRendererDraining,
  CNHapticRendererStopped,
};

typedef NS_ENUM(NSInteger, CNHapticEngineHealth) {
  CNHapticEngineReady,
  CNHapticEngineNeedsRestart,
};

typedef NS_ENUM(NSInteger, CNHapticBlockOutcome) {
  CNHapticBlockRendered,
  CNHapticBlockDropped,
  CNHapticBlockFailed,
};

constexpr std::size_t CNHapticPendingLimit = 4;
constexpr std::uint64_t CNHapticStaleNanoseconds = 40000000;
constexpr std::uint64_t CNHapticRestartBackoffNanoseconds = 500000000;
constexpr NSTimeInterval CNHapticCarrierSeconds = 3600.0;
constexpr std::uint64_t CNHapticCarrierRefreshNanoseconds = 3000ULL * 1000000000ULL;
constexpr NSTimeInterval CNHapticSilenceGrace = 0.025;
constexpr std::size_t CNHapticTransientLimit = 8;
constexpr std::size_t CNHapticLargestBlock = video::HapticBlock::largest;

@implementation CNControllerHapticsRenderer {
  dispatch_queue_t _queue;
  dispatch_source_t _silenceTimer;
  NSArray<CHHapticEngine *> *_engines;
  NSArray<id<CHHapticPatternPlayer>> *_players;
  NSMutableArray<id<CHHapticPatternPlayer>> *_transientPlayers;
  std::mutex _lock;
  video::HapticBlockRing<CNHapticPendingLimit> _pending;
  std::array<CNHapticShaperState, 2> _shapers;
  CNHapticRendererPhase _phase;
  CNHapticEngineHealth _health;
  std::uint64_t _restartNotBefore;
  std::uint64_t _playersStarted;
  NSTimeInterval _continuation;
  NSTimeInterval _silenceDeadline;
  NSUInteger _submittedBuffers;
  NSUInteger _renderedBuffers;
  NSUInteger _failedBuffers;
  NSUInteger _droppedBuffers;
}

+ (std::uint64_t)uptime {
  return clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
}

- (nullable instancetype)initWithController:(GCController *)controller {
  self = [super init];
  if (!self || !controller.haptics ||
      ![controller.haptics.supportedLocalities containsObject:GCHapticsLocalityLeftHandle] ||
      ![controller.haptics.supportedLocalities containsObject:GCHapticsLocalityRightHandle]) {
    return nil;
  }
  _queue = dispatch_queue_create("io.streetpea.chiaki.controller-haptics", DISPATCH_QUEUE_SERIAL);
  dispatch_set_target_queue(_queue, dispatch_get_global_queue(QOS_CLASS_USER_INTERACTIVE, 0));
  CHHapticEngine *left = [controller.haptics createEngineWithLocality:GCHapticsLocalityLeftHandle];
  CHHapticEngine *right =
      [controller.haptics createEngineWithLocality:GCHapticsLocalityRightHandle];
  if (!left || !right) {
    return nil;
  }
  _engines = @[ left, right ];
  _transientPlayers = [NSMutableArray arrayWithCapacity:CNHapticTransientLimit];
  const CNHapticShaperTuning tuning = CNHapticShaperDefaultTuning();
  for (auto &shaper : _shapers) {
    CNHapticShaperResetWithTuning(&shaper, &tuning);
  }
  _phase = CNHapticRendererIdle;
  _health = CNHapticEngineReady;
  if (![self preparePlayers]) {
    [self stopEngines];
    return nil;
  }
  __weak CNControllerHapticsRenderer *weakSelf = self;
  for (CHHapticEngine *engine in _engines) {
    engine.stoppedHandler = ^(CHHapticEngineStoppedReason reason) {
      [weakSelf engineInterrupted];
    };
    engine.resetHandler = ^{
      [weakSelf engineInterrupted];
    };
  }
  _silenceTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, _queue);
  dispatch_source_set_timer(_silenceTimer, DISPATCH_TIME_FOREVER, DISPATCH_TIME_FOREVER, 0);
  dispatch_source_set_event_handler(_silenceTimer, ^{
    [weakSelf silenceExpired];
  });
  dispatch_resume(_silenceTimer);
  return self;
}

- (nullable CHHapticPattern *)continuousPatternLasting:(NSTimeInterval)duration {
  CHHapticEventParameter *intensity =
      [[CHHapticEventParameter alloc] initWithParameterID:CHHapticEventParameterIDHapticIntensity
                                                    value:1.0F];
  CHHapticEventParameter *sharpness =
      [[CHHapticEventParameter alloc] initWithParameterID:CHHapticEventParameterIDHapticSharpness
                                                    value:0.5F];
  CHHapticEvent *event = [[CHHapticEvent alloc] initWithEventType:CHHapticEventTypeHapticContinuous
                                                       parameters:@[ intensity, sharpness ]
                                                     relativeTime:0
                                                         duration:duration];
  NSError *error = nil;
  CHHapticPattern *pattern = [[CHHapticPattern alloc] initWithEvents:@[ event ]
                                                          parameters:@[]
                                                               error:&error];
  if (!pattern || error) {
    return nil;
  }
  return pattern;
}

- (NSArray<CHHapticDynamicParameter *> *)silentParameters {
  return @[ [[CHHapticDynamicParameter alloc]
      initWithParameterID:CHHapticDynamicParameterIDHapticIntensityControl
                    value:0
             relativeTime:0] ];
}

- (nullable id<CHHapticPatternPlayer>)plainPlayerOn:(CHHapticEngine *)engine {
  CHHapticPattern *pattern = [self continuousPatternLasting:CNHapticCarrierSeconds];
  NSError *error = nil;
  id<CHHapticPatternPlayer> player =
      pattern ? [engine createPlayerWithPattern:pattern error:&error] : nil;
  if (!player || error) {
    return nil;
  }
  return player;
}

- (BOOL)preparePlayers {
  for (CHHapticEngine *engine in _engines) {
    NSError *error = nil;
    if (![engine startAndReturnError:&error] || error) {
      return NO;
    }
  }
  NSMutableArray<id<CHHapticPatternPlayer>> *players = [NSMutableArray arrayWithCapacity:2];
  for (CHHapticEngine *engine in _engines) {
    id<CHHapticPatternPlayer> player = [self plainPlayerOn:engine];
    if (!player) {
      return NO;
    }
    [players addObject:player];
  }
  NSMutableArray<id<CHHapticPatternPlayer>> *started = [NSMutableArray arrayWithCapacity:2];
  for (id<CHHapticPatternPlayer> player in players) {
    NSError *error = nil;
    if (![player startAtTime:CHHapticTimeImmediate error:&error] || error) {
      for (id<CHHapticPatternPlayer> running in started) {
        [running stopAtTime:CHHapticTimeImmediate error:nil];
      }
      return NO;
    }
    [started addObject:player];
    [player sendParameters:[self silentParameters] atTime:CHHapticTimeImmediate error:nil];
  }
  for (id<CHHapticPatternPlayer> player in _players) {
    [player stopAtTime:CHHapticTimeImmediate error:nil];
  }
  _players = players;
  _playersStarted = [CNControllerHapticsRenderer uptime];
  [_transientPlayers removeAllObjects];
  _continuation = 0;
  return YES;
}

- (void)stopEngines {
  for (CHHapticEngine *engine in _engines) {
    engine.stoppedHandler = ^(CHHapticEngineStoppedReason reason) {
    };
    engine.resetHandler = ^{
    };
    [engine stopWithCompletionHandler:nil];
  }
}

- (BOOL)isStopped {
  const std::lock_guard lock(_lock);
  return _phase == CNHapticRendererStopped;
}

- (void)engineInterrupted {
  dispatch_async(_queue, ^{
    if ([self isStopped]) {
      return;
    }
    self->_health = CNHapticEngineNeedsRestart;
    self->_continuation = 0;
  });
}

- (BOOL)ensureEngines {
  const std::uint64_t now = [CNControllerHapticsRenderer uptime];
  if (_health == CNHapticEngineReady && now - _playersStarted < CNHapticCarrierRefreshNanoseconds) {
    return YES;
  }
  if (now < _restartNotBefore) {
    return NO;
  }
  if (![self preparePlayers]) {
    _restartNotBefore = now + CNHapticRestartBackoffNanoseconds;
    return NO;
  }
  _health = CNHapticEngineReady;
  return YES;
}

- (void)silenceExpired {
  if ([self isStopped] || _health != CNHapticEngineReady || _silenceDeadline <= 0) {
    return;
  }
  NSTimeInterval now = _engines.firstObject.currentTime;
  if (now + 0.001 < _silenceDeadline) {
    [self armSilenceAfter:_silenceDeadline - now];
    return;
  }
  _silenceDeadline = 0;
  _continuation = 0;
  for (id<CHHapticPatternPlayer> player in _players) {
    [player sendParameters:[self silentParameters] atTime:CHHapticTimeImmediate error:nil];
  }
}

- (BOOL)playTransient:(CNHapticShaperTransient)transient
               engine:(CHHapticEngine *)engine
                 time:(NSTimeInterval)time {
  NSError *error = nil;
  CHHapticEventParameter *intensity =
      [[CHHapticEventParameter alloc] initWithParameterID:CHHapticEventParameterIDHapticIntensity
                                                    value:transient.intensity];
  CHHapticEventParameter *sharpness =
      [[CHHapticEventParameter alloc] initWithParameterID:CHHapticEventParameterIDHapticSharpness
                                                    value:transient.sharpness];
  CHHapticEvent *event = [[CHHapticEvent alloc] initWithEventType:CHHapticEventTypeHapticTransient
                                                       parameters:@[ intensity, sharpness ]
                                                     relativeTime:0];
  CHHapticPattern *pattern = [[CHHapticPattern alloc] initWithEvents:@[ event ]
                                                          parameters:@[]
                                                               error:&error];
  id<CHHapticPatternPlayer> player =
      pattern && !error ? [engine createPlayerWithPattern:pattern error:&error] : nil;
  if (!player || error) {
    return NO;
  }
  [_transientPlayers addObject:player];
  while (_transientPlayers.count > CNHapticTransientLimit) {
    [_transientPlayers removeObjectAtIndex:0];
  }
  return [player startAtTime:time error:&error] && !error;
}

- (BOOL)scheduleBlock:(const CNHapticShaperBlock &)block
                 side:(NSUInteger)side
                start:(NSTimeInterval)start
                scale:(double)scale {
  id<CHHapticPatternPlayer> player = _players[side];
  NSError *error = nil;
  NSMutableArray<CHHapticDynamicParameter *> *parameters =
      [NSMutableArray arrayWithCapacity:block.pointCount * 2];
  for (const auto &point : std::span{block.points}.first(block.pointCount)) {
    NSTimeInterval time = point.time * scale;
    [parameters addObject:[[CHHapticDynamicParameter alloc]
                              initWithParameterID:CHHapticDynamicParameterIDHapticIntensityControl
                                            value:point.intensity
                                     relativeTime:time]];
    [parameters addObject:[[CHHapticDynamicParameter alloc]
                              initWithParameterID:CHHapticDynamicParameterIDHapticSharpnessControl
                                            value:point.sharpness - 0.5F
                                     relativeTime:time]];
  }
  if (![player sendParameters:parameters atTime:start error:&error] || error) {
    return NO;
  }
  if (block.transientCount == 0) {
    return YES;
  }
  return [self playTransient:block.transient
                      engine:_engines[side]
                        time:start + block.transient.time * scale];
}

- (void)armSilenceAfter:(NSTimeInterval)delay {
  dispatch_time_t deadline = dispatch_time(
      DISPATCH_TIME_NOW, static_cast<std::int64_t>(std::fmax(delay, 0.001) * NSEC_PER_SEC));
  dispatch_source_set_timer(_silenceTimer, deadline, DISPATCH_TIME_FOREVER, NSEC_PER_MSEC);
}

- (CNHapticBlockOutcome)renderBlock:(const video::HapticBlock &)pending {
  const std::size_t frames = pending.count / 2;
  if (frames == 0) {
    return CNHapticBlockFailed;
  }
  if (![self ensureEngines]) {
    return CNHapticBlockFailed;
  }
  std::array<CNHapticShaperBlock, 2> blocks{};
  for (std::size_t side = 0; side < blocks.size(); ++side) {
    CNHapticShaperAnalyze(&_shapers[side], pending.samples.data(), frames, side, pending.gain,
                          &blocks[side]);
  }
  if ([CNControllerHapticsRenderer uptime] - pending.arrival > CNHapticStaleNanoseconds) {
    return CNHapticBlockDropped;
  }
  NSTimeInterval now = std::fmax(_engines[0].currentTime, _engines[1].currentTime);
  CNHapticScheduleDecision decision = CNHapticScheduleBlock(_continuation, now, blocks[0].duration);
  if (decision.action == CNHapticScheduleDrop) {
    return CNHapticBlockDropped;
  }
  double scale = blocks[0].duration > 0 ? decision.duration / blocks[0].duration : 1.0;
  BOOL scheduled = [self scheduleBlock:blocks[0] side:0 start:decision.start scale:scale];
  scheduled = [self scheduleBlock:blocks[1] side:1 start:decision.start scale:scale] && scheduled;
  _continuation = decision.start + decision.duration;
  _silenceDeadline = _continuation + CNHapticSilenceGrace;
  [self armSilenceAfter:_silenceDeadline - now];
  return scheduled ? CNHapticBlockRendered : CNHapticBlockFailed;
}

- (void)submitPCM:(const uint8_t *)pcm length:(size_t)length gain:(float)gain {
  if (!pcm || length == 0 || length % 4 || length > CNHapticLargestBlock) {
    return;
  }
  const std::uint64_t arrival = [CNControllerHapticsRenderer uptime];
  {
    const std::lock_guard lock(_lock);
    if (_phase == CNHapticRendererStopped) {
      return;
    }
    _submittedBuffers++;
    if (_pending.push(std::span<const std::uint8_t>{pcm, length}, gain, arrival)) {
      _droppedBuffers++;
    }
    if (_phase == CNHapticRendererDraining) {
      return;
    }
    _phase = CNHapticRendererDraining;
  }
  dispatch_async(_queue, ^{
    [self drain];
  });
}

- (std::optional<video::HapticBlock>)nextPending {
  const std::lock_guard lock(_lock);
  if (_phase != CNHapticRendererDraining) {
    return std::nullopt;
  }
  auto next = _pending.pop();
  if (!next) {
    _phase = CNHapticRendererIdle;
  }
  return next;
}

- (void)drain {
  while (const auto next = [self nextPending]) {
    const CNHapticBlockOutcome outcome = [self renderBlock:*next];
    const std::lock_guard lock(_lock);
    switch (outcome) {
      case CNHapticBlockRendered:
        _renderedBuffers++;
        break;
      case CNHapticBlockDropped:
        _droppedBuffers++;
        break;
      case CNHapticBlockFailed:
        _failedBuffers++;
        break;
    }
  }
}

- (NSUInteger)submittedBuffers {
  const std::lock_guard lock(_lock);
  return _submittedBuffers;
}

- (NSUInteger)renderedBuffers {
  const std::lock_guard lock(_lock);
  return _renderedBuffers;
}

- (NSUInteger)failedBuffers {
  const std::lock_guard lock(_lock);
  return _failedBuffers;
}

- (NSUInteger)droppedBuffers {
  const std::lock_guard lock(_lock);
  return _droppedBuffers;
}

- (void)dealloc {
  if (_silenceTimer) {
    dispatch_source_cancel(_silenceTimer);
  }
}

- (void)stop {
  {
    const std::lock_guard lock(_lock);
    if (_phase == CNHapticRendererStopped) {
      return;
    }
    _phase = CNHapticRendererStopped;
    _pending.clear();
  }
  dispatch_async(_queue, ^{
    dispatch_source_cancel(self->_silenceTimer);
    for (id<CHHapticPatternPlayer> player in self->_players) {
      [player sendParameters:[self silentParameters] atTime:CHHapticTimeImmediate error:nil];
    }
    [self stopEngines];
    [self->_transientPlayers removeAllObjects];
  });
}

@end
