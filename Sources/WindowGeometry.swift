import AppKit
import CoreGraphics
import Foundation

struct WindowFrame: Equatable, Sendable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    var maxX: Double { x + width }
    var maxY: Double { y + height }

    func isApproximatelyEqual(to other: WindowFrame, tolerance: Double = 4) -> Bool {
        abs(x - other.x) <= tolerance
            && abs(y - other.y) <= tolerance
            && abs(width - other.width) <= tolerance
            && abs(height - other.height) <= tolerance
    }

    static func from(_ rect: CGRect) -> WindowFrame {
        WindowFrame(
            x: rect.origin.x,
            y: rect.origin.y,
            width: rect.size.width,
            height: rect.size.height
        )
    }

    var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}

enum LayoutPreset: Int, CaseIterable, Sendable {
    case compact = 1
    case balanced = 2
    case nearFullScreen = 3

    var widthScale: Double {
        switch self {
        case .compact: 0.60
        case .balanced: 0.72
        case .nearFullScreen: 0.98
        }
    }

    var heightScale: Double {
        switch self {
        case .compact: 0.72
        case .balanced: 0.78
        case .nearFullScreen: 0.98
        }
    }

    var shortcutTitle: String { "Option+\(rawValue)" }

    var actionTitle: String {
        switch self {
        case .compact: "Center 60% × 72%"
        case .balanced: "Center 72% × 78%"
        case .nearFullScreen: "Center 98% × 98%"
        }
    }
}

struct LayoutWindow: Equatable, Sendable {
    let id: String
    var frame: WindowFrame
}

struct ScreenGeometry: Sendable {
    let uuid: String
    let usableFrame: WindowFrame
    let screenFrame: WindowFrame
    let mainScreenHeight: Double

    init?(screen: NSScreen) {
        guard let uuid = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        let displayID = CGDirectDisplayID(uuid.uint32Value)
        if let displayUUID = CGDisplayCreateUUIDFromDisplayID(displayID) {
            let value = displayUUID.takeRetainedValue()
            self.uuid = CFUUIDCreateString(nil, value) as String? ?? String(uuid.uint32Value)
        } else {
            self.uuid = String(uuid.uint32Value)
        }
        let mainHeight = Double(NSScreen.main?.frame.maxY ?? 0)
        let visibleFrame = screen.visibleFrame
        self.usableFrame = WindowFrame.from(CGRect(
            x: visibleFrame.minX,
            y: CGFloat(mainHeight) - visibleFrame.maxY,
            width: visibleFrame.width,
            height: visibleFrame.height
        ))
        self.screenFrame = WindowFrame.from(screen.frame)
        self.mainScreenHeight = mainHeight
    }

    init(uuid: String, usableFrame: WindowFrame) {
        self.uuid = uuid
        self.usableFrame = usableFrame
        self.screenFrame = usableFrame
        self.mainScreenHeight = 0
    }

    func accessibilityFrame(from appKitFrame: CGRect) -> CGRect {
        return CGRect(
            x: appKitFrame.origin.x,
            y: mainScreenHeight - appKitFrame.maxY,
            width: appKitFrame.width,
            height: appKitFrame.height
        )
    }

    func appKitFrame(from accessibilityFrame: CGRect) -> CGRect {
        return CGRect(
            x: accessibilityFrame.origin.x,
            y: mainScreenHeight - accessibilityFrame.maxY,
            width: accessibilityFrame.width,
            height: accessibilityFrame.height
        )
    }
}

enum LayoutMode: String, Sendable {
    case stacked
    case overlap
}

struct WindowLayoutState: Sendable {
    let mode: LayoutMode
    let orderedWindowIDs: [String]
    let preset: LayoutPreset
    let screenUUID: String
}

struct WindowTarget: Sendable {
    let windowID: String
    let frame: WindowFrame
}

enum LayoutCommand: Sendable {
    case center(focusedWindowID: String, frame: WindowFrame)
    case arrange(targets: [WindowTarget], resultingState: WindowLayoutState)
}

enum WindowGeometry {
    static func targetFrame(for preset: LayoutPreset, in screen: ScreenGeometry) -> WindowFrame {
        let visible = screen.usableFrame
        let width = visible.width * preset.widthScale
        let height = visible.height * preset.heightScale
        return WindowFrame(
            x: visible.x + (visible.width - width) / 2,
            y: visible.y + (visible.height - height) / 2,
            width: width,
            height: height
        )
    }

    static func stackOffset(count: Int, screen: ScreenGeometry, windowFrame: WindowFrame) -> Double {
        guard count >= 2 else { return 0 }
        return max(0, min(
            36,
            (screen.usableFrame.width - windowFrame.width) / Double(count - 1),
            (screen.usableFrame.height - windowFrame.height) / Double(count - 1)
        ))
    }

    static func arrangement(
        windows: [LayoutWindow],
        focusedWindowID: String,
        preset: LayoutPreset,
        screen: ScreenGeometry,
        mode: LayoutMode
    ) -> (targets: [WindowTarget], state: WindowLayoutState)? {
        guard !windows.isEmpty, windows.contains(where: { $0.id == focusedWindowID }) else { return nil }

        let base = targetFrame(for: preset, in: screen)
        let offset = mode == .stacked ? stackOffset(count: windows.count, screen: screen, windowFrame: base) : 0
        let targets = windows.enumerated().map { index, window in
            let shift = Double(index) * offset
            return WindowTarget(
                windowID: window.id,
                frame: WindowFrame(
                    x: base.x + shift,
                    y: base.y + shift,
                    width: base.width,
                    height: base.height
                )
            )
        }
        return (targets, WindowLayoutState(
            mode: mode,
            orderedWindowIDs: windows.map(\.id),
            preset: preset,
            screenUUID: screen.uuid
        ))
    }

    static func isIntact(
        state: WindowLayoutState?,
        windows: [LayoutWindow],
        preset: LayoutPreset,
        screen: ScreenGeometry,
        tolerance: Double = 4
    ) -> Bool {
        guard let state,
              state.mode == .stacked,
              state.preset == preset,
              state.screenUUID == screen.uuid,
              state.orderedWindowIDs.count == windows.count,
              Set(state.orderedWindowIDs) == Set(windows.map(\.id)),
              let expected = arrangement(
                windows: windows.sorted { lhs, rhs in
                    (state.orderedWindowIDs.firstIndex(of: lhs.id) ?? .max)
                        < (state.orderedWindowIDs.firstIndex(of: rhs.id) ?? .max)
                },
                focusedWindowID: state.orderedWindowIDs[0],
                preset: preset,
                screen: screen,
                mode: .stacked
              ) else { return false }

        let currentByID = Dictionary(uniqueKeysWithValues: windows.map { ($0.id, $0.frame) })
        return expected.targets.allSatisfy { target in
            currentByID[target.windowID]?.isApproximatelyEqual(to: target.frame, tolerance: tolerance) == true
        }
    }
}
