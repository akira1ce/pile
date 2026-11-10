<div align="center">

<img src="icon/macos/AppIcon256.png" width="128" alt="pile" />

# pile

**Three shortcuts to tidy up the windows on your current screen — center, pile, switch**

Swift 6 · SwiftPM · AppKit + SwiftUI · macOS 26+

[![Platform](https://img.shields.io/badge/platform-macOS%2026%2B-blue?logo=apple)](#build--run)
[![Swift](https://img.shields.io/badge/Swift-6.0-F05138?logo=swift&logoColor=white)](Package.swift)
[![UI](https://img.shields.io/badge/UI-SwiftUI%20%2B%20AppKit-0A84FF)](#architecture)

[English](README.md) · [简体中文](README.zh-CN.md)

</div>

## Features

- 🎯 **Presets** — Center the focused window at a preset size with the modifier plus a number key. Three presets by default, up to five; width and height are set as screen percentages
- 🗂 **Pile / expand** — Pile every window on the current screen into a centered stack, then spread it out with another press. The stack takes the focused window's size, and spacing is adjustable
- ⇥ **Window switcher** — Hold the modifier and press Tab for a horizontal strip in the center of the screen, so you pick a window directly instead of cycling. Hover reveals close / minimize buttons; the panel uses Liquid Glass
- 🖥 **Menu bar app** — No Dock icon, no main window. Trigger every action, check status, and open Settings or the feature tour from the menu
- ⌨️ **Configurable shortcuts** — All shortcuts share one modifier (⌥ / ⌃ / ⇧, default ⌥) and re-register immediately when changed
- 🚀 **Launch at login** — Powered by `SMAppService`. When launched at login it stays quietly in the menu bar
- ⬆️ **In-app updates** — Sparkle checks GitHub releases; review the release notes and confirm download, installation and restart. Automatic checks can be disabled in About
- 🖥 **Multiple displays** — Actions always target the current screen; the switcher uses the screen under the mouse when no window is focused
- ✨ **Smooth animation** — Windows move first, then resize. Can be disabled in Settings
- 🧭 **First-run guide** — Walks through the accessibility permission and plays a built-in demo; reopen it from the menu anytime

### Shortcuts

All shortcuts use the modifier from Settings (⌥ by default).

| Shortcut | Action |
| --- | --- |
| `⌥ + 1–5` | Center the focused window at the matching preset size |
| `⌥ + ·` | Pile / expand the windows on the current screen |
| `⌥ + Tab` | Open the window switcher and pick a window |

After the switcher opens:

| Action | Effect |
| --- | --- |
| Hold `⌥` and press `Tab` / `⇧ + Tab` | Move the highlight forward / backward |
| `←` / `→` | Move the highlight |
| `Return` | Switch to the highlighted window |
| `Esc` | Cancel |
| Release `⌥` | Switch to the highlighted window |
| Click an icon | Switch to that window |
| Left-click outside the switcher | Cancel; the click still reaches the window underneath |

> Centering and pile / expand require a focused standard window and a closed Settings window; `⌥ + Tab` works even on an empty desktop.

## Build & Run

Requires **macOS 26+** and **Xcode 26+** (Swift 6).

```bash
# One-time release setup: create the Sparkle update key in the login keychain
./Scripts/setup-updates.sh

# Debug build, output in build/pile.app
./Scripts/build-app.sh debug
open build/pile.app

# Release build
./Scripts/build-app.sh release
```

You can also build with SwiftPM directly:

```bash
swift build
```

### Package a DMG

```bash
./Scripts/build-dmg.sh
# Output: build/pile-<version>.dmg
```

The script builds a Release app, lays out the drag-to-install window, and signs the app with a fixed Apple Development certificate. The build machine needs the certificate and its private key. Set `PILE_SIGN_IDENTITY` to another certificate's SHA-1 fingerprint to override the default. The build is not notarized; right-click the icon and choose "Open" the first time. To use Launch at Login, move pile.app into Applications first.

Sparkle and its helpers are embedded and signed with the same certificate. The first setup creates a separate EdDSA key under the keychain account `com.akira1ce.pile` and records only its public key in `Resources/Info.plist`. Keep a secure backup of the private key: future updates must use the original key. Setup reuses an existing key and rejects a key that differs from the app's public key. Other developers can compile with the committed public key; publishing updates requires the original private key.

### Publish an update

See the [release and in-app update handbook (Chinese)](docs/releasing.md) for the full workflow, signing setup, proxy configuration and troubleshooting.

1. Increase both version fields in `Resources/Info.plist` and add `docs/releases/<version>.md`.
2. Run `./Scripts/build-dmg.sh release`. It generates the DMG and stages a signed feed in `build/updates/appcast.xml`; release notes are embedded.
3. Commit and push the release source, create a GitHub Release at that commit with the version as its tag (for example `1.2.0`), and upload `build/pile-<version>.dmg`.
4. Run `./Scripts/publish-updates.sh`. It verifies the local signatures and downloads the uploaded asset to ensure it matches before copying the feed to `site/appcast.xml`.
5. Commit and push the updated feed to `main`; the existing Pages workflow deploys it to `https://akira1ce.github.io/pile/appcast.xml`.

If your release tag includes `v`, set it when packaging: `PILE_RELEASE_TAG=v1.2.0 ./Scripts/build-dmg.sh release`. Upload first, then promote the feed, so users are only notified once the signed archive is available. Do not hand-edit a generated signed feed. The initial empty feed is signed during setup and reports no new updates.

The first version containing Sparkle needs one manual installation. Subsequent releases can be installed inside pile. Automatic checks are enabled by default; downloading and installation require confirmation. System profiling and silent installation are disabled.

### Accessibility after an update

The build script uses the same certificate across builds to keep the signing identity stable. Keep the signing certificate, bundle identifier, and installation path consistent across updates. Moving from the earlier ad-hoc builds to certificate signing may require granting accessibility access again once.

If an updated app reports no access, quit pile, remove its old entry under System Settings → Privacy & Security → Accessibility, add `/Applications/pile.app` again, and relaunch it. Keep the installed app in Applications and verify that access is retained when installing the next build.

### First run

1. Launch pile and follow the guide to enable it under System Settings → Privacy & Security → Accessibility
2. After granting access, the feature tour and Settings open automatically
3. Close Settings and the centering / pile shortcuts become available

## How it works & permissions

- **Accessibility** — Reads window position, size, and minimized state through `AXUIElement`, and moves, resizes, closes, minimizes, focuses, and raises windows. Without access the shortcuts are unavailable and the menu offers a guide
- **Window discovery** — Uses `CGWindowListCopyWindowInfo` for on-screen ordering, then matches AX windows by title and role. Only standard windows on the current screen are kept, in front-to-back order
- **Global shortcuts** — Presets and `·` use Carbon `RegisterEventHotKey`; `⌥ + Tab` needs press / release semantics, so it goes through a session-level `CGEvent` tap that is re-enabled automatically if the system disables it
- **Switcher panel** — A non-activating `NSPanel` (`.nonactivatingPanel`, `popUpMenu` level, joins all spaces) that never steals focus; hovering and clicking do not change system focus either
- **Pile state** — Collapsed layouts are tracked per display UUID; only an untouched collapsed pile expands, and the state is cleared when the space or display changes
- **Local window management** — Window information and preferences stay on the Mac. Sparkle uses HTTPS to check the update feed and download releases; it does not send system profiles

## Architecture

The app uses a single SwiftPM executable target. Source files are grouped by responsibility; feature-specific UI and support code stay together.

```
Sources/
├─ App/
│  ├─ main.swift                       # NSApplication entry point
│  └─ AppController.swift              # Lifecycle, menu bar, permissions, shortcut and window coordination
├─ Layout/
│  ├─ LayoutCoordinator.swift          # Per-screen pile state; decides collapse or expand
│  └─ WindowGeometry.swift             # Screen geometry, presets, pile layout math
├─ WindowSystem/
│  ├─ AccessibilityWindowService.swift # Window discovery and AX window operations
│  ├─ WindowIdentity.swift             # AX window identity, metadata, frame updates and results
│  └─ WindowAnimation.swift            # Animation easing curves
├─ Input/
│  ├─ HotKeyManager.swift              # Carbon global hot keys (presets, pile / expand)
│  └─ OptionTabMonitor.swift           # CGEvent tap (keyboard and outside left-click cancellation)
└─ Features/
   ├─ FocusSwitcher/
   │  ├─ FocusSwitcher.swift           # Switcher controller, data model, non-activating panel
   │  └─ FocusSwitcherView.swift       # Liquid Glass window strip and hover actions
   ├─ Settings/
   │  ├─ SettingsView.swift            # Sidebar settings (General / Expand style / Presets / About)
   │  ├─ PreferencesStore.swift        # Preference persistence and validation (UserDefaults + Codable)
   │  ├─ LaunchAtLogin.swift           # SMAppService login item
   │  └─ FadingMaterialBackground.swift # Frosted background for scrolling settings content
   ├─ Onboarding/
   │  ├─ PermissionOnboardingView.swift # Accessibility permission onboarding
   │  ├─ FeatureTourView.swift         # First-run feature tour
   │  └─ FeatureTourDemoView.swift     # Animated demo inside the feature tour
   └─ Updates/
      └─ UpdateController.swift       # Sparkle lifecycle, menu actions and update preferences
```

## Known limitations

- Minimized, fullscreen, and non-standard windows (dialogs, floating panels) are excluded from the pile and the switcher
- The switcher handles one screen at a time and never mixes windows across displays
- No live window previews, per-app grouping, or switching across fullscreen spaces
- Some apps may refuse AX resizing, closing, or minimizing; pile leaves them untouched
