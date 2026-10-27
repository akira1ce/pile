import SwiftUI

@MainActor
struct SettingsView: View {
    @ObservedObject var store: PreferencesStore

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 5) {
                Text("设置")
                    .font(.title2.weight(.semibold))
                Text("预设顺序对应修饰键后的数字键。更改会立即生效。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("全局快捷键修饰键")
                Spacer()
                Picker("修饰键", selection: Binding(
                    get: { store.preferences.modifier },
                    set: { store.setModifier($0) }
                )) {
                    ForEach(HotKeyModifier.allCases) { modifier in
                        Text(modifier.title).tag(modifier)
                    }
                }
                .labelsHidden()
                .frame(width: 180)
            }

            Divider()

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("窗口尺寸预设")
                        .font(.headline)
                    Text("宽高范围为 1–100%。最多可设置五个预设。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    store.addPreset()
                } label: {
                    Label("添加预设", systemImage: "plus")
                }
                .disabled(store.preferences.presets.count >= 5)
            }

            ScrollView {
                VStack(spacing: 10) {
                    ForEach(store.preferences.presets) { preset in
                        let index = store.preferences.presets.firstIndex(where: { $0.id == preset.id }) ?? 0
                        presetRow(index: index, preset: preset)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }

            HStack {
                Text("快捷键")
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(store.preferences.modifier.symbol) + 1–\(store.preferences.presets.count)")
                    .font(.system(.body, design: .rounded).weight(.medium))
            }
        }
        .padding(24)
        .frame(width: 560, height: 620)
    }

    private func presetRow(index: Int, preset: WindowPresetSettings) -> some View {
        HStack(spacing: 12) {
            Text("\(index + 1)")
                .font(.system(.body, design: .rounded).weight(.semibold))
                .frame(width: 28, height: 28)
                .background(Color(nsColor: .controlBackgroundColor), in: Circle())

            dimensionField(
                title: "宽",
                value: Binding(
                    get: { store.widthPercent(for: preset.id) ?? preset.widthPercent },
                    set: { store.setWidth($0, for: preset.id) }
                )
            )
            dimensionField(
                title: "高",
                value: Binding(
                    get: { store.heightPercent(for: preset.id) ?? preset.heightPercent },
                    set: { store.setHeight($0, for: preset.id) }
                )
            )

            Spacer(minLength: 4)
            Button(role: .destructive) {
                store.removePreset(id: preset.id)
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.plain)
            .help("删除预设")
            .disabled(store.preferences.presets.count <= 1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
    }

    private func dimensionField(title: String, value: Binding<Double>) -> some View {
        HStack(spacing: 6) {
            Text(title).foregroundStyle(.secondary)
            TextField(title, value: value, format: .number.precision(.fractionLength(0...2)))
                .textFieldStyle(.roundedBorder)
                .frame(width: 70)
            Text("%")
                .foregroundStyle(.secondary)
        }
    }
}
