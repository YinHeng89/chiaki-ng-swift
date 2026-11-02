# ``MenuFocus``

Controller and keyboard navigation for every chiaki-ng menu, sheet, overlay and prompt.

## Overview

`MenuFocus` turns navigation commands from a controller or the keyboard into focus moves, activations and
Back presses on SwiftUI views. It depends on `ChiakiModels`, `DesignSystem` and `PlatformUI` only, and it
never imports The Composable Architecture, a client or a feature.

The engine is an instance, not a singleton. The composition root creates one ``PlatformMenuNavigator``
(``AppKitMenuNavigator`` on macOS, `TouchMenuNavigator` on iOS), hands it a ``MenuInputPolicy`` that
describes what the host application allows, and injects it with ``SwiftUICore/View/menuNavigator(_:)``. Views
read it from the `menuNavigator` environment value. Both navigators share the pure ``FocusGeometry``, so
directional moves pick the same neighbour on every platform.

Views never register closures on global notification names. They declare handlers with
``SwiftUICore/View/menuHandlers(enabled:move:activate:modalActivate:back:)``, listen for commands with
``SwiftUICore/View/onMenuCommand(_:perform:)``, and block the content behind them with
``SwiftUICore/View/menuInputBlocking(_:prompt:)``.

Read <doc:ControllerNavigation> before building or changing any interactive view.

## Topics

### Essentials

- <doc:ControllerNavigation>
- ``MenuNavigator``
- ``AppKitMenuNavigator``
- ``MenuInputPolicy``
- ``MenuFocusDiagnostics``

### Handlers and commands

- ``MenuHandlerStack``
- ``MenuHandlerID``
- ``MenuHandlers``
- ``MenuCommand``
- ``MenuCommandRouter``
- ``MenuCommandEvent``
- ``MenuCommandSubscription``
- ``MenuCommandCode``
- ``MenuArrowKey``

### Blocking content behind a presentation

- ``MenuInputGate``
- ``MenuInputBlocking``

### Focus

- ``MenuMoveDirection``
- ``FocusGeometry``
- ``WindowFocus``
- ``PlaybackWindowControl``
- ``FocusRegionTracker``
- ``MenuButtonFocus``
- ``SelfManagedFocusScrolling``
- ``FlowTransition``

### Input mode

- ``InputMode``
- ``InputModeCenter``
- ``InputModeEnvironment``

### Focus highlight

- ``FocusHighlightShape``
- ``FocusHighlightOverlay``
- ``NativeFocusHighlight``
- ``InteractiveGrowth``
- ``GrowthLimit``
- ``ContainedFocusGlow``

### Controls

- ``FocusButton``
- ``GlassControlStyle``
- ``FocusableSegments``
- ``NativeMenuAnchorReference``
- ``NativeMenuAnchor``
- ``AccentCheckboxToggleStyle``

### Confirmations and dismissal

- ``AppConfirmation``
- ``AppConfirmationPresentation``
- ``AppConfirmationCard``
- ``DismissOnOutsideClick``

### On-screen keyboard

- ``ControllerKeyboardLayout``
- ``ControllerKeyboardPresentation``
- ``ControllerKeyboardSheet``
- ``ControllerOnScreenKeyboard``
