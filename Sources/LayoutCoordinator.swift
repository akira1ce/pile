import Foundation

final class LayoutCoordinator {
    private struct PendingPress {
        let preset: LayoutPreset
        let focusedWindowID: String
        let shouldCollapse: Bool
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
            let mode: LayoutMode = pendingPress.shouldCollapse ? .overlap : .stacked
            guard let arrangement = WindowGeometry.arrangement(
                windows: windows,
                focusedWindowID: focusedWindowID,
                preset: preset,
                screen: screen,
                mode: mode
            ) else { return nil }
            return .arrange(targets: arrangement.targets, resultingState: arrangement.state)
        }

        let existing = statesByScreen[screen.uuid]
        let shouldCollapse = WindowGeometry.isIntact(
            state: existing,
            windows: windows,
            preset: preset,
            screen: screen
        )
        pendingPress = PendingPress(
            preset: preset,
            focusedWindowID: focusedWindowID,
            shouldCollapse: shouldCollapse,
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
