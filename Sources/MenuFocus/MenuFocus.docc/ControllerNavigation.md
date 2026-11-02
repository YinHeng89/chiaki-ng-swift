# Controller navigation

The contract every interactive chiaki-ng view must meet so that it works with a controller as well as it
works with the pointer.

## Overview

A menu has controller navigation only when every contract below holds. It must work with a gamepad and with
the arrow, Return, Space, Escape and Tab keys. Most regressions came from one missing contract, usually
initial focus, focus after dismissal, or a neighbour that never learned a new control exists.

Per-screen focus graphs are specified by their hosted-window tests in `MenuFocusTests`.

## How input reaches a view

1. The host application turns the navigation controller's buttons into ``MenuCommand`` values: the four
   directions, `confirm`, `back`, `alternate`, `previous` and `next` for L1 and R1, `focusToolbar` for
   Triangle, `settings` for Options and `streamMenu` for the stream menu shortcut. Only the controller that
   drives navigation produces commands; seated couch controllers do not.
2. The injected ``MenuNavigator`` performs each command for the key window.
   - Alerts are handled first.
   - Directions go to the focus move handlers in its ``MenuHandlerStack``, newest first. When none returns
     `true`, the navigator synthesises an arrow key.
   - Confirm goes to modal activation handlers, then activation handlers, then a synthesised Space, or
     Return inside text and menus.
   - Back goes to back handlers, newest first. When none returns `true`, a synthesised Escape reaches
     ``SwiftUICore/View/onMenuExitCommand(perform:)`` and `.keyboardShortcut(.cancelAction)`.
   - Every other command is sent through the navigator's ``MenuCommandRouter``, tagged with its window.
     Views receive it with ``SwiftUICore/View/onMenuCommand(_:perform:)`` and call
     ``MenuCommandEvent/targets(_:)`` to act only for their own window.
3. Synthesised keys land on the focused SwiftUI view. ``FocusButton`` applies ``MenuButtonFocus``, which
   makes it focusable, activates it on Return and Space, and routes arrows to the `menuMove` environment
   closure, or to key view order when none is set.
4. Focus is drawn only while the navigator's ``InputModeCenter`` reports ``InputMode/controller``; pointer
   movement switches the highlight off. Never draw a custom focus ring. Use
   ``SwiftUICore/View/menuFocused(_:equals:)``, ``SwiftUICore/View/interactiveGrowth()``,
   ``SwiftUICore/View/nativeFocusHighlight()``, ``AccentCheckboxToggleStyle`` or ``FocusableSegments`` so the
   accent colour and input-mode rules stay consistent.

Synthesised events are tagged, and ``AppKitMenuNavigator/isControllerEvent(_:)`` recognises them. Code that
reads keyboard input must ignore them where keyboard customisation applies, and must leave the menu keys
alone in menus.

The application decides what the navigator may do through its ``MenuInputPolicy``: whether menu input is
accepted at all, which windows host a stream, and what Tab means in a stream window. `MenuFocus` itself
never knows about playback.

## The contracts

1. **Every control is a focus stop.** Use ``FocusButton`` with ``SwiftUICore/View/menuFocused(_:equals:)``.
   Toggles use ``AccentCheckboxToggleStyle``; segmented choices use ``FocusableSegments``. Menus use
   `.menuStyle(.button)` with ``SwiftUICore/View/glassControlStyle(_:)``. Text fields add
   `controllerKeyboard(title:text:isFocused:)` so Cross opens the on-screen keyboard; in a
   selection-driven modal the field is also one of the modal's stops. The only exception is a pointer-only
   affordance that duplicates something focus already does: build it from `SwiftUI.Button` with
   `.focusable(false)`.
2. **Initial focus lands the moment the view appears.** Own a ``MenuFocusState`` enum for the view and set
   the first item once the view is in a window, retrying for a few turns because SwiftUI drops requests made
   before the view is committed. Modals start on the safe choice so a stray Cross never destroys anything.
3. **Directions follow the visible layout and never dead-end silently.** Define the graph with `menuMove`
   closures or a move handler in ``SwiftUICore/View/menuHandlers(enabled:move:activate:modalActivate:back:)``.
   For an irregular graph prefer `moveGeometric(_:in:)` over hand-written tables. Every
   neighbour that should lead into the view learns about it, including when it is hidden.
4. **Confirm activates exactly the focused control.** An activation handler that remembers a target steps
   aside when another control actually holds focus. Confirm never repeats.
5. **Back always does the expected thing.** A sub-level returns to its parent control, a modal cancels, a
   root screen goes back a flow step or offers to quit. A handler acts only for its own window and returns
   `false` when it has nothing to do, so Escape still reaches the screen underneath. Check Back from every
   control, including rows that swap in place, pickers inside a panel and focused text fields that are not
   being edited.
6. **Focus is restored after anything closes or rebuilds.** Focus returns to the control that opened a
   modal, sheet, popover, panel or confirmation, or to its nearest valid replacement. After a rebuild,
   remember the focused frame and call ``MenuNavigator/focusNearest(to:in:)``.
