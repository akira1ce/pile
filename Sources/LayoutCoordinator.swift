import Foundation

final class LayoutCoordinator {
    private var statesByScreen: [String: WindowLayoutState] = [:]

    func centerCommand(
        focusedWindowID: String,
        preset: LayoutPreset,
        screen: ScreenGeometry
    ) -> LayoutCommand {
        .center(
            focusedWindowID: focusedWindowID,
            frame: WindowGeometry.targetFrame(for: preset, in: screen)
        )
    }

    func pileCommand(
        focusedWindow: LayoutWindow,
        screen: ScreenGeometry,
        windows: [LayoutWindow],
        stackGap: Double
    ) -> LayoutCommand? {
        guard windows.contains(where: { $0.id == focusedWindow.id }) else { return nil }

        // Only an intact collapsed pile expands into a stack. Everything else —
        // a neutral screen, an intact stack, or a layout the user has since
        // disturbed — collapses, so the two pile modes alternate.
        let existing = statesByScreen[screen.uuid]
        let shouldStack = existing?.mode == .overlap
            && WindowGeometry.isIntact(state: existing, windows: windows, screen: screen)

        // The pile takes the size the focused window currently has, so centering at
        // a preset and then piling reproduces that preset without recording it.
        // Only the size is read, which keeps the base stable no matter which window
        // of the pile happens to be focused.
        guard let arrangement = WindowGeometry.arrangement(
            windows: windows,
            focusedWindowID: focusedWindow.id,
            base: WindowGeometry.centeredFrame(sizeOf: focusedWindow.frame, in: screen),
            stackGap: stackGap,
            screen: screen,
            mode: shouldStack ? .stacked : .overlap
        ) else { return nil }
        return .arrange(targets: arrangement.targets, resultingState: arrangement.state)
    }

    func recordApplied(_ state: WindowLayoutState) {
        statesByScreen[state.screenUUID] = state
    }

    func clearState() {
        statesByScreen.removeAll()
    }
}
