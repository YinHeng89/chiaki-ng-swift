# ``ChiakiNG``

The chiaki-ng app: its composition root, the controller layer and the live stream glue over the native player.

## Overview

``ChiakiNGMain`` opens the app's data store and reads the command line: it prints the registered consoles for
`--list`, rejects bad arguments, or builds one ``AppComposition`` and starts ``ChiakiNGApp`` over it with any
launch request. ``AppComposition`` is the composition root. It builds every live dependency once, including the
one ``InputServices``, and installs them before the app's `RootFeature` store reads any of them. The screens,
reducers and their views live in `ChiakiFeatures`; the app shows `RootView` and hands it the controller
navigation, the on-screen gamepad and the shared art caches through the environment.

``InputServices`` owns the controller layer: ``SDLInputCoordinator`` routes controller events between menus and
the stream, ``GameInputPipeline`` turns them into console states, ``ControllerLights``, ``MicrophoneLight`` and
``ControllerSystemGestureOwner`` drive the controllers' outputs, and the menu navigator answers its input
questions through ``PlaybackMenuInputPolicy``. Views see these services only as
`ChiakiClients/ControllerNavigation`.

``NativeStreamLauncher`` prepares a ``NativeStreamPlayer`` for each console, cloud or guest stream. Each player
builds its ``StreamInputSession`` with the ``StreamInputOptions`` the stream offers. ``StreamPlayers`` decides
who plays where through ``PlayerOneInput``, ``CouchSeatInput`` and ``KeyboardTouchOverlay``, and
its input poller applies each poll. They compose the focused input types (``PlayerOneController``,
``CouchSeatRouter``, ``HapticRouter``, ``RumbleDriver``, ``StreamKeyboardInput``,
``TouchpadInput``, ``MotionInput`` and ``LightbarController``) through one
``InputEnvironment`` over the app's input services.

``AccountSignInBrowser`` shows the account sign-in page and drives it with a controller.

## Topics

### App and composition root

- ``ChiakiNGMain``
- ``ChiakiNGApp``
- ``ChiakiApplicationDelegate``
- ``AppComposition``
- ``SystemPowerObserver``

### Launch requests

- ``LaunchWindowControl``
- ``LaunchCommandLine``

### Accounts

- ``AccountSignInBrowser``
- ``AccountSignInPages``

### Streaming

- ``NativeStreamLauncher``
- ``ConsoleStreamLauncher``
- ``CloudStreamLauncher``
- ``GuestStreamLauncher``
- ``NativeStreamPlayer``
- ``StreamPlayerControls``

### Input

- ``InputServices``
- ``StreamInputSession``
- ``StreamInputOptions``
- ``StreamPlayers``
- ``InputEnvironment``
- ``PlayerOneInput``
- ``PlayerOneController``
- ``CouchSeatInput``
- ``CouchSeatRouter``
- ``KeyboardTouchOverlay``
- ``HapticRouter``
- ``RumbleDriver``
- ``StreamKeyboardInput``
- ``TouchpadInput``
- ``MotionInput``
- ``LightbarController``
- ``SDLInputCoordinator``
- ``SDLControllerBackend``
- ``GameInputPipeline``
- ``ControllerLights``
- ``MicrophoneLight``
- ``ControllerSystemGestureOwner``
- ``PlaybackMenuInputPolicy``
