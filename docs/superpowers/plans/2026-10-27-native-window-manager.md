# Native macOS Window Manager Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a lightweight native macOS menu bar app that reproduces the three window sizing presets and center/stack/collapse interactions from `init.lua`, with a reliable first-run Accessibility permission guide.

**Architecture:** Use a Swift Package executable with AppKit/SwiftUI and a small packaging script that creates a standard `.app` bundle. Keep geometry/state transitions in a pure layout engine, wrap Apple's public Accessibility API in a narrow window service, register global hotkeys through Carbon, and gate shortcut registration on Accessibility trust.

**Tech Stack:** Swift 6.4, Swift Package Manager, AppKit, SwiftUI for onboarding content, ApplicationServices Accessibility (`AXUIElement`), Carbon `RegisterEventHotKey`, CoreGraphics window list, shell packaging script.

**Spec:** `docs/superpowers/specs/2026-10-27-native-window-manager-design.md`

## Global Constraints

- The app must not depend on Hammerspoon or a Lua runtime.
- The app runs in the menu bar; the menu bar is limited to shortcut-related controls and status.
- The first launch presents an Accessibility onboarding window with retry/check-again behavior.
- Do not register layout hotkeys until Accessibility trust is confirmed.
- Preserve Option+1/2/3, scales 0.60/0.72, 0.72/0.78, 0.98/0.98, 0.45 second double press, and 36 point capped stack offset.
- Use Apple's public Accessibility APIs; do not use private CGS/SkyLight APIs or screen recording.
- Use `NSScreen.visibleFrame` and convert to/from Accessibility global top-left coordinates.
- Scope layout state per screen; clear it on public active-Space change notifications because a stable public Space identifier is not available.
- Keep AX calls off the UI thread, apply a finite messaging timeout, and treat failed window operations as failures rather than successful layouts.
- This repository has no existing app project and `.git/index` is not writable in the current environment; do not stage or commit changes.

---

## File map

- `Package.swift` — executable target definition with no external package dependencies.
- `Sources/main.swift` — app entry point and `NSApplicationDelegate` wiring.
- `Sources/AppController.swift` — menu bar lifecycle, onboarding window presentation, permission/hotkey state transitions.
- `Sources/PermissionOnboardingView.swift` — three-step Accessibility permission guide and retry controls.
- `Sources/HotKeyManager.swift` — Carbon global hotkey registration/unregistration and key-code mapping.
- `Sources/WindowGeometry.swift` — pure frame, coordinate conversion, preset, and stacking computations.
- `Sources/LayoutCoordinator.swift` — first-tap/double-tap state machine and per-screen saved layout state.
- `Sources/AccessibilityWindowService.swift` — public AX calls for focused-window discovery, candidate enumeration, geometry reads/writes, and trust checks.
- `Sources/WindowIdentity.swift` — stable in-process identity and frame/title metadata for AX windows.
- `Resources/Info.plist` — bundle metadata, accessory-app policy, executable/icon names.
- `Resources/PkgInfo` — standard `APPL????` package marker.
- `Scripts/build-app.sh` — build the Swift executable and assemble `pile.app`.
- `docs/superpowers/specs/2026-10-27-native-window-manager-design.md` — approved product and architecture design.
- `docs/superpowers/plans/2026-10-27-native-window-manager.md` — this implementation plan.

## Task 1: Create the native app skeleton and bundle packaging

**Files:**
- Create: `Package.swift`
- Create: `Sources/main.swift`
- Create: `Sources/AppController.swift`
- Create: `Resources/Info.plist`
- Create: `Scripts/build-app.sh`
- Use: `icon/macos/AppIcon.icns`

**Interfaces:**
- `@main` creates `NSApplication.shared`, assigns `AppController` as delegate, and runs the app.
- `AppController.applicationDidFinishLaunching(_:)` creates the `NSStatusItem` and owns later permission and shortcut setup.
- `Scripts/build-app.sh [configuration]` builds the package executable and creates `build/pile.app` with executable, `Info.plist`, and icon.

