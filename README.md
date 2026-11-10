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

The script builds a Release app, lays out the drag-to-install window, and ad-hoc signs it. The build is not notarized; right-click the icon and choose "Open" the first time. To use Launch at Login, move pile.app into Applications first.

### Accessibility after an update

The current build script uses ad-hoc signing. Its signing identity depends on the binary's hash, so a rebuilt app can stop matching an existing accessibility grant even while System Settings still lists pile as enabled. This is not an app preference that pile can restore itself.

If an updated app reports no access, quit pile, remove its old entry under System Settings → Privacy & Security → Accessibility, add `/Applications/pile.app` again, and relaunch it. Keep the installed app in Applications. Retaining access across updates requires a stable certificate-based signing identity and the same bundle identifier; the current ad-hoc builds cannot guarantee it.

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
- **No background service** — A single menu bar process with no network requests; preferences live in local `UserDefaults` only

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
   └─ Onboarding/
      ├─ PermissionOnboardingView.swift # Accessibility permission onboarding
      ├─ FeatureTourView.swift         # First-run feature tour
      └─ FeatureTourDemoView.swift     # Animated demo inside the feature tour
```

## Known limitations

- Minimized, fullscreen, and non-standard windows (dialogs, floating panels) are excluded from the pile and the switcher
- The switcher handles one screen at a time and never mixes windows across displays
- No live window previews, per-app grouping, or switching across fullscreen spaces
- Some apps may refuse AX resizing, closing, or minimizing; pile leaves them untouched
