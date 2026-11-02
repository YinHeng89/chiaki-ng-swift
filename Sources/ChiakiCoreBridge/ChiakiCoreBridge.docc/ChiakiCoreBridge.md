# ``ChiakiCoreBridge``

The Swift face of the C++ streaming core: opening it over the app's stores, and every core call the clients
make for consoles, pairing, accounts, the cloud catalog, Kakusan devices and diagnostics.

## Overview

`ChiakiCoreBridge` is compiled with C++ interoperability and talks to the Swift-facing C++ types in
`lib/bridge/include/chiaki_bridge` through the `ChiakiBridge` module. Everything it returns is a
`ChiakiModels` type, so clients and features never see a C or C++ type.

``CoreSession/open(catalog:consoles:credentials:datacenters:devices:)`` wraps the four persisted stores in one
`CoreStoreGateway` from `ChiakiPersistence` and hands it to the C++ adapters in `ChiakiStoreAdapters`, so the
core reads and writes consoles, credentials, datacenter measurements and Kakusan devices through Swift
persistence. Only one session is open at a time.

Each bridge wraps one area of the core. ``PairingBridge/pair(_:progress:)`` runs one pairing on a background
queue, forwards each progress report, cancels the core attempt when the calling task is cancelled, and turns
the outcome into a `PairedConsole` or a typed `PairingFailure`. ``UsersBridge`` signs accounts in with an
NPSSO that is wiped when the attempt ends. ``CoreCancellation`` is the stop flag the core checks while one
operation runs.

## Cloud invitation commands

``GameInvitationsBridge/join(account:sessionID:)`` reads the player session's
`tokenizedPlayerGameIntent`, finds the account's cloud console, and asks the core to post a
`sendGameIntent` command through cloud-assisted navigation. It waits for the command result and
preserves cancellation and failure reasons. Command completion means the console processed the
request; it does not independently verify membership inside the game.

The command carries `cronosDuid` and `tokenizedPlayerGameIntent`; it does not use the experimental
Takion invitation deep links. Sending invitations to other players, through
`POST /v1/playerSessions/{sessionId}/invitations`, remains a separate operation whose payload and token
permissions need validation.

## Topics

### Core

- ``CoreSession``
- ``CoreOpenFailure``
- ``CoreCancellation``
- ``CoreUnanswered``
- ``RememberedConsoles``

### Consoles and pairing

- ``ConsoleBridge``
- ``ConsoleFactsReader``
- ``DiscoveryBridge``
- ``PairingBridge``
- ``AccountConsolesBridge``
- ``ConsoleTitlesBridge``

### Accounts

- ``UsersBridge``
- ``CredentialsBridge``

### Cloud catalog and caches

- ``CatalogBridge``
- ``CatalogUnanswered``
- ``TitleChecksBridge``
- ``CloudLaunchClearance``
- ``CloudClearedLaunch``
- ``CachesBridge``
- ``CoreCacheEntry``
- ``CoreCacheID``
- ``CoreCacheSummary``
- ``CoreImageCalls``

### Streams

- ``GameInvitationsBridge``
- ``PSNMessagesBridge``
- ``PSNTrophiesBridge``
- ``SessionSharingBridge``
- ``NatTypeBridge``
- ``StreamOutcomeReader``
- ``OperationProgressReader``
- ``StreamStatisticsReader``
- ``CloudNoticeReader``
- ``SeatRefusalReader``
- ``ControllerSampleWriter``

### Kakusan

- ``KakusanDevicesBridge``
- ``KakusanEventReader``
- ``KakusanCommandReader``
- ``KakusanGuestEnd``

### Diagnostics

- ``HTTPCallsBridge``
