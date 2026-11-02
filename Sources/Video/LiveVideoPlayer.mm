#import "LiveVideoPlayer.h"

#import <GameController/GameController.h>

#include <os/lock.h>
#include <os/log.h>
#include <os/signpost.h>
#include <time.h>
#include <memory>
#include <span>
#include <string>
#include <string_view>

#include <algorithm>
#include <array>
#include <atomic>
#include <chrono>
#include <cmath>
#include <cstring>
#include <limits>
#include <mutex>
#include <optional>
#include "Exclusive.hpp"
#include "chiaki_bridge/media.hpp"
#include "chiaki_bridge/play.hpp"
#include "chiaki_bridge/stream.hpp"

#import "ControllerHapticsRenderer.h"
#import "FrameInterpolationClient.h"
#import "LiveEncodedVideo.h"
#import "StatusCodes.h"
#import "VideoSurface.h"

typedef NS_ENUM(NSInteger, CNHapticBurst) {
  CNHapticBurstQuiet,
  CNHapticBurstPlaying,
};

typedef NS_ENUM(NSInteger, CNHapticAudioPhase) {
  CNHapticAudioClosed,
  CNHapticAudioOpening,
  CNHapticAudioReady,
};

typedef NS_ENUM(NSInteger, CNPlayerPhase) {
  CNPlayerIdle,
  CNPlayerRunning,
  CNPlayerStopping,
  CNPlayerStopped,
};

struct CNHapticPath {
  CNHapticRoute route = CNHapticRouteNone;
  float gain = 0;
  CNControllerHapticsRenderer *renderer = nil;
  CNHapticReportHandler reports = nil;
  std::shared_ptr<chiaki_bridge::HapticAudio> audio;
};

@interface CNLiveVideoPlayer ()
+ (NSString *)stringOf:(std::string_view)text;
+ (NSString *)keyboardTextOf:(std::string_view)text;
+ (NSInteger)colourOf:(libchiaking::controllers::SeatLight)light;
+ (libchiaking::play::Session::SystemUi)systemUIOf:(CNSystemUIState)state;
+ (chiaki_bridge::Bytes)bytesOf:(nullable NSData *)data;
+ (std::optional<libchiaking::controllers::ControllerKind>)controllerOf:(NSInteger)type;
+ (BOOL)decoderRecovers:(OSStatus)status;
+ (chiaki_bridge::DecodedFrame)decodedFrame:(uint16_t)index
                                     status:(OSStatus)status
                                    surface:(nullable CVPixelBufferRef)surface;
+ (float)clampedHapticGain:(float)gain;
+ (BOOL)silentHaptics:(const uint8_t *)pcm gain:(float)gain;
+ (os_log_t)videoLog;
+ (os_signpost_id_t)signpostOf:(uint16_t)index;
- (std::shared_ptr<chiaki_bridge::Stream>)currentStream;
- (std::shared_ptr<chiaki_bridge::Stream>)runningStream;
- (video::Exclusive<chiaki_bridge::Stream>)exchangeStream:
    (video::Exclusive<chiaki_bridge::Stream>)stream;
- (std::shared_ptr<const CNHapticPath>)hapticPath;
- (void)publishHapticPathLocked;
- (libchiaking::media::VideoResult)decodeEncoded:(const chiaki_bridge::EncodedFrame &)frame
                                        signpost:(os_signpost_id_t)signpost;
- (NSUInteger)currentKakusanSession;
- (void)deliverKakusanEvent:(const chiaki_bridge::KakusanEvent &)event
                       text:(nullable NSString *)text
                    session:(NSUInteger)session;
- (libchiaking::media::VideoResult)submitEncoded:(const chiaki_bridge::EncodedFrame &)frame;
- (void)presentSurface:(CVPixelBufferRef)surface;
- (void)sendHapticPCM:(const uint8_t *)pcm intensity:(uint8_t)intensity;
- (void)sendHapticFrames:(const uint8_t *)pcm size:(size_t)size intensity:(uint8_t)intensity;
- (void)sendControllerSpeakerPCM:(std::span<const int16_t>)pcm;
- (void)routeControllerSpeaker;
- (void)storeRumblePad:(uint8_t)pad left:(uint8_t)left right:(uint8_t)right;
- (void)markMotionReset;
- (void)markMotionSettingsTiltCorrection:(BOOL)tiltCorrection deadband:(BOOL)deadband;
- (void)presentWithoutVideo;
- (void)deliverEvent:(dispatch_block_t)event;
- (void)deliverDatacenters:(const libchiaking::play::DatacenterOffer &)offer;
- (void)deliverDatacenterChoice:(const libchiaking::play::DatacenterChoice &)choice;
+ (NSArray<NSDictionary<NSString *, id> *> *)logsOf:(chiaki_bridge::Stream &)stream;
+ (NSArray<NSData *> *)apiCapturesOf:(chiaki_bridge::Stream &)stream;
- (libchiaking::play::AccessibilityRequest)cloudAccessibility;
@end

@interface CNDatacenterOffer ()
- (instancetype)initWithEntry:(const libchiaking::play::DatacenterOffer::Entry &)entry
                       lowest:(BOOL)lowest;
@end

@implementation CNDatacenterOffer
- (instancetype)initWithEntry:(const libchiaking::play::DatacenterOffer::Entry &)entry
                       lowest:(BOOL)lowest {
  self = [super init];
  if (self) {
    _name = [CNLiveVideoPlayer stringOf:entry.name().text()];
    const auto roundTrip = entry.round_trip();
    _roundTripMilliseconds = roundTrip ? static_cast<NSInteger>(roundTrip->count()) : -1;
    _highLatency = entry.is_high_latency();
    _lowest = lowest;
  }
  return self;
}
@end

class CNStreamRelay final : public chiaki_bridge::StreamListener {
 public:
  explicit CNStreamRelay(CNLiveVideoPlayer *player) : player_(player) {}

  auto on_video(const chiaki_bridge::EncodedFrame &frame)
      -> libchiaking::media::VideoResult override {
    return [player_ submitEncoded:frame];
  }

  void on_connected(bool reconnected) override {
    CNLiveVideoPlayer *player = player_;
    [player deliverEvent:^{
      if (reconnected && player.reconnectedHandler) {
        player.reconnectedHandler();
      }
      if (player.streamVideoDisabled) {
        [player presentWithoutVideo];
      }
    }];
  }

  void on_start_attempt(std::uint32_t attempt) override {
    CNLiveVideoPlayer *player = player_;
    [player deliverEvent:^{
      if (player.startAttemptHandler) {
        player.startAttemptHandler(attempt);
      }
    }];
  }

  void on_reconnecting(std::uint32_t attempt) override {
    CNLiveVideoPlayer *player = player_;
    [player deliverEvent:^{
      if (player.reconnectingHandler) {
        player.reconnectingHandler(attempt);
      }
    }];
  }

  void on_connect_progress(const libchiaking::play::ConnectProgress &progress) override {
    [player_ deliverConnectProgress:progress];
  }

  void on_launch_progress(const libchiaking::play::LaunchProgress &progress,
                          bool playing) override {
    [player_ deliverLaunchProgress:progress playing:playing];
  }

  void on_datacenters_offered(const libchiaking::play::DatacenterOffer &offer) override {
    [player_ deliverDatacenters:offer];
  }

  void on_datacenter_chosen(const libchiaking::play::DatacenterChoice &choice) override {
    [player_ deliverDatacenterChoice:choice];
  }

  void on_picture_blocked(bool blocked) override {
    CNLiveVideoPlayer *player = player_;
    [player deliverEvent:^{
      if (player.displayProhibitedHandler) {
        player.displayProhibitedHandler(blocked);
      }
    }];
  }

  void on_connection_waiting(bool waiting) override {
    CNLiveVideoPlayer *player = player_;
    [player deliverEvent:^{
      if (player.connectionWaitingHandler) {
        player.connectionWaitingHandler(waiting);
      }
    }];
  }

  void on_play_time_left(std::chrono::minutes left,
                         libchiaking::play::PlayTimeLimit limit) override {
    CNLiveVideoPlayer *player = player_;
    const auto minutes = static_cast<NSInteger>(
        std::clamp<std::chrono::minutes::rep>(left.count(), 0, std::numeric_limits<int>::max()));
    [player deliverEvent:^{
      if (player.playTimeLeftHandler) {
        player.playTimeLeftHandler(minutes, limit);
      }
    }];
  }

  void on_login_pin_needed(bool retry) override {
    CNLiveVideoPlayer *player = player_;
    [player deliverEvent:^{
      if (player.loginPINRequestHandler) {
        player.loginPINRequestHandler(retry);
      }
    }];
  }

  void on_seat_passcode_needed(libchiaking::controllers::SeatNumber seat, bool retry) override {
    CNLiveVideoPlayer *player = player_;
    const NSInteger pad = seat.index();
    [player deliverEvent:^{
      if (player.controllerPasscodeRequestHandler) {
        player.controllerPasscodeRequestHandler(pad, retry);
      }
    }];
  }

  void on_seat_joined(libchiaking::controllers::SeatNumber seat) override {
    couch(CNCouchEventAnnounced, seat.index(), 0);
  }

  void on_seat_confirmed(libchiaking::controllers::SeatNumber seat,
                         libchiaking::controllers::SeatLight light) override {
    couch(CNCouchEventConfirmed, seat.index(), [CNLiveVideoPlayer colourOf:light]);
  }

  void on_seat_left(libchiaking::controllers::SeatNumber seat) override {
    couch(CNCouchEventDropped, seat.index(), 0);
  }

  void on_seat_refused(const libchiaking::play::SeatRefusal &refusal) override {
    CNLiveVideoPlayer *player = player_;
    const libchiaking::play::SeatRefusal refused = refusal;
    [player deliverEvent:^{
      if (player.seatRefusedHandler) {
        player.seatRefusedHandler(&refused);
      }
    }];
  }

  void on_lightbar(libchiaking::controllers::SeatLight light) override {
    CNLiveVideoPlayer *player = player_;
    const NSInteger rgb = [CNLiveVideoPlayer colourOf:light];
    [player deliverEvent:^{
      if (player.lightColorHandler) {
        player.lightColorHandler(0, rgb);
      }
    }];
  }

  void on_motion_reset() override { [player_ markMotionReset]; }

  void on_motion_settings(bool tilt_correction, bool angular_velocity_deadband) override {
    [player_ markMotionSettingsTiltCorrection:tilt_correction deadband:angular_velocity_deadband];
  }

  void on_rumble(libchiaking::controllers::SeatNumber seat, std::uint8_t low,
                 std::uint8_t high) override {
    [player_ storeRumblePad:seat.index() left:low right:high];
  }

  void on_haptic_block(
      std::span<const std::uint8_t, libchiaking::controllers::HapticBlock::size> pcm,
      std::uint8_t intensity) override {
    [player_ sendHapticPCM:pcm.data() intensity:intensity];
  }

  void on_haptic_frames(std::span<const std::uint8_t> pcm, std::uint8_t intensity) override {
    [player_ sendHapticFrames:pcm.data() size:pcm.size() intensity:intensity];
  }

