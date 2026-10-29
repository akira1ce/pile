import Foundation

final class LayoutCoordinator {
    private struct PendingPress {
        let preset: LayoutPreset
        let focusedWindowID: String
        let shouldStack: Bool
        let deadline: Date
    }

    private var statesByScreen: [String: WindowLayoutState] = [:]
    private var pendingPress: PendingPress?

    func handle(
        preset: LayoutPreset,
        focusedWindowID: String,
        screen: ScreenGeometry,
        windows: [LayoutWindow],
        now: Date = Date()
    ) -> LayoutCommand? {
        guard windows.contains(where: { $0.id == focusedWindowID }) else {
            pendingPress = nil
            return nil
        }

        if let pendingPress,
           pendingPress.preset == preset,
           pendingPress.focusedWindowID == focusedWindowID,
           pendingPress.deadline >= now {
            self.pendingPress = nil
            let mode: LayoutMode = pendingPress.shouldStack ? .stacked : .overlap
            guard let arrangement = WindowGeometry.arrangement(
                windows: windows,
                focusedWindowID: focusedWindowID,
                preset: preset,
                screen: screen,
                mode: mode
            ) else { return nil }
            return .arrange(targets: arrangement.targets, resultingState: arrangement.state)
        }

        // Only an intact collapsed pile expands into a stack. Everything else —
        // a neutral screen, an intact stack, or a layout the user has since
        // disturbed — collapses, so the two pile modes alternate.
        let existing = statesByScreen[screen.uuid]
        let shouldStack = existing?.preset == preset
            && existing?.mode == .overlap
            && WindowGeometry.isIntact(
                state: existing,
                windows: windows,
                screen: screen
            )
        pendingPress = PendingPress(
            preset: preset,
            focusedWindowID: focusedWindowID,
            shouldStack: shouldStack,
            deadline: now.addingTimeInterval(0.45)
        )
        return .center(
            focusedWindowID: focusedWindowID,
            frame: WindowGeometry.targetFrame(for: preset, in: screen)
        )
    }

    func recordApplied(_ state: WindowLayoutState) {
        statesByScreen[state.screenUUID] = state
    }

    func clearState() {
        pendingPress = nil
        statesByScreen.removeAll()
    }
}
