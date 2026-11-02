# ``ChiakiModels``

Pure value types shared by every layer of chiaki-ng: identifiers, secrets, workflow state machines and store
protocols.

## Overview

`ChiakiModels` depends only on Foundation, CoreGraphics geometry and Synchronization. It never imports
SwiftUI, AppKit, UIKit, The Composable Architecture, GRDB or any C or C++ module, so every other target can
use its types without inheriting a framework or the C++ interoperability mode.

## Topics

### Identity

- ``AccountID``
- ``HardwareID``
- ``ProfileID``
- ``ConsoleID``
- ``UUIDIdentifier``
- ``ProductID``
- ``CloudService``
- ``ConsoleDeviceUID``
- ``OperationID``

### App

- ``AppIdentity``
- ``HostProcess``
- ``UserData``
- ``UserDataArgument``
- ``DatabaseOpening``
- ``DatabaseOpenFailure``

### Consoles

- ``ConsoleKind``
- ``ConsoleFirmware``
- ``ConsoleNameSource``
- ``StoredConsole``
- ``RegistrationFlow``
- ``RegistrationFailure``

### Pairing

- ``PairingFlow``
- ``PairingAttempt``
- ``PairingTarget``
- ``AccountConsoleTarget``
- ``PairingRequest``
- ``PairingCredentials``
- ``PairedConsole``
- ``PairingFailure``
- ``InternetPairingStage``
- ``PairingProgress``
- ``PairingStep``
- ``StoredPairing``

### Progress

- ``ProgressWait``
- ``ProgressWaitReason``
- ``OperationProgressText``

### Settings

- ``SettingKeys``
- ``DeveloperSettings``
- ``DeveloperSettingsError``
- ``TakionTarget``
- ``InterfaceSettings``
- ``LibraryRailEdge``
- ``StreamDiagnosticsAppearance``
- ``LogLevel``
- ``LogSettings``
- ``InternetConnectionSettings``
- ``InternetConnectionSettingsFailure``
- ``PlayStationAccessibilitySettings``
- ``PlayStationAccessibilityDefaults``
- ``CloudPictureSettings``
- ``PictureAdjustments``
- ``PictureSettings``
- ``PictureSettingsError``
- ``PresentationFrameRate``
- ``StreamProfile``
- ``UpscaledOutput``
- ``VideoFit``
- ``VideoFitMode``
- ``VideoFrame``
- ``VideoUpscaler``
- ``ConsoleLeaveAction``
- ``ConsolePowerSettings``
- ``StreamExitAction``
- ``StreamExitOutcome``
- ``KakusanMediaTuning``
- ``KakusanSettings``
- ``KakusanTuningDraft``
- ``SaveablePhase``
- ``SliderAdjustment``
- ``AudioOutputKind``
- ``SoundRendering``
- ``SoundSettings``
- ``SoundSettingsError``
- ``SoundTarget``
- ``SpatialAudio``
- ``StreamMedia``

### Stream

- ``StreamOutcome``
- ``StreamEndReport``
- ``CloudLaunchRefused``
- ``PlaybackFailure``
- ``ConsoleKeyboard``
- ``ConsoleKeyboardCommand``
- ``ConsoleKeyboardEvent``
- ``ConsoleKeyboardPhase``
- ``ConsoleKeyboardSession``
- ``ConsoleKeyboardSignal``
- ``MicrophoneFailure``
- ``MicrophoneMachine``
- ``MicrophoneProcessing``

### Launch

- ``LaunchConsoleReference``
- ``LaunchDisplay``
- ``LaunchRequest``
- ``LaunchRequestError``
- ``LaunchRequestParser``
- ``LaunchRoute``
- ``LaunchStream``
- ``LaunchStreamExit``
- ``ExitWatch``

### Library

- ``LibraryActivity``
- ``ConsoleShelfLoad``
- ``LibraryFocusEntry``
- ``LibraryContentFocus``
- ``CloudLibraryFocus``
- ``ArtworkBox``
- ``GameDetailMedia``

### Cloud grid

- ``CloudGridShape``
- ``CloudGridFit``
- ``CloudGridMetrics``
- ``CloudGridMove``
- ``CloudGridStop``
- ``CloudGridNavigation``
- ``CloudPageDot``
- ``CloudPageDots``
- ``CloudPageJump``
- ``CloudPageControl``
- ``CloudPageSwipe``
- ``CloudPageHold``

### Input

