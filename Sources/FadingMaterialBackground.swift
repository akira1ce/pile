import SwiftUI

/// Frosted material that fades to transparent toward the bottom, so a pinned
/// header blends into content scrolling underneath instead of ending in a hard edge.
struct FadingMaterialBackground: ViewModifier {
    func body(content: Content) -> some View {
        content.background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .black, location: 0),
                            .init(color: .black, location: 0.55),
                            .init(color: .clear, location: 1),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
    }
}

extension View {
    func fadingMaterialBackground() -> some View {
        modifier(FadingMaterialBackground())
    }
}