- [ ] Create a SwiftPM executable manifest targeting macOS 13 or later, with one executable product named `pile` and no external dependencies.
- [ ] Add a minimal AppKit delegate that creates a status item, displays the app name and a Quit item, and sets accessory activation policy so no Dock icon is shown.
- [ ] Add bundle metadata with a stable bundle identifier `com.akira1ce.pile`, `LSUIElement=true`, and `AppIcon.icns` as the app icon.
- [ ] Add a packaging script that runs `swift build -c "$CONFIGURATION"`, copies the executable and resources into a conventional `.app` directory, and marks the script executable.
- [ ] Run `swift build` and `Scripts/build-app.sh debug`; confirm the executable and `.app/Contents/Info.plist` exist.

## Task 2: Implement geometry and layout transitions

**Files:**
- Create: `Sources/WindowGeometry.swift`
- Create: `Sources/LayoutCoordinator.swift`

**Interfaces:**
- `enum LayoutPreset: Int, CaseIterable` maps keys 1, 2, 3 to the three width/height scale pairs.
- `struct WindowFrame` stores x, y, width, and height in points.
- `struct WindowLayoutState` stores mode, ordered window identities, preset scales, and screen UUID.
- `enum LayoutCommand` returns either a centered focused frame or target frames for `.stacked`/`.overlap` plus the updated state.
- `LayoutCoordinator.handle(preset:focusedWindowID:screen:windows:now:) -> LayoutCommand?` implements the 0.45 second second-press rule.

- [ ] Implement pure functions for centered frame calculation, stack offset (`min(36, horizontalAvailable/(count-1), verticalAvailable/(count-1))`), overlap frames, and diagonal stack frames.
- [ ] Implement exact double-press scope by preset and focused window ID; retain the first press's “should collapse” decision so moving the focused window does not invalidate the prior stack check.
- [ ] Validate prior stack integrity against window IDs, preset scales, and expected frames with a 4 point tolerance before treating the next double press as collapse.
- [ ] Expire pending presses after 0.45 seconds and clear pending state when preset, focused window, screen, or active Space changes.
- [ ] Run `swift build`; fix compiler issues before connecting the engine to Accessibility.

## Task 3: Implement public Accessibility window control

**Files:**
- Create: `Sources/AccessibilityWindowService.swift`
- Create: `Sources/WindowIdentity.swift`
- Modify: `Sources/WindowGeometry.swift`

**Interfaces:**
- `AccessibilityWindowService.isTrusted(prompt:) -> Bool` checks `AXIsProcessTrustedWithOptions`.
- `AccessibilityWindowService.focusedWindow(completion:)` gets the system focused window and its owning app on a serial AX queue.
- `AccessibilityWindowService.windows(on:focusedWindowID:completion:)` returns visible standard, non-minimized, non-full-screen windows on the selected screen in CG z-order.
- `AccessibilityWindowService.setFrame(_:for:completion:)` sets AX position and size and verifies the resulting frame.
- `WindowIdentity` holds an `AXUIElement`, PID, title, current frame, minimized/full-screen/standard flags, and screen UUID; its ID is the matching CG window number where available.

- [ ] Add small helpers for AX attribute reads/writes, AXValue CGPoint/CGSize conversion, error mapping, and `AXUIElementSetMessagingTimeout` with a bounded timeout.
- [ ] Discover the focused app/window through the system-wide focused UI element; fail gracefully when the focused item is not a controllable standard window.
- [ ] Enumerate on-screen windows using `CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID)` for visible order, then match windows to app AX window elements using owner PID and title/frame metadata. Keep the focused window first. If a CG entry cannot be matched unambiguously, omit it rather than act on the wrong AX element.
- [ ] Filter out minimized, full-screen, non-standard, non-visible, and other-screen windows. Use `NSScreen.visibleFrame` and implement explicit AppKit-to-AX coordinate conversion for all displays.
- [ ] Implement frame writes through `kAXPositionAttribute` and `kAXSizeAttribute`; read back after a short asynchronous delay and return failure if the observed frame differs by more than the configured tolerance.
- [ ] Run `swift build`; ensure AX calls run outside the main actor and no AX failure is recorded as a successful frame change.

