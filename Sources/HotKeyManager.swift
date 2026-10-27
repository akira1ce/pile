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

    func registerAll(count: Int, modifier: HotKeyModifier, handler: @escaping (Int) -> Void) -> Bool {
        unregisterLayoutHotKeys()
        guard (1...5).contains(count) else { return false }
        guard installEventHandler() else { return false }

        for number in 1...count {
            guard let keyCode = keyCode(for: number) else { continue }
            let identifier = UInt32(number)
            let hotKeyID = EventHotKeyID(signature: signature, id: identifier)
            var reference: EventHotKeyRef?
            let status = RegisterEventHotKey(
                keyCode,
                modifierFlags(for: modifier),
                hotKeyID,
                GetApplicationEventTarget(),
                0,
                &reference
            )
            guard status == noErr, let reference else {
                unregisterLayoutHotKeys()
                return false
            }
            registrations[identifier] = reference
            callbacks[identifier] = { handler(number) }
        }
        guard registrations.count == count else {
            unregisterLayoutHotKeys()
            return false
        }
        return true
    }

    func unregisterLayoutHotKeys() {
        for reference in registrations.values {
            UnregisterEventHotKey(reference)
        }
        registrations.removeAll()
        for identifier in 1...5 {
            callbacks.removeValue(forKey: UInt32(identifier))
        }
        if registrations.isEmpty, let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    func unregisterAll() {
        unregisterLayoutHotKeys()
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

    private func keyCode(for number: Int) -> UInt32? {
        switch number {
        case 1: UInt32(kVK_ANSI_1)
        case 2: UInt32(kVK_ANSI_2)
        case 3: UInt32(kVK_ANSI_3)
        case 4: UInt32(kVK_ANSI_4)
        case 5: UInt32(kVK_ANSI_5)
        default: nil
        }
    }

    private func modifierFlags(for modifier: HotKeyModifier) -> UInt32 {
        switch modifier {
        case .option: UInt32(optionKey)
        case .command: UInt32(cmdKey)
        case .control: UInt32(controlKey)
        case .shift: UInt32(shiftKey)
        }
    }
}
