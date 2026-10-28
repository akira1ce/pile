import Foundation

enum WindowAnimationCurve: Sendable {
    case linear
    case easeIn
    case easeOut
    case easeInOut

    func progress(at value: Double) -> Double {
        let value = min(1, max(0, value))
        return switch self {
        case .linear:
            value
        case .easeIn:
            value * value * value
        case .easeOut:
            1 - pow(1 - value, 3)
        case .easeInOut:
            value < 0.5
                ? 4 * value * value * value
                : 1 - pow(-2 * value + 2, 3) / 2
        }
    }
}

enum WindowFrameSequence {
    static func positionFrames(
        from start: WindowFrame,
        to target: WindowFrame,
        steps: Int,
        curve: WindowAnimationCurve
    ) -> [WindowFrame] {
        guard steps > 0 else { return [target] }

        return (1...steps).map { step in
            let fraction = curve.progress(at: Double(step) / Double(steps))
            return WindowFrame(
                x: start.x + (target.x - start.x) * fraction,
                y: start.y + (target.y - start.y) * fraction,
                width: target.width,
                height: target.height
            )
        }
    }
}
