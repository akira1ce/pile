import AppKit
import SwiftUI

final class AppController: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let accessibility = AccessibilityWindowService()
    private let hotKeys = HotKeyManager()
    private let layouts = LayoutCoordinator()
    private let preferences = PreferencesStore()
    private var statusItem: NSStatusItem?
    private var permissionWindow: NSWindow?
    private var preferencesWindow: NSWindow?
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
        _ = hotKeys.registerSettingsHotKey { [weak self] in
            DispatchQueue.main.async {
                self?.openPreferencesWindow()
            }
        }
        configureStatusItem()
        observeSystemChanges()
        refreshPermissionState(showGuideIfNeeded: true)
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
            button.image = NSApp.applicationIconImage
            button.image?.isTemplate = false
            button.toolTip = "pile"
        }
        statusItem = item
        rebuildMenu()
    }

    private func rebuildMenu() {
        guard let statusItem else { return }
        let menu = NSMenu()
        let status = NSMenuItem(title: statusMessage, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())

        if accessibility.isTrusted() {
            for preset in preferences.layoutPresets {
                let item = NSMenuItem(
                    title: "\(preset.shortcutTitle(for: preferences.preferences.modifier))  居中",
                    action: #selector(selectPreset(_:)),
                    keyEquivalent: ""
                )
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

    private func observeSystemChanges() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshPermissionState(showGuideIfNeeded: false)
        })
        observers.append(center.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.layouts.clearState()
        })
        observers.append(center.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.layouts.clearState()
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
    }

    @discardableResult
    private func registerConfiguredHotKeys() -> Bool {
        let current = preferences.preferences
        let succeeded = hotKeys.registerAll(
            count: current.presets.count,
            modifier: current.modifier
        ) { [weak self] presetNumber in
            let pressedAt = Date()
            DispatchQueue.main.async {
                self?.perform(number: presetNumber, pressedAt: pressedAt)
            }
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
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 620),
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
        guard accessibility.isTrusted() else {
            leaveReadyState()
            statusMessage = "需要辅助功能权限"
            rebuildMenu()
            showPermissionGuide()
            return
        }

        accessibility.focusedWindow { [weak self] focused in
            DispatchQueue.main.async {
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
                self.accessibility.windows(on: screen, focusedWindowID: focused.id) { visibleWindows in
                    DispatchQueue.main.async {
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

    private func apply(_ command: LayoutCommand, windows: [WindowIdentity], focused: WindowIdentity) {
        let windowsByID = Dictionary(uniqueKeysWithValues: windows.map { ($0.id, $0) })
        switch command {
        case let .center(focusedWindowID, frame):
            guard let window = windowsByID[focusedWindowID] else { return }
            accessibility.setFrame(frame, for: window) { [weak self] succeeded in
                DispatchQueue.main.async {
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
        completion: @escaping (Bool) -> Void
    ) {
        guard index < targets.count else {
            completion(true)
            return
        }
        let target = targets[index]
        guard let window = windowsByID[target.windowID] else {
            completion(false)
            return
        }
        accessibility.setFrame(target.frame, for: window) { [weak self] succeeded in
            DispatchQueue.main.async {
                guard let self else { completion(false); return }
                guard succeeded else { completion(false); return }
                self.applyTarget(targets, at: index + 1, windowsByID: windowsByID, completion: completion)
            }
        }
    }
}