  void on_controller_speaker(std::uint8_t seat, std::span<const std::int16_t> pcm) override {
    [player_ sendControllerSpeakerPCM:pcm];
  }

  void on_keyboard(chiaki_bridge::KeyboardChange change, std::string_view text) override {
    CNLiveVideoPlayer *player = player_;
    NSString *value = [CNLiveVideoPlayer keyboardTextOf:text];
    const CNKeyboardEvent kind = keyboardEvent(change);
    [player deliverEvent:^{
      if (player.keyboardEventHandler) {
        player.keyboardEventHandler(kind, value);
      }
    }];
  }

  void on_cloud_notice(const libchiaking::play::CloudNotice &notice) override {
    CNLiveVideoPlayer *player = player_;
    const libchiaking::play::CloudNotice copied = notice;
    [player deliverEvent:^{
      if (player.cloudNoticeHandler) {
        player.cloudNoticeHandler(&copied);
      }
    }];
  }

  void on_recording_banner(const libchiaking::play::RecordingBanner &banner) override {
    CNLiveVideoPlayer *player = player_;
    const BOOL recording = banner.recording;
    NSString *elapsed = [CNLiveVideoPlayer stringOf:banner.elapsed];
    [player deliverEvent:^{
      if (player.recordingBannerHandler) {
        player.recordingBannerHandler(recording, elapsed);
      }
    }];
  }

  void on_capture_thumbnail(const libchiaking::play::CloudCapture &capture) override {
    CNLiveVideoPlayer *player = player_;
    NSString *identifier = [CNLiveVideoPlayer stringOf:capture.id];
    const BOOL video = capture.video;
    NSData *image = [NSData dataWithBytes:capture.thumbnail.data() length:capture.thumbnail.size()];
    [player deliverEvent:^{
      if (player.captureThumbnailHandler) {
        player.captureThumbnailHandler(identifier, video, image);
      }
    }];
  }

  void on_capture_uploaded(const libchiaking::play::CloudCaptureUpload &upload) override {
    CNLiveVideoPlayer *player = player_;
    NSString *identifier = [CNLiveVideoPlayer stringOf:upload.id];
    NSString *gallery = [CNLiveVideoPlayer stringOf:upload.gallery_id];
    NSString *suffix = [CNLiveVideoPlayer stringOf:upload.extension];
    NSString *taken = [CNLiveVideoPlayer stringOf:upload.created];
    const uint64_t size = upload.size;
    const BOOL video = upload.video;
    [player deliverEvent:^{
      if (player.captureUploadedHandler) {
        player.captureUploadedHandler(identifier, gallery, suffix, size, video, taken);
      }
    }];
  }

  void on_kakusan(const chiaki_bridge::KakusanEvent &event, std::string_view text) override {
    NSString *lent = text.empty() ? nil : [CNLiveVideoPlayer stringOf:text];
    [player_ deliverKakusanEvent:event text:lent session:[player_ currentKakusanSession]];
  }

 private:
  static auto keyboardEvent(chiaki_bridge::KeyboardChange change) -> CNKeyboardEvent {
    switch (change) {
      case chiaki_bridge::KeyboardChange::opened:
        return CNKeyboardEventOpened;
      case chiaki_bridge::KeyboardChange::text_changed:
        return CNKeyboardEventTextChanged;
      case chiaki_bridge::KeyboardChange::closed:
        break;
    }
    return CNKeyboardEventRemoteClosed;
  }

  void couch(CNCouchEvent kind, NSInteger pad, NSInteger detail) {
    CNLiveVideoPlayer *player = player_;
    [player deliverEvent:^{
      if (player.couchEventHandler) {
        player.couchEventHandler(kind, pad, detail);
      }
    }];
  }

  __unsafe_unretained CNLiveVideoPlayer *player_;
};

