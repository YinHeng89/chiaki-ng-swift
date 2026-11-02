#ifdef __cplusplus
#import <TargetConditionals.h>
#if TARGET_OS_OSX
#import <AppKit/AppKit.h>
typedef NSView CNPlatformView;
#else
#import <UIKit/UIKit.h>
typedef UIView CNPlatformView;
#endif
#import "RenderStatistics.h"
#import "VideoOptions.h"
#include "chiaki_bridge/catalog.hpp"
#include "chiaki_bridge/stream_facts.hpp"
NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, CNHapticRoute) {
  CNHapticRouteNone,
  CNHapticRouteCoreHaptics,
  CNHapticRouteUSBAudio,
  CNHapticRouteBluetoothReports,
  CNHapticRouteRumble
};

typedef BOOL (^CNHapticReportHandler)(const uint8_t *pcm, float gain);

typedef NS_ENUM(NSInteger, CNStreamCodec) {
  CNStreamCodecH264 = 0,
  CNStreamCodecHEVC = 1,
  CNStreamCodecHEVCHDR = 2
};

typedef NS_ENUM(NSInteger, CNStreamRoute) {
  CNStreamRouteUnknown = 0,
  CNStreamRouteLocal = 1,
  CNStreamRouteInternet = 2,
  CNStreamRoutePSNow = 3,
  CNStreamRoutePSCloud = 4
};

typedef NS_ENUM(NSInteger, CNStreamConsole) {
  CNStreamConsoleUnknown = 0,
  CNStreamConsolePS4 = 4,
  CNStreamConsolePS5 = 5
};

typedef NS_ENUM(NSInteger, CNCouchEvent) {
  CNCouchEventAnnounced = 0,
  CNCouchEventConfirmed = 1,
  CNCouchEventDropped = 2
};

typedef NS_CLOSED_ENUM(NSInteger, CNMicrophoneConnectState) {
  CNMicrophoneConnectStatePending = 0,
  CNMicrophoneConnectStateAccepted = 1,
  CNMicrophoneConnectStateRejected = 2
};

typedef NS_CLOSED_ENUM(NSInteger, CNSystemUIState) {
  CNSystemUIStateGame = 0,
  CNSystemUIStateOverlaid = 1,
  CNSystemUIStateBackground = 2
};

typedef NS_ENUM(NSInteger, CNKeyboardEvent) {
  CNKeyboardEventOpened = 0,
  CNKeyboardEventTextChanged = 1,
  CNKeyboardEventRemoteClosed = 2
};

typedef struct {
  NSInteger height;
  NSInteger fps;
  NSInteger bitrate;
  BOOL hevc;
  BOOL hdr;
  CNStreamRoute route;
  CNStreamConsole console;
  double streamSeconds;
} CNRequestedStream;

@interface CNDatacenterOffer : NSObject
@property(nonatomic, copy, readonly) NSString *name;
@property(nonatomic, readonly) NSInteger roundTripMilliseconds;
@property(nonatomic, readonly) BOOL highLatency;
@property(nonatomic, readonly) BOOL lowest;
@end

@interface CNLiveVideoPlayer : NSObject
@property(nonatomic, readonly) BOOL restRefused;
@property(nonatomic, copy, readonly, nullable) NSString *failureDiagnostics;
- (NSArray<NSDictionary<NSString *, id> *> *)takeDiagnosticLogs;
@property(nonatomic) BOOL captureAPI;
- (void)setTakionVersionsLocalPS4:(uint32_t)localPS4
                         localPS5:(uint32_t)localPS5
                            psNow:(uint32_t)psNow
                          psCloud:(uint32_t)psCloud;
- (void)setTakionNegotiationLocalPS4:(BOOL)localPS4
                            localPS5:(BOOL)localPS5
                               psNow:(BOOL)psNow
                             psCloud:(BOOL)psCloud;
- (void)setPortGuessingForced:(BOOL)forced count:(uint32_t)count;
- (NSArray<NSData *> *)takeAPICaptures;
@property(nonatomic, copy, nullable) void (^firstFramePresentedHandler)(void);
@property(nonatomic, copy, nullable) void (^displayProhibitedHandler)(BOOL);
@property(nonatomic, copy, nullable) void (^connectionWaitingHandler)(BOOL);
@property(nonatomic, copy, nullable) void (^playTimeLeftHandler)
    (NSInteger minutes, libchiaking::play::PlayTimeLimit limit);
