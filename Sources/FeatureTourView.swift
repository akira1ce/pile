import AppKit
import SwiftUI

@MainActor
struct FeatureTourView: View {
    let modifierSymbol: String
    let onFinish: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            FeatureTourDemoView(modifierSymbol: modifierSymbol)
            shortcutList
            Text("预设尺寸、数量、修饰键与动画都可以在设置中调整。")
                .font(.caption)
                .foregroundStyle(.secondary)
            footer
        }
        .padding(28)
        .frame(width: 620)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 12) {
            appIcon
            VStack(alignment: .leading, spacing: 3) {
                Text("认识 pile")
                    .font(.system(size: 22, weight: .semibold))
                Text("三个快捷键，管理当前屏幕的窗口")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var appIcon: some View {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let image = NSImage(contentsOf: url) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: 44, height: 44)
        } else {
            Image(systemName: "rectangle.stack.fill")
                .font(.system(size: 28))
                .foregroundStyle(.tint)
                .frame(width: 44, height: 44)
        }
    }

    private var shortcutList: some View {
        VStack(spacing: 0) {
            shortcutRow(keys: "\(modifierSymbol) + 1–3", title: "把窗口居中到你设定的尺寸")
            Divider()
                .padding(.leading, 16)
            shortcutRow(keys: "\(modifierSymbol) + ·", title: "把当前屏幕的窗口展开 / 收起")
            Divider()
                .padding(.leading, 16)
            shortcutRow(keys: "\(modifierSymbol) + Tab", title: "在当前屏幕的窗口之间轮换聚焦")
            Divider()
                .padding(.leading, 16)
            Label("使用快捷键前，请先关闭设置窗口。", systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(
            Color(nsColor: .controlBackgroundColor).opacity(0.48),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
    }

    private func shortcutRow(keys: String, title: String) -> some View {
        HStack(spacing: 12) {
            Text(keys)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .frame(width: 92, alignment: .leading)
                .padding(.vertical, 5)
                .background(
                    Color.primary.opacity(0.07),
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
            Text(title)
                .font(.callout)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("开始使用", action: onFinish)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
    }
}
