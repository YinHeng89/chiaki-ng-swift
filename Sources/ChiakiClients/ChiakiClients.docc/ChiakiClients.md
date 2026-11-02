# ``ChiakiClients``

The dependency clients features use to reach the core and persistence.

## Overview

There is one client per context. Its `testValue` reports an issue when a test calls an operation it did not override.
This target holds the interfaces only and builds without C++ interoperability; the live values are in
`ChiakiClientsLive`, which only the app links. Clients return `ChiakiModels` types only, so a feature never
sees a C, C++ or GRDB type. Failures come back as a `Result` with a typed model failure, which a feature sends
back into its reducer tagged with the operation id that started the work.

``ConsolesClient`` pairs consoles, reads and edits the saved pairings, shares the local-network scan, wakes
consoles, keeps the login PINs and launches recently played titles. ``NetworkClient`` checks the network and
sends the few HTTP requests the core does not make, such as an account's avatar download.

``StreamSessionClient`` starts console, cloud and guest streams and reaches the live player: the stream menu's
tuning, the brightness marker, light measurement, the diagnostics overlay, the couch's seats and controllers and
the microphone. It also lists and joins game invitations, invites friends and saves PS5 cloud captures. Its live
implementation, with the lease and session types it runs on, is in `ChiakiClientsLive`.

``KakusanClient`` hosts and joins shared sessions, reads this device's identity and manages remembered
devices through the stream player's Kakusan entry points; the desks that meet the console and guest streams
are in `ChiakiClientsLive`. ``KakusanClient/useStunServers`` passes the user's own STUN servers to the core; an empty list leaves the
choice to the core.

The same client plays the guest's stream through ``StreamSessionClient`` and loads and saves the Kakusan
preferences. A build made with `CHIAKI_KAKUSAN=0` uses ``KakusanClient/unavailable`` as the live client, which
refuses hosting and joining and remembers no device.

``ControllerNavigation`` is how views see the controller that drives menus: its glyph family, whether the stream
menu has it, and button capture for bindings. The app's input services conform; features read it from the
environment. ``CatalogClient`` reads the cloud catalog, draws its artwork, reads and clears the core's caches, explains
entitlements and reads the time on the PlayStation Network servers for release countdowns; the app also supplies
it to views through the environment. ``PlatformClient`` reaches the app's lifecycle, its window, the pasteboard,
shared and saved files and the system's alerts.

## Topics

### Streams

- ``StreamSessionClient``
- ``StreamStatisticsSample``
- ``StreamPlayer``
- ``PlayerSignal``

### Consoles

- ``ConsolesClient``

### Kakusan

- ``KakusanClient``

### Cloud

- ``PSNMessagesClient``
- ``PSNTrophiesClient``
- ``CloudClient``

### Settings

- ``SettingsClient``

### Network

- ``NetworkClient``
- ``HTTPResponse``

### Input

- ``ControllersClient``
- ``ControllerNavigation``

### Catalog

- ``CatalogClient``

### Platform

- ``PlatformClient``