static const uint32_t CNRumblePending = 1u << 16;
@implementation CNLiveVideoPlayer {
  CNLiveEncodedVideo *_encodedDecoder;
  CNVideoSurface *_surface;
  std::unique_ptr<CNStreamRelay> _relay;
  video::Exclusive<chiaki_bridge::Stream> _stream;
  os_unfair_lock _streamLock;
  std::atomic<std::uint64_t> _finalSurfaces;
  NSArray<NSDictionary<NSString *, id> *> *_finalDiagnosticLogs;
  NSArray<NSData *> *_finalAPICaptures;
  std::mutex _lock;
  CNVideoUpscaler _videoUpscaler;
  NSInteger _targetOutputHeight;
  CNFrameInterpolationClient *_frameInterpolation;
  NSInteger _sourceFrameRate;
  BOOL _frameGenerationEnabled;
  NSInteger _requestedHeight;
  NSInteger _requestedFPS;
  NSInteger _requestedBitrate;
  BOOL _requestedHEVC;
  BOOL _requestedHDR;
  CNStreamRoute _route;
  CNStreamConsole _routeConsole;
  uint32_t _feedbackDevice;
  float _hapticGain;
  CNHapticRoute _hapticRoute;
  CNControllerHapticsRenderer *_hapticsRenderer;
  video::Exclusive<chiaki_bridge::HapticAudio> _hapticAudio;
  CNHapticAudioPhase _hapticAudioPhase;
  uint32_t _hapticAudioDevice;
  uint64_t _hapticAudioRequest;
  std::atomic<NSUInteger> _hapticAudioOpened;
  std::atomic<NSUInteger> _hapticAudioFailed;
  std::atomic<NSUInteger> _hapticAudioNotReady;
  dispatch_queue_t _hapticAudioQueue;
  CNHapticReportHandler _hapticReports;
  chiaki_bridge::HapticRumble _hapticRumble;
  os_unfair_lock _hapticRumbleLock;
  std::atomic<long> _publishedHapticRoute;
  std::shared_ptr<const CNHapticPath> _hapticPath;
  os_unfair_lock _hapticPathLock;
  chiaki_bridge::TakionSetup _takion;
  BOOL _portGuessingForced;
  uint32_t _portGuessCount;
  std::atomic<NSUInteger> _hapticBuffersReceived;
  std::atomic<NSUInteger> _hapticReportsQueued;
  std::atomic<CNHapticBurst> _hapticBurst;
  std::atomic<NSUInteger> _hapticReportsRejected;
  CFAbsoluteTime _startedAt;
  std::atomic<uint32_t> _rumbleSlot;
  std::atomic<bool> _motionResetPending;
  std::atomic<bool> _videoSuspended;
  std::atomic<int> _motionSettingsPending;
  std::array<std::atomic<uint32_t>, 4> _padRumbleSlots;
  std::atomic<CNPlayerPhase> _phase;
  std::atomic<NSUInteger> _kakusanSession;
  BOOL _kakusanArmed;
  NSInteger _kakusanCapacity;
  NSInteger _kakusanLocalSeats;
}
+ (NSString *)stringOf:(std::string_view)text {
  return [[NSString alloc] initWithBytes:text.data()
                                  length:text.size()
                                encoding:NSUTF8StringEncoding]
             ?: @"";
}
+ (NSString *)keyboardTextOf:(std::string_view)text {
  if (text.empty()) {
    return @"";
  }
  NSData *bytes = [NSData dataWithBytes:text.data() length:text.size()];
  NSString *converted = nil;
  BOOL lossy = NO;
  [NSString stringEncodingForData:bytes
                  encodingOptions:@{
                    NSStringEncodingDetectionSuggestedEncodingsKey : @[ @(NSUTF8StringEncoding) ],
                    NSStringEncodingDetectionUseOnlySuggestedEncodingsKey : @YES,
                    NSStringEncodingDetectionAllowLossyKey : @YES
                  }
                  convertedString:&converted
              usedLossyConversion:&lossy];
  return converted ?: @"";
}
+ (NSInteger)colourOf:(libchiaking::controllers::SeatLight)light {
  return (light.red << 16) | (light.green << 8) | light.blue;
}
+ (libchiaking::play::Session::SystemUi)systemUIOf:(CNSystemUIState)state {
  using SystemUi = libchiaking::play::Session::SystemUi;
  switch (state) {
    case CNSystemUIStateGame:
      return SystemUi::game;
    case CNSystemUIStateOverlaid:
      return SystemUi::overlaid;
    case CNSystemUIStateBackground:
      return SystemUi::background;
  }
  return SystemUi::game;
}
+ (chiaki_bridge::Bytes)bytesOf:(NSData *)data {
  const auto *bytes = static_cast<const uint8_t *>(data.bytes);
  return chiaki_bridge::Bytes(bytes, bytes + data.length);
}
+ (std::optional<libchiaking::controllers::ControllerKind>)controllerOf:(NSInteger)type {
  switch (type) {
    case 0:
      return libchiaking::controllers::ControllerKind::console_default;
    case 2:
      return libchiaking::controllers::ControllerKind::dualshock4;
    case 6:
      return libchiaking::controllers::ControllerKind::dualsense;
    default:
      return std::nullopt;
  }
}
+ (BOOL)decoderRecovers:(OSStatus)status {
  switch (status) {
    case kVTVideoDecoderBadDataErr:
    case kVTVideoDecoderReferenceMissingErr:
    case kVTVideoDecoderMalfunctionErr:
    case kVTInvalidSessionErr:
      return YES;
    default:
      return NO;
  }
}
+ (chiaki_bridge::DecodedFrame)decodedFrame:(uint16_t)index
                                     status:(OSStatus)status
                                    surface:(CVPixelBufferRef)surface {
  using Kind = chiaki_bridge::DecodedFrame::Kind;
  if (status != noErr && ![CNLiveVideoPlayer decoderRecovers:status]) {
    return {.kind = Kind::failed, .index = index, .status = status};
  }
  if (status != noErr || !surface) {
    return {.kind = Kind::rejected, .index = index, .status = status};
  }
  return {.kind = Kind::picture, .index = index, .status = status};
}
+ (float)clampedHapticGain:(float)gain {
  return isfinite(gain) ? fmaxf(0.0f, fminf(2.4f, gain)) : 0.0f;
}
+ (BOOL)silentHaptics:(const uint8_t *)pcm gain:(float)gain {
  for (int index = 0; index < 128; index++) {
    int16_t sample;
    memcpy(&sample, pcm + index * 2, sizeof sample);
    if (fabsf((float)sample * gain / 256.0f) >= 1.0f) {
      return NO;
    }
  }
  return YES;
}
+ (os_log_t)videoLog {
  static os_log_t const pipeline = os_log_create("io.streetpea.chiaki", "VideoPipeline");
  return pipeline;
}
+ (os_signpost_id_t)signpostOf:(uint16_t)index {
  return static_cast<os_signpost_id_t>(index) + 1;
}
- (std::shared_ptr<chiaki_bridge::Stream>)currentStream {
  os_unfair_lock_lock(&_streamLock);
  std::shared_ptr<chiaki_bridge::Stream> stream = _stream.share();
  os_unfair_lock_unlock(&_streamLock);
  return stream;
}
- (std::shared_ptr<chiaki_bridge::Stream>)runningStream {
  if (_phase.load() != CNPlayerRunning) {
    return nullptr;
  }
  return [self currentStream];
}
- (video::Exclusive<chiaki_bridge::Stream>)exchangeStream:
    (video::Exclusive<chiaki_bridge::Stream>)stream {
  os_unfair_lock_lock(&_streamLock);
  std::swap(_stream, stream);
  os_unfair_lock_unlock(&_streamLock);
  return stream;
}
- (std::shared_ptr<const CNHapticPath>)hapticPath {
  os_unfair_lock_lock(&_hapticPathLock);
  std::shared_ptr<const CNHapticPath> path = _hapticPath;
  os_unfair_lock_unlock(&_hapticPathLock);
  return path;
}
- (void)publishHapticPathLocked {
  auto path = std::make_shared<CNHapticPath>();
  path->route = _hapticRoute;
  path->gain = _hapticGain;
  path->renderer = _hapticsRenderer;
  path->reports = _hapticReports;
  path->audio = _hapticRoute == CNHapticRouteUSBAudio ? _hapticAudio.share() : nullptr;
  std::shared_ptr<const CNHapticPath> published = std::move(path);
  os_unfair_lock_lock(&_hapticPathLock);
  std::swap(_hapticPath, published);
  os_unfair_lock_unlock(&_hapticPathLock);
  _publishedHapticRoute.store(_hapticRoute);
}
- (libchiaking::media::VideoResult)submitEncoded:(const chiaki_bridge::EncodedFrame &)frame {
  os_log_t pipeline = [CNLiveVideoPlayer videoLog];
  const os_signpost_id_t signpost = [CNLiveVideoPlayer signpostOf:frame.index];
  os_signpost_interval_begin(pipeline, signpost, "Submit", "frame %u",
                             static_cast<unsigned>(frame.index));
  const libchiaking::media::VideoResult result = [self decodeEncoded:frame signpost:signpost];
  os_signpost_interval_end(pipeline, signpost, "Submit", "verdict %d",
                           static_cast<int>(result.verdict));
  return result;
}
- (libchiaking::media::VideoResult)decodeEncoded:(const chiaki_bridge::EncodedFrame &)frame
                                        signpost:(os_signpost_id_t)signpost {
  using libchiaking::media::VideoVerdict;
  if (!_encodedDecoder) {
    return {VideoVerdict::format_failed, CNStatusOutOfMemory};
  }
  if (_videoSuspended.load()) {
    return {VideoVerdict::accepted, noErr};
  }
  const std::weak_ptr<chiaki_bridge::Stream> decoded = [self currentStream];
  if (decoded.expired()) {
    return {VideoVerdict::dropped, noErr};
  }
  if (!frame.header.empty()) {
    _encodedDecoder.hevc = frame.hevc;
  }
  os_log_t pipeline = [CNLiveVideoPlayer videoLog];
  const uint16_t index = frame.index;
  const NSUInteger rebuildsBefore = _encodedDecoder.rebuilds;
  CNEncodedVideoSubmission submission = [_encodedDecoder
            submit:reinterpret_cast<const uint8_t *>(frame.bytes.data())
            length:frame.bytes.size()
            header:frame.header.empty() ? nullptr
                                        : reinterpret_cast<const uint8_t *>(frame.header.data())
      headerLength:frame.header.size()
            output:^(OSStatus status, CVPixelBufferRef surface, CMTime pts) {
              (void)pts;
              os_signpost_interval_begin(pipeline, signpost, "Present", "frame %u",
                                         static_cast<unsigned>(index));
              const auto current = decoded.lock();
              const auto loss =
                  current && current->video_decoded([CNLiveVideoPlayer decodedFrame:index
                                                                             status:status
                                                                            surface:surface]);
              if (loss) {
                [self presentSurface:surface];
              }
              os_signpost_interval_end(pipeline, signpost, "Present", "status %d presented %d",
                                       static_cast<int>(status), loss ? 1 : 0);
            }];
  if (_encodedDecoder.rebuilds != rebuildsBefore) {
    if (const auto stream = decoded.lock()) {
      stream->request_keyframe();
    }
  }
  const int detail = submission.status;
  if (submission.configuring) {
    return {VideoVerdict::format_failed, detail};
  }
  switch (submission.result) {
    case CNVideoSubmitAccepted:
      return {VideoVerdict::accepted, detail};
    case CNVideoSubmitWouldBlock:
      return {VideoVerdict::dropped, detail};
    case CNVideoSubmitInvalidSample:
      return {VideoVerdict::recover, detail};
    case CNVideoSubmitFailed:
      break;
  }
  return {[CNLiveVideoPlayer decoderRecovers:submission.status] ? VideoVerdict::recover
                                                                : VideoVerdict::submit_failed,
          detail};
}
- (void)setVideoUpscaler:(CNVideoUpscaler)videoUpscaler {
  _videoUpscaler = videoUpscaler;
  _surface.videoUpscaler = videoUpscaler;
}
- (CNVideoUpscaler)videoUpscaler {
  return _videoUpscaler;
}
- (void)setTargetOutputHeight:(NSInteger)targetOutputHeight {
  _targetOutputHeight = targetOutputHeight;
  _surface.targetOutputHeight = targetOutputHeight;
#if TARGET_OS_OSX
  [_surface setNeedsLayout:YES];
#else
  [_surface setNeedsLayout];
#endif
}
- (NSInteger)targetOutputHeight {
  return _targetOutputHeight;
}
- (void)setSourceFrameRate:(NSInteger)frameRate {
  _sourceFrameRate = frameRate == 30 ? 30 : 60;
  [_frameInterpolation setSourceFrameRate:_sourceFrameRate];
  _surface.presentationFrameRate = _sourceFrameRate * (_frameGenerationEnabled ? 2 : 1);
}
- (NSInteger)sourceFrameRate {
  return _sourceFrameRate == 30 ? 30 : 60;
}
- (void)setFrameGenerationEnabled:(BOOL)enabled {
  _frameGenerationEnabled = enabled;
  _surface.presentationFrameRate = self.sourceFrameRate * (enabled ? 2 : 1);
  [_frameInterpolation setEnabled:enabled];
}
- (BOOL)frameGenerationEnabled {
  return _frameGenerationEnabled;
}
- (void)setVideoDiagnosticMode:(CNVideoDiagnosticMode)mode {
  _surface.videoDiagnosticMode = mode;
}
- (CNVideoDiagnosticMode)videoDiagnosticMode {
  return _surface.videoDiagnosticMode;
}
- (void)setLightMarkerX:(double)x y:(double)y {
  [_surface setLightMarkerX:x y:y];
}
- (CGPoint)lightMarker {
  return _surface.lightMarker;
}
- (void)setLightMarkerShown:(BOOL)shown {
  _surface.lightMarkerShown = shown;
}
- (BOOL)lightMarkerShown {
  return _surface.lightMarkerShown;
}
- (void)setMeasuresLight:(BOOL)measures {
  _surface.measuresLight = measures;
}
- (BOOL)measuresLight {
  return _surface.measuresLight;
}
- (void)setPictureBrightness:(float)brightness
                    contrast:(float)contrast
                  saturation:(float)saturation
                       gamma:(float)gamma
                      deband:(BOOL)deband {
  _surface.pictureAdjustment =
      (CNPictureAdjustment){brightness, contrast, saturation, gamma, deband};
}
- (void)setAudioVolume:(double)audioVolume {
  NSAssert(NSThread.isMainThread, @"Audio preferences must be set on main");
  _audioVolume = MIN(1, MAX(0, audioVolume));
  if (const auto stream = [self currentStream]) {
    stream->set_audio_gain((float)_audioVolume);
  }
}
- (void)setControllerSpeakerEnabled:(BOOL)controllerSpeakerEnabled {
  NSAssert(NSThread.isMainThread, @"Audio preferences must be set on main");
  _controllerSpeakerEnabled = controllerSpeakerEnabled;
  if (const auto stream = [self currentStream]) {
    stream->request_controller_speaker(controllerSpeakerEnabled);
  }
  [self routeControllerSpeaker];
}
- (void)setChatVolume:(double)chatVolume {
  NSAssert(NSThread.isMainThread, @"Audio preferences must be set on main");
  _chatVolume = MIN(1, MAX(0, chatVolume));
  if (const auto stream = [self currentStream]) {
    stream->set_voice_gain((float)_chatVolume);
  }
}
- (void)setAudio3DEnabled:(BOOL)audio3DEnabled {
  NSAssert(NSThread.isMainThread, @"Audio preferences must be set on main");
  _audio3DEnabled = audio3DEnabled;
  if (const auto stream = [self currentStream]) {
    stream->set_audio_3d(audio3DEnabled);
  }
}
- (BOOL)pressCreate:(NSInteger)press {
  NSAssert(NSThread.isMainThread, @"Create presses must be sent on main");
  using Press = libchiaking::play::Session::CreatePress;
  const auto stream = [self currentStream];
  if (!stream || press < 0 || press > static_cast<NSInteger>(Press::long_press)) {
    return NO;
  }
  return stream->press_create(static_cast<Press>(press));
}
- (BOOL)joinInvitation:(NSString *)invitationID session:(NSString *)sessionID {
  NSAssert(NSThread.isMainThread, @"Invitations must be joined on main");
  const auto stream = [self currentStream];
  if (!stream || invitationID.length == 0 || sessionID.length == 0) {
    return NO;
  }
  return stream->join_invitation(invitationID.UTF8String, sessionID.UTF8String);
}
- (BOOL)openSavedData {
  NSAssert(NSThread.isMainThread, @"Saved data must be opened on main");
  const auto stream = [self currentStream];
  return stream && stream->open_saved_data();
}
- (void)setVideoSuspended:(BOOL)videoSuspended {
  NSAssert(NSThread.isMainThread, @"Video suspension must be set on main");
  const bool was = _videoSuspended.exchange(videoSuspended);
  if (!was || videoSuspended) {
    return;
  }
  if (const auto stream = [self currentStream]) {
    stream->request_keyframe();
  }
}
- (BOOL)videoSuspended {
  return _videoSuspended.load();
}
- (libchiaking::play::AccessibilityRequest)cloudAccessibility {
  return libchiaking::play::AccessibilityRequest{
      static_cast<bool>(self.cloudScreenReader),      static_cast<int>(self.cloudScreenReaderSpeed),
      static_cast<int>(self.cloudScreenReaderVolume), static_cast<int>(self.cloudTextSize),
      static_cast<bool>(self.cloudBoldText),          static_cast<bool>(self.cloudHigherContrast)};
}
- (void)updateCloudAccessibility {
  NSAssert(NSThread.isMainThread, @"Accessibility must be updated on main");
  if (const auto stream = [self currentStream]) {
    stream->update_accessibility([self cloudAccessibility]);
  }
}
- (void)setSystemUIState:(CNSystemUIState)systemUIState {
  NSAssert(NSThread.isMainThread, @"System UI state must be set on main");
  _systemUIState = systemUIState;
  if (const auto stream = [self currentStream]) {
    stream->set_system_ui([CNLiveVideoPlayer systemUIOf:systemUIState]);
  }
}
- (void)setAudioSpatialEnabled:(BOOL)audioSpatialEnabled {
  NSAssert(NSThread.isMainThread, @"Audio preferences must be set on main");
  _audioSpatialEnabled = audioSpatialEnabled;
  if (const auto stream = [self currentStream]) {
    stream->set_audio_spatial(audioSpatialEnabled);
  }
}
- (void)applyAudioPreferences:(chiaki_bridge::Stream &)stream {
  NSString *device = self.audioOutputDevice ?: @"";
  stream.set_audio_buffer(std::chrono::milliseconds{MAX(0, self.audioBufferMilliseconds)});
  stream.set_audio_output(device.UTF8String);
  stream.set_audio_gain((float)_audioVolume);
  stream.set_voice_gain((float)_chatVolume);
  stream.set_audio_3d(self.audio3DEnabled);
  stream.set_audio_spatial(self.audioSpatialEnabled);
  static_cast<void>(stream.request_audio_channels((uint32_t)MAX(0, self.requestedAudioChannels)));
  stream.request_controller_speaker(self.controllerSpeakerEnabled);
  stream.route_controller_speaker(static_cast<bool>([self controllerSpeakerWired]));
  stream.set_media_off({.audio = static_cast<bool>(self.streamAudioDisabled),
                        .video = static_cast<bool>(self.streamVideoDisabled)});
}
- (chiaki_bridge::Stream *)openStream {
  {
    const std::lock_guard lock(_lock);
    _finalDiagnosticLogs = nil;
    _finalAPICaptures = nil;
  }
  _finalSurfaces.store(0, std::memory_order_relaxed);
  std::unique_ptr<chiaki_bridge::Stream> opened = chiaki_bridge::Stream::open(*_relay);
  chiaki_bridge::Stream *stream = opened.get();
  stream->set_system_ui([CNLiveVideoPlayer systemUIOf:self.systemUIState]);
  [self applyAudioPreferences:*stream];
  stream->set_api_capture(self.captureAPI);
  stream->set_takion(_takion);
  static_cast<void>(
      [self exchangeStream:video::Exclusive<chiaki_bridge::Stream>(std::move(opened))]);
  return stream;
}
- (void)resetFeedbackSlots {
  _rumbleSlot.store(0);
  _motionResetPending.store(false);
  _motionSettingsPending.store(0);
  for (NSUInteger pad = 0; pad < 4; pad++) {
    _padRumbleSlots[pad].store(0);
  }
}
- (instancetype)initWithShader:(NSString *)shader fsrcnnWeights:(NSData *)fsrcnnWeights {
  self = [super init];
  if (!self) {
    return nil;
  }
  _hapticRumbleLock = OS_UNFAIR_LOCK_INIT;
  _streamLock = OS_UNFAIR_LOCK_INIT;
  _hapticPathLock = OS_UNFAIR_LOCK_INIT;
  _hapticPath = std::make_shared<const CNHapticPath>();
  _hapticAudioQueue =
      dispatch_queue_create("io.streetpea.chiaki.haptic-audio", DISPATCH_QUEUE_SERIAL);
  _surface = [[CNVideoSurface alloc] initWithShader:shader fsrcnnWeights:fsrcnnWeights];
  if (!_surface) {
    return nil;
  }
  _relay = std::make_unique<CNStreamRelay>(self);
  _audioVolume = 1;
  _chatVolume = 1;
  _audioBufferMilliseconds = chiaki_bridge::PlayBridge::audio_buffering().usual_ms;
  _frameInterpolation = [CNFrameInterpolationClient new];
  return self;
}
- (void)deliverEvent:(dispatch_block_t)event {
  dispatch_async(dispatch_get_main_queue(), event);
}
- (void)deliverLaunchProgress:(const libchiaking::play::LaunchProgress &)progress
                      playing:(BOOL)playing {
  const libchiaking::play::LaunchProgress copy = progress;
  const auto bandwidth = progress.bandwidth_kbps();
  dispatch_async(dispatch_get_main_queue(), ^{
    if (bandwidth && *bandwidth > 0) {
      self->_requestedBitrate = static_cast<NSInteger>(*bandwidth);
    }
    if (self.launchProgressHandler) {
      self.launchProgressHandler(&copy, playing);
    }
  });
}
- (void)deliverConnectProgress:(const libchiaking::play::ConnectProgress &)progress {
  const libchiaking::play::ConnectProgress copy = progress;
  const auto elapsed = static_cast<NSInteger>(
      std::chrono::duration_cast<std::chrono::milliseconds>(progress.elapsed).count());
  dispatch_async(dispatch_get_main_queue(), ^{
    if (self.connectProgressHandler) {
      self.connectProgressHandler(&copy);
    }
    if (!copy.reconnecting && self.setupProgressHandler) {
      self.setupProgressHandler(copy.step, elapsed);
    }
  });
}
- (void)deliverDatacenters:(const libchiaking::play::DatacenterOffer &)offer {
  NSMutableArray<CNDatacenterOffer *> *offers =
      [NSMutableArray arrayWithCapacity:offer.entries().size()];
  for (const auto &entry : offer.entries()) {
    [offers addObject:[[CNDatacenterOffer alloc] initWithEntry:entry
                                                        lowest:offer.is_lowest(entry)]];
  }
  const auto wait = static_cast<NSInteger>(offer.wait().count());
  dispatch_async(dispatch_get_main_queue(), ^{
    if (self.cloudDatacentersHandler) {
      self.cloudDatacentersHandler(offers, wait);
    }
  });
}
- (void)deliverDatacenterChoice:(const libchiaking::play::DatacenterChoice &)choice {
  NSString *name = [CNLiveVideoPlayer stringOf:choice.name().text()];
  if (!name.length) {
    return;
  }
  const auto roundTrip = choice.round_trip();
  const NSInteger rtt = roundTrip ? static_cast<NSInteger>(roundTrip->count()) : -1;
  const auto how = choice.how();
  dispatch_async(dispatch_get_main_queue(), ^{
    if (self.cloudDatacenterSelectedHandler) {
      self.cloudDatacenterSelectedHandler(name, rtt, how);
    }
  });
}
- (CNPlatformView *)view {
  return _surface;
}
- (void)setFirstFramePresentedHandler:(void (^)(void))handler {
  _surface.firstFramePresentedHandler = handler;
}
- (void (^)(void))firstFramePresentedHandler {
  return _surface.firstFramePresentedHandler;
}
- (CNSurfaceStatistics)surfaceStatistics {
  return [_surface statistics];
}
- (chiaki_bridge::StreamStatistics)streamStatistics {
  const auto stream = [self currentStream];
  return stream ? stream->statistics() : chiaki_bridge::StreamStatistics{};
}
- (CNRequestedStream)requestedStream {
  const std::lock_guard lock(_lock);
  return {.height = _requestedHeight,
          .fps = _requestedFPS,
          .bitrate = _requestedBitrate,
          .hevc = _requestedHEVC,
          .hdr = _requestedHDR,
          .route = _route,
          .console = _routeConsole,
          .streamSeconds = _startedAt > 0 ? CFAbsoluteTimeGetCurrent() - _startedAt : 0};
}
- (NSNumber *)generatedFrames {
  return _frameInterpolation.statistics[@"generated"];
}
- (void)submitLoginPIN:(NSString *)pin completion:(void (^)(BOOL accepted))completion {
  if (pin.length != 4) {
    completion(NO);
    return;
  }
  NSString *code = [pin copy];
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    BOOL accepted = NO;
    if (const auto stream = [self currentStream]) {
      accepted = stream->submit_login_pin(code.UTF8String) && stream->await_login_pin();
    }
    completion(accepted);
  });
}
- (BOOL)selectCloudDatacenter:(NSString *)name {
  if (!name.length) {
    return NO;
  }
  const auto stream = [self currentStream];
  return stream && stream->choose_datacenter(name.UTF8String);
}
- (BOOL)submitControllerPasscode:(NSString *)passcode pad:(NSInteger)pad {
  if (passcode.length != 4 || pad < 0 || pad > UINT8_MAX) {
    return NO;
  }
  const auto stream = [self currentStream];
  return stream && stream->submit_seat_passcode((uint8_t)pad, passcode.UTF8String);
}
- (BOOL)goHome {
  const auto stream = [self runningStream];
  return stream && stream->go_home();
}
- (BOOL)connectMicrophoneRequest:(uint32_t)request {
  const auto stream = [self runningStream];
  return stream && stream->connect_microphone(request);
}
- (CNMicrophoneConnectState)microphoneConnectState:(uint32_t)request {
  const auto stream = [self runningStream];
  if (!stream) {
    return CNMicrophoneConnectStateRejected;
  }
  switch (stream->microphone_state(request)) {
    case libchiaking::play::Microphone::ConnectState::pending:
      return CNMicrophoneConnectStatePending;
    case libchiaking::play::Microphone::ConnectState::accepted:
      return CNMicrophoneConnectStateAccepted;
    case libchiaking::play::Microphone::ConnectState::rejected:
      return CNMicrophoneConnectStateRejected;
  }
  return CNMicrophoneConnectStateRejected;
}
- (BOOL)setMicrophoneMuted:(BOOL)muted {
  const auto stream = [self runningStream];
  return stream && stream->set_microphone_muted(muted);
}
- (BOOL)sendMicrophoneFrame:(const uint8_t *)frame length:(NSUInteger)length {
  if (!frame) {
    return NO;
  }
  const auto stream = [self runningStream];
  return stream && stream->send_microphone(std::span<const std::uint8_t>{frame, length});
}
- (BOOL)setKeyboardText:(NSString *)text {
  NSData *bytes = [text dataUsingEncoding:NSUTF8StringEncoding];
  if (!bytes || bytes.length > libchiaking::play::ConsoleKeyboard::text_limit) {
    return NO;
  }
  const auto stream = [self runningStream];
  return stream && stream->set_keyboard_text(
                       std::string_view{static_cast<const char *>(bytes.bytes), bytes.length});
}
- (NSDictionary<NSString *, NSNumber *> *)microphoneStatistics {
  libchiaking::play::Microphone::Statistics statistics;
  if (const auto stream = [self currentStream]) {
    statistics = stream->microphone_statistics();
  }
  return @{
    @"queued" : @(statistics.frames_queued),
    @"sent" : @(statistics.frames_sent),
    @"dropped" : @(statistics.frames_dropped),
    @"failures" : @(statistics.send_failures),
    @"lastCause" : @(statistics.last_error ? static_cast<int>(*statistics.last_error) : -1)
  };
}
- (BOOL)acceptKeyboardText:(NSString *)text {
  NSData *bytes = [text dataUsingEncoding:NSUTF8StringEncoding];
  if (!bytes || bytes.length > libchiaking::play::ConsoleKeyboard::text_limit) {
    return NO;
  }
  const auto stream = [self runningStream];
  if (!stream) {
    return NO;
  }
  return stream->set_keyboard_text(
             std::string_view{static_cast<const char *>(bytes.bytes), bytes.length}) &&
         stream->close_keyboard(true);
}
- (BOOL)sendKeyboardModifiers:(uint8_t)modifiers leds:(uint8_t)leds keys:(NSData *)keys {
  const size_t count = keys.length / sizeof(uint16_t);
  if (count > libchiaking::play::KeyboardState::max_keys) {
    return NO;
  }
  const auto stream = [self runningStream];
  return stream && stream->send_keyboard(modifiers, leds,
                                         std::span<const std::uint16_t>{
                                             static_cast<const uint16_t *>(keys.bytes), count});
}
- (BOOL)rejectKeyboard {
  const auto stream = [self runningStream];
  return stream && stream->close_keyboard(false);
}
+ (NSArray<NSDictionary<NSString *, id> *> *)logsOf:(chiaki_bridge::Stream &)stream {
  NSMutableArray<NSDictionary<NSString *, id> *> *result = [NSMutableArray array];
  for (const auto &line : stream.read_logs(288)) {
    NSString *message = [CNLiveVideoPlayer stringOf:line.message];
    [result addObject:@{@"severity" : @(static_cast<int>(line.severity)), @"message" : message}];
  }
  return result;
}
- (NSArray<NSDictionary<NSString *, id> *> *)takeDiagnosticLogs {
  if (const auto stream = [self currentStream]) {
    return [CNLiveVideoPlayer logsOf:*stream];
  }
  NSArray<NSDictionary<NSString *, id> *> *result = nil;
  {
    const std::lock_guard lock(_lock);
    result = _finalDiagnosticLogs;
    _finalDiagnosticLogs = nil;
  }
  return result ?: @[];
}
+ (NSArray<NSData *> *)apiCapturesOf:(chiaki_bridge::Stream &)stream {
  NSMutableArray<NSData *> *result = [NSMutableArray array];
  for (NSUInteger i = 0; i < 33; i++) {
    const auto capture = stream.take_api_capture();
    if (!capture) {
      break;
    }
    const auto text = capture->view();
    [result addObject:[NSData dataWithBytes:text.data() length:text.size()]];
  }
  return result;
}
- (NSArray<NSData *> *)takeAPICaptures {
  if (const auto stream = [self currentStream]) {
    return [CNLiveVideoPlayer apiCapturesOf:*stream];
  }
  NSArray<NSData *> *result = nil;
  {
    const std::lock_guard lock(_lock);
    result = _finalAPICaptures;
    _finalAPICaptures = nil;
  }
  return result ?: @[];
}
- (NSUInteger)decodedFrames {
  if (const auto stream = [self currentStream]) {
    return static_cast<NSUInteger>(stream->statistics().surfaces);
  }
  return static_cast<NSUInteger>(_finalSurfaces.load(std::memory_order_relaxed));
}
- (void)setTakionVersionsLocalPS4:(uint32_t)localPS4
                         localPS5:(uint32_t)localPS5
                            psNow:(uint32_t)psNow
                          psCloud:(uint32_t)psCloud {
  _takion.local_ps4.version = localPS4;
  _takion.local_ps5.version = localPS5;
  _takion.ps_now.version = psNow;
  _takion.ps_cloud.version = psCloud;
}
- (void)setTakionNegotiationLocalPS4:(BOOL)localPS4
                            localPS5:(BOOL)localPS5
                               psNow:(BOOL)psNow
                             psCloud:(BOOL)psCloud {
  _takion.local_ps4.negotiate = localPS4;
  _takion.local_ps5.negotiate = localPS5;
  _takion.ps_now.negotiate = psNow;
  _takion.ps_cloud.negotiate = psCloud;
}
- (void)setPortGuessingForced:(BOOL)forced count:(uint32_t)count {
  _portGuessingForced = forced;
  _portGuessCount = count;
}
- (void)concludeStream:(NSString *)diagnostics then:(dispatch_block_t)deliver {
  [_encodedDecoder stop];
  _encodedDecoder = nil;
  NSString *failureDiagnostics = diagnostics.length ? diagnostics : nil;
  video::Exclusive<chiaki_bridge::Stream> concluded =
      [self exchangeStream:video::Exclusive<chiaki_bridge::Stream>{}];
  if (const std::shared_ptr<chiaki_bridge::Stream> finished = concluded.share()) {
    NSArray<NSDictionary<NSString *, id> *> *logs = [CNLiveVideoPlayer logsOf:*finished];
    NSArray<NSData *> *captures = [CNLiveVideoPlayer apiCapturesOf:*finished];
    _finalSurfaces.store(finished->statistics().surfaces, std::memory_order_relaxed);
    const std::lock_guard lock(_lock);
    _finalDiagnosticLogs = logs;
    _finalAPICaptures = captures;
  }
  _phase.store(CNPlayerStopped);
  concluded.reset();
  dispatch_async(dispatch_get_main_queue(), ^{
    [self->_frameInterpolation stop];
    [self->_surface close];
    self->_failureDiagnostics = failureDiagnostics;
    deliver();
  });
}
- (void)refuseStart:(void (^)(const chiaki_bridge::StreamOutcome *outcome))completion {
  static_cast<void>([self exchangeStream:video::Exclusive<chiaki_bridge::Stream>{}]);
  const auto outcome = chiaki_bridge::StreamOutcome::unrecorded();
  completion(&outcome);
}
- (void)startConsoleForAccount:(NSData *)accountID
                    hardwareID:(NSData *)hardwareID
                  overInternet:(BOOL)overInternet
                           ps5:(BOOL)ps5
                        height:(NSInteger)height
                           fps:(NSInteger)fps
                       bitrate:(NSInteger)bitrate
                         codec:(CNStreamCodec)codec
                    completion:(void (^)(const chiaki_bridge::StreamOutcome *outcome))completion {
  NSAssert(NSThread.isMainThread, @"Surface lifecycle must be on main");
  if (accountID.length != libchiaking::psn_account_id_size ||
      hardwareID.length != libchiaking::consoles::HardwareId::size ||
      _phase.load() != CNPlayerIdle || codec < CNStreamCodecH264 || codec > CNStreamCodecHEVCHDR ||
      height < 0 || fps < 0 || bitrate < 0) {
    [self refuseStart:completion];
    return;
  }
  _kakusanSession.fetch_add(1);
  _restRefused = NO;
  chiaki_bridge::Stream *stream = [self openStream];
  if (_kakusanArmed && ![self applyKakusanHost:*stream]) {
    [self refuseStart:completion];
    return;
  }
  if (_portGuessCount) {
    stream->set_port_guessing(_portGuessingForced, _portGuessCount);
  }
  const CNStreamCodec launchCodec = ps5 ? codec : CNStreamCodecH264;
  if (!stream->set_picture({.height = static_cast<uint32_t>(height),
                            .fps = static_cast<uint32_t>(fps),
                            .bitrate_kbps = static_cast<uint32_t>(bitrate),
                            .codec = static_cast<libchiaking::media::VideoCodec>(launchCodec)})) {
    [self refuseStart:completion];
    return;
  }
  _requestedHeight = height;
  _requestedFPS = fps;
  self.sourceFrameRate = fps;
  _requestedBitrate = bitrate;
  _requestedHEVC = launchCodec != CNStreamCodecH264;
  _requestedHDR = launchCodec == CNStreamCodecHEVCHDR;
  _route = overInternet ? CNStreamRouteInternet : CNStreamRouteLocal;
  _routeConsole = ps5 ? CNStreamConsolePS5 : CNStreamConsolePS4;
  _startedAt = CFAbsoluteTimeGetCurrent();
  stream->set_console_handover(self.consoleJustLeft ? libchiaking::play::ConsoleHandover::just_left
                                                    : libchiaking::play::ConsoleHandover::fresh);
  stream->set_reconnect_after_drop(self.reconnectAfterDrop);
  stream->set_text_entry(self.consoleTextEntryEnabled);
  [self resetFeedbackSlots];
  _phase.store(CNPlayerRunning);
  const chiaki_bridge::Bytes account = [CNLiveVideoPlayer bytesOf:accountID];
  const chiaki_bridge::Bytes hardware = [CNLiveVideoPlayer bytesOf:hardwareID];
  const auto route =
      overInternet ? libchiaking::consoles::Route::internet : libchiaking::consoles::Route::home;
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INTERACTIVE, 0), ^{
    self->_encodedDecoder = [[CNLiveEncodedVideo alloc] initWithHEVC:self->_requestedHEVC];
    const chiaki_bridge::StreamOutcome outcome = stream->run_console(account, hardware, route);
    NSString *diagnostics = [CNLiveVideoPlayer stringOf:outcome.diagnostics()];
    [self concludeStream:diagnostics
                    then:^{
                      self->_restRefused =
                          outcome.rest() == libchiaking::play::RestOutcome::refused;
                      completion(&outcome);
                    }];
  });
}
- (void)startCloudForAccount:(NSData *)accountID
                   productID:(NSString *)productID
                     psCloud:(BOOL)psCloud
                      height:(NSInteger)height
                     bitrate:(NSInteger)bitrate
                         hdr:(BOOL)hdr
            measureBandwidth:(BOOL)measureBandwidth
               clearedLaunch:(const chiaki_bridge::ClearedLaunch *)clearedLaunch
                  completion:(void (^)(const chiaki_bridge::StreamOutcome *outcome))completion {
  NSAssert(NSThread.isMainThread, @"Surface lifecycle must be on main");
  if (_phase.load() != CNPlayerIdle || !productID.length ||
      accountID.length != libchiaking::psn_account_id_size || height < 0 || bitrate < 0) {
    [self refuseStart:completion];
    return;
  }
  _restRefused = NO;
  chiaki_bridge::Stream *stream = [self openStream];
  const BOOL hevc = psCloud;
  const BOOL dynamicRange = hevc && hdr;
  CNStreamCodec codec = CNStreamCodecH264;
  if (dynamicRange) {
    codec = CNStreamCodecHEVCHDR;
  } else if (hevc) {
    codec = CNStreamCodecHEVC;
  }
  if (!stream->set_picture({.height = static_cast<uint32_t>(height),
                            .fps = 60,
                            .bitrate_kbps = static_cast<uint32_t>(bitrate),
                            .codec = static_cast<libchiaking::media::VideoCodec>(codec),
                            .measure_bandwidth = static_cast<bool>(measureBandwidth),
                            .stable_quality = static_cast<bool>(self.cloudStableQuality)})) {
    [self refuseStart:completion];
    return;
  }
  _requestedHeight = height;
  _requestedFPS = 60;
  self.sourceFrameRate = 60;
  _requestedBitrate = bitrate;
  _requestedHEVC = hevc;
  _requestedHDR = dynamicRange;
  _route = hevc ? CNStreamRoutePSCloud : CNStreamRoutePSNow;
  _routeConsole = CNStreamConsoleUnknown;
  _startedAt = CFAbsoluteTimeGetCurrent();
  [self resetFeedbackSlots];
  stream->set_accessibility([self cloudAccessibility]);
  const NSInteger selectTimeout = self.cloudDatacenterSelectTimeoutMilliseconds;
  chiaki_bridge::CloudStart start{
      .product_id = productID.UTF8String,
      .datacenter = {.name = self.cloudForcedDatacenter.UTF8String ?: "",
                     .ask_within = std::nullopt},
      .cleared = clearedLaunch};
  if (self.cloudSelectDatacenterAtLaunch) {
    start.datacenter.ask_within = std::chrono::milliseconds{
        selectTimeout > 0 && selectTimeout <= UINT32_MAX ? selectTimeout : 0};
  }
  _phase.store(CNPlayerRunning);
  const chiaki_bridge::Bytes account = [CNLiveVideoPlayer bytesOf:accountID];
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    self->_encodedDecoder = [[CNLiveEncodedVideo alloc] initWithHEVC:self->_requestedHEVC];
    const chiaki_bridge::StreamOutcome outcome = stream->run_cloud(account, start);
    NSString *diagnostics = [CNLiveVideoPlayer stringOf:outcome.diagnostics()];
    [self concludeStream:diagnostics
                    then:^{
                      completion(&outcome);
                    }];
  });
}
- (BOOL)takeRumbleForPad:(NSInteger)pad left:(uint8_t *)left right:(uint8_t *)right {
  if (pad == 0) {
    return [self takeRumbleLeft:left right:right];
  }
  if (pad < 0 || pad > 3) {
    return NO;
  }
  uint32_t value = _padRumbleSlots[pad].exchange(0);
  if (!(value & CNRumblePending)) {
    return NO;
  }
  *left = (uint8_t)(value >> 8);
  *right = (uint8_t)value;
  return YES;
}
- (void)storeRumblePad:(uint8_t)pad left:(uint8_t)left right:(uint8_t)right {
  if (pad != 0) {
    atomic_store(&_padRumbleSlots[pad & 3], CNRumblePending | ((uint32_t)left << 8) | right);
    return;
  }
  _rumbleSlot.store(CNRumblePending | ((uint32_t)left << 8) | right);
}
- (BOOL)takeRumbleLeft:(uint8_t *)left right:(uint8_t *)right {
  uint32_t value = _rumbleSlot.exchange(0);
  if (!(value & CNRumblePending)) {
    return NO;
  }
  *left = (uint8_t)(value >> 8);
  *right = (uint8_t)value;
  return YES;
}
- (void)takeHapticRumbleLow:(float *)low high:(float *)high scale:(float)scale {
  chiaki_bridge::RumbleLevels levels{};
  if (_publishedHapticRoute.load() == CNHapticRouteRumble) {
    os_unfair_lock_lock(&_hapticRumbleLock);
    levels = _hapticRumble.linear(clock_gettime_nsec_np(CLOCK_UPTIME_RAW) / 1000000, scale);
    os_unfair_lock_unlock(&_hapticRumbleLock);
  }
  *low = levels.left;
  *high = levels.right;
}
- (void)takeHapticRumbleLeft:(float *)left right:(float *)right scale:(float)scale {
  chiaki_bridge::RumbleLevels levels{};
  if (_publishedHapticRoute.load() == CNHapticRouteRumble) {
    os_unfair_lock_lock(&_hapticRumbleLock);
    levels = _hapticRumble.curved(clock_gettime_nsec_np(CLOCK_UPTIME_RAW) / 1000000, scale);
    os_unfair_lock_unlock(&_hapticRumbleLock);
  }
  *left = levels.left;
  *right = levels.right;
}
- (void)consoleFeedbackIntensityHaptic:(uint8_t *)haptic trigger:(uint8_t *)trigger {
  chiaki_bridge::FeedbackIntensities levels;
  if (const auto stream = [self currentStream]) {
    levels = stream->feedback_intensities();
  }
  if (haptic) {
    *haptic = levels.haptic;
  }
  if (trigger) {
    *trigger = levels.trigger;
  }
}
- (void)setControllerHapticGain:(float)hapticGain {
  const std::lock_guard lock(_lock);
  _hapticGain = [CNLiveVideoPlayer clampedHapticGain:hapticGain];
  [self publishHapticPathLocked];
}
- (nullable NSData *)feedbackForPad:(uint8_t)pad {
  std::array<std::uint8_t, chiaki_bridge::Stream::feedback_report_size> packet{};
  const auto stream = [self runningStream];
  const BOOL available =
      stream && stream->take_feedback(pad, chiaki_bridge::Stream::FeedbackReport{packet});
  return available ? [NSData dataWithBytes:packet.data() length:packet.size()] : nil;
}
- (nullable NSData *)controllerFeedback {
  return [self feedbackForPad:0];
}
- (nullable NSData *)controllerFeedbackForPad:(NSInteger)pad {
  if (pad < 1 || pad > 3) {
    return nil;
  }
  return [self feedbackForPad:(uint8_t)pad];
}
- (chiaki_bridge::HapticDelivery)hapticDeliveryLocked:(BOOL)frames {
  if (frames) {
    return chiaki_bridge::HapticDelivery::frames;
  }
  return _hapticRoute != CNHapticRouteNone ? chiaki_bridge::HapticDelivery::blocks
                                           : chiaki_bridge::HapticDelivery::polled;
}
- (void)routeHaptics:(chiaki_bridge::HapticDelivery)delivery {
  if (const auto stream = [self currentStream]) {
    stream->route_haptics(delivery);
  }
  [self routeControllerSpeaker];
}
- (BOOL)controllerSpeakerWired {
  const std::shared_ptr<const CNHapticPath> path = [self hapticPath];
  return _controllerSpeakerEnabled && path->route == CNHapticRouteUSBAudio && path->audio &&
         path->audio->has_speaker();
}
- (void)routeControllerSpeaker {
  if (const auto stream = [self currentStream]) {
    stream->route_controller_speaker(static_cast<bool>([self controllerSpeakerWired]));
  }
}
- (void)sendControllerSpeakerPCM:(std::span<const int16_t>)pcm {
  const std::shared_ptr<const CNHapticPath> path = [self hapticPath];
  if (path->route == CNHapticRouteUSBAudio && path->audio) {
    static_cast<void>(path->audio->push_speaker(pcm, 1.0F));
  }
}
- (BOOL)keepHapticsRendererForDevice:(uint32_t)device gain:(float)gain {
  {
    const std::lock_guard lock(_lock);
    const BOOL kept =
        _hapticRoute == CNHapticRouteCoreHaptics && _hapticsRenderer && _feedbackDevice == device;
    if (!kept) {
      return NO;
    }
    _hapticGain = gain;
    [self publishHapticPathLocked];
  }
  [self routeHaptics:chiaki_bridge::HapticDelivery::frames];
  return YES;
}
- (CNHapticRoute)configureControllerFeedbackDevice:(uint32_t)device
                                             route:(CNHapticRoute)route
                                        hapticGain:(float)hapticGain
                                           reports:(nullable CNHapticReportHandler)reports {
  float gain = [CNLiveVideoPlayer clampedHapticGain:hapticGain];
  if (device == 0) {
    route = CNHapticRouteNone;
  }
  if (route == CNHapticRouteBluetoothReports && !reports) {
    route = CNHapticRouteCoreHaptics;
  }
  _lock.lock();
  BOOL keepsRenderer = _hapticRoute == CNHapticRouteCoreHaptics && _hapticsRenderer &&
                       _feedbackDevice == device && route == CNHapticRouteCoreHaptics;
  _lock.unlock();
  if (keepsRenderer && [self keepHapticsRendererForDevice:device gain:gain]) {
    return CNHapticRouteCoreHaptics;
  }

  _lock.lock();
  CNControllerHapticsRenderer *oldRenderer = _hapticsRenderer;
  _hapticsRenderer = nil;
  BOOL sameAudioDevice = _hapticAudioPhase != CNHapticAudioClosed && _hapticAudioDevice == device;
  BOOL keepsAudio = sameAudioDevice &&
                    (route == CNHapticRouteUSBAudio ||
                     (route == CNHapticRouteRumble && _hapticAudioPhase == CNHapticAudioOpening));
  video::Exclusive<chiaki_bridge::HapticAudio> oldAudio;
  if (!keepsAudio) {
    oldAudio = std::move(_hapticAudio);
    _hapticAudioPhase = CNHapticAudioClosed;
    _hapticAudioRequest++;
  }
  BOOL opensAudio = route == CNHapticRouteUSBAudio && _hapticAudioPhase == CNHapticAudioClosed;
  uint64_t request = 0;
  if (opensAudio) {
    _hapticAudioPhase = CNHapticAudioOpening;
    _hapticAudioDevice = device;
    request = ++_hapticAudioRequest;
  }
  _hapticReports = nil;
  _feedbackDevice = device;
  _hapticGain = gain;
  _hapticRoute = CNHapticRouteNone;
  [self publishHapticPathLocked];
  _lock.unlock();
  [oldRenderer stop];
  [self closeHapticAudio:std::move(oldAudio)];
  if (opensAudio) {
    [self openHapticAudioForDevice:device request:request];
  }
  CNControllerHapticsRenderer *renderer = nil;
  if (route == CNHapticRouteCoreHaptics) {
    for (GCController *controller in GCController.controllers) {
      if (controller.haptics && [controller.productCategory hasPrefix:@"DualSense"] &&
          [controller.haptics.supportedLocalities containsObject:GCHapticsLocalityLeftHandle] &&
          [controller.haptics.supportedLocalities containsObject:GCHapticsLocalityRightHandle]) {
        renderer = [[CNControllerHapticsRenderer alloc] initWithController:controller];
        if (renderer) {
          break;
        }
      }
    }
  }

  _lock.lock();
  _hapticsRenderer = renderer;
  BOOL audio = route == CNHapticRouteUSBAudio && _hapticAudioPhase == CNHapticAudioReady &&
               _hapticAudioDevice == device && static_cast<bool>(_hapticAudio);
  _hapticReports = route == CNHapticRouteBluetoothReports ? [reports copy] : nil;
  if (route != CNHapticRouteRumble) {
    os_unfair_lock_lock(&_hapticRumbleLock);
    _hapticRumble.reset();
    os_unfair_lock_unlock(&_hapticRumbleLock);
  }
  _hapticRoute = audio                          ? CNHapticRouteUSBAudio
                 : _hapticReports               ? CNHapticRouteBluetoothReports
                 : renderer                     ? CNHapticRouteCoreHaptics
                 : route == CNHapticRouteRumble ? CNHapticRouteRumble
                                                : CNHapticRouteNone;
  _hapticBuffersReceived.store(0, std::memory_order_relaxed);
  _hapticReportsQueued.store(0, std::memory_order_relaxed);
  _hapticBurst.store(CNHapticBurstQuiet, std::memory_order_relaxed);
  _hapticReportsRejected.store(0, std::memory_order_relaxed);
  const chiaki_bridge::HapticDelivery delivery = [self hapticDeliveryLocked:renderer != nil];
  CNHapticRoute active = _hapticRoute;
  [self publishHapticPathLocked];
  _lock.unlock();
  [self routeHaptics:delivery];
  return active;
}
- (void)sendHapticFrames:(const uint8_t *)pcm size:(size_t)size intensity:(uint8_t)intensity {
  _hapticBuffersReceived.fetch_add(1, std::memory_order_relaxed);
  if (_publishedHapticRoute.load(std::memory_order_relaxed) == CNHapticRouteNone) {
    return;
  }
  const std::shared_ptr<const CNHapticPath> path = [self hapticPath];
  if (path->route == CNHapticRouteNone || !path->renderer) {
    return;
  }
  _hapticReportsQueued.fetch_add(1, std::memory_order_relaxed);
  [path->renderer submitPCM:pcm
                     length:size
                       gain:path->gain * chiaki_bridge::ConsoleFeedback::scale_of(intensity)];
}
- (void)sendHapticPCM:(const uint8_t *)pcm intensity:(uint8_t)intensity {
  _hapticBuffersReceived.fetch_add(1, std::memory_order_relaxed);
  if (_publishedHapticRoute.load(std::memory_order_relaxed) == CNHapticRouteNone) {
    return;
  }
  const std::shared_ptr<const CNHapticPath> path = [self hapticPath];
  const float gain = path->gain * chiaki_bridge::ConsoleFeedback::scale_of(intensity);
  switch (path->route) {
    case CNHapticRouteNone:
      return;
    case CNHapticRouteRumble:
      os_unfair_lock_lock(&_hapticRumbleLock);
      _hapticRumble.push(std::span<const uint8_t>{pcm, chiaki_bridge::HapticAudio::block_size},
                         path->gain, clock_gettime_nsec_np(CLOCK_UPTIME_RAW) / 1000000);
      os_unfair_lock_unlock(&_hapticRumbleLock);
      return;
    case CNHapticRouteUSBAudio:
      if (path->audio) {
        const bool pushed = path->audio->push(
            chiaki_bridge::HapticAudio::Block{pcm, chiaki_bridge::HapticAudio::block_size}, gain);
        auto &counter = pushed ? _hapticReportsQueued : _hapticReportsRejected;
        counter.fetch_add(1, std::memory_order_relaxed);
      }
      return;
    case CNHapticRouteCoreHaptics:
    case CNHapticRouteBluetoothReports:
      break;
  }
  if (!path->reports) {
    return;
  }
  const BOOL silent = [CNLiveVideoPlayer silentHaptics:pcm gain:gain];
  const CNHapticBurst previous = _hapticBurst.exchange(
      silent ? CNHapticBurstQuiet : CNHapticBurstPlaying, std::memory_order_relaxed);
  if (silent && previous == CNHapticBurstQuiet) {
    return;
  }
  auto &counter = path->reports(pcm, gain) ? _hapticReportsQueued : _hapticReportsRejected;
  counter.fetch_add(1, std::memory_order_relaxed);
}
- (void)markMotionReset {
  _motionResetPending.store(true);
}
- (void)presentWithoutVideo {
  [_surface presentWithoutVideo];
}
- (BOOL)takeMotionReset {
  return _motionResetPending.exchange(false);
}
- (void)markMotionSettingsTiltCorrection:(BOOL)tiltCorrection deadband:(BOOL)deadband {
  _motionSettingsPending.store(4 | (tiltCorrection ? 2 : 0) | (deadband ? 1 : 0));
}
- (NSInteger)takeMotionSettings {
  int pending = _motionSettingsPending.exchange(0);
  return pending == 0 ? -1 : pending & 3;
}
- (NSDictionary<NSString *, NSNumber *> *)controllerFeedbackDiagnostics {
  const auto stream = [self currentStream];
  const chiaki_bridge::FeedbackStatistics source =
      stream ? stream->feedback_statistics() : chiaki_bridge::FeedbackStatistics{};
  CNControllerHapticsRenderer *renderer = nil;
  uint32_t device = 0;
  CNHapticRoute route = CNHapticRouteNone;
  {
    const std::lock_guard lock(_lock);
    renderer = _hapticsRenderer;
    device = _feedbackDevice;
    route = _hapticRoute;
  }
  return @{
    @"device" : @(device),
    @"waveformEnabled" : @(route != CNHapticRouteNone && route != CNHapticRouteRumble),
    @"rumbleHaptics" : @(route == CNHapticRouteRumble),
    @"usbAudioOpened" : @(_hapticAudioOpened.load(std::memory_order_relaxed)),
    @"usbAudioFailed" : @(_hapticAudioFailed.load(std::memory_order_relaxed)),
    @"usbAudioNotReady" : @(_hapticAudioNotReady.load(std::memory_order_relaxed)),
    @"buffersReceived" : @(_hapticBuffersReceived.load(std::memory_order_relaxed)),
    @"reportsQueued" : @(_hapticReportsQueued.load(std::memory_order_relaxed)),
    @"reportsRejected" : @(_hapticReportsRejected.load(std::memory_order_relaxed)),
    @"reportsWritten" : @(renderer.renderedBuffers),
    @"reportsWriteFailed" : @(renderer.failedBuffers),
    @"reportsExpired" : @(renderer.droppedBuffers),
    @"averageWriteUS" : @0,
    @"maximumWriteUS" : @0,
    @"sourceRumbleCallbacks" : @(source.rumbles),
    @"sourceCallbacks" : @(source.callbacks),
    @"sourceBytes" : @(source.bytes),
    @"sourceMalformed" : @(source.malformed),
    @"sourcePacketsTaken" : @(source.packets_taken),
    @"sourceBufferedBytes" : @(source.buffered_bytes),
  };
}
- (BOOL)setControllerButtons:(uint32_t)buttons
                          l2:(uint8_t)l2
                          r2:(uint8_t)r2
                       leftX:(int16_t)leftX
                       leftY:(int16_t)leftY
                      rightX:(int16_t)rightX
                      rightY:(int16_t)rightY {
  return [self setControllerButtons:buttons
                                 l2:l2
                                 r2:r2
                              leftX:leftX
                              leftY:leftY
                             rightX:rightX
                             rightY:rightY
                                pad:0];
}
- (BOOL)setControllerButtons:(uint32_t)buttons
                          l2:(uint8_t)l2
                          r2:(uint8_t)r2
                       leftX:(int16_t)leftX
                       leftY:(int16_t)leftY
                      rightX:(int16_t)rightX
                      rightY:(int16_t)rightY
                         pad:(NSInteger)pad {
  return [self setControllerButtons:buttons
                                 l2:l2
                                 r2:r2
                              leftX:leftX
                              leftY:leftY
                             rightX:rightX
                             rightY:rightY
                                pad:pad
                            touchID:-1
                             touchX:0
                             touchY:0];
}
- (BOOL)setControllerButtons:(uint32_t)buttons
                          l2:(uint8_t)l2
                          r2:(uint8_t)r2
                       leftX:(int16_t)leftX
                       leftY:(int16_t)leftY
                      rightX:(int16_t)rightX
                      rightY:(int16_t)rightY
                         pad:(NSInteger)pad
                     touchID:(NSInteger)touchID
                      touchX:(uint16_t)touchX
                      touchY:(uint16_t)touchY {
  if (touchID > 0x7f) {
    return NO;
  }
  chiaki_bridge::ControllerSample sample{.buttons = buttons,
                                         .l2 = l2,
                                         .r2 = r2,
                                         .left_x = leftX,
                                         .left_y = leftY,
                                         .right_x = rightX,
                                         .right_y = rightY};
  if (touchID >= 0) {
    sample.first_touch =
        chiaki_bridge::TouchSample{.id = (uint8_t)touchID, .x = touchX, .y = touchY};
  }
  return [self sendControllerSample:sample pad:pad];
}
- (BOOL)sendControllerSample:(chiaki_bridge::ControllerSample)sample pad:(NSInteger)pad {
  if (pad < 0 || pad > 3) {
    return NO;
  }
  const auto stream = [self runningStream];
  return stream && stream->send_controller((uint8_t)pad, sample);
}
- (BOOL)couchJoinPad:(NSInteger)pad
      controllerType:(uint8_t)controllerType
           accountID:(nullable NSData *)accountID {
  const auto controller = [CNLiveVideoPlayer controllerOf:controllerType];
  if (pad < 1 || pad > 3 || !controller ||
      (accountID && accountID.length != libchiaking::psn_account_id_size)) {
    return NO;
  }
  const auto stream = [self runningStream];
  return stream &&
         stream->add_couch_player((uint8_t)pad, *controller, [CNLiveVideoPlayer bytesOf:accountID]);
}
- (BOOL)couchRemovePad:(NSInteger)pad {
  if (pad < 1 || pad > 3) {
    return NO;
  }
  const auto stream = [self runningStream];
  return stream && stream->remove_couch_player((uint8_t)pad);
}
- (void)presentSurface:(CVPixelBufferRef)surface {
  CNVideoSurface *videoSurface = _surface;
  [_frameInterpolation offer:surface
                     handler:^(CVPixelBufferRef output, BOOL generated) {
                       [videoSurface offer:output generated:generated];
                     }];
}
- (NSUInteger)currentKakusanSession {
  return _kakusanSession.load();
}
- (void)deliverKakusanEvent:(const chiaki_bridge::KakusanEvent &)event
                       text:(NSString *)text
                    session:(NSUInteger)session {
  const chiaki_bridge::KakusanEvent copied = event;
  dispatch_async(dispatch_get_main_queue(), ^{
    if (session != self->_kakusanSession.load()) {
      return;
    }
    if (copied.kind == chiaki_bridge::KakusanEvent::Kind::stream_ready && copied.video_fps > 0) {
      self.sourceFrameRate = copied.video_fps;
    }
    if (self.kakusanEventHandler) {
      self.kakusanEventHandler(&copied, text);
    }
  });
}
- (chiaki_bridge::KakusanCommandOutcome)notArmed {
  return chiaki_bridge::KakusanCommandOutcome::refused(
      chiaki_bridge::KakusanCommandRefusal::not_armed);
}
- (chiaki_bridge::KakusanCommandOutcome)invalidArgument {
  return chiaki_bridge::KakusanCommandOutcome::declined(
      libchiaking::kakusan::Refusal::Kind::invalid_argument);
}
- (chiaki_bridge::KakusanCommandOutcome)armKakusanHostWithCapacity:(NSInteger)capacity
                                                        localSeats:(NSInteger)localSeats {
  NSAssert(NSThread.isMainThread, @"Kakusan hosting is armed on main");
  const auto most = static_cast<NSInteger>(libchiaking::kakusan::SharingRules::most_seats);
  if (capacity < 1 || capacity > most || localSeats < 1 || localSeats > capacity) {
    return [self invalidArgument];
  }
  if (_phase.load() != CNPlayerIdle) {
    return chiaki_bridge::KakusanCommandOutcome::declined(
        libchiaking::kakusan::Refusal::Kind::busy);
  }
  _kakusanArmed = YES;
  _kakusanCapacity = capacity;
  _kakusanLocalSeats = localSeats;
  return chiaki_bridge::KakusanCommandOutcome::accepted({});
}
- (void)disarmKakusanHost {
  NSAssert(NSThread.isMainThread, @"Kakusan hosting is armed on main");
  _kakusanArmed = NO;
}
- (BOOL)applyKakusanHost:(chiaki_bridge::Stream &)stream {
  _kakusanArmed = NO;
  const auto outcome =
      stream.arm_kakusan({.capacity = static_cast<uint8_t>(_kakusanCapacity),
                          .local_seats = static_cast<uint8_t>(_kakusanLocalSeats),
                          .force_port_guessing = static_cast<bool>(_portGuessingForced)});
  return outcome.kind() == chiaki_bridge::KakusanCommandOutcome::Kind::accepted;
}
- (chiaki_bridge::KakusanCommandOutcome)inviteKakusanGuest {
  const auto stream = [self currentStream];
  return stream ? stream->invite_guest() : [self notArmed];
}
- (chiaki_bridge::KakusanCommandOutcome)importKakusanReply:(NSString *)reply {
  NSData *block = [reply dataUsingEncoding:NSUTF8StringEncoding];
  if (!block.length) {
    return [self invalidArgument];
  }
  const auto stream = [self currentStream];
  return stream ? stream->import_reply(
                      std::string_view{static_cast<const char *>(block.bytes), block.length})
                : [self notArmed];
}
- (chiaki_bridge::KakusanCommandOutcome)kakusanEnterCode:(NSString *)code
                                                 guestID:(NSData *)guestID {
  NSData *digits = [code dataUsingEncoding:NSASCIIStringEncoding];
  if (!digits.length) {
    return [self invalidArgument];
  }
  const auto stream = [self currentStream];
  return stream ? stream->enter_guest_code(
                      [CNLiveVideoPlayer bytesOf : guestID],
                      std::string_view { static_cast<const char *>(digits.bytes), digits.length })
                : [self notArmed];
}
- (chiaki_bridge::KakusanCommandOutcome)kakusanApproveGuestID:(NSData *)guestID
                                                          pad:(NSInteger)pad
                                               controllerType:(NSInteger)controllerType
                                                    accountID:(NSData *)accountID {
  const auto controller = [CNLiveVideoPlayer controllerOf:controllerType];
  if (pad < 0 || pad > UINT8_MAX || !controller) {
    return [self invalidArgument];
  }
  const auto stream = [self currentStream];
  return stream ? stream->give_seat([CNLiveVideoPlayer bytesOf:guestID], (uint8_t)pad, *controller,
                                    [CNLiveVideoPlayer bytesOf:accountID])
                : [self notArmed];
}
- (chiaki_bridge::KakusanCommandOutcome)kakusanRemoveGuestID:(NSData *)guestID {
  const auto stream = [self currentStream];
  return stream ? stream->remove_guest([CNLiveVideoPlayer bytesOf:guestID]) : [self notArmed];
}
- (chiaki_bridge::KakusanCommandOutcome)kakusanSetLocalSeats:(NSInteger)localSeats {
  if (localSeats < 1 || localSeats > UINT8_MAX) {
    return [self invalidArgument];
  }
  const auto stream = [self currentStream];
  return stream ? stream->set_local_seats((uint8_t)localSeats) : [self notArmed];
}
- (chiaki_bridge::KakusanCommandOutcome)kakusanSetCapacity:(NSInteger)capacity {
  if (capacity < 1 || capacity > UINT8_MAX) {
    return [self invalidArgument];
  }
  const auto stream = [self currentStream];
  return stream ? stream->set_capacity((uint8_t)capacity) : [self notArmed];
}
- (chiaki_bridge::KakusanCommandOutcome)kakusanSetMediaTuning:(NSArray<NSNumber *> *)values {
  using std::chrono::milliseconds;
  constexpr NSUInteger fields = 9;
  if (values.count != fields) {
    return [self invalidArgument];
  }
  std::array<uint32_t, fields> numbers{};
  for (NSUInteger index = 0; index < fields; index++) {
    const long long value = values[index].longLongValue;
    if (value < 0 || value > UINT32_MAX) {
      return [self invalidArgument];
    }
    numbers[index] = (uint32_t)value;
  }
  libchiaking::kakusan::Tuning tuning;
  tuning.queue_age_min = milliseconds{numbers[0]};
  tuning.queue_age_max = milliseconds{numbers[1]};
  tuning.queue_age_round_trips = numbers[2];
  tuning.startup_grace = milliseconds{numbers[3]};
  tuning.drop_seconds_to_end = numbers[4];
  tuning.acknowledgement_timeout = milliseconds{numbers[5]};
  tuning.queue_bytes = std::size_t{numbers[6]} * 1024;
  tuning.queue_packets = numbers[7];
  tuning.keyframe_interval = milliseconds{numbers[8]};
  const auto stream = [self currentStream];
  return stream ? stream->tune_sharing(tuning) : [self notArmed];
}
- (chiaki_bridge::RememberOutcome)kakusanRememberDevice:(NSData *)identity
                                               nickname:(NSString *)nickname
                                                replace:(BOOL)replace {
  const auto stream = [self currentStream];
  if (!stream) {
    return chiaki_bridge::RememberOutcome::declined(chiaki_bridge::RememberDeclineFacts{
        libchiaking::kakusan::RememberRefusal::Kind::unknown_device, std::nullopt});
  }
  return stream->remember_device([CNLiveVideoPlayer bytesOf:identity], nickname.UTF8String ?: "",
                                 replace);
}
- (void)startKakusanGuestWithInvitation:(NSString *)invitation
                             completion:
                                 (void (^)(const chiaki_bridge::GuestOutcome *outcome))completion {
  NSAssert(NSThread.isMainThread, @"Surface lifecycle must be on main");
  NSData *block = [invitation dataUsingEncoding:NSUTF8StringEncoding];
  if (_phase.load() != CNPlayerIdle || !block.length) {
    const auto outcome = chiaki_bridge::GuestOutcome::declined(
        libchiaking::kakusan::Refusal::Kind::invalid_argument);
    completion(&outcome);
    return;
  }
  _kakusanArmed = NO;
  _kakusanSession.fetch_add(1);
  _restRefused = NO;
  chiaki_bridge::Stream *stream = [self openStream];
  _requestedHeight = 0;
  _requestedFPS = 0;
  self.sourceFrameRate = 60;
  _requestedBitrate = 0;
  _requestedHEVC = NO;
  _requestedHDR = NO;
  _route = CNStreamRouteUnknown;
  _routeConsole = CNStreamConsoleUnknown;
  _startedAt = CFAbsoluteTimeGetCurrent();
  [self resetFeedbackSlots];
  _phase.store(CNPlayerRunning);
  const BOOL forcesPortGuessing = _portGuessingForced;
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INTERACTIVE, 0), ^{
    self->_encodedDecoder = [[CNLiveEncodedVideo alloc] initWithHEVC:NO];
    const chiaki_bridge::GuestOutcome outcome = stream->join_kakusan(
        std::string_view{static_cast<const char *>(block.bytes), block.length}, forcesPortGuessing);
    NSString *diagnostics = [CNLiveVideoPlayer stringOf:outcome.diagnostics()];
    [self concludeStream:diagnostics
                    then:^{
                      completion(&outcome);
                    }];
  });
}
- (chiaki_bridge::KakusanCommandOutcome)kakusanGuestEnterCode:(NSString *)code {
  NSData *digits = [code dataUsingEncoding:NSASCIIStringEncoding];
  if (!digits.length) {
    return [self invalidArgument];
  }
  const auto stream = [self currentStream];
  return stream ? stream->enter_host_code(
                      std::string_view{static_cast<const char *>(digits.bytes), digits.length})
                : [self notArmed];
}
- (chiaki_bridge::KakusanCommandOutcome)kakusanGuestLeave {
  const auto stream = [self currentStream];
  return stream ? stream->leave_kakusan() : [self notArmed];
}
- (void)stop {
  [self stopWith:^(chiaki_bridge::Stream &stream) {
    stream.cancel();
  }];
}
- (void)stopForSleep {
  [self stopWith:^(chiaki_bridge::Stream &stream) {
    stream.stop_for_sleep();
  }];
}
- (void)stopWithRest {
  [self stopWith:^(chiaki_bridge::Stream &stream) {
    static_cast<void>(stream.stop_with_rest(false));
  }];
}
- (void)stopForSleepWithRest {
  [self stopWith:^(chiaki_bridge::Stream &stream) {
    static_cast<void>(stream.stop_with_rest(true));
  }];
}
- (void)stopWith:(void (^)(chiaki_bridge::Stream &stream))request {
  [_frameInterpolation stop];
  _lock.lock();
  CNControllerHapticsRenderer *renderer = _hapticsRenderer;
  _hapticsRenderer = nil;
  video::Exclusive<chiaki_bridge::HapticAudio> audio = std::move(_hapticAudio);
  _hapticAudioPhase = CNHapticAudioClosed;
  _hapticAudioRequest++;
  _hapticReports = nil;
  _hapticRoute = CNHapticRouteNone;
  [self publishHapticPathLocked];
  os_unfair_lock_lock(&_hapticRumbleLock);
  _hapticRumble.reset();
  os_unfair_lock_unlock(&_hapticRumbleLock);
  _lock.unlock();
  CNPlayerPhase running = CNPlayerRunning;
  if (_phase.compare_exchange_strong(running, CNPlayerStopping)) {
    chiaki_bridge::Stream *stream = [self currentStream].get();
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INTERACTIVE, 0), ^{
      const auto current = [self currentStream];
      if (current && current.get() == stream) {
        request(*current);
      }
    });
  }
  [renderer stop];
  [self closeHapticAudio:std::move(audio)];
}
- (void)closeHapticAudio:(video::Exclusive<chiaki_bridge::HapticAudio>)audio {
  if (!audio) {
    return;
  }
  const auto closing =
      std::make_shared<video::Exclusive<chiaki_bridge::HapticAudio>>(std::move(audio));
  dispatch_async(_hapticAudioQueue, ^{
    closing->reset();
  });
}
- (void)openHapticAudioForDevice:(uint32_t)device request:(uint64_t)request {
  dispatch_async(_hapticAudioQueue, ^{
    BOOL ready = chiaki_bridge::AudioOutputs::dualsense_ready();
    video::Exclusive<chiaki_bridge::HapticAudio> audio;
    if (ready) {
      if (auto opened = chiaki_bridge::HapticAudio::open()) {
        audio = video::Exclusive<chiaki_bridge::HapticAudio>(
            std::make_unique<chiaki_bridge::HapticAudio>(std::move(*opened)));
      }
    }
    if (!ready) {
      self->_hapticAudioNotReady.fetch_add(1, std::memory_order_relaxed);
    } else if (audio) {
      self->_hapticAudioOpened.fetch_add(1, std::memory_order_relaxed);
    } else {
      self->_hapticAudioFailed.fetch_add(1, std::memory_order_relaxed);
    }
    self->_lock.lock();
    BOOL current = self->_hapticAudioRequest == request && self->_hapticAudioDevice == device &&
                   self->_hapticAudioPhase == CNHapticAudioOpening;
    if (current) {
      self->_hapticAudioPhase = audio ? CNHapticAudioReady : CNHapticAudioClosed;
      std::swap(self->_hapticAudio, audio);
    }
    self->_lock.unlock();
  });
}
- (void)dealloc {
  [_hapticsRenderer stop];
}
@end