@property(nonatomic, copy, nullable) void (^cloudNoticeHandler)
    (const libchiaking::play::CloudNotice *notice);
@property(nonatomic, copy, nullable) void (^recordingBannerHandler)
    (BOOL recording, NSString *elapsed);
@property(nonatomic, copy, nullable) void (^captureThumbnailHandler)
    (NSString *captureID, BOOL video, NSData *jpeg);
@property(nonatomic, copy, nullable) void (^captureUploadedHandler)
    (NSString *captureID, NSString *galleryID, NSString *extension, uint64_t size, BOOL video,
     NSString *created);
@property(nonatomic, copy, nullable) void (^loginPINRequestHandler)(BOOL);
@property(nonatomic, copy, nullable) void (^controllerPasscodeRequestHandler)(NSInteger, BOOL);
@property(nonatomic, copy, nullable) void (^couchEventHandler)
    (CNCouchEvent event, NSInteger pad, NSInteger detail);
@property(nonatomic, copy, nullable) void (^seatRefusedHandler)
    (const libchiaking::play::SeatRefusal *refusal);
@property(nonatomic) BOOL consoleTextEntryEnabled;
@property(nonatomic, copy, nullable) void (^keyboardEventHandler)
    (CNKeyboardEvent event, NSString *text);
@property(nonatomic, copy, nullable) void (^lightColorHandler)(NSInteger pad, NSInteger rgb);
@property(nonatomic) BOOL extendedFeedbackEnabled;
@property(nonatomic) double audioVolume;
/// The level party voice from the cloud service is mixed at, from 0 to 1; the game audio's volume
/// applies on top.
@property(nonatomic) double chatVolume;
@property(nonatomic, copy, nullable) NSString *audioOutputDevice;
@property(nonatomic) NSInteger audioBufferMilliseconds;
@property(nonatomic) BOOL audio3DEnabled;
@property(nonatomic) BOOL audioSpatialEnabled;
@property(nonatomic) BOOL videoSuspended;
@property(nonatomic) CNSystemUIState systemUIState;
- (BOOL)pressCreate:(NSInteger)press;
- (BOOL)joinInvitation:(NSString *)invitationID session:(NSString *)sessionID;
- (BOOL)openSavedData;
@property(nonatomic) NSInteger requestedAudioChannels;
@property(nonatomic) BOOL controllerSpeakerEnabled;
@property(nonatomic, readonly) BOOL controllerSpeakerWired;
@property(nonatomic) BOOL streamAudioDisabled;
@property(nonatomic) BOOL streamVideoDisabled;
@property(nonatomic) CNVideoUpscaler videoUpscaler;
@property(nonatomic) NSInteger targetOutputHeight;
@property(nonatomic) NSInteger sourceFrameRate;
@property(nonatomic) BOOL frameGenerationEnabled;
@property(nonatomic) CNVideoDiagnosticMode videoDiagnosticMode;
- (void)setLightMarkerX:(double)x y:(double)y;
@property(nonatomic) BOOL lightMarkerShown;
@property(nonatomic, readonly) CGPoint lightMarker;
@property(nonatomic) BOOL measuresLight;
- (void)setPictureBrightness:(float)brightness
                    contrast:(float)contrast
                  saturation:(float)saturation
                       gamma:(float)gamma
                      deband:(BOOL)deband;
@property(nonatomic, copy, nullable) void (^launchProgressHandler)
    (const libchiaking::play::LaunchProgress *progress, BOOL playing);
@property(nonatomic, copy, nullable) void (^connectProgressHandler)
    (const libchiaking::play::ConnectProgress *progress);
- (void)deliverLaunchProgress:(const libchiaking::play::LaunchProgress &)progress
                      playing:(BOOL)playing;
