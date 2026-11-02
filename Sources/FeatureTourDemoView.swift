import AppKit
import SwiftUI

@MainActor
struct FeatureTourDemoView: View {
    let modifierSymbol: String

    @State private var frames: [String: WindowFrame] = ["a": DemoLayout.scattered]
    @State private var visibleIDs: Set<String> = ["a"]
    @State private var focusedID = "a"
    @State private var zOrder = ["a", "b", "c"]
    @State private var sceneTitle = "居中预设"
    @State private var keycap = "1"

    var body: some View {
        ZStack(alignment: .topLeading) {
            backdrop

            ForEach(["a", "b", "c"], id: \.self) { id in
                if let frame = frames[id] {
                    DemoWindowView(
                        title: DemoLayout.title(for: id),
                        tint: DemoLayout.tint(for: id),
                        isFocused: focusedID == id
                    )
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.x + frame.width / 2, y: frame.y + frame.height / 2)
                    .opacity(visibleIDs.contains(id) ? 1 : 0)
                    .zIndex(Double(zOrder.firstIndex(of: id) ?? 0))
                    .transition(.opacity)
                }
            }

            VStack {
                HStack {
                    badge(sceneTitle)
                    Spacer()
                    keycapBadge("\(modifierSymbol) \(keycap)")
                }
                Spacer()
            }
            .padding(12)
        }
        .frame(width: DemoLayout.size.width, height: DemoLayout.size.height)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .task { await runDemo() }
    }

    private var backdrop: some View {
        Color.white
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial, in: Capsule())
    }

    private func keycapBadge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                .ultraThinMaterial,
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
    }

    private func runDemo() async {
        while !Task.isCancelled {
            await playPresetScene()
            await playPileScene()
            await playCycleScene()
            await resetScene()
        }
    }

    private func playPresetScene() async {
        sceneTitle = "居中预设"
        keycap = "1"
        focusedID = "a"
        zOrder = ["a", "b", "c"]
        frames["a"] = DemoLayout.scattered
        visibleIDs = ["a"]
        await wait(900)

        withAnimation(.easeOut(duration: 0.2)) {
            frames["a"] = DemoLayout.presetOne
        }
        await wait(950)

        withAnimation(.easeOut(duration: 0.2)) {
            frames["a"] = DemoLayout.presetTwo
            keycap = "2"
        }
        await wait(1000)
    }

    private func playPileScene() async {
        sceneTitle = "展开 / 收起"
        keycap = "·"
        withAnimation(.easeOut(duration: 0.2)) {
            visibleIDs = ["a", "b", "c"]
            frames = DemoLayout.neutral
            focusedID = "a"
            zOrder = ["b", "c", "a"]
        }
        await wait(1000)

        withAnimation(.easeOut(duration: 0.2)) {
            frames = DemoLayout.frames(mode: .collapsed)
        }
        await wait(950)

        withAnimation(.easeOut(duration: 0.2)) {
            frames = DemoLayout.frames(mode: .stacked)
        }
        await wait(1100)

        withAnimation(.easeOut(duration: 0.2)) {
            frames = DemoLayout.frames(mode: .collapsed)
        }
        await wait(900)
    }

    private func playCycleScene() async {
        sceneTitle = "轮换聚焦"
        keycap = "Tab"
        withAnimation(.easeOut(duration: 0.2)) {
            frames = DemoLayout.frames(mode: .stacked)
            focusedID = "b"
            zOrder = ["a", "c", "b"]
        }
        await wait(900)

        withAnimation(.easeOut(duration: 0.16)) {
            focusedID = "c"
            zOrder = ["a", "b", "c"]
        }
        await wait(900)

        withAnimation(.easeOut(duration: 0.16)) {
            focusedID = "a"
            zOrder = ["b", "c", "a"]
        }
        await wait(900)
    }

    private func resetScene() async {
        withAnimation(.easeOut(duration: 0.2)) {
            visibleIDs = ["a"]
            frames["a"] = DemoLayout.scattered
            focusedID = "a"
            zOrder = ["a", "b", "c"]
        }
        await wait(700)
    }

    private func wait(_ milliseconds: Int) async {
        try? await Task.sleep(for: .milliseconds(milliseconds))
    }
}

private enum DemoLayout {
    static let size = CGSize(width: 564, height: 340)
    static let screen = ScreenGeometry(
        uuid: "demo",
        usableFrame: WindowFrame(x: 0, y: 0, width: 564, height: 340)
    )

    static let scattered = WindowFrame(x: 30, y: 30, width: 232, height: 172)

    static let neutral: [String: WindowFrame] = [
        "a": WindowFrame(x: 36, y: 28, width: 240, height: 174),
        "b": WindowFrame(x: 206, y: 128, width: 240, height: 174),
        "c": WindowFrame(x: 118, y: 76, width: 248, height: 180),
    ]

    static let presetOne = WindowGeometry.targetFrame(
        for: LayoutPreset(number: 1, widthPercent: 58, heightPercent: 70),
        in: screen
    )
    static let presetTwo = WindowGeometry.targetFrame(
        for: LayoutPreset(number: 2, widthPercent: 72, heightPercent: 78),
        in: screen
    )
    static let pileBase = WindowGeometry.centeredFrame(
        sizeOf: WindowFrame(x: 0, y: 0, width: 248, height: 184),
        in: screen
    )

    static func frames(mode: LayoutMode) -> [String: WindowFrame] {
        let ids = ["a", "b", "c"]
        let windows = ids.map { LayoutWindow(id: $0, frame: pileBase) }
        guard let arrangement = WindowGeometry.arrangement(
            windows: windows,
            focusedWindowID: ids[0],
            base: pileBase,
            spacing: 22,
            screen: screen,
            mode: mode
        ) else { return [:] }
        return Dictionary(uniqueKeysWithValues: arrangement.targets.map { ($0.windowID, $0.frame) })
    }

    static func title(for id: String) -> String {
        switch id {
        case "a": "项目"
        case "b": "浏览器"
        default: "终端"
        }
    }

    static func tint(for id: String) -> Color {
        switch id {
        case "a": .blue
        case "b": .purple
        default: .teal
        }
    }
}

private struct DemoWindowView: View {
    let title: String
    let tint: Color
    let isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                HStack(spacing: 3) {
                    trafficLight(.red)
                    trafficLight(.yellow)
                    trafficLight(.green)
                    Spacer()
                }
                Text(title)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 7)
            .frame(height: 16)
            .background(Color(nsColor: .windowBackgroundColor))

            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(tint.opacity(0.28))
                    .frame(height: 24)
                skeleton
                skeleton
                    .padding(.trailing, 44)
                skeleton
                    .padding(.trailing, 76)
                Spacer(minLength: 0)
            }
            .padding(9)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(nsColor: .textBackgroundColor))
        }
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(
                    isFocused ? Color.accentColor : Color.primary.opacity(0.14),
                    lineWidth: isFocused ? 2 : 1
                )
        }
        .shadow(color: .black.opacity(0.20), radius: isFocused ? 12 : 6, y: isFocused ? 6 : 3)
        .animation(.easeOut(duration: 0.14), value: isFocused)
    }

    private func trafficLight(_ color: Color) -> some View {
        Circle()
            .fill(color)
            .frame(width: 5, height: 5)
    }

    private var skeleton: some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(Color.primary.opacity(0.10))
            .frame(height: 5)
    }
}
