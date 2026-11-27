# Repository Guidelines

## Project Structure & Module Organization

pile is a macOS 26+ menu bar window manager built with Swift 6, AppKit, SwiftUI, and Sparkle. `Package.swift` defines one executable target spanning `Sources/`:

- `App/`: application lifecycle and coordination.
- `Layout/`, `WindowSystem/`, `Input/`: geometry, accessibility operations, and global shortcuts.
- `Features/`: settings, onboarding, window switching, and updates.

`Resources/` contains bundle metadata; `icon/` holds app icons. `Scripts/` contains build and release tooling, with Python tests in `Scripts/tests/`. `site/` hosts the static website and update feed. Release documentation lives in `docs/`; generated artifacts go into `build/` and `.build/`.

## Build, Test, and Development Commands

Use macOS 26+ and Xcode 26+ with Swift 6. Run commands from the repository root:

- `swift build`: compile the executable through SwiftPM.
- `./Scripts/build-app.sh debug`: assemble and sign `build/pile.app`; launch with `open build/pile.app`.
- `./Scripts/build-app.sh release`: build the release app bundle.
- `./Scripts/build-dmg.sh release`: package the app and stage a signed update feed; requires release signing credentials.
- `swift package resolve`: fetch dependencies, including Sparkle signing tools.
- `python3 -m unittest discover -s Scripts/tests -v`: run release-tooling tests.

## Coding Style & Naming Conventions

Match existing four-space indentation in Swift and Python. Use `UpperCamelCase` for Swift types and `lowerCamelCase` for methods and properties. Name Swift files after their primary type and keep feature support code beside its UI. Python tests use `test_*.py` files and `test_*` methods. No repository-wide formatter or linter configuration is committed; follow surrounding code.

## Testing Guidelines

Release tooling uses Python `unittest`; publishing tests skip when Sparkle's signing tool is unavailable. There is no Swift test target or enforced coverage threshold. For app changes, build and manually check affected shortcuts, accessibility permissions, settings persistence, and multiple displays. Include the checks performed in your PR.

## Commit & Pull Request Guidelines

Follow scoped Conventional Commit subjects seen in history, such as `feat(updates): ...` and `docs(releasing): ...`. Keep commits focused. PRs should explain the behavior change, link relevant issues, report validation, and include screenshots or recordings for UI changes.

## Release & Agent Notes

Follow `docs/releasing.md`; keep private signing keys out of Git and never hand-edit signed appcasts. When `.codegraph/` exists, use CodeGraph before searching or reading code: `codegraph explore "PreferencesStore"`.