- (void)deliverConnectProgress:(const libchiaking::play::ConnectProgress &)progress;
@property(nonatomic, copy, nullable) NSString *cloudForcedDatacenter;
@property(nonatomic) BOOL cloudScreenReader;
@property(nonatomic) NSInteger cloudScreenReaderSpeed;
@property(nonatomic) NSInteger cloudScreenReaderVolume;
@property(nonatomic) NSInteger cloudTextSize;
@property(nonatomic) BOOL cloudBoldText;
@property(nonatomic) BOOL cloudHigherContrast;
- (void)updateCloudAccessibility;
@property(nonatomic) BOOL cloudStableQuality;
@property(nonatomic) BOOL consoleJustLeft;
@property(nonatomic) BOOL reconnectAfterDrop;
@property(nonatomic) BOOL cloudSelectDatacenterAtLaunch;
@property(nonatomic) NSInteger cloudDatacenterSelectTimeoutMilliseconds;
@property(nonatomic, copy, nullable) void (^cloudDatacentersHandler)
    (NSArray<CNDatacenterOffer *> *offers, NSInteger waitMilliseconds);
@property(nonatomic, copy, nullable) void (^cloudDatacenterSelectedHandler)
    (NSString *name, NSInteger rttMilliseconds, libchiaking::play::DatacenterChoice::How how);
@property(nonatomic, copy, nullable) void (^startAttemptHandler)(NSInteger attempt);
@property(nonatomic, copy, nullable) void (^reconnectingHandler)(NSInteger attempt);
@property(nonatomic, copy, nullable) void (^reconnectedHandler)(void);
@property(nonatomic, readonly) CNPlatformView *view;
@property(nonatomic, readonly) NSUInteger decodedFrames;
- (chiaki_bridge::StreamStatistics)streamStatistics;
- (CNSurfaceStatistics)surfaceStatistics;
- (CNRequestedStream)requestedStream;
@property(nonatomic, readonly, nullable) NSNumber *generatedFrames;
@property(nonatomic, copy, nullable) void (^setupProgressHandler)
    (libchiaking::play::ConnectStep step, NSInteger elapsedMilliseconds);
- (nullable instancetype)initWithShader:(NSString *)shader fsrcnnWeights:(NSData *)fsrcnnWeights;
- (BOOL)selectCloudDatacenter:(NSString *)name;
- (void)startConsoleForAccount:(NSData *)accountID
                    hardwareID:(NSData *)hardwareID
                  overInternet:(BOOL)overInternet
                           ps5:(BOOL)ps5
                        height:(NSInteger)height
                           fps:(NSInteger)fps
                       bitrate:(NSInteger)bitrate
                         codec:(CNStreamCodec)codec
                    completion:(void (^)(const chiaki_bridge::StreamOutcome *outcome))completion;
- (void)startCloudForAccount:(NSData *)accountID
                   productID:(NSString *)productID
                     psCloud:(BOOL)psCloud
                      height:(NSInteger)height
                     bitrate:(NSInteger)bitrate
                         hdr:(BOOL)hdr
            measureBandwidth:(BOOL)measureBandwidth
               clearedLaunch:(nullable const chiaki_bridge::ClearedLaunch *)clearedLaunch
                  completion:(void (^)(const chiaki_bridge::StreamOutcome *outcome))completion;
- (BOOL)setControllerButtons:(uint32_t)buttons
                          l2:(uint8_t)l2
                          r2:(uint8_t)r2
                       leftX:(int16_t)leftX
                       leftY:(int16_t)leftY
                      rightX:(int16_t)rightX
                      rightY:(int16_t)rightY;
- (BOOL)setControllerButtons:(uint32_t)buttons
                          l2:(uint8_t)l2
                          r2:(uint8_t)r2
                       leftX:(int16_t)leftX
                       leftY:(int16_t)leftY
                      rightX:(int16_t)rightX
                      rightY:(int16_t)rightY
                         pad:(NSInteger)pad;
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
                      touchY:(uint16_t)touchY;
- (BOOL)sendControllerSample:(chiaki_bridge::ControllerSample)sample pad:(NSInteger)pad;
- (BOOL)takeMotionReset;
- (NSInteger)takeMotionSettings;
- (BOOL)couchJoinPad:(NSInteger)pad
      controllerType:(uint8_t)controllerType
           accountID:(nullable NSData *)accountID;
