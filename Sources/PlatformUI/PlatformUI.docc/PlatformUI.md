# ``PlatformUI``

The small seam between SwiftUI code and AppKit or UIKit, so the UI targets compile for macOS and iOS
from one source.

## Overview

Each type names one platform concept once. On macOS the aliases resolve to AppKit types and on iOS to UIKit
types, so `DesignSystem`, `MenuFocus` and the app never write `#if os(macOS)` just to name a view, a window or
an image. ``PlatformViewRepresentable`` bridges one view type into SwiftUI on both platforms, and
``WindowAccessor`` reports the window a SwiftUI view lives in without taking part in hit testing.

## Topics

### Platform types

- ``PlatformView``
- ``PlatformWindow``
- ``PlatformScreen``
- ``PlatformImage``
- ``PlatformColor``

### Hosting platform views

- ``PlatformViewRepresentable``
- ``WindowAccessor``

### System services

- ``PlatformPasteboard``
- ``PlatformWorkspace``
- ``PlatformAccessibility``
