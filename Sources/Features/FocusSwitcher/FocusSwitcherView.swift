import AppKit
import SwiftUI

struct FocusSwitcherView: View {
    @ObservedObject var model: FocusSwitcherModel
    let width: CGFloat
    let onPick: (Int) -> Void
    let onClose: (Int) -> Void
    let onMinimize: (Int) -> Void
    @State private var hoveredIndex: Int?

    private static let closeColor = Color(red: 1.0, green: 0.37, blue: 0.35)
    private static let minimizeColor = Color(red: 1.0, green: 0.74, blue: 0.18)

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                        itemView(item, index: index)
                            .id(item.id)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .scrollIndicators(.never)
            .onChange(of: model.selection) { _, selection in
                guard model.items.indices.contains(selection) else { return }
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(model.items[selection].id, anchor: .center)
                }
            }
        }
        .frame(width: width, height: 108)
        .glassEffect(
            .regular.interactive(),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
    }

    private func itemView(_ item: FocusSwitcherItem, index: Int) -> some View {
        let isSelected = index == model.selection
        let isHovered = index == hoveredIndex
        let caption = item.title.isEmpty ? item.appName : item.title
        return ZStack(alignment: .topLeading) {
            Button {
                onPick(index)
            } label: {
                VStack(spacing: 6) {
                    Image(nsImage: item.icon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 52, height: 52)
                    Text(caption)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                        .frame(width: 76)
                }
                .padding(.vertical, 8)
                .frame(width: 92)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isSelected ? Color.primary.opacity(0.12)
                              : isHovered ? Color.primary.opacity(0.06)
                              : Color.clear)
                }
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)

            HStack(spacing: 3) {
                windowButton(symbol: "xmark", color: Self.closeColor, label: "关闭窗口") {
                    onClose(index)
                }
                windowButton(symbol: "minus", color: Self.minimizeColor, label: "最小化窗口") {
                    onMinimize(index)
                }
            }
            .padding(.leading, 16)
            .padding(.top, 4)
            .opacity(isHovered ? 1 : 0)
            .allowsHitTesting(isHovered)
            .accessibilityHidden(!isHovered)
            .animation(.easeOut(duration: 0.12), value: isHovered)
        }
        .scaleEffect(isSelected ? 1.06 : (isHovered ? 1.04 : 1))
        .animation(.snappy(duration: 0.18), value: isSelected)
        .animation(.snappy(duration: 0.18), value: isHovered)
        .onHover { hovering in
            if hovering {
                hoveredIndex = index
            } else if hoveredIndex == index {
                hoveredIndex = nil
            }
        }
        .help(item.title.isEmpty ? item.appName : "\(item.appName) — \(item.title)")
        .accessibilityLabel(item.title.isEmpty ? item.appName : "\(item.appName)，\(item.title)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func windowButton(
        symbol: String,
        color: Color,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(Color.black.opacity(0.6))
                .frame(width: 12, height: 12)
                .background(Circle().fill(color))
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}
