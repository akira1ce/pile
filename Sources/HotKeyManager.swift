import Carbon.HIToolbox
import Foundation

private let pileWindowHotKeyHandler: EventHandlerProcPtr = { _, event, userData in
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr else { return status }
    Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue().dispatch(hotKeyID.id)
    return noErr
}

final class HotKeyManager {
    private let signature: OSType = 0x50494C45 // PILE
    private var eventHandler: EventHandlerRef?
    private var registrations: [UInt32: EventHotKeyRef] = [:]
    private var callbacks: [UInt32: () -> Void] = [:]

    func registerAll(_ handler: @escaping (LayoutPreset) -> Void) -> Bool {
        unregisterAll()
        guard installEventHandler() else { return false }

        for preset in LayoutPreset.allCases {
            guard let keyCode = keyCode(for: preset) else { continue }
            let identifier = UInt32(preset.rawValue)
            let hotKeyID = EventHotKeyID(signature: signature, id: identifier)
            var reference: EventHotKeyRef?
            let status = RegisterEventHotKey(
                keyCode,
                UInt32(optionKey),
                hotKeyID,
                GetApplicationEventTarget(),
                0,
                &reference
            )
            guard status == noErr, let reference else {
                unregisterAll()
                return false
            }
            registrations[identifier] = reference
            callbacks[identifier] = { handler(preset) }
        }
        return registrations.count == LayoutPreset.allCases.count
    }

    func unregisterAll() {
        for reference in registrations.values {
            UnregisterEventHotKey(reference)
        }
        registrations.removeAll()
        callbacks.removeAll()
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    fileprivate func dispatch(_ identifier: UInt32) {
        callbacks[identifier]?()
    }

    private func installEventHandler() -> Bool {
        guard eventHandler == nil else { return true }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            pileWindowHotKeyHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
        return status == noErr
    }

    private func keyCode(for preset: LayoutPreset) -> UInt32? {
        switch preset {
        case .compact: UInt32(kVK_ANSI_1)
        case .balanced: UInt32(kVK_ANSI_2)
        case .nearFullScreen: UInt32(kVK_ANSI_3)
        }
    }
}
