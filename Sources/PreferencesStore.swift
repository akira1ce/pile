import Combine
import Foundation

enum HotKeyModifier: String, CaseIterable, Codable, Identifiable, Sendable {
    case option
    case command
    case control
    case shift

    var id: String { rawValue }

    var title: String {
        switch self {
        case .option: "Option (⌥)"
        case .command: "Command (⌘)"
        case .control: "Control (⌃)"
        case .shift: "Shift (⇧)"
        }
    }

    var symbol: String {
        switch self {
        case .option: "⌥"
        case .command: "⌘"
        case .control: "⌃"
        case .shift: "⇧"
        }
    }
}

struct WindowPresetSettings: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var widthPercent: Double
    var heightPercent: Double

    init(id: UUID = UUID(), widthPercent: Double, heightPercent: Double) {
        self.id = id
        self.widthPercent = widthPercent
        self.heightPercent = heightPercent
    }
}

struct AppPreferences: Codable, Equatable, Sendable {
    var modifier: HotKeyModifier
    var presets: [WindowPresetSettings]

    static let defaults = AppPreferences(
        modifier: .option,
        presets: [
            WindowPresetSettings(widthPercent: 60, heightPercent: 72),
            WindowPresetSettings(widthPercent: 72, heightPercent: 78),
            WindowPresetSettings(widthPercent: 98, heightPercent: 98),
        ]
    )
}

@MainActor
final class PreferencesStore: ObservableObject {
    private static let storageKey = "pile.preferences.v1"
    private let userDefaults: UserDefaults

    @Published private(set) var preferences: AppPreferences
    var onChange: ((AppPreferences, AppPreferences) -> Void)?

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        if let data = userDefaults.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode(AppPreferences.self, from: data),
           Self.isValid(decoded) {
            preferences = decoded
        } else {
            preferences = .defaults
        }
    }

    var layoutPresets: [LayoutPreset] {
        preferences.presets.enumerated().map { index, preset in
            LayoutPreset(
                number: index + 1,
                widthPercent: preset.widthPercent,
                heightPercent: preset.heightPercent
            )
        }
    }

    func layoutPreset(number: Int) -> LayoutPreset? {
        guard preferences.presets.indices.contains(number - 1) else { return nil }
        let settings = preferences.presets[number - 1]
        return LayoutPreset(number: number, widthPercent: settings.widthPercent, heightPercent: settings.heightPercent)
    }

    func setModifier(_ modifier: HotKeyModifier) {
        guard modifier != preferences.modifier else { return }
        var updated = preferences
        updated.modifier = modifier
        save(updated)
    }

    func widthPercent(for id: UUID) -> Double? {
        preferences.presets.first(where: { $0.id == id })?.widthPercent
    }

    func heightPercent(for id: UUID) -> Double? {
        preferences.presets.first(where: { $0.id == id })?.heightPercent
    }

    func setWidth(_ value: Double, for id: UUID) {
        updatePreset(id: id) { $0.widthPercent = Self.clamped(value) }
    }

    func setHeight(_ value: Double, for id: UUID) {
        updatePreset(id: id) { $0.heightPercent = Self.clamped(value) }
    }

    func addPreset() {
        guard preferences.presets.count < 5 else { return }
        var updated = preferences
        updated.presets.append(WindowPresetSettings(widthPercent: 80, heightPercent: 85))
        save(updated)
    }

    func removePreset(id: UUID) {
        guard preferences.presets.count > 1,
              preferences.presets.contains(where: { $0.id == id }) else { return }
        var updated = preferences
        updated.presets.removeAll { $0.id == id }
        save(updated)
    }

    private func updatePreset(id: UUID, update: (inout WindowPresetSettings) -> Void) {
        guard let index = preferences.presets.firstIndex(where: { $0.id == id }) else { return }
        var updated = preferences
        update(&updated.presets[index])
        save(updated)
    }

    private func save(_ updated: AppPreferences) {
        guard Self.isValid(updated), updated != preferences else { return }
        let old = preferences
        preferences = updated
        if let data = try? JSONEncoder().encode(updated) {
            userDefaults.set(data, forKey: Self.storageKey)
        }
        onChange?(old, updated)
    }

    private static func clamped(_ value: Double) -> Double {
        guard value.isFinite else { return 1 }
        return min(100, max(1, value))
    }

    private static func isValid(_ preferences: AppPreferences) -> Bool {
        (1...5).contains(preferences.presets.count)
            && preferences.presets.allSatisfy {
                $0.widthPercent.isFinite && (1...100).contains($0.widthPercent)
                    && $0.heightPercent.isFinite && (1...100).contains($0.heightPercent)
            }
    }
}
