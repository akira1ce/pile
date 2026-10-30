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
    let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
    Task { @MainActor in
        manager.dispatch(hotKeyID.id)
    }
    return noErr
}

struct HotKeyHandlers: Sendable {
    let preset: @MainActor @Sendable (Int) -> Void
    let pile: @MainActor @Sendable () -> Void
    let cycleFocus: @MainActor @Sendable () -> Void
}

@MainActor
final class HotKeyManager {
    private static let pileIdentifier: UInt32 = 0
    private static let cycleFocusIdentifier: UInt32 = 6

    private let signature: OSType = 0x50494C45 // PILE
    private var eventHandler: EventHandlerRef?
    private var registrations: [UInt32: EventHotKeyRef] = [:]
    private var callbacks: [UInt32: @MainActor @Sendable () -> Void] = [:]

    func registerAll(count: Int, modifier: HotKeyModifier, handlers: HotKeyHandlers) -> Bool {
        unregisterLayoutHotKeys()
        guard (1...5).contains(count) else { return false }
        guard installEventHandler() else { return false }

        for number in 1...count {
            guard let keyCode = keyCode(for: number),
                  register(keyCode: keyCode, identifier: UInt32(number), modifier: modifier) else {
                unregisterLayoutHotKeys()
                return false
            }
            callbacks[UInt32(number)] = { handlers.preset(number) }
        }
        guard registerFixed(
            keyCode: UInt32(kVK_Tab),
            identifier: Self.pileIdentifier,
            modifier: modifier,
            handler: handlers.pile
        ), registerFixed(
            keyCode: UInt32(kVK_ANSI_Grave),
            identifier: Self.cycleFocusIdentifier,
            modifier: modifier,
            handler: handlers.cycleFocus
        ) else {
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
        callbacks.removeAll()
        if let eventHandler {
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

    private func registerFixed(
        keyCode: UInt32,
        identifier: UInt32,
        modifier: HotKeyModifier,
        handler: @escaping @MainActor @Sendable () -> Void
    ) -> Bool {
        guard register(keyCode: keyCode, identifier: identifier, modifier: modifier) else { return false }
        callbacks[identifier] = handler
        return true
    }

    private func register(keyCode: UInt32, identifier: UInt32, modifier: HotKeyModifier) -> Bool {
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode,
            modifierFlags(for: modifier),
            EventHotKeyID(signature: signature, id: identifier),
            GetApplicationEventTarget(),
            0,
            &reference
        )
        guard status == noErr, let reference else { return false }
        registrations[identifier] = reference
        return true
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
        case .control: UInt32(controlKey)
        case .shift: UInt32(shiftKey)
        }
    }
}
