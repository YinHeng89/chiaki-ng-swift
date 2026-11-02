# ``DesignSystem``

The tokens, shared controls and branding that give every chiaki-ng screen the same look.

## Overview

`DesignSystem` depends on `ChiakiModels`, `PlatformUI` and the bundled assets only. It never imports The
Composable Architecture, a client or a feature, and it knows nothing about controller focus: focus-aware
controls live in `MenuFocus`, which builds on these tokens.

Use the tokens instead of literals. ``Palette/accent`` is the one lime of the app, ``GlassPanel/Radius``
names the four corner radii a glass surface may have, ``Dimming`` names how far an overlay darkens what is
behind it, and ``ModalCard`` draws the chrome of every modal card.

## Topics

### Tokens

- ``Palette``
- ``AppGlass``
- ``GlassPanel``
- ``Dimming``
- ``AppMotion``

### Modals

- ``ModalCard``

### Controls

- ``AppScrollStyle``
- ``ScrollingText``
- ``QRCodeImage``

### Layout

- ``ScreenLayout``
- ``ScreenCanvas``
- ``TopChromeInset``

### Privacy

- ``StreamerMode``
- ``StreamerHiddenField``

### Controller hints

- ``ControllerGlyph``
- ``ControllerButton``
- ``ControllerPromptControl``
- ``ControllerGlyphResolver``
- ``ControllerGlyphLabel``
- ``ControllerPrompt``
- ``SliderAdjustmentPrompt``

### Branding

- ``ChiakiLogo``
- ``AmbientBackground``
- ``AmbientMotionState``
