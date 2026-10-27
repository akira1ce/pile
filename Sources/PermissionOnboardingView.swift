import AppKit
import SwiftUI

struct PermissionOnboardingView: View {
    let onRequestAccess: () -> Void
    let onOpenSettings: () -> Void
    let onCheckAgain: () -> Void
    let onQuit: () -> Void

    @State private var requestSent = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 14) {
                Image(systemName: "rectangle.3.group")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(.tint)
                    .frame(width: 52, height: 52)
                    .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 4) {
                    Text("先开启辅助功能权限")
                        .font(.title2.weight(.semibold))
                    Text("完成这一步后，Option + 数字快捷键就能管理窗口。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Text("此权限仅用于查找可见窗口并调整它们的位置和大小。应用不会读取屏幕内容，也不会捕获你的键盘输入。")
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 16) {
                instruction(number: "1", title: "请求 macOS 授权", detail: "点击下方按钮，然后在系统弹窗中选择打开系统设置。")
                instruction(number: "2", title: "允许 pile 管理窗口", detail: "在“隐私与安全性 → 辅助功能”中开启 pile。如果列表中没有它，请点“+”并从“应用程序”中添加。")
                instruction(number: "3", title: "返回此处确认", detail: "回到这个窗口；应用会自动检查，也可以点“重新检查权限”。")
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))

            if requestSent {
                Label("完成系统设置后，回到这里继续。", systemImage: "arrow.uturn.backward.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Button("请求权限") {
                    requestSent = true
                    onRequestAccess()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)

                Button("打开系统设置", action: onOpenSettings)
                    .buttonStyle(.bordered)

                Button("重新检查权限", action: onCheckAgain)
                    .buttonStyle(.bordered)
            }

            HStack {
                Spacer()
                Button("退出应用", action: onQuit)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(30)
        .frame(width: 560)
    }

    private func instruction(number: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Color.accentColor, in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
