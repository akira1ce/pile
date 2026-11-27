// Run: swiftc Sources/Layout/WindowGeometry.swift Sources/Layout/LayoutCoordinator.swift Sources/Features/Settings/PreferencesStore.swift Scripts/tests/test_layout_modes.swift -o /tmp/pile-layout-tests && /tmp/pile-layout-tests
import Foundation

@main
struct LayoutModeTests {
    @MainActor static func main() throws {
        let screen = ScreenGeometry(uuid: "test", usableFrame: WindowFrame(x: 0, y: 0, width: 1000, height: 800))
        let base = WindowFrame(x: 300, y: 250, width: 400, height: 300)
        let windows = (0..<3).map { LayoutWindow(id: String($0), frame: base) }
        // Literal offsets catch swapped axes, resizing, and compressed spacing.
        for (name, expectedX, expectedY) in [("stacked", 320.0, 270.0), ("vertical", 300.0, 270.0), ("horizontal", 320.0, 250.0)] {
            guard let mode = LayoutMode(rawValue: name) else { fatalError("Missing layout mode: \(name)") }
            let result = WindowGeometry.arrangement(windows: windows, focusedWindowID: "0", base: base, spacing: 10, screen: screen, mode: mode)!
            assert(result.targets[2].frame == WindowFrame(x: expectedX, y: expectedY, width: 400, height: 300))
            let arranged = result.targets.map { LayoutWindow(id: $0.windowID, frame: $0.frame) }
            assert(WindowGeometry.isIntact(state: result.state, windows: arranged, screen: screen))

            let coordinator = LayoutCoordinator()
            guard case let .arrange(_, collapsed)? = coordinator.pileCommand(focusedWindow: windows[0], screen: screen, windows: windows, expandMode: mode, spacing: 10) else { fatalError("Missing collapse") }
            assert(collapsed.mode == .collapsed)
            coordinator.recordApplied(collapsed)
            guard case let .arrange(targets, expanded)? = coordinator.pileCommand(focusedWindow: windows[0], screen: screen, windows: windows, expandMode: mode, spacing: 10) else { fatalError("Missing expansion") }
            assert(expanded.mode == mode)
            assert(targets[2].frame == result.targets[2].frame)
            coordinator.recordApplied(expanded)
            guard case let .arrange(_, next)? = coordinator.pileCommand(focusedWindow: arranged[0], screen: screen, windows: arranged, expandMode: mode, spacing: 10) else { fatalError("Missing second collapse") }
            assert(next.mode == .collapsed)
            coordinator.recordApplied(next)
            guard case let .arrange(repeated, _)? = coordinator.pileCommand(focusedWindow: windows[0], screen: screen, windows: windows, expandMode: mode, spacing: 10) else { fatalError("Missing repeated expansion") }
            assert(repeated.map(\.frame) == targets.map(\.frame))

            var preferences = AppPreferences.defaults
            preferences.expandMode = mode
            let decoded = try JSONDecoder().decode(AppPreferences.self, from: JSONEncoder().encode(preferences))
            assert(decoded.expandMode == mode && decoded.stacked == preferences.stacked && decoded.presets == preferences.presets)

            let many = (0..<30).map { LayoutWindow(id: String($0), frame: base) }
            let crowded = WindowGeometry.arrangement(windows: many, focusedWindowID: "0", base: base, spacing: 20, screen: screen, mode: mode)!
            let last = crowded.targets[29].frame
            assert(last.x == (name == "vertical" ? 300 : 880))
            assert(last.y == (name == "horizontal" ? 250 : 830))
            assert(last.width == 400 && last.height == 300)
        }
        let legacy = Data(#"{"modifier":"option","expandMode":"stacked","stackGap":12,"presets":[{"id":"00000000-0000-0000-0000-000000000001","widthPercent":60,"heightPercent":72}]}"#.utf8)
        let decodedLegacy = try JSONDecoder().decode(AppPreferences.self, from: legacy)
        assert(decodedLegacy.expandMode == .stacked && decodedLegacy.stacked.gap == 12)
        assert(decodedLegacy.presets[0].widthPercent == 60)
        print("Layout modes: fixed offsets, sizes, toggle cycle and preferences passed")
    }
}
