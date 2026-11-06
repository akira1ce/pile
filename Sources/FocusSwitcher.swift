import AppKit
import SwiftUI

struct FocusSwitcherItem: Identifiable {
    let id: String
    let title: String
    let appName: String
    let icon: NSImage
    let window: WindowIdentity
}

@MainActor
final class FocusSwitcherModel: ObservableObject {
    @Published var selection = 0
}

/// Shows every window on the active screen as an icon strip while the user holds
/// the modifier, so they can pick a window directly instead of walking the stack.
@MainActor
final class FocusSwitcherController {
    private let accessibility: AccessibilityWindowService
    private let onStatus: (String) -> Void

    private var panel: FocusSwitcherPanel?
    private var model: FocusSwitcherModel?
    private var items: [FocusSwitcherItem] = []
    private var selection = 0
    private var focusedWindowID = ""
    private var pendingSteps = 0
    private var isPresenting = false
    private var presentationToken = 0
    private var animationsEnabled = true

    init(accessibility: AccessibilityWindowService, onStatus: @escaping (String) -> Void) {
        self.accessibility = accessibility
        self.onStatus = onStatus
    }

    var isActive: Bool { panel != nil || isPresenting }

    func begin(
        focused: WindowIdentity,
        screen: NSScreen,
        animationsEnabled: Bool,
        initialStep: Int = 1
    ) {
        guard !isActive else { return }
        isPresenting = true
        self.animationsEnabled = animationsEnabled
        focusedWindowID = focused.id
        pendingSteps = initialStep
        presentationToken &+= 1
        let token = presentationToken
        let displayID = Self.displayID(of: screen)

        accessibility.windows(on: screen, focusedWindowID: focused.id) { [weak self] windows in
            Task { @MainActor [weak self] in
                guard let self, self.presentationToken == token else { return }
                self.isPresenting = false
                guard windows.count > 1 else {
                    self.pendingSteps = 0
                    self.onStatus("当前屏幕没有其他窗口")
                    return
                }
                guard let target = displayID.flatMap(Self.screen(for:)) ?? NSScreen.main else {
                    self.pendingSteps = 0
                    return
                }
                self.items = windows.map(Self.item(for:))
                self.selection = Self.wrap(self.pendingSteps, count: windows.count)
                self.pendingSteps = 0
                self.present(on: target)
            }
        }
    }

    func advance(reverse: Bool) {
        if isPresenting {
            pendingSteps += reverse ? -1 : 1
            return
        }
        guard panel != nil, !items.isEmpty else { return }
        selection = Self.wrap(selection + (reverse ? -1 : 1), count: items.count)
        model?.selection = selection
    }

    func pick(_ index: Int) {
        guard panel != nil, items.indices.contains(index) else { return }
        selection = index
        model?.selection = index
        commit()
    }

    func commit() {
        guard panel != nil else {
            cancelPending()
            return
        }
        let chosen = items[selection]
        let needsFocus = chosen.window.id != focusedWindowID
        dismiss()
        if needsFocus {
            accessibility.focus(chosen.window) { _ in }
        }
    }

    func cancel() {
        guard panel != nil else {
            cancelPending()
            return
        }
        dismiss()
    }

    private func cancelPending() {
        guard isPresenting else { return }
        presentationToken &+= 1
        isPresenting = false
        pendingSteps = 0
    }

    private func present(on screen: NSScreen) {
        let itemWidth: CGFloat = 92
        let spacing: CGFloat = 10
        let horizontalPadding: CGFloat = 24
        let height: CGFloat = 108

        let idealWidth = CGFloat(items.count) * itemWidth
            + CGFloat(max(items.count - 1, 0)) * spacing
            + horizontalPadding
        let width = min(idealWidth, screen.visibleFrame.width * 0.82)

        let model = FocusSwitcherModel()
        model.selection = selection
        self.model = model

        let panel = FocusSwitcherPanel()
        panel.setContentSize(NSSize(width: width, height: height))
        panel.contentView = FirstMouseHostingView(rootView: FocusSwitcherView(
            items: items,
            model: model,
            width: width,
            onPick: { [weak self] index in self?.pick(index) }
        ))

        let visibleFrame = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(
            x: visibleFrame.midX - width / 2,
            y: visibleFrame.midY - height / 2
        ))
        panel.alphaValue = animationsEnabled ? 0 : 1
        panel.orderFrontRegardless()
        self.panel = panel

        if animationsEnabled {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                panel.animator().alphaValue = 1
            }
        }
    }

    private func dismiss() {
        presentationToken &+= 1
        pendingSteps = 0
        isPresenting = false
        items = []
        model = nil
        guard let panel else { return }
        self.panel = nil
        panel.orderOut(nil)
    }

    private static func item(for window: WindowIdentity) -> FocusSwitcherItem {
        let app = NSRunningApplication(processIdentifier: window.processID)
        let icon = app?.icon
            ?? NSImage(systemSymbolName: "macwindow", accessibilityDescription: nil)
            ?? NSImage(size: NSSize(width: 64, height: 64))
        return FocusSwitcherItem(
            id: window.id,
            title: window.title,
            appName: app?.localizedName ?? "",
            icon: icon,
            window: window
        )
    }

    private static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    private static func screen(for id: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first { displayID(of: $0) == id }
    }

    private static func wrap(_ index: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let remainder = index % count
        return remainder >= 0 ? remainder : remainder + count
    }
}

/// The panel never becomes key, so clicks have to be accepted on the first press.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Borderless non-activating panel: it shows above every app without stealing focus.
final class FocusSwitcherPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 108),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        level = .popUpMenu
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovable = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        animationBehavior = .none
        isFloatingPanel = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
