import SwiftUI

@MainActor
struct SettingsView: View {
    @ObservedObject var store: PreferencesStore

    var body: some View {
        VStack(spacing: 0) {
            pageHeader

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    globalSettings
                    presetSettings
                }
                .padding(.horizontal, 26)
                .padding(.vertical, 20)
            }

            shortcutFooter
        }
        .frame(width: 620, height: 700)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("快捷键与布局")
                .font(.system(size: 23, weight: .semibold))
            Text("调整快捷键、窗口预设和堆叠行为。修改后立即生效。")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 26)
        .padding(.top, 24)
        .padding(.bottom, 8)
    }

    private var globalSettings: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionHeading(title: "全局设置", subtitle: "所有预设共用")

            HStack {
                Label("快捷键修饰键", systemImage: "command")
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
                    Text("居中和堆叠时平滑移动窗口，不动画缩放")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("堆叠间距", systemImage: "square.3.layers.3d")
                    Spacer()
                    valueBadge("\(Int(store.preferences.stackGap)) pt")
                }
                Slider(
                    value: Binding(
                        get: { store.preferences.stackGap },
                        set: { store.setStackGap($0) }
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
        .padding(18)
        .background(sectionSurface, in: RoundedRectangle(cornerRadius: 16))
    }

    private var modifierPicker: some View {
        modifierPickerControl.pickerStyle(.tabs)
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

    private var presetSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                sectionHeading(title: "窗口预设", subtitle: "数字键按列表顺序对应，最多五个")
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
        .background(sectionSurface, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
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

    private var shortcutFooter: some View {
        HStack(spacing: 12) {
            Label("快捷键", systemImage: "keyboard")
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(store.preferences.modifier.symbol) + 1–\(store.preferences.presets.count) 居中")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text("\(store.preferences.modifier.symbol) + Tab 堆叠 / 收起")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 16)
        .background(Color(nsColor: .underPageBackgroundColor))
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