- ``ButtonChordDetector``
- ``ButtonLayout``
- ``ControllerButtonCaptureState``
- ``ControllerDevice``
- ``ControllerFamily``
- ``ControllerLightChanges``
- ``ControllerLightLedger``
- ``ControllerLightPlan``
- ``ControllerLightTarget``
- ``ControllerLightbar``
- ``ControllerLightbarSwatch``
- ``ControllerLightbars``
- ``ControllerMotion``
- ``ControllerPreferences``
- ``ControllerState``
- ``ControllerTouch``
- ``ControllerTouchSlots``
- ``ControllerTriggerStates``
- ``ControlsConfiguration``
- ``DeviceOrientation``
- ``HDRumblePacer``
- ``HDRumbleTone``
- ``HapticFeedback``
- ``HapticOutput``
- ``InputBinding``
- ``InputFailure``
- ``InputMapper``
- ``InputPreset``
- ``InputSource``
- ``KeyChord``
- ``KeyboardMode``
- ``MotionSource``
- ``PhysicalTouchpad``
- ``PlayStationControl``
- ``RememberedController``
- ``RumbleLevel``
- ``RumbleMix``
- ``ShortcutModifiers``
- ``StickGyro``
- ``StickGyroControl``
- ``StickGyroMode``
- ``StickGyroPose``
- ``StickRamp``
- ``StreamMenuShortcut``
- ``TouchButton``
- ``TouchpadArbiter``
- ``TouchpadRegion``
- ``TouchpadShortcut``
- ``TouchpadSource``
- ``TouchpadSurface``
- ``TouchpadTiming``
- ``VirtualGamepad``
- ``VirtualGamepadPresence``
- ``VirtualTouchpad``

### Couch

- ``CouchFailure``
- ``CouchLights``
- ``CouchSessionEvent``

### Kakusan

- ``KakusanAdmission``
- ``KakusanApproval``
- ``KakusanAttemptOutcome``
- ``KakusanBlock``
- ``KakusanBlockAdvice``
- ``KakusanBlockFile``
- ``KakusanBuild``
- ``KakusanCode``
- ``KakusanCodeEntry``
- ``KakusanCommandOutcome``
- ``KakusanControl``
- ``KakusanControlGrid``
- ``KakusanCountdown``
- ``KakusanError``
- ``KakusanFingerprint``
- ``KakusanGridStep``
- ``KakusanGuestConfiguration``
- ``KakusanGuestControls``
- ``KakusanGuestEvent``
- ``KakusanGuestHost``
- ``KakusanGuestID``
- ``KakusanGuestInput``
- ``KakusanGuestJoin``
- ``KakusanGuestOutcome``
- ``KakusanGuestPhase``
- ``KakusanGuestStream``
- ``KakusanGuestVideo``
- ``KakusanHostAttempt``
- ``KakusanHostClaim``
- ``KakusanHostCommand``
- ``KakusanHostConfiguration``
- ``KakusanHostEvent``
- ``KakusanStreamEvent``
- ``KakusanHostInput``
- ``KakusanHostMilestone``
- ``KakusanHostNotice``
- ``KakusanHostPhase``
- ``KakusanIdentity``
- ``KakusanIdentityHint``
- ``KakusanInvitation``
- ``KakusanInvitationPreview``
- ``KakusanInvitationSummary``
- ``KakusanInviteControls``
- ``KakusanLeavePrompt``
- ``KakusanPeer``
- ``KakusanPublicKey``
- ``KakusanReason``
- ``KakusanRecognition``
- ``KakusanRememberResult``
- ``KakusanRemotePlayer``
- ``KakusanReplyImport``
- ``KakusanSeatGrant``
- ``KakusanSeatSnapshot``
- ``KakusanSessionState``
- ``KakusanSettingsError``
- ``KakusanStateChange``
- ``KakusanTransition``
- ``KakusanVerification``

### Notifications

- ``PSNAlert``
- ``PSNMessageAlert``
- ``PSNPartyAlert``
- ``PSNConversation``
- ``PSNChatMessage``
- ``PSNChatThread``
- ``PSNMessagesFailure``
- ``PSNAlertSettings``
- ``PSNAlertGate``
- ``CloudGameInvitation``
- ``CloudInvitationFailure``
- ``PSNFriend``
- ``OwnGameSession``
- ``SessionLink``
- ``InvitationTarget``

### Network

- ``NatType``
- ``NatTypeFailure``

### Trophies

- ``TrophySummary``
- ``TrophyCounts``
- ``TrophyGrade``
- ``TrophyTitle``
- ``TrophyPlatform``
- ``TrophyGroup``
- ``PSNTrophy``
- ``TrophyProgress``
- ``TrophyRarity``
- ``TitleTrophies``
- ``PSNTrophiesFailure``

### Cloud

- ``CloudBandwidthReport``
- ``CloudDatacenterConnection``
- ``CloudDatacenterLaunchOffer``
- ``CloudDatacenterMeasurement``
- ``CloudDatacenterPingRow``
- ``CloudDatacenterSelection``
- ``CloudDatacenterService``
- ``CloudDatacenterSettings``
- ``CloudSavedBandwidth``
- ``CloudLaunchRequest``
- ``CloudLaunchDecision``
- ``CloudLaunchClearanceEvent``
- ``CloudPlaybackFailure``
- ``CatalogFailure``
- ``CloudLibraryFetchState``
- ``CloudStatusSnapshot``
- ``CloudStatusFailure``
- ``CloudAccountScope``
- ``CloudCatalogEvidence``
- ``CloudAvailability``
- ``CloudGameAccess``
- ``CloudOtherVersion``
- ``CloudSystemUIState``

### Stores

- ``ConsoleStoring``
- ``ConsoleStoreFailure``
- ``SavedConsoles``

### Secrets

- ``SecretBytes``
- ``PairingPIN``

### Encoding

- ``Hex``

### Time

- ``Timestamp``
