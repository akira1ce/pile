# App Updates Implementation Plan

> **For agentic workers:** Use executing-plans to implement these tasks in this session. Do not commit or publish; the user handles Git and GitHub releases.

**Goal:** Check, download and install pile updates using Sparkle and GitHub hosting.

**Architecture:** One app-owned Sparkle controller feeds native menus and SwiftUI settings. Existing DMG scripts embed/sign Sparkle and generate staged update metadata. A separate promotion step publishes metadata only after the release asset exists.

**Tech Stack:** Swift 6, AppKit, SwiftUI, Sparkle 2, Bash, Python standard library, GitHub Pages.

**Spec:** `docs/superpowers/specs/2026-11-10-app-updates-design.md`

## Global Constraints

- macOS 26 minimum; keep `com.akira1ce.pile` and the existing Apple Development signing default.
- Use official Sparkle tools and a separate EdDSA keychain account; no private keys in Git.
- User confirms installation; no silent install or system profiling.
- User commits and publishes manually; stage metadata before promoting it.

### Task 1: App integration

Files: `Package.swift`, `Sources/Features/Updates/UpdateController.swift`, `Sources/App/AppController.swift`, `Sources/Features/Settings/SettingsView.swift`, `Resources/Info.plist`.

- [x] Resolve Sparkle; inspect its public headers and signing tools before using their APIs.
- [x] Add `UpdateController` holding `SPUStandardUpdaterController`. Observe `canCheckForUpdates` and `automaticallyChecksForUpdates` via Combine/KVO; forward manual checking and the preference to Sparkle.
- [x] Initialize at app launch. Wire menu actions independent of accessibility state and pass the controller to settings.
- [x] Add a check button and automatic-check toggle to the existing about card. Compile a release build against the real framework; UI forwarding gets no synthetic framework tests.

### Task 2: Packaging and release metadata

Files: `Scripts/build-app.sh`, `Scripts/build-dmg.sh`, `Scripts/setup-updates.sh`, `Scripts/publish-updates.sh`, `Scripts/validate-appcast.py`, `Scripts/tests/test_validate_appcast.py`, `site/appcast.xml`.

- [x] Write failing tests that run the metadata validator with fixtures: version/build distinction, signed enclosure, unsigned rejection, size matching, and release URL.
- [x] Use Sparkle's official `generate_appcast` with embedded Markdown notes; no custom feed generator. Run validator tests until they pass.
- [x] Embed Sparkle and sign helper bundles, XPC services, then framework, then app. Verify load commands; confirm the final signed bundle after user packaging.
- [x] Add one-time keychain setup. Read back the public key into Info.plist; do not print or export the private key.
- [x] Stage signed metadata after DMG creation. Keep the public feed empty until a real release is uploaded. Add an explicit promotion command comparing the uploaded GitHub asset before copying metadata to `site/`.
- [x] Verify real staged signatures; exercise promotion failure and success with local fixtures.

### Task 3: Verification and documentation

Files: both READMEs, `docs/releases/1.2.0.md`, `Resources/Info.plist`.

- [x] Bump to 1.2.0 / build 5 and document one-time setup, unchanged packaging command, release upload then metadata promotion, first manual install, and key backup.
- [x] Run Python regression tests, shell syntax checks, plist lint, release build, and inspect the final bundle. Verify actual signing/DMG if macOS permissions permit; clearly report anything requiring the user's terminal.
- [x] Review the diff for accidental permission/shortcut behavior changes and secrets. Leave changes uncommitted.

## Verification results

- Sparkle 2.10.1 release compilation passed; existing AX `unsafeBitCast` warnings remain.
- 11 Python tests passed. Publication fixtures use Sparkle's real EdDSA tool and replace only the GitHub download.
- All changed shell scripts pass syntax checks; Info.plist lint and Git diff whitespace checks pass.
- User ran one-time key setup and release packaging. Generated 1.2.0 / build 5, arm64, macOS 26+, 1,538,048-byte DMG.
- DMG checksum passed. Independent CryptoKit verification with the app's public key passed for the initial empty feed, staged release feed, and DMG.
- User's `codesign --verify --deep --strict --verbose=2` validated pile and all Sparkle helpers; application satisfies its designated requirement.
- Independent read-only review found no actionable defects.
- GitHub publication remains user-managed. Test a real upgrade from this first updater-enabled version to a later signed version after publishing; cross-version accessibility and Launch at Login retention remain to be confirmed.
