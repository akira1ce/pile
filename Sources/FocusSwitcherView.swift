import AppKit
import SwiftUI

struct FocusSwitcherView: View {
    let items: [FocusSwitcherItem]
    @ObservedObject var model: FocusSwitcherModel
    let width: CGFloat
    let onPick: (Int) -> Void
    @State private var hoveredIndex: Int?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        itemView(item, index: index)
                            .id(index)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .scrollIndicators(.never)
            .onChange(of: model.selection) { _, selection in
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(selection, anchor: .center)
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
        return Button {
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
}
