import AppKit
import SwiftUI

@MainActor
struct FeatureTourView: View {
    let modifierSymbol: String
    let presetCount: Int
    let finishTitle: String
    let onFinish: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            HStack(alignment: .top, spacing: 24) {
                FeatureTourDemoView(modifierSymbol: modifierSymbol, presetCount: presetCount)
                shortcutList
                    .frame(width: 220)
            }
            Spacer(minLength: 0)
            footer
        }
        .padding(26)
        .frame(width: 860, height: 560)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 12) {
            appIcon
            VStack(alignment: .leading, spacing: 3) {
                Text("三个快捷键，整理当前屏幕")
                    .font(.system(size: 22, weight: .semibold))
                Text("居中、收起 / 展开、切换窗口")
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
        let presetNumbers = presetCount == 1 ? "1" : "1–\(presetCount)"
        return VStack(alignment: .leading, spacing: 12) {
            shortcutRow(
                keys: "\(modifierSymbol) \(presetNumbers)",
                title: "居中预设",
                description: "把聚焦窗口调整到你设定的尺寸。",
                symbol: "rectangle.center.inset.filled"
            )
            shortcutRow(
                keys: "\(modifierSymbol) ·",
                title: "收起 / 展开",
                description: "把当前屏幕的窗口集中，再按一次展开。",
                symbol: "square.3.layers.3d"
            )
            shortcutRow(
                keys: "\(modifierSymbol) Tab",
                title: "窗口切换",
                description: "按住修饰键选择窗口，松开后切换。Esc 或外部左键取消。",
                symbol: "rectangle.3.group"
            )
        }
    }

    private func shortcutRow(keys: String, title: String, description: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                Image(systemName: symbol)
                    .foregroundStyle(.tint)
                Text(title)
                    .fontWeight(.semibold)
                Spacer(minLength: 0)
            }
            .font(.system(size: 13))

            Text(description)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(keys)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.75), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        }
    }

    private var footer: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("居中与收起 / 展开前，请先关闭设置窗口。")
                    .font(.system(size: 12))
                Text("窗口切换随时可用；尺寸、快捷键与动画可在设置中调整。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(finishTitle, action: onFinish)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
    }
}