7. **L1 and R1 switch tabs.** Any tabbed surface handles `previous` and `next` through
   ``SwiftUICore/View/onMenuCommand(_:perform:)``, wraps at the ends and moves focus to the selected tab. Only the
   frontmost tabbed surface in that window reacts: it ignores the command while
   ``MenuInputGate/isBlocking`` is true, unless it is that presentation.
8. **Nothing behind a modal reacts.** A modal applies ``SwiftUICore/View/menuInputBlocking(_:prompt:)`` while it
   is shown, with `prompt` set for confirmation prompts that must also stop Options. Content underneath
   checks ``MenuInputGate/isBlocking``. Release the gate as soon as the user chooses, not when the view
   disappears, because the fade-out keeps the view alive.
9. **The focused control stays visible.** Ordinary scroll views are revealed automatically. A scroll view
   that scrolls itself to focus adds ``SwiftUICore/View/selfManagedFocusScrolling()``.
10. **The highlight fits the control.** Focus is an outline that hugs the control, never a halo, blur or
    shadow. Glass buttons, dropdowns and segmented controls resolve ``FocusHighlightShape/control`` from
    their control size; sliders and pills declare ``FocusHighlightShape/capsule``; anything else that is not a
    10-point rounded rectangle declares ``SwiftUICore/View/focusHighlightShape(_:)``. Exactly one outline per
    control: a card does not outline itself while a button inside it is focused, and a view that draws its
    own border adds ``SwiftUICore/View/drawsOwnFocusHighlight()``. Use
    ``SwiftUICore/View/focusBorderShape(_:)``, apply the highlight before any `.frame`, draw a control's own
    background inside its label, and add ``SwiftUICore/View/focusWithoutGrowth()`` inside a tight track. Verify
    with a real window capture, because `cacheDisplay` drops Liquid Glass.
11. **Hints match the controller.** Use `ControllerPrompt` from `DesignSystem`; it shows the glyph for the
    connected controller family and hides itself when no controller is connected.
12. **Pointer still works.** Helper views in backgrounds and overlays return `nil` from hit testing, padded
    plain labels get a `contentShape`, and controls layered over a growing control need a higher `zIndex`.

## Pitfalls

- **Hand focus to another view by requesting it, never by clearing your own first.** Clearing your focus and
  requesting a neighbour's in the same update can leave nothing focused.
- **A focus value with no bound view is not remembered.** Track focus of foreign controls in a per-window
  record instead of a sentinel value.
- **Focus records are per window.** Key shared records by window and compare the handler's window with the
  host window.
- **Handlers read live state.** Captured environment values and `let` properties go stale; read through
  state, focus state or a reference object.
- **Handlers exist only while the view is enabled.** Pass `enabled` to
  ``SwiftUICore/View/menuHandlers(enabled:move:activate:modalActivate:back:)``; a disabled view under a modal
  must not keep handling input.
- **Focus moved during a disappearing view is lost.** Apply the parent focus, then verify it after about
  80 ms and 250 ms and reapply it if it was dropped.
- **System alerts are not acceptable for controller flows.** Use
  `appConfirmation(_:confirm:cancel:)` instead of `confirmationDialog`, `.alert` or
  `NSAlert`.
- **Faded chrome releases focus.** A hidden control never keeps keyboard focus during gameplay.
- **`opacity(0)` disables hit testing but not focus.** Hide with layout or hit testing plus an explicit focus
  release, and never disable a control just because another presentation holds the input gate.
- **Measure neighbouring chrome.** Use geometry changes into a shared layout object instead of fixed offsets.
- **Horizontal focus movement can steal slider adjustment.** Every slider in Settings and the stream menu has
  an explicit Confirm-to-adjust state, `SliderAdjustment` in `ChiakiModels`. Outside it Left and Right
  navigate; inside it they change the value. Confirm keeps the new value and Back restores the value from
  when adjusting started; both keep focus on the slider, and Up or Down keep the value and move on. Show the
  mode below the focused slider with `SliderAdjustmentPrompt`, and test the value and focus where a
  neighbour exists in the direction pressed.
- **A dropdown needs a selected starting point.** Confirm opens its choices from a focus row through
  ``NativeMenuAnchorReference`` even when macOS Keyboard navigation is off, with the current choice marked
  and positioned. Focus returns to the row after a choice or a dismissal. The hosted harness cannot open
  native menus, so tests drive dropdowns by direction and the popup needs a real-controller check.

## Testing

Hosted-window tests use `MenuFocusHarness` and `MenuFocusHostingView` from `ChiakiTestSupport`, which inject
one test navigator with a standalone input policy. Suites that need a window server carry
`.requiresWindowServer` and are skipped when `CHIAKI_HEADLESS_TESTS=1`. The harness window cannot become
key, cannot open native menus and does not reproduce every SwiftUI focus race: when a test passes both with
and without a change, say so and check the path with a real controller. Animated scroll-reveal tests fail
while the screen is locked.