- (BOOL)couchRemovePad:(NSInteger)pad;
- (BOOL)takeRumbleForPad:(NSInteger)pad left:(uint8_t *)left right:(uint8_t *)right;
- (nullable NSData *)controllerFeedback;
- (nullable NSData *)controllerFeedbackForPad:(NSInteger)pad;
- (BOOL)takeRumbleLeft:(uint8_t *)left right:(uint8_t *)right;
- (void)takeHapticRumbleLow:(float *)low high:(float *)high scale:(float)scale;
- (void)takeHapticRumbleLeft:(float *)left right:(float *)right scale:(float)scale;
- (void)consoleFeedbackIntensityHaptic:(uint8_t *)haptic trigger:(uint8_t *)trigger;
- (void)setControllerHapticGain:(float)hapticGain;
- (CNHapticRoute)configureControllerFeedbackDevice:(uint32_t)device
                                             route:(CNHapticRoute)route
                                        hapticGain:(float)hapticGain
                                           reports:(nullable CNHapticReportHandler)reports;
- (NSDictionary<NSString *, NSNumber *> *)controllerFeedbackDiagnostics;
- (void)submitLoginPIN:(NSString *)pin completion:(void (^)(BOOL accepted))completion;
- (BOOL)submitControllerPasscode:(NSString *)passcode pad:(NSInteger)pad;
@property(nonatomic, copy, nullable) void (^kakusanEventHandler)
    (const chiaki_bridge::KakusanEvent *event, NSString *_Nullable text);
- (chiaki_bridge::KakusanCommandOutcome)armKakusanHostWithCapacity:(NSInteger)capacity
                                                        localSeats:(NSInteger)localSeats;
- (void)disarmKakusanHost;
- (chiaki_bridge::KakusanCommandOutcome)inviteKakusanGuest;
- (chiaki_bridge::KakusanCommandOutcome)importKakusanReply:(NSString *)reply;
- (chiaki_bridge::KakusanCommandOutcome)kakusanEnterCode:(NSString *)code guestID:(NSData *)guestID;
- (chiaki_bridge::KakusanCommandOutcome)kakusanApproveGuestID:(NSData *)guestID
                                                          pad:(NSInteger)pad
                                               controllerType:(NSInteger)controllerType
                                                    accountID:(nullable NSData *)accountID;
- (chiaki_bridge::KakusanCommandOutcome)kakusanRemoveGuestID:(NSData *)guestID;
- (chiaki_bridge::KakusanCommandOutcome)kakusanSetLocalSeats:(NSInteger)localSeats;
- (chiaki_bridge::KakusanCommandOutcome)kakusanSetCapacity:(NSInteger)capacity;
- (chiaki_bridge::KakusanCommandOutcome)kakusanSetMediaTuning:(NSArray<NSNumber *> *)values;
- (chiaki_bridge::RememberOutcome)kakusanRememberDevice:(NSData *)identity
                                               nickname:(NSString *)nickname
                                                replace:(BOOL)replace;
- (void)startKakusanGuestWithInvitation:(NSString *)invitation
                             completion:
                                 (void (^)(const chiaki_bridge::GuestOutcome *outcome))completion;
- (chiaki_bridge::KakusanCommandOutcome)kakusanGuestEnterCode:(NSString *)code;
- (chiaki_bridge::KakusanCommandOutcome)kakusanGuestLeave;
- (BOOL)goHome;
- (BOOL)connectMicrophoneRequest:(uint32_t)request;
- (CNMicrophoneConnectState)microphoneConnectState:(uint32_t)request;
- (BOOL)setMicrophoneMuted:(BOOL)muted;
- (BOOL)sendMicrophoneFrame:(const uint8_t *)frame length:(NSUInteger)length;
- (NSDictionary<NSString *, NSNumber *> *)microphoneStatistics;
- (BOOL)setKeyboardText:(NSString *)text;
- (BOOL)acceptKeyboardText:(NSString *)text;
- (BOOL)rejectKeyboard;
- (BOOL)sendKeyboardModifiers:(uint8_t)modifiers leds:(uint8_t)leds keys:(NSData *)keys;
- (void)stop;
- (void)stopForSleep;
- (void)stopWithRest;
- (void)stopForSleepWithRest;
@end
NS_ASSUME_NONNULL_END

#endif
