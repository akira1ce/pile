import ApplicationServices
import Foundation

final class WindowIdentity: @unchecked Sendable {
    let id: String
    let processID: pid_t
    let title: String
    let frame: WindowFrame
    let isMinimized: Bool
    let isFullScreen: Bool
    let isStandard: Bool
    let screenUUID: String
    let accessibilityElement: AXUIElement

    init(
        id: String,
        processID: pid_t,
        title: String,
        frame: WindowFrame,
        isMinimized: Bool,
        isFullScreen: Bool,
        isStandard: Bool,
        screenUUID: String,
        accessibilityElement: AXUIElement
    ) {
        self.id = id
        self.processID = processID
        self.title = title
        self.frame = frame
        self.isMinimized = isMinimized
        self.isFullScreen = isFullScreen
        self.isStandard = isStandard
        self.screenUUID = screenUUID
        self.accessibilityElement = accessibilityElement
    }

    var layoutWindow: LayoutWindow { LayoutWindow(id: id, frame: frame) }

    func withID(_ replacementID: String) -> WindowIdentity {
        WindowIdentity(
            id: replacementID,
            processID: processID,
            title: title,
            frame: frame,
            isMinimized: isMinimized,
            isFullScreen: isFullScreen,
            isStandard: isStandard,
            screenUUID: screenUUID,
            accessibilityElement: accessibilityElement
        )
    }
}
