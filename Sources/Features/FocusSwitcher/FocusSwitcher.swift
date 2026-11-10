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
    @Published var items: [FocusSwitcherItem]
    @Published var selection: Int

    init(items: [FocusSwitcherItem], selection: Int) {
        self.items = items
        self.selection = selection
    }
}

/// Shows every window on the active screen as an icon strip while the user holds
/// the modifier, so they can pick a window directly instead of walking the stack.
@MainActor
final class FocusSwitcherController {
    private let accessibility: AccessibilityWindowService
    private let onStatus: (String) -> Void

    private var panel: FocusSwitcherPanel?
    private var model: FocusSwitcherModel?
    private var anchorWindowID: String?
    private var presentationDisplayID: CGDirectDisplayID?
    private var pendingSteps = 0
    private var isPresenting = false
    private var presentationToken = 0
    private var animationsEnabled = true

    init(accessibility: AccessibilityWindowService, onStatus: @escaping (String) -> Void) {
        self.accessibility = accessibility
        self.onStatus = onStatus
    }

    var isActive: Bool { panel != nil || isPresenting }

    /// Uses AppKit screen coordinates, matching CGEvent's unflipped location.
    func contains(_ screenPoint: CGPoint) -> Bool {
        panel?.frame.contains(screenPoint) ?? false
    }

    func begin(
        anchor: WindowIdentity?,
        screen: NSScreen,
        animationsEnabled: Bool,
        initialStep: Int = 0
    ) {
        guard !isActive else { return }
        isPresenting = true
        self.animationsEnabled = animationsEnabled
        anchorWindowID = anchor?.id
        pendingSteps = initialStep
        presentationToken &+= 1
        let token = presentationToken
        let displayID = Self.displayID(of: screen)

        accessibility.windows(on: screen, focusedWindowID: anchor?.id) { [weak self] windows in
            Task { @MainActor [weak self] in
                guard let self, self.presentationToken == token else { return }
                self.isPresenting = false
                guard !windows.isEmpty else {
                    self.pendingSteps = 0
                    self.onStatus("当前屏幕没有可切换的窗口")
                    return
                }
                guard let target = displayID.flatMap(Self.screen(for:)) ?? NSScreen.main else {
                    self.pendingSteps = 0
                    return
                }
                let items = windows.map(Self.item(for:))
                let selection = Self.wrap(self.pendingSteps, count: items.count)
                self.pendingSteps = 0
                self.present(items: items, selection: selection, on: target)
            }
        }
    }

    func advance(reverse: Bool) {
        if isPresenting {
            pendingSteps += reverse ? -1 : 1
            return
        }
        guard let model, !model.items.isEmpty else { return }
        model.selection = Self.wrap(model.selection + (reverse ? -1 : 1), count: model.items.count)
    }

    func pick(_ index: Int) {
        guard let model, model.items.indices.contains(index) else { return }
        model.selection = index
        commit()
    }

    func close(_ index: Int) {
        guard let model, model.items.indices.contains(index) else { return }
        let window = model.items[index].window
        let id = model.items[index].id
        accessibility.close(window) { [weak self] succeeded in
            Task { @MainActor [weak self] in
                guard let self, succeeded else { return }
                self.removeItem(id: id)
            }
        }
    }

    func minimize(_ index: Int) {
        guard let model, model.items.indices.contains(index) else { return }
        let window = model.items[index].window
        let id = model.items[index].id
        accessibility.minimize(window) { [weak self] succeeded in
            Task { @MainActor [weak self] in
                guard let self, succeeded else { return }
                self.removeItem(id: id)
            }
        }
    }

    func commit() {
        guard let model, model.items.indices.contains(model.selection) else {
            cancelPending()
            return
        }
        let chosen = model.items[model.selection]
        let needsFocus = chosen.window.id != anchorWindowID
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

    private func present(items: [FocusSwitcherItem], selection: Int, on screen: NSScreen) {
        let model = FocusSwitcherModel(items: items, selection: selection)
        self.model = model
        presentationDisplayID = Self.displayID(of: screen)

        let panel = FocusSwitcherPanel()
        applyLayout(to: panel, model: model, on: screen)
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

    private func removeItem(id: String) {
        guard let model, let index = model.items.firstIndex(where: { $0.id == id }) else { return }
        model.items.remove(at: index)
        guard !model.items.isEmpty else {
            dismiss()
            return
        }
        if index < model.selection {
            model.selection -= 1
        } else if model.selection >= model.items.count {
            model.selection = model.items.count - 1
        }
        guard let panel, let displayID = presentationDisplayID,
              let screen = Self.screen(for: displayID) else { return }
        applyLayout(to: panel, model: model, on: screen)
    }

    /// Sizes and centers the panel for the current item count, then rebuilds the
    /// content so the new width takes effect.
    private func applyLayout(to panel: NSPanel, model: FocusSwitcherModel, on screen: NSScreen) {
        let itemWidth: CGFloat = 92
        let spacing: CGFloat = 10
        let horizontalPadding: CGFloat = 24
        let height: CGFloat = 108

        let idealWidth = CGFloat(model.items.count) * itemWidth
            + CGFloat(max(model.items.count - 1, 0)) * spacing
            + horizontalPadding
        let width = min(idealWidth, screen.visibleFrame.width * 0.82)

        panel.setContentSize(NSSize(width: width, height: height))
        panel.setFrameOrigin(NSPoint(
            x: screen.visibleFrame.midX - width / 2,
            y: screen.visibleFrame.midY - height / 2
        ))
        panel.contentView = FirstMouseHostingView(rootView: FocusSwitcherView(
            model: model,
            width: width,
            onPick: { [weak self] index in self?.pick(index) },
            onClose: { [weak self] index in self?.close(index) },
            onMinimize: { [weak self] index in self?.minimize(index) }
        ))
    }

    private func dismiss() {
        presentationToken &+= 1
        pendingSteps = 0
        isPresenting = false
        model = nil
        presentationDisplayID = nil
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
