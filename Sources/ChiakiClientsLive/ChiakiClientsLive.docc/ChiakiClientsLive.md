# ``ChiakiClientsLive``

The live implementations of the `ChiakiClients` interfaces, over the core, the database and the platform.

## Overview

`ChiakiClients` declares each client with its test value; this target conforms the clients to
`DependencyKey` with their real implementations, and builds the clients that need the app's one open database
and core. It is built with C++ interoperability so it can reach `ChiakiCoreBridge`, and only the app links it:
features see the interfaces alone.

The live ``ChiakiClients/StreamSessionClient`` holds the one native lease in ``StreamLeases``, keyed by the
session's id, and runs each stream as a ``LiveStreamSession`` that owns the player and reports it through one
``PlayerEventRelay``. Player handlers become ordered events with no task per handler; once a session stops, its
relay is closed, so a late handler can never reach the input or the next session. The launchers that prepare the
native player live in the app target, conform to ``StreamLauncher`` and are installed at the composition root.

Kakusan hosting meets the console stream through ``KakusanHostDesk``: the host feature arms and disarms, the
console stream attaches its player, and whichever comes second binds them. Guest commands reach the running
guest stream through ``KakusanGuestDesk``, and ``KakusanDesks`` exposes both desks' operations to the live
client.

``AppDatabaseClient`` opens the app database for the one owner of the open database. ``ArtworkCache`` holds
decoded artwork for the artwork pipeline.

## Topics

### Persistence

- ``AppDatabaseClient``

### Accounts

- ``AccountService``
- ``AccountDiagnostic``
- ``InvitationsDiagnostic``

### Catalog

- ``ArtworkCache``
- ``CloudCatalogClient``
- ``CloudLibraryService``
- ``CloudStatusService``

### Consoles

- ``ConsoleNetworkLocality``
- ``ConsoleCatalogChanges``
- ``ConsoleLocationClient``
- ``DiscoveryClient``
- ``PSNConsoleClient``
- ``RecentlyPlayedService``
- ``RecentlyPlayedConsole``
- ``ConsoleTitlesTransport``

### Streaming

- ``StreamLauncher``
- ``StreamSessionOpener``
- ``LiveStreamSession``
- ``PlayerEventRelay``
- ``StreamLeases``
- ``KakusanHostDesk``
- ``KakusanGuestDesk``
- ``KakusanDesks``
- ``CloudCaptureSaver``
- ``MicrophoneInputDevices``
