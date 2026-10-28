import AppKit
import SwiftUI

@MainActor
final class AppController: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let accessibility = AccessibilityWindowService()
    private let hotKeys = HotKeyManager()
    private let layouts = LayoutCoordinator()
    private let preferences = PreferencesStore()
    private var statusItem: NSStatusItem?
    private var permissionWindow: NSWindow?
    private var preferencesWindow: NSWindow?
    private var isSettingsClosePromptPresented = false
    private var observers: [NSObjectProtocol] = []
    private var isReady = false
    private var statusMessage = "正在检查辅助功能权限"

    func applicationDidFinishLaunching(_ notification: Notification) {
        preferences.onChange = { [weak self] oldValue, newValue in
            guard let self else { return }
            let hotKeyConfigurationChanged = oldValue.modifier != newValue.modifier
                || oldValue.presets.count != newValue.presets.count
            if self.isReady && hotKeyConfigurationChanged {
                self.registerConfiguredHotKeys()
            }
            self.rebuildMenu()
        }
        configureMainMenu()
        configureStatusItem()
        observeSystemChanges()
        refreshPermissionState(showGuideIfNeeded: true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        guard !hasVisibleWindows else { return true }
        if accessibility.isTrusted() {
            openPreferencesWindow()
        } else {
            showPermissionGuide()
        }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeys.unregisterAll()
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window === preferencesWindow else { return }
        preferencesWindow = nil
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            let appIcon = Bundle.main.url(forResource: "AppIcon", withExtension: "icns")
                .flatMap(NSImage.init(contentsOf:))
            let image = appIcon ?? NSImage(systemSymbolName: "rectangle.3.group", accessibilityDescription: "pile")
            image?.size = NSSize(width: 18, height: 18)
            image?.isTemplate = false
            button.image = image
            button.imageScaling = .scaleProportionallyDown
            button.imagePosition = .imageOnly
            button.toolTip = "pile"
        }
        statusItem = item
        rebuildMenu()
    }

    private func configureMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        let about = NSMenuItem(
            title: "关于 pile",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        about.target = NSApplication.shared
        appMenu.addItem(about)
        appMenu.addItem(.separator())

        let settings = NSMenuItem(title: "设置…", action: #selector(openPreferences), keyEquivalent: ",")
        settings.keyEquivalentModifierMask = [.command]
        settings.target = self
        appMenu.addItem(settings)
        appMenu.addItem(.separator())

        let quit = NSMenuItem(title: "退出 pile", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        appMenu.addItem(quit)
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let windowMenuItem = NSMenuItem(title: "窗口", action: nil, keyEquivalent: "")
        let windowMenu = NSMenu()
        let close = NSMenuItem(
            title: "关闭窗口",
            action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w"
        )
        close.keyEquivalentModifierMask = [.command]
        windowMenu.addItem(close)
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        NSApplication.shared.mainMenu = mainMenu
        NSApplication.shared.windowsMenu = windowMenu
    }

    private func rebuildMenu() {
        guard let statusItem else { return }
        let menu = NSMenu()
        if statusMessage != shortcutsEnabledMessage {
            let status = NSMenuItem(title: statusMessage, action: nil, keyEquivalent: "")
            status.isEnabled = false
            menu.addItem(status)
            menu.addItem(.separator())
        }

        if accessibility.isTrusted() {
            for preset in preferences.layoutPresets {
                let item = NSMenuItem(
                    title: presetMenuTitle(for: preset.number),
                    action: #selector(selectPreset(_:)),
                    keyEquivalent: String(preset.number)
                )
                item.keyEquivalentModifierMask = menuModifierFlags(for: preferences.preferences.modifier)
                item.target = self
                item.tag = preset.number
                menu.addItem(item)
            }
        } else {
            let item = NSMenuItem(title: "打开权限引导…", action: #selector(openPermissionGuide), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }

        menu.addItem(.separator())
        let settings = NSMenuItem(title: "设置…", action: #selector(openPreferences), keyEquivalent: ",")
        settings.keyEquivalentModifierMask = [.command]
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        statusItem.menu = menu
    }

    private func presetMenuTitle(for number: Int) -> String {
        let numerals = ["一", "二", "三", "四", "五"]
        guard numerals.indices.contains(number - 1) else { return "堆\(number)" }
        return "堆\(numerals[number - 1])"
    }

    private func menuModifierFlags(for modifier: HotKeyModifier) -> NSEvent.ModifierFlags {
        switch modifier {
        case .option: .option
        case .command: .command
        case .control: .control
        case .shift: .shift
        }
    }

    private func observeSystemChanges() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshPermissionState(showGuideIfNeeded: false)
            }
        })
        observers.append(center.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.layouts.clearState()
            }
        })
        observers.append(center.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.layouts.clearState()
            }
        })
    }

    private func refreshPermissionState(showGuideIfNeeded: Bool) {
        if accessibility.isTrusted() {
            enterReadyState()
        } else {
            leaveReadyState()
            statusMessage = "需要辅助功能权限"
            rebuildMenu()
            if showGuideIfNeeded || permissionWindow != nil {
                showPermissionGuide()
            }
        }
    }

    private func enterReadyState() {
        if isReady {
            statusMessage = shortcutsEnabledMessage
            rebuildMenu()
            closePermissionGuide()
            return
        }
        registerConfiguredHotKeys()
        closePermissionGuide()
        if preferencesWindow == nil {
            openPreferencesWindow()
        }
    }

    @discardableResult
    private func registerConfiguredHotKeys() -> Bool {
        let current = preferences.preferences
        let succeeded = hotKeys.registerAll(
            count: current.presets.count,
            modifier: current.modifier
        ) { [weak self] presetNumber in
            let pressedAt = Date()
            self?.perform(number: presetNumber, pressedAt: pressedAt)
        }
        isReady = succeeded
        statusMessage = succeeded ? shortcutsEnabledMessage : "快捷键注册失败"
        rebuildMenu()
        return succeeded
    }

    private var shortcutsEnabledMessage: String {
        let modifier = preferences.preferences.modifier.symbol
        let count = preferences.preferences.presets.count
        return "快捷键已启用：\(modifier) + 1–\(count)"
    }

    private func leaveReadyState() {
        guard isReady else { return }
        hotKeys.unregisterLayoutHotKeys()
        layouts.clearState()
        isReady = false
    }

    private func showPermissionGuide() {
        if let permissionWindow {
            NSApplication.shared.activate(ignoringOtherApps: true)
            permissionWindow.makeKeyAndOrderFront(nil)
            return
        }

        let view = PermissionOnboardingView(
            onRequestAccess: { [weak self] in self?.requestAccessibilityAccess() },
            onOpenSettings: { [weak self] in self?.openSystemSettings() },
            onCheckAgain: { [weak self] in self?.refreshPermissionState(showGuideIfNeeded: true) },
            onQuit: { NSApplication.shared.terminate(nil) }
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 530),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.title = "pile 权限设置"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: view)
        window.center()
        permissionWindow = window
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func closePermissionGuide() {
        permissionWindow?.orderOut(nil)
        permissionWindow = nil
    }

    private func openPreferencesWindow() {
        if let preferencesWindow {
            NSApplication.shared.activate(ignoringOtherApps: true)
            preferencesWindow.makeKeyAndOrderFront(nil)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 700),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "pile 设置"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: SettingsView(store: preferences))
        window.center()
        preferencesWindow = window
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    @objc private func requestAccessibilityAccess() {
        if accessibility.isTrusted(prompt: true) {
            enterReadyState()
        } else {
            statusMessage = "请在系统设置中允许窗口管理"
            rebuildMenu()
        }
    }

    private func openSystemSettings() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.systempreferences") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func selectPreset(_ sender: NSMenuItem) {
        perform(number: sender.tag, pressedAt: Date())
    }

    @objc private func openPermissionGuide() {
        showPermissionGuide()
    }

    @objc private func openPreferences() {
        openPreferencesWindow()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func perform(number: Int, pressedAt: Date) {
        guard let preset = preferences.layoutPreset(number: number) else { return }
        perform(preset, pressedAt: pressedAt)
    }

    private func perform(_ preset: LayoutPreset, pressedAt: Date) {
        guard !promptToCloseSettingsWindow() else { return }

        guard accessibility.isTrusted() else {
            leaveReadyState()
            statusMessage = "需要辅助功能权限"
            rebuildMenu()
            showPermissionGuide()
            return
        }

        accessibility.focusedWindow { [weak self] focused in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard let focused,
                      focused.isStandard,
                      !focused.isFullScreen,
                      !focused.isMinimized,
                      let screen = NSScreen.screens.first(where: {
                        ScreenGeometry(screen: $0)?.uuid == focused.screenUUID
                      }) else {
                    self.statusMessage = "当前没有可调整的窗口"
                    self.rebuildMenu()
                    return
                }
                let screenUUID = focused.screenUUID
                self.accessibility.windows(on: screen, focusedWindowID: focused.id) { [weak self] visibleWindows in
                    Task { @MainActor [weak self] in
                        guard let self,
                              let screen = NSScreen.screens.first(where: {
                                  ScreenGeometry(screen: $0)?.uuid == screenUUID
                              }) else { return }
                        var windows = visibleWindows
                        if !windows.contains(where: { $0.id == focused.id }) {
                            windows.insert(focused, at: 0)
                        }
                        windows = windows.filter {
                            $0.isStandard && !$0.isFullScreen && !$0.isMinimized && $0.screenUUID == focused.screenUUID
                        }
                        guard let geometry = ScreenGeometry(screen: screen),
                              let command = self.layouts.handle(
                                preset: preset,
                                focusedWindowID: focused.id,
                                screen: geometry,
                                windows: windows.map(\.layoutWindow),
                                now: pressedAt
                              ) else {
                            self.statusMessage = "当前没有可调整的窗口"
                            self.rebuildMenu()
                            return
                        }
                        self.apply(command, windows: windows, focused: focused)
                    }
                }
            }
        }
    }

    private func promptToCloseSettingsWindow() -> Bool {
        guard let window = preferencesWindow, window.isVisible else { return false }
        guard !isSettingsClosePromptPresented else { return true }

        isSettingsClosePromptPresented = true
        statusMessage = "请先关闭 pile 设置窗口"
        rebuildMenu()

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "请先关闭 pile 设置窗口"
        alert.informativeText = "关闭设置窗口后，再使用居中或堆叠快捷键。"
        alert.addButton(withTitle: "关闭设置")
        alert.addButton(withTitle: "取消")
        let previousStatusMessage = statusMessage
        NSApplication.shared.activate(ignoringOtherApps: true)
        alert.beginSheetModal(for: window) { [weak self, weak window] response in
            Task { @MainActor [weak self, weak window] in
                guard let self else { return }
                self.isSettingsClosePromptPresented = false
                if response == .alertFirstButtonReturn {
                    window?.performClose(nil)
                }
                self.statusMessage = previousStatusMessage
                self.rebuildMenu()
            }
        }
        return true
    }

    private func apply(_ command: LayoutCommand, windows: [WindowIdentity], focused: WindowIdentity) {
        let windowsByID = Dictionary(uniqueKeysWithValues: windows.map { ($0.id, $0) })
        switch command {
        case let .center(focusedWindowID, frame):
            guard let window = windowsByID[focusedWindowID] else { return }
            accessibility.setFrame(frame, for: window) { [weak self] succeeded in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.statusMessage = succeeded ? "窗口已居中" : "窗口未能调整"
                    self.rebuildMenu()
                }
            }
        case let .arrange(targets, resultingState):
            let reverseTargets = Array(targets.reversed())
            applyTarget(reverseTargets, at: 0, windowsByID: windowsByID) { [weak self] succeeded in
                guard let self else { return }
                if succeeded {
                    self.layouts.recordApplied(resultingState)
                    let focusedWindow = windowsByID[focused.id] ?? focused
                    self.accessibility.raise(focusedWindow) { _ in }
                    self.statusMessage = resultingState.mode == .stacked ? "窗口已堆叠" : "堆叠已收起"
                } else {
                    self.statusMessage = "部分窗口未能调整"
                }
                self.rebuildMenu()
            }
        }
    }

    private func applyTarget(
        _ targets: [WindowTarget],
        at index: Int,
        windowsByID: [String: WindowIdentity],
        allSucceeded: Bool = true,
        completion: @MainActor @Sendable @escaping (Bool) -> Void
    ) {
        guard index < targets.count else {
            completion(allSucceeded)
            return
        }
        let target = targets[index]
        guard let window = windowsByID[target.windowID] else {
            applyTarget(
                targets,
                at: index + 1,
                windowsByID: windowsByID,
                allSucceeded: false,
                completion: completion
            )
            return
        }
        accessibility.setFrame(target.frame, for: window) { [weak self] succeeded in
            Task { @MainActor [weak self] in
                guard let self else { completion(false); return }
                self.applyTarget(
                    targets,
                    at: index + 1,
                    windowsByID: windowsByID,
                    allSucceeded: allSucceeded && succeeded,
                    completion: completion
                )
            }
        }
    }
}