## Task 4: Add global Option+number shortcuts and app lifecycle

**Files:**
- Create: `Sources/HotKeyManager.swift`
- Modify: `Sources/AppController.swift`
- Modify: `Sources/LayoutCoordinator.swift`
- Modify: `Sources/AccessibilityWindowService.swift`

**Interfaces:**
- `HotKeyManager.registerAll(_:) -> Bool` registers Carbon hotkeys for all presets; `unregisterAll()` removes all registrations.
- `AppController` registers shortcuts only after permission succeeds and unregisters them on permission loss or app termination.
- `AppController.perform(_:pressedAt:)` gets focus/screen/windows, asks `LayoutCoordinator` for a command, and asks `AccessibilityWindowService` to apply target frames.

- [ ] Implement Carbon `RegisterEventHotKey`/`UnregisterEventHotKey` for key codes 18, 19, and 20 with Option modifier; retain callback handlers and unregister reliably.
- [ ] On each shortcut, identify focused window and its screen, build candidate list, invoke the coordinator, apply returned frames in the engine's order, and raise/focus the original window last if supported publicly.
- [ ] Observe `NSWorkspace.activeSpaceDidChangeNotification` and screen parameter changes; clear per-screen state and pending taps without calling private APIs.
- [ ] No-op cleanly if there is no controllable focused window. Keep failure messages in app status rather than presenting disruptive alerts during normal shortcut use.
- [ ] Run `swift build` and `Scripts/build-app.sh debug` after lifecycle integration.

## Task 5: Build the first-run permission onboarding flow

**Files:**
- Create: `Sources/PermissionOnboardingView.swift`
- Modify: `Sources/AppController.swift`
- Modify: `Sources/AccessibilityWindowService.swift`

**Interfaces:**
- `PermissionOnboardingView` provides three visible steps, “Request access”, “Open System Settings”, “Check again”, and “Quit”.
- `AppController` shows onboarding before registering layout hotkeys, rechecks when app becomes active, transitions to ready only after trust is confirmed, and returns to onboarding when access is revoked.

- [ ] Create a focused onboarding window explaining the permission's purpose and the three actions: trigger the native prompt, enable the app in Privacy & Security > Accessibility, return and verify.
- [ ] Call the native trust prompt only in response to the onboarding action; add a fallback “Open System Settings” action and manual navigation instructions for when the app is absent from the list.
- [ ] Recheck permission on onboarding activation and via the explicit Check again button. When untrusted, keep shortcuts unregistered; when trusted, register all three and show a concise success message before closing onboarding.
- [ ] Make the onboarding reachable again if the permission is revoked. Ensure status item indicates “permission required” without adding unrelated settings.
- [ ] Run `swift build` and `Scripts/build-app.sh debug`; inspect the built app's Info.plist and verify it is an accessory app.

## Task 6: Package and validate the complete app

**Files:**
- Modify: `Scripts/build-app.sh`
- Modify: `Resources/Info.plist`
- Modify: `docs/superpowers/specs/2026-10-27-native-window-manager-design.md` only if implementation reveals a material API constraint.

- [ ] Build a clean debug `.app` bundle and verify all required bundle resources are present.
- [ ] Run `swift build -c release` and `Scripts/build-app.sh release`; resolve compiler and packaging errors.
- [ ] Launch the packaged app once for smoke validation: confirm the menu bar icon appears, onboarding displays before permission, grant permission, return and confirm shortcut-ready state, then quit cleanly.
- [ ] If Accessibility permission cannot be exercised in the current automation environment, report that limitation explicitly and leave the built `.app` available for the user to run through the permission flow.
- [ ] Review the final diff and report exact files, build commands/results, current platform baseline, and the fact that a stable Developer ID signature is still required for a distributable release.
