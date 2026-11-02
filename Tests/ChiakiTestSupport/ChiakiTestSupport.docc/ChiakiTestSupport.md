# ``ChiakiTestSupport``

Fixtures and hosted-window helpers shared by the test targets.

## Overview

``TestEnvironment`` reports facts about the machine tests run on, such as whether a window server is
available, so suites that open real windows can be skipped in headless runs. ``MenuFocusHarness`` hosts a
SwiftUI view in a real window through ``MenuFocusHostingView`` and drives it with the shared navigator from
``MenuFocusTestEnvironment``, using ``StandaloneMenuInputPolicy`` in place of the app's playback policy, and
``RecordingControllerNavigation`` in place of the app's input services.
``KakusanFixture`` builds Kakusan ids, keys, blocks and host attempts driven to a chosen
``KakusanHostStage``.

## Topics

### Environment

- ``TestEnvironment``

### Controller focus

- ``MenuFocusHarness``
- ``MenuFocusHostingView``
- ``MenuFocusRoot``
- ``MenuFocusTestEnvironment``
- ``StandaloneMenuInputPolicy``
- ``RecordingControllerNavigation``
- ``testNavigator``
- ``testControllerNavigation``

### Kakusan

- ``KakusanFixture``
- ``KakusanHostStage``

### Streams

- ``ChiakiModels/RenderStatistics``
