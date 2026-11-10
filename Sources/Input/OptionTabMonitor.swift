import AppKit
import Carbon.HIToolbox
import CoreGraphics

private enum OptionTabHandleResult: Sendable {
    case pass
    case consume
}

private let optionTabEventCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let monitor = Unmanaged<OptionTabMonitor>.fromOpaque(userInfo).takeUnretainedValue()
    let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
    let flags = event.flags
    let location = event.unflippedLocation
    let result = MainActor.assumeIsolated {
        monitor.handle(type: type, keyCode: keyCode, flags: flags, location: location)
    }
    return result == .consume ? nil : Unmanaged.passUnretained(event)
}

/// Intercepts Option+Tab at the session level so the switcher can advance while
/// the key repeats and commit as soon as the modifier is released. Carbon hot
/// keys only report the initial press, so they can't express that interaction.
@MainActor
final class OptionTabMonitor {
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isSwitching: (@MainActor () -> Bool)?
    private var containsPoint: (@MainActor (CGPoint) -> Bool)?
    private var onStep: (@MainActor (Bool) -> Void)?
    private var onCommit: (@MainActor () -> Void)?
    private var onCancel: (@MainActor () -> Void)?

    @discardableResult
    func start(
        isSwitching: @escaping @MainActor () -> Bool,
        containsPoint: @escaping @MainActor (CGPoint) -> Bool,
        onStep: @escaping @MainActor (Bool) -> Void,
        onCommit: @escaping @MainActor () -> Void,
        onCancel: @escaping @MainActor () -> Void
    ) -> Bool {
        stop()
        self.isSwitching = isSwitching
        self.containsPoint = containsPoint
        self.onStep = onStep
        self.onCommit = onCommit
        self.onCancel = onCancel

        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
            | CGEventMask(1 << CGEventType.flagsChanged.rawValue)
            | CGEventMask(1 << CGEventType.leftMouseDown.rawValue)
            | CGEventMask(1 << CGEventType.tapDisabledByTimeout.rawValue)
            | CGEventMask(1 << CGEventType.tapDisabledByUserInput.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: optionTabEventCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            return false
        }

        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        runLoopSource = source
        return true
    }

    func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        tap = nil
        runLoopSource = nil
        isSwitching = nil
        containsPoint = nil
        onStep = nil
        onCommit = nil
        onCancel = nil
    }

    fileprivate func handle(
        type: CGEventType,
        keyCode: Int,
        flags: CGEventFlags,
        location: CGPoint
    ) -> OptionTabHandleResult {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return .pass
        }

        if type == .leftMouseDown {
            if isSwitching?() == true, containsPoint?(location) != true {
                onCancel?()
            }
            return .pass
        }

        if type == .keyDown {
            if flags.contains(.maskAlternate), keyCode == kVK_Tab {
                onStep?(flags.contains(.maskShift))
                return .consume
            }

            guard isSwitching?() == true else { return .pass }
            switch keyCode {
            case kVK_Return, kVK_ANSI_KeypadEnter:
                onCommit?()
                return .consume
            case kVK_Escape:
                onCancel?()
                return .consume
            case kVK_LeftArrow:
                onStep?(true)
                return .consume
            case kVK_RightArrow:
                onStep?(false)
                return .consume
            default:
                return .pass
            }
        }

        if type == .flagsChanged, isSwitching?() == true, !flags.contains(.maskAlternate) {
            onCommit?()
        }
        return .pass
    }
}
