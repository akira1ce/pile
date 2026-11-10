import AppKit
import SwiftUI

private enum SettingsCategory: String, CaseIterable, Identifiable {
    case general
    case expand
    case presets
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "通用"
        case .expand: "展开方式"
        case .presets: "窗口预设"
        case .about: "关于 pile"
        }
    }

    var subtitle: String {
        switch self {
        case .general: "调整快捷键修饰键与窗口动画，修改后立即生效"
        case .expand: "设置收起后再次触发时采用的展开方式"
        case .presets: "数字键按列表顺序对应，最多添加五个预设"
        case .about: "版本信息与项目说明"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .expand: "rectangle.stack.fill"
        case .presets: "square.grid.2x2.fill"
        case .about: "info.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .general: .gray
        case .expand: .blue
        case .presets: .teal
        case .about: .gray
        }
    }
}

@MainActor
struct SettingsView: View {
    @ObservedObject var store: PreferencesStore
    @ObservedObject var updates: UpdateController
    @State private var selection: SettingsCategory = .general
    @State private var launchAtLoginEnabled = LaunchAtLogin.isEnabled
    @State private var launchAtLoginRequiresApproval = LaunchAtLogin.requiresApproval
    @State private var launchAtLoginError: String?

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 200)
                .background(Color(nsColor: .underPageBackgroundColor))

            Divider()

            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .ignoresSafeArea(.container, edges: .top)
        .onAppear {
            refreshLaunchAtLoginState()
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Leaves the traffic lights alone; the sidebar is fixed and never collapses.
            Color.clear
                .frame(height: 32)

            sidebarSectionLabel("设置")
            ForEach([SettingsCategory.general, .expand, .presets]) { category in
                sidebarRow(category)
            }

            sidebarSectionLabel("应用")
            sidebarRow(.about)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
    }

    private func sidebarSectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.top, 10)
            .padding(.bottom, 5)
    }

    private func sidebarRow(_ category: SettingsCategory) -> some View {
        let isSelected = selection == category
        return Button {
            selection = category
        } label: {
            HStack(spacing: 10) {
                Image(systemName: category.symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(
                        category.tint.gradient,
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                    )

                Text(category.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.primary.opacity(0.08) : .clear)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var detail: some View {
        switch selection {
        case .general: generalPage
        case .expand: expandPage
        case .presets: presetsPage
        case .about: aboutPage
        }
    }

    private func page<Content: View>(
        _ category: SettingsCategory,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                content()
            }
            .padding(.horizontal, 26)
            .padding(.top, 22)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            pageHeader(category)
                .padding(.horizontal, 26)
                .padding(.top, 16)
                .padding(.bottom, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fadingMaterialBackground()
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func pageHeader(_ category: SettingsCategory) -> some View {
        HStack(spacing: 10) {
            Image(systemName: category.symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(
                    category.tint.gradient,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(category.title)
                    .font(.system(size: 19, weight: .semibold))
                Text(category.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var generalPage: some View {
        page(.general) {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Label("快捷键修饰键", systemImage: "command")
                        Text("所有快捷键共用这一个修饰键")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    modifierPicker
                        .frame(width: 190)
                }

                Divider()

                Toggle(isOn: Binding(
                    get: { store.preferences.animationsEnabled },
                    set: { store.setAnimationsEnabled($0) }
                )) {
                    VStack(alignment: .leading, spacing: 3) {
                        Label("窗口动画", systemImage: "move.3d")
                        Text("居中和展开时平滑移动与缩放窗口")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)

                Divider()

                Toggle(isOn: Binding(
                    get: { launchAtLoginEnabled },
                    set: { setLaunchAtLogin($0) }
                )) {
                    VStack(alignment: .leading, spacing: 3) {
                        Label("登录时启动", systemImage: "power")
                        Text(launchAtLoginDescription)
                            .font(.caption)
                            .foregroundStyle(launchAtLoginError == nil ? Color.secondary : Color.red)
                    }
                }
                .toggleStyle(.switch)
            }
            .padding(18)
            .background(sectionSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(alignment: .leading, spacing: 10) {
                sectionHeading(title: "快捷键", subtitle: "关闭设置窗口后可用")
                shortcutCard
            }
        }
    }

    private var shortcutCard: some View {
        let modifier = store.preferences.modifier.symbol
        let count = store.preferences.presets.count
        return VStack(spacing: 0) {
            shortcutRow(
                title: "居中窗口",
                keys: "\(modifier) + 1–\(count)"
            )
            Divider()
                .padding(.leading, 16)
            shortcutRow(
                title: "\(store.preferences.expandMode.title) / 收起",
                keys: "\(modifier) + ·"
            )
            Divider()
                .padding(.leading, 16)
            shortcutRow(
                title: "切换窗口",
                keys: "\(modifier) + Tab"
            )
        }
        .background(sectionSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func shortcutRow(title: String, keys: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(keys)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Color.primary.opacity(0.07),
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }

    private var expandPage: some View {
        page(.expand) {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Label("展开模式", systemImage: "square.on.square.squareshape")
                        Text("收起后再次触发时的排列方式")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    expandModePicker
                        .frame(width: 190)
                }

                if store.preferences.expandMode == .stacked {
                    Divider()

                    stackedGapSettings
                }
            }
            .padding(18)
            .background(sectionSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private var expandModePicker: some View {
        Picker("展开模式", selection: Binding(
            get: { store.preferences.expandMode },
            set: { store.setExpandMode($0) }
        )) {
            ForEach(LayoutMode.expandModes) { mode in
                Text(mode.title)
                    .tag(mode)
            }
        }
        .labelsHidden()
        .settingsPickerStyle()
    }

    /// Only the selected expand mode shows its own options, so a mode's settings
    /// never sit in the global section.
    private var stackedGapSettings: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("堆叠间距", systemImage: LayoutMode.stacked.symbol)
                Spacer()
                valueBadge("\(Int(store.preferences.stacked.gap)) pt")
            }
            Slider(
                value: Binding(
                    get: { store.preferences.stacked.gap },
                    set: { store.setStackedGap($0) }
                ),
                in: 2...20
            )
            HStack {
                Text("2 pt")
                Spacer()
                Text("20 pt")
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
    }

    private var modifierPicker: some View {
        modifierPickerControl.settingsPickerStyle()
    }

    private var modifierPickerControl: some View {
        Picker("快捷键修饰键", selection: Binding(
            get: { store.preferences.modifier },
            set: { store.setModifier($0) }
        )) {
            ForEach(HotKeyModifier.allCases) { modifier in
                Text(modifier.symbol)
                    .tag(modifier)
                    .help(modifier.title)
            }
        }
        .labelsHidden()
    }

    private var presetsPage: some View {
        page(.presets) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("预设列表")
                        .font(.headline)
                    Text("拖动滑块调整每个预设占屏幕的宽高比例")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    store.addPreset()
                } label: {
                    Label("添加", systemImage: "plus")
                }
                .disabled(store.preferences.presets.count >= 5)
            }

            VStack(spacing: 10) {
                ForEach(store.preferences.presets) { preset in
                    let index = store.preferences.presets.firstIndex(where: { $0.id == preset.id }) ?? 0
                    presetCard(index: index, preset: preset)
                }
            }
        }
    }

    private func presetCard(index: Int, preset: WindowPresetSettings) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(spacing: 10) {
                Text("\(store.preferences.modifier.symbol) \(index + 1)")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.accentColor.opacity(0.12), in: Capsule())
                    .foregroundStyle(Color.accentColor)

                Text("预设 \(index + 1)")
                    .font(.subheadline.weight(.medium))

                Spacer()

                Button(role: .destructive) {
                    store.removePreset(id: preset.id)
                } label: {
                    Image(systemName: "trash")
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("删除预设")
                .disabled(store.preferences.presets.count <= 1)
            }

            HStack(spacing: 24) {
                percentageSlider(
                    title: "宽度",
                    value: Binding(
                        get: { store.widthPercent(for: preset.id) ?? preset.widthPercent },
                        set: { store.setWidth($0, for: preset.id) }
                    )
                )
                percentageSlider(
                    title: "高度",
                    value: Binding(
                        get: { store.heightPercent(for: preset.id) ?? preset.heightPercent },
                        set: { store.setHeight($0, for: preset.id) }
                    )
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(sectionSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        }
    }

    private func percentageSlider(title: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                valueBadge("\(Int(value.wrappedValue.rounded()))%")
            }
            Slider(value: value, in: 1...100)
                .accessibilityLabel(title)
        }
        .frame(maxWidth: .infinity)
    }

    private var aboutPage: some View {
        page(.about) {
            VStack(spacing: 18) {
                appIcon

                VStack(spacing: 6) {
                    Text("pile")
                        .font(.title2.weight(.semibold))
                    Text("版本 \(appVersion)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Text("把当前屏幕的窗口居中堆叠到一起的菜单栏工具。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button("检查更新…") {
                    updates.checkForUpdates()
                }
                .disabled(!updates.canCheckForUpdates)

                Toggle("自动检查更新", isOn: Binding(
                    get: { updates.automaticallyChecksForUpdates },
                    set: { updates.setAutomaticallyChecksForUpdates($0) }
                ))
                .toggleStyle(.checkbox)

                Text("发现新版本后，由你确认下载并安装。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
            .background(sectionSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    @ViewBuilder private var appIcon: some View {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let image = NSImage(contentsOf: url) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: 96, height: 96)
        } else {
            Image(systemName: "rectangle.3.group")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
                .frame(width: 96, height: 96)
        }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    private var launchAtLoginDescription: String {
        if let launchAtLoginError { return launchAtLoginError }
        if launchAtLoginRequiresApproval {
            return "需要在「系统设置 → 通用 → 登录项」中允许"
        }
        return "登录 macOS 后自动在菜单栏运行"
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLogin.set(enabled)
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = "操作失败，请确认 pile 已放在「应用程序」文件夹"
        }
        refreshLaunchAtLoginState()
    }

    private func refreshLaunchAtLoginState() {
        launchAtLoginEnabled = LaunchAtLogin.isEnabled
        launchAtLoginRequiresApproval = LaunchAtLogin.requiresApproval
    }

    private var sectionSurface: Color {
        Color(nsColor: .controlBackgroundColor).opacity(0.48)
    }

    private func sectionHeading(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func valueBadge(_ value: String) -> some View {
        Text(value)
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .frame(minWidth: 48, alignment: .trailing)
    }
}

private extension View {
    /// `.tabs` picker style is macOS 27-only; use segmented controls on 26.
    @ViewBuilder
    func settingsPickerStyle() -> some View {
        if #available(macOS 27.0, *) {
            pickerStyle(.tabs)
        } else {
            pickerStyle(.segmented)
        }
    }
}
