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
