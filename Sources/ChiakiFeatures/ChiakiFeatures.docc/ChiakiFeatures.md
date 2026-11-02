# ``ChiakiFeatures``

The TCA features and their views: reducers that own a screen's state and effects, built on `ChiakiModels`
workflows and `ChiakiClients` dependencies, without C++ interoperability.

## Overview

A feature's state holds its finite state machine from `ChiakiModels`; its reducer turns view intents into
machine transitions and client calls, tags every asynchronous completion with the operation id that started
it, and reports upward only through its `Delegate` actions. Every feature keeps its views here; a view reaches
the controller layer only through the ``SwiftUICore/EnvironmentValues/controllerNavigation`` and
``SwiftUICore/EnvironmentValues/virtualGamepadLink`` values the app supplies, and shows video through
``StreamSurfaceView`` over the player's `ChiakiModels/StreamSurface`.

``RootFeature`` owns the app: a `Route` for the screen on show (welcome, sign-in, library, adding and pairing a
console, a stream, joining someone's Kakusan) and a presented `Destination` for settings, the console
editor and alerts. App data that outlives a screen, such as the accounts, the console catalog, discovery and
the stream session, lives in root state. The stream sits in ``RootFeature`` as a plain ``StreamFeature``
property rather than inside its route, because the session keeps closing after its screen is left.

The on-screen gamepad for touch play also lives in root state, as ``VirtualGamepadFeature``. The root view hands
its store to the stream's views, and the feature publishes every pad change into the ``VirtualGamepadLink``,
where the app's input takes it each frame without reaching into the store; a press that comes and goes between
two frames is latched there and every press is held for a short minimum, so the console still samples it.

``StreamFeature`` plays console, cloud and guest streams through one session machine and one ``StreamView``.
It arms Kakusan hosting when a console stream starts. ``StreamMenuReducer`` runs the in-stream menu through
its `Navigation` machine, and ``CouchReducer`` seats extra local and remote players with
``CouchControlsFeature`` presented over the stream.

``LibraryFeature`` is the home screen: console shelves, recently played titles and the PS Cloud library from
``CloudLibraryFeature``. ``SettingsFeature`` holds every settings pane and mounts only the one selected.

``AccountsFeature`` and ``ConsoleCatalogFeature`` hold the accounts and saved consoles that the app root shares
with every screen, and ``LifecycleFeature`` reacts to sleep, wake and quit. ``SignInFeature`` and
``AccountIDEntryFeature`` add an account. ``PersistedSettingFeature`` loads one setting and saves every
accepted edit, and ``SettingsRoute`` names the selected settings pane.

``PairingFeature`` pairs one console. It is the app root's `pairing` route, which starts an internet target
with ``PairingFeature/Action/start`` and reacts to ``PairingFeature/Action/Delegate``.

``KakusanHostFeature`` hosts Kakusan on a console stream. The stream forwards its lifecycle as
``KakusanHostFeature/Action/armed`` and ``KakusanHostFeature/Action/disarmed`` and nothing else; the
feature arms through `KakusanClient`, presents ``KakusanInviteFeature`` and ``KakusanRememberFeature``
as destinations, and asks the couch for seats through its delegate. ``KakusanSettingsFeature`` reuses the
remember feature to rename a remembered device.

## Topics

### Root navigation

- ``RootFeature``
- ``RootView``
- ``EntryScreen``
- ``EntryFocusGraph``
- ``RootConfirmation``
- ``AppAlertPresentation``

### Pairing

- ``PairingFeature``
- ``PairingFailureMessage``
- ``PairingView``

### Kakusan

- ``KakusanHostFeature``
- ``KakusanInviteFeature``
- ``KakusanRememberFeature``
- ``KakusanSettingsFeature``
- ``KakusanModal``
- ``KakusanGuestFeature``
- ``KakusanGuestView``
- ``KakusanHostView``
- ``KakusanSettingsView``

### Notifications

- ``PSNAlertsFeature``
- ``AlertsPanel``
- ``ConversationsFeature``
- ``ConversationFeature``

### Library

- ``LibraryFeature``
- ``LibraryView``
- ``LibraryRail``
- ``ConsoleShelfView``
- ``CloudSearchFeature``
- ``LibraryDiscovery``
- ``GameDetailFeature``

### Trophies

- ``TrophiesFeature``

### Accounts

- ``AccountsFeature``
- ``AccountsFailureMessage``
- ``SignInFeature``
- ``SignInView``
- ``AccountSignInPanel``
- ``SignInWebView``
- ``SignInPageViews``
- ``AccountIDEntryFeature``
- ``AccountIDEntryView``
- ``ProfileFeature``
- ``AccountControls``
- ``WelcomeView``

### Consoles

- ``ConsoleCatalogFeature``
- ``ConsoleEditorFeature``
- ``FlowTitle``
- ``FlowPrimaryButton``
- ``FlowSecondaryButton``
- ``AddConsoleFeature``
- ``AccountConsolesFeature``
- ``DiscoveryFeature``
- ``AutoConnectFeature``
- ``WakeResumeFeature``
- ``ConsoleEditor``
- ``RecentlyPlayedReducer``
- ``TitleLaunchFeature``
- ``ConsoleArtReducer``
- ``ConsoleCard``

### App lifecycle

- ``LifecycleFeature``

### Settings

- ``SettingsFeature``
- ``SettingsView``
- ``SettingsPanelPresentation``
- ``ControlsSettingsFeature``
- ``PersistedSettingFeature``
- ``NatTypeFeature``
- ``NatTypeSettingsView``
- ``SettingsRoute``
- ``SettingsCard``
- ``SettingsLayout``
- ``SettingsPageTitle``
- ``SettingsPersistenceBanner``
- ``SettingsRow``
- ``CachesReducer``
- ``EntitlementsReducer``
- ``RequestsReducer``
- ``TokensReducer``
- ``NetworkSettingsFeature``
- ``SoundSettingsFeature``
- ``DeveloperSettingsFeature``

### App

- ``AppVersion``
- ``AppIcon``

### Launch requests

- ``LaunchFeature``
- ``LaunchFlow``
- ``LaunchFailure``

### PS Cloud library

- ``CloudLibraryView``
- ``CloudGameDetail``
- ``CloudLibraryFeature``
- ``CloudStatusFeature``
- ``CloudGameActions``
- ``CloudLaunchChecks``

### Streaming

- ``StreamFeature``
- ``StreamView``
- ``StreamNavigationMirror``
- ``StreamSurfaceView``
- ``StreamFailureMessage``
- ``StreamTarget``
- ``StreamChromeReducer``
- ``StreamDiagnosticsReducer``
- ``StreamTelemetry``
- ``MicrophoneReducer``

### Stream menu and couch play

- ``StreamMenuReducer``
- ``StreamMenuOverlay``
- ``CouchReducer``
- ``CouchControlsFeature``
- ``CouchSeats``
- ``StreamPlayersPanel``
- ``InviteFriendsFeature``

### Controller input

- ``ControllerGlyphs``
- ``VirtualGamepadFeature``
- ``VirtualGamepadLink``
- ``VirtualTouchpadModel``
