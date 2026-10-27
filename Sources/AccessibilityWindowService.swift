import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

final class AccessibilityWindowService: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.akira1ce.pile.accessibility", qos: .userInitiated)
    private let messagingTimeout: Float = 0.35

    func isTrusted(prompt: Bool = false) -> Bool {
        let options: CFDictionary? = prompt
            ? ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            : nil
        return AXIsProcessTrustedWithOptions(options)
    }

    @MainActor
    func focusedWindow(completion: @escaping @Sendable (WindowIdentity?) -> Void) {
        let screens = NSScreen.screens.compactMap { ScreenGeometry(screen: $0) }
        let frontmostProcessID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        queue.async {
            guard self.isTrusted(prompt: false) else {
                completion(nil)
                return
            }

            let system = AXUIElementCreateSystemWide()
            let focusedApplication = self.axElement(self.attribute(system, kAXFocusedApplicationAttribute))
            let focusedUIElement = self.axElement(self.attribute(system, kAXFocusedUIElementAttribute))

            var processIDs: [pid_t] = []
            if let focusedApplication {
                var processID: pid_t = 0
                if AXUIElementGetPid(focusedApplication, &processID) == .success {
                    processIDs.append(processID)
                }
            }
            if let focusedUIElement {
                var processID: pid_t = 0
                if AXUIElementGetPid(focusedUIElement, &processID) == .success,
                   !processIDs.contains(processID) {
                    processIDs.append(processID)
                }
            }
            if let frontmostProcessID, !processIDs.contains(frontmostProcessID) {
                processIDs.append(frontmostProcessID)
            }

            let cgWindows = self.visibleCGWindows()
            for processID in processIDs {
                let app = focusedApplication.flatMap { element -> AXUIElement? in
                    var focusedProcessID: pid_t = 0
                    guard AXUIElementGetPid(element, &focusedProcessID) == .success,
                          focusedProcessID == processID else { return nil }
                    return element
                } ?? AXUIElementCreateApplication(processID)
                AXUIElementSetMessagingTimeout(app, self.messagingTimeout)

                let cgCandidates = cgWindows.filter { $0.processID == processID && $0.layer == 0 }
                let preferredElements = [
                    self.axElement(self.attribute(app, kAXFocusedWindowAttribute)),
                    self.axElement(self.attribute(app, kAXMainWindowAttribute)),
                ].compactMap { $0 }

                var nonstandardFocusedIdentity: WindowIdentity?
                for element in preferredElements {
                    guard let identity = self.identity(
                        for: element,
                        preferredWindowNumber: nil,
                        screens: screens
                    ) else { continue }
                    if identity.isStandard {
                        completion(self.identity(identity, matchedTo: cgCandidates))
                        return
                    }
                    if nonstandardFocusedIdentity == nil {
                        nonstandardFocusedIdentity = identity
                    }
                }

                let appWindows = (self.attribute(app, kAXWindowsAttribute) as? [AXUIElement]) ?? []
                let identities = appWindows.compactMap {
                    self.identity(for: $0, preferredWindowNumber: nil, screens: screens)
                }
                var consumed = Set<String>()
                for cgWindow in cgCandidates {
                    guard let identity = self.match(
                        cgWindow,
                        among: identities,
                        excluding: consumed,
                        screens: screens
                    ) else { continue }
                    consumed.insert(identity.id)
                    guard identity.isStandard, !identity.isMinimized, !identity.isFullScreen else { continue }
                    completion(identity.withID(cgWindow.id))
                    return
                }

                if let identity = identities.first(where: { $0.isStandard && !$0.isMinimized && !$0.isFullScreen }) {
                    completion(self.identity(identity, matchedTo: cgCandidates))
                    return
                }

                if let nonstandardFocusedIdentity {
                    completion(nonstandardFocusedIdentity)
                    return
                }
            }

            completion(nil)
        }
    }

    @MainActor
    func windows(on screen: NSScreen, focusedWindowID: String, completion: @escaping @Sendable ([WindowIdentity]) -> Void) {
        let screens = NSScreen.screens.compactMap { ScreenGeometry(screen: $0) }
        guard let screenGeometry = ScreenGeometry(screen: screen) else {
            completion([])
            return
        }
        queue.async {
            guard self.isTrusted(prompt: false) else {
                completion([])
                return
            }

            let cgWindows = self.visibleCGWindows()
                .filter { $0.layer == 0 && $0.processID > 0 }
                .filter { self.screenUUID(for: $0.frame, screens: screens) == screenGeometry.uuid }

            var axWindowsByProcess: [pid_t: [WindowIdentity]] = [:]
            for cgWindow in cgWindows where axWindowsByProcess[cgWindow.processID] == nil {
                let app = AXUIElementCreateApplication(cgWindow.processID)
                AXUIElementSetMessagingTimeout(app, self.messagingTimeout)
                let elements = (self.attribute(app, kAXWindowsAttribute) as? [AXUIElement]) ?? []
                axWindowsByProcess[cgWindow.processID] = elements.compactMap {
                    self.identity(for: $0, preferredWindowNumber: nil, screens: screens)
                }
            }

            var result: [WindowIdentity] = []
            var consumedElements = Set<String>()
            for cgWindow in cgWindows {
                guard let appWindows = axWindowsByProcess[cgWindow.processID],
                      let match = self.match(cgWindow, among: appWindows, excluding: consumedElements, screens: screens),
                      !match.isMinimized,
                      !match.isFullScreen,
                      match.isStandard else { continue }
                consumedElements.insert(match.id)
                result.append(match.withID(cgWindow.id))
            }

            if let focusedIndex = result.firstIndex(where: { $0.id == focusedWindowID }) {
                let focused = result.remove(at: focusedIndex)
                result.insert(focused, at: 0)
            }
            completion(result)
        }
    }

    func setFrame(_ frame: WindowFrame, for window: WindowIdentity, completion: @escaping @Sendable (Bool) -> Void) {
        queue.async {
            var point = CGPoint(x: frame.x, y: frame.y)
            var size = CGSize(width: frame.width, height: frame.height)
            guard let positionValue = AXValueCreate(.cgPoint, &point),
                  let sizeValue = AXValueCreate(.cgSize, &size),
                  AXUIElementSetAttributeValue(
                    window.accessibilityElement,
                    kAXPositionAttribute as CFString,
                    positionValue
                  ) == .success,
                  AXUIElementSetAttributeValue(
                    window.accessibilityElement,
                    kAXSizeAttribute as CFString,
                    sizeValue
                  ) == .success else {
                completion(false)
                return
            }

            Thread.sleep(forTimeInterval: 0.05)
            guard let observed = self.frame(of: window.accessibilityElement) else {
                completion(false)
                return
            }
            completion(observed.isApproximatelyEqual(to: frame, tolerance: 4))
        }
    }

    func raise(_ window: WindowIdentity, completion: @escaping @Sendable (Bool) -> Void) {
        queue.async {
            completion(AXUIElementPerformAction(window.accessibilityElement, kAXRaiseAction as CFString) == .success)
        }
    }

    private struct CGWindowRecord {
        let id: String
        let processID: pid_t
        let title: String
        let frame: CGRect
        let layer: Int
    }

    private func visibleCGWindows() -> [CGWindowRecord] {
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return [] }

        return info.compactMap { entry in
            guard let number = entry[kCGWindowNumber as String] as? NSNumber,
                  let processID = entry[kCGWindowOwnerPID as String] as? NSNumber,
                  let layer = entry[kCGWindowLayer as String] as? NSNumber,
                  let boundsValue = entry[kCGWindowBounds as String] else { return nil }
            let boundsRef = boundsValue as CFTypeRef
            guard CFGetTypeID(boundsRef) == CFDictionaryGetTypeID() else { return nil }
            let bounds = unsafeBitCast(boundsRef, to: CFDictionary.self)
            var frame = CGRect.zero
            guard CGRectMakeWithDictionaryRepresentation(bounds, &frame) else { return nil }
            return CGWindowRecord(
                id: String(number.uint32Value),
                processID: processID.int32Value,
                title: entry[kCGWindowName as String] as? String ?? "",
                frame: frame,
                layer: layer.intValue
            )
        }
    }

    private func screenUUID(for accessibilityFrame: CGRect, screens: [ScreenGeometry]) -> String? {
        guard !screens.isEmpty else { return nil }
        let center = CGPoint(x: accessibilityFrame.midX, y: accessibilityFrame.midY)
        if let exact = screens.first(where: { $0.accessibilityFrame(from: $0.screenFrame.cgRect).contains(center) }) {
            return exact.uuid
        }
        let nearest = screens.max { lhs, rhs in
            lhs.accessibilityFrame(from: lhs.screenFrame.cgRect).intersection(accessibilityFrame).area
                < rhs.accessibilityFrame(from: rhs.screenFrame.cgRect).intersection(accessibilityFrame).area
        }
        guard let nearest,
              nearest.accessibilityFrame(from: nearest.screenFrame.cgRect).intersection(accessibilityFrame).area > 0 else {
            return nil
        }
        return nearest.uuid
    }

    private func match(
        _ cgWindow: CGWindowRecord,
        among elements: [WindowIdentity],
        excluding consumed: Set<String>,
        screens: [ScreenGeometry]
    ) -> WindowIdentity? {
        let candidates = elements.filter {
            !consumed.contains($0.id)
                && $0.screenUUID == screenUUID(for: cgWindow.frame, screens: screens)
        }
        guard !candidates.isEmpty else { return nil }

        let matchingTitle = candidates.filter { !$0.title.isEmpty && $0.title == cgWindow.title }
        let pool = matchingTitle.isEmpty ? candidates : matchingTitle
        guard let closest = pool.min(by: { frameDistance($0.frame, cgWindow.frame) < frameDistance($1.frame, cgWindow.frame) }),
              frameDistance(closest.frame, cgWindow.frame) <= 40 else { return nil }
        return closest
    }

    private func identity(for element: AXUIElement, preferredWindowNumber: String?, screens: [ScreenGeometry]) -> WindowIdentity? {
        AXUIElementSetMessagingTimeout(element, messagingTimeout)
        guard let role = attribute(element, kAXRoleAttribute) as? String,
              role == (kAXWindowRole as String),
              let frame = frame(of: element),
              let screenUUID = screenUUID(for: frame.cgRect, screens: screens) else { return nil }
        var processID: pid_t = 0
        guard AXUIElementGetPid(element, &processID) == .success else { return nil }

        let subrole = attribute(element, kAXSubroleAttribute) as? String ?? ""
        let minimized = (attribute(element, kAXMinimizedAttribute) as? NSNumber)?.boolValue ?? false
        let fullScreen = (attribute(element, "AXFullScreen") as? NSNumber)?.boolValue ?? false
        let title = attribute(element, kAXTitleAttribute) as? String ?? ""
        let identity = preferredWindowNumber ?? "\(processID):\(title):\(Int(frame.x.rounded())):\(Int(frame.y.rounded())):\(Int(frame.width.rounded())):\(Int(frame.height.rounded()))"
        return WindowIdentity(
            id: identity,
            processID: processID,
            title: title,
            frame: frame,
            isMinimized: minimized,
            isFullScreen: fullScreen,
            isStandard: subrole == (kAXStandardWindowSubrole as String),
            screenUUID: screenUUID,
            accessibilityElement: element
        )
    }

    private func frame(of element: AXUIElement) -> WindowFrame? {
        guard let position = axValue(attribute(element, kAXPositionAttribute)),
              let size = axValue(attribute(element, kAXSizeAttribute)) else { return nil }
        var point = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(position, .cgPoint, &point), AXValueGetValue(size, .cgSize, &dimensions) else { return nil }
        return WindowFrame(x: point.x, y: point.y, width: dimensions.width, height: dimensions.height)
    }

    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private func axElement(_ value: CFTypeRef?) -> AXUIElement? {
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    private func axValue(_ value: CFTypeRef?) -> AXValue? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        return unsafeBitCast(value, to: AXValue.self)
    }

    private func frameDistance(_ frame: WindowFrame, _ cgFrame: CGRect) -> Double {
        abs(frame.x - cgFrame.origin.x)
            + abs(frame.y - cgFrame.origin.y)
            + abs(frame.width - cgFrame.width)
            + abs(frame.height - cgFrame.height)
    }

    private func identity(
        _ identity: WindowIdentity,
        matchedTo candidates: [CGWindowRecord]
    ) -> WindowIdentity {
        let titleMatches = candidates.filter { !$0.title.isEmpty && $0.title == identity.title }
        let pool = titleMatches.isEmpty ? candidates : titleMatches
        let cgMatch = pool.min {
            frameDistance(identity.frame, $0.frame) < frameDistance(identity.frame, $1.frame)
        }.flatMap { frameDistance(identity.frame, $0.frame) <= 40 ? $0 : nil }
        return cgMatch.map { identity.withID($0.id) } ?? identity
    }
}

private extension CGRect {
    var area: CGFloat { max(0, width) * max(0, height) }
}
