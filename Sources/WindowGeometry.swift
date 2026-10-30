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

struct LayoutPreset: Equatable, Sendable {
    let number: Int
    let widthPercent: Double
    let heightPercent: Double

    var widthScale: Double { widthPercent / 100 }
    var heightScale: Double { heightPercent / 100 }

    func shortcutTitle(for modifier: HotKeyModifier) -> String {
        "\(modifier.symbol) + \(number)"
    }

    var actionTitle: String {
        "居中 \(Self.format(widthPercent))% × \(Self.format(heightPercent))%"
    }

    private static func format(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
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

enum LayoutMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case collapsed
    case stacked

    var id: String { rawValue }

    /// Collapsing has one shape; expanding will gain more (tiling, etc.) and this
    /// is the list the settings picker offers.
    static var expandModes: [LayoutMode] { [.stacked] }

    var title: String {
        switch self {
        case .collapsed: "收起"
        case .stacked: "堆叠"
        }
    }

    var symbol: String {
        switch self {
        case .collapsed: "square.stack.3d.down.right"
        case .stacked: "square.3.layers.3d"
        }
    }

    var completedMessage: String {
        switch self {
        case .collapsed: "窗口已居中收起"
        case .stacked: "窗口已堆叠"
        }
    }
}

struct WindowLayoutState: Sendable {
    let mode: LayoutMode
    let orderedWindowIDs: [String]
    let base: WindowFrame
    /// What the gap means depends on the mode: a cascade step when stacked, unused
    /// when collapsed. Holds the value in effect at apply time, so editing the
    /// setting afterwards can't make an intact layout look disturbed.
    let spacing: Double
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

    /// Keeps a frame's size but recenters it on the screen, which is what the pile
    /// action uses: the focused window's current size becomes the pile's size.
    static func centeredFrame(sizeOf frame: WindowFrame, in screen: ScreenGeometry) -> WindowFrame {
        let visible = screen.usableFrame
        return WindowFrame(
            x: visible.x + (visible.width - frame.width) / 2,
            y: visible.y + (visible.height - frame.height) / 2,
            width: frame.width,
            height: frame.height
        )
    }

    static func stackOffset(count: Int, gap: Double) -> Double {
        count >= 2 ? gap : 0
    }

    static func arrangement(
        windows: [LayoutWindow],
        focusedWindowID: String,
        base: WindowFrame,
        spacing: Double,
        screen: ScreenGeometry,
        mode: LayoutMode
    ) -> (targets: [WindowTarget], state: WindowLayoutState)? {
        guard !windows.isEmpty, windows.contains(where: { $0.id == focusedWindowID }) else { return nil }

        let targets = windows.enumerated().map { index, window in
            WindowTarget(
                windowID: window.id,
                frame: frame(
                    at: index,
                    count: windows.count,
                    base: base,
                    spacing: spacing,
                    mode: mode
                )
            )
        }
        return (targets, WindowLayoutState(
            mode: mode,
            orderedWindowIDs: windows.map(\.id),
            base: base,
            spacing: spacing,
            screenUUID: screen.uuid
        ))
    }

    /// Where one window of the pile goes. Adding an expand mode is a new case
    /// here; collapsing ignores the index and puts everything on the base.
    private static func frame(
        at index: Int,
        count: Int,
        base: WindowFrame,
        spacing: Double,
        mode: LayoutMode
    ) -> WindowFrame {
        switch mode {
        case .collapsed:
            return base
        case .stacked:
            let shift = Double(index) * stackOffset(count: count, gap: spacing)
            return WindowFrame(
                x: base.x + shift,
                y: base.y + shift,
                width: base.width,
                height: base.height
            )
        }
    }

    static func isIntact(
        state: WindowLayoutState?,
        windows: [LayoutWindow],
        screen: ScreenGeometry,
        tolerance: Double = 4
    ) -> Bool {
        guard let state,
              state.screenUUID == screen.uuid,
              state.orderedWindowIDs.count == windows.count,
              Set(state.orderedWindowIDs) == Set(windows.map(\.id)),
              let expected = arrangement(
                windows: windows.sorted { lhs, rhs in
                    (state.orderedWindowIDs.firstIndex(of: lhs.id) ?? .max)
                        < (state.orderedWindowIDs.firstIndex(of: rhs.id) ?? .max)
                },
                focusedWindowID: state.orderedWindowIDs[0],
                base: state.base,
                spacing: state.spacing,
                screen: screen,
                mode: state.mode
              ) else { return false }

        let currentByID = Dictionary(uniqueKeysWithValues: windows.map { ($0.id, $0.frame) })
        return expected.targets.allSatisfy { target in
            currentByID[target.windowID]?.isApproximatelyEqual(to: target.frame, tolerance: tolerance) == true
        }
    }
}
