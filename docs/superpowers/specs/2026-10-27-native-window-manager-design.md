# Native macOS Window Manager Design

## Goal

Turn the behavior in `init.lua` into a lightweight native macOS menu bar app. The app must not depend on Hammerspoon or a Lua runtime. The first version preserves the script's three size presets and its center, stack, and collapse interactions.

## User experience

- The app runs in the menu bar and does not need a regular Dock presence.
- The menu bar item is limited to shortcut-related controls and status: show the assigned shortcuts, allow the user to trigger the three layouts, and quit the app. It is not a general settings dashboard.
- On first launch, show a dedicated onboarding window explaining that Accessibility access lets the app find and resize other apps' windows. Guide the user in three visible steps: request access, enable this app under System Settings > Privacy & Security > Accessibility, then return to this app.
- Call `AXIsProcessTrustedWithOptions` with the prompt option to ask macOS to present its native authorization alert, which can open the relevant settings area. Since macOS labels and Settings navigation can vary by release and localization, include a fallback instruction to open Privacy & Security > Accessibility manually and add the app if it is not listed.
- When the app becomes active again, recheck authorization. Keep a clear manual “Check again” action in the onboarding window. Do not register layout hotkeys until the Accessibility API reports trust.
- If permission remains unavailable, keep onboarding visible with steps to retry or quit. Do not leave the app running in a state where the shortcuts appear active but cannot move windows.
- After authorization, show a short success state, register hotkeys, then close onboarding. If access is later revoked, unregister layout hotkeys and return to the permission state.

## Layout behavior to preserve

The existing bindings remain Option+1, Option+2, and Option+3. Their screen-relative width and height scales are respectively 0.60/0.72, 0.72/0.78, and 0.98/0.98.

For a selected preset:

1. The first key press centers the focused, non-minimized, non-full-screen window in its screen's usable frame.
2. The app records whether the matching centered stack was intact before moving the focused window, then starts a 0.45 second double-press window scoped to the preset and focused window.
3. A second press in that interval arranges eligible windows on that screen. If the prior matching stack was intact, place all eligible windows at the same centered frame (collapse the visible stack into an overlap). Otherwise arrange them in a diagonal stack, with offset capped at 36 points and further capped so the stack remains within the usable screen frame.
4. Raise the focused window after arranging and retain the ordered window IDs, preset, and layout mode per screen and active Space context so the next press can detect an intact stack.

The current behavior does not introduce new tiled layouts or user-configurable dimensions. Windows are filtered to visible, standard, non-full-screen, non-minimized windows on the focused window's screen, with the focused window first.

## Architecture

### Menu bar and hotkeys

Use a small AppKit/SwiftUI menu bar shell. Register Option+1/2/3 as global hotkeys using Carbon's `RegisterEventHotKey`, through a thin Swift library such as [HotKey](https://github.com/soffes/HotKey), or a small in-house wrapper if its lifecycle proves simpler. Do not use a global event tap; the app only needs key-down activation, not keyboard capture or suppression.

The app lifecycle owns the hotkey registrations. They are created only after the Accessibility permission gate succeeds and removed when permission is lost or the app exits.

### Window service

Use Apple's public Accessibility client API (`AXUIElement`) to find the focused window and read/write window position and size. Implement a narrow Swift wrapper in the app around the operations needed by this product rather than adopting a full window-manager framework. A wrapper such as [AXSwift](https://github.com/tmandry/AXSwift) is a possible alternative, but it does not own layout policy and adds little for this limited API surface.

The service filters candidate windows, groups them by screen, and returns a stable front-to-back list with the focused window first. It ignores unsupported or stale AX elements and reports a non-blocking status if the focused window cannot be controlled.

### Layout engine

Keep layout decisions independent from Accessibility calls. The engine receives a screen's usable frame, candidate window IDs and frames, focused ID, preset, and current layout state. It returns target frames plus updated state. `WindowService` applies the result through AX position/size attributes and reads frames back when needed to detect rejected changes.

Use `NSScreen.visibleFrame` for the usable area, matching Hammerspoon's screen frame intent. Convert between AppKit's screen coordinates and Accessibility's global top-left coordinates, and use points consistently across display scale factors.

Persist only small state needed for behavior, keyed by screen UUID and active Space identity when that identity is available through supported means. Do not introduce private CGS/SkyLight APIs for Space switching or window management. If public APIs cannot reliably identify the active Space, scope state to screen and visible windows and document the limitation.

## Permission and failure handling

- Accessibility is required to enumerate/control other apps' windows. The app checks trust before enabling shortcuts and checks again when returning from System Settings.
- AX operations can fail because an app is unresponsive, a window disappeared, or an attribute is unsupported. Bound AX messaging timeouts, avoid blocking the UI, and skip failed windows while continuing with the rest.
- A hotkey with no focused controllable window is a no-op with a quiet status update.
- A failed resize/move should not be recorded as a successful stack. Verify target frames before marking a stack intact.
- Avoid private APIs and screen-recording permission; this feature does not require screenshots.

## Dependencies and platform baseline

- Native Swift with AppKit for menu bar lifecycle and screen geometry; SwiftUI may be used for the onboarding window.
- Apple's public ApplicationServices Accessibility APIs for window control.
- Optional HotKey package for Carbon global-hotkey registration.
- No Hammerspoon, Lua runtime, third-party server, network access, or private WindowServer APIs.
- Set the minimum macOS version after confirming the current development/deployment target; the APIs used here are long-standing, but the release target has not yet been chosen.

## Validation plan for implementation

When implementation begins, validate manually on multiple displays and with common apps: first-press centering, second-press stacking, collapse of an intact stack, timeout expiration, changing presets, focused-window changes, minimized/full-screen windows, denied and newly granted Accessibility permission, and display/Space changes. Automated tests should cover pure layout math and double-press state transitions without requiring Accessibility access.

## Known limits

macOS Accessibility is an inter-process API and some applications expose incomplete window attributes or reject geometry changes. Exact active-Space enumeration is not fully available through the public APIs used by this design. The first release prioritizes public APIs and predictable behavior on the active visible screen over private Space manipulation.
