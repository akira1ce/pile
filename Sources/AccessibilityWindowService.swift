import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import QuartzCore

final class AccessibilityWindowService: @unchecked Sendable {
    private struct AnimationPhase {
        let updates: [WindowFrameUpdate]
        let starts: [WindowFrame]
        let targets: [WindowFrame]
        let activeIndices: [Int]
        let changesSize: Bool
        let startTime: CFTimeInterval
        let duration: TimeInterval
        let tickCount: Int
        let onFinish: @Sendable (Bool) -> Void
    }

    private let queue = DispatchQueue(label: "com.akira1ce.pile.accessibility", qos: .userInitiated)
    private let messagingTimeout: Float = 0.35
    private let tickInterval: TimeInterval = 1.0 / 60.0
    private let moveDuration: TimeInterval = 0.14
    private let resizeDuration: TimeInterval = 0.16
    private let settleDelay: TimeInterval = 0.05
    private var activeAnimationID: UUID?
    private var activeAnimationCompletion: (@Sendable (WindowFrameOperationResult) -> Void)?

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
            processIDs.removeAll { $0 == ProcessInfo.processInfo.processIdentifier }

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
                .filter {
                    $0.layer == 0
                        && $0.processID > 0
                        && $0.processID != ProcessInfo.processInfo.processIdentifier
                }
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

    func setFrame(
        _ frame: WindowFrame,
        for window: WindowIdentity,
        completion: @escaping @Sendable (WindowFrameOperationResult) -> Void
    ) {
        setFrames([WindowFrameUpdate(window: window, frame: frame)], animated: false, completion: completion)
    }

    func setFrames(
        _ updates: [WindowFrameUpdate],
        animated: Bool,
        completion: @escaping @Sendable (WindowFrameOperationResult) -> Void
    ) {
        guard !updates.isEmpty else {
            completion(.completed)
            return
        }
        guard updates.allSatisfy({ $0.window.processID != ProcessInfo.processInfo.processIdentifier }) else {
            completion(.failed)
            return
        }

        queue.async {
            self.cancelActiveAnimation()

            guard animated else {
                var succeeded = true
                for update in updates {
                    succeeded = self.setSize(update.frame, on: update.window.accessibilityElement) && succeeded
                }
                for update in updates {
                    succeeded = self.setPosition(update.frame, on: update.window.accessibilityElement) && succeeded
                }
                Thread.sleep(forTimeInterval: self.settleDelay)
                completion(self.verify(updates) && succeeded ? .completed : .failed)
                return
            }

            // Read the untouched frames first so each phase starts from where the
            // window actually is.
            let startingFrames = updates.map { self.frame(of: $0.window.accessibilityElement) }
            guard !startingFrames.contains(where: { $0 == nil }) else {
                completion(.failed)
                return
            }

            let animationID = UUID()
            self.activeAnimationID = animationID
            self.activeAnimationCompletion = completion
            self.startAnimation(
                animationID: animationID,
                updates: updates,
                starts: startingFrames.compactMap { $0 }
            )
        }
    }

    private func startAnimation(animationID: UUID, updates: [WindowFrameUpdate], starts: [WindowFrame]) {
        // Position and size are two separate AX commits with no way to make them
        // atomic, so animating both at once shows a mixed "new origin, old size"
        // frame in between and the edges wobble. Move first, then resize, so only
        // one attribute changes at a time.
        let movedFrames = updates.indices.map { index in
            WindowFrame(
                x: updates[index].frame.x,
                y: updates[index].frame.y,
                width: starts[index].width,
                height: starts[index].height
            )
        }

        runPhase(
            animationID: animationID,
            updates: updates,
            from: starts,
            to: movedFrames,
            changesSize: false,
            duration: moveDuration,
            succeeded: true
        ) { [weak self] moveSucceeded in
            guard let self else { return }
            self.runPhase(
                animationID: animationID,
                updates: updates,
                from: movedFrames,
                to: updates.map(\.frame),
                changesSize: true,
                duration: self.resizeDuration,
                succeeded: moveSucceeded
            ) { [weak self] resizeSucceeded in
                guard let self else { return }
                self.queue.asyncAfter(deadline: .now() + self.settleDelay) { [weak self] in
                    self?.finishAnimation(
                        animationID: animationID,
                        updates: updates,
                        succeeded: resizeSucceeded
                    )
                }
            }
        }
    }

    private func runPhase(
        animationID: UUID,
        updates: [WindowFrameUpdate],
        from starts: [WindowFrame],
        to targets: [WindowFrame],
        changesSize: Bool,
        duration: TimeInterval,
        succeeded: Bool,
        onFinish: @escaping @Sendable (Bool) -> Void
    ) {
        guard activeAnimationID == animationID else { return }

        let activeIndices = updates.indices.filter { index in
            !starts[index].isApproximatelyEqual(to: targets[index], tolerance: 0.5)
        }
        guard !activeIndices.isEmpty else {
            onFinish(succeeded)
            return
        }

        let phase = AnimationPhase(
            updates: updates,
            starts: starts,
            targets: targets,
            activeIndices: activeIndices,
            changesSize: changesSize,
            startTime: CACurrentMediaTime(),
            duration: duration,
            tickCount: max(1, Int((duration / tickInterval).rounded(.up))),
            onFinish: onFinish
        )
        queue.asyncAfter(deadline: .now() + tickInterval) { [weak self] in
            self?.runPhaseTick(animationID: animationID, phase: phase, tick: 1, succeeded: succeeded)
        }
    }

    private func runPhaseTick(animationID: UUID, phase: AnimationPhase, tick: Int, succeeded: Bool) {
        guard activeAnimationID == animationID else { return }

        // Interpolate from elapsed time instead of a step index: when an AX call
        // stalls, the next tick renders the frame for *now* rather than replaying
        // the ones it missed, so the total duration stays put.
        let elapsed = CACurrentMediaTime() - phase.startTime
        let progress = WindowAnimationCurve.easeOut.progress(at: elapsed / phase.duration)
        var succeeded = succeeded
        for index in phase.activeIndices {
            let start = phase.starts[index]
            let target = phase.targets[index]
            let frame = WindowFrame(
                x: start.x + (target.x - start.x) * progress,
                y: start.y + (target.y - start.y) * progress,
                width: start.width + (target.width - start.width) * progress,
                height: start.height + (target.height - start.height) * progress
            )
            let element = phase.updates[index].window.accessibilityElement
            if phase.changesSize {
                succeeded = setSize(frame, on: element) && succeeded
            } else {
                succeeded = setPosition(frame, on: element) && succeeded
            }
        }

        guard tick < phase.tickCount else {
            phase.onFinish(succeeded)
            return
        }

        let succeededSoFar = succeeded
        let now = CACurrentMediaTime()
        // Skip slots a stalled AX call already missed, and land the last tick exactly
        // on the end of the phase so the next one starts without a dead gap.
        let nextTick = min(Int(((now - phase.startTime) / tickInterval).rounded(.down)) + 1, phase.tickCount)
        let deadline = phase.startTime + min(Double(nextTick) * tickInterval, phase.duration)
        queue.asyncAfter(deadline: .now() + max(0, deadline - now)) { [weak self] in
            self?.runPhaseTick(animationID: animationID, phase: phase, tick: nextTick, succeeded: succeededSoFar)
        }
    }

    private func finishAnimation(animationID: UUID, updates: [WindowFrameUpdate], succeeded: Bool) {
        guard activeAnimationID == animationID else { return }
        let completion = activeAnimationCompletion
        activeAnimationID = nil
        activeAnimationCompletion = nil
        completion?(verify(updates) && succeeded ? .completed : .failed)
    }

    private func cancelActiveAnimation() {
        guard activeAnimationID != nil else { return }
        let completion = activeAnimationCompletion
        activeAnimationID = nil
        activeAnimationCompletion = nil
        completion?(.cancelled)
    }

    private func verify(_ updates: [WindowFrameUpdate]) -> Bool {
        updates.allSatisfy { update in
            guard let observed = frame(of: update.window.accessibilityElement) else { return false }
            return observed.isApproximatelyEqual(to: update.frame, tolerance: 4)
        }
    }

    private func setSize(_ frame: WindowFrame, on element: AXUIElement) -> Bool {
        var size = CGSize(width: frame.width, height: frame.height)
        guard let sizeValue = AXValueCreate(.cgSize, &size) else { return false }
        return AXUIElementSetAttributeValue(
            element,
            kAXSizeAttribute as CFString,
            sizeValue
        ) == .success
    }

    private func setPosition(_ frame: WindowFrame, on element: AXUIElement) -> Bool {
        var point = CGPoint(x: frame.x, y: frame.y)
        guard let positionValue = AXValueCreate(.cgPoint, &point) else { return false }
        return AXUIElementSetAttributeValue(
            element,
            kAXPositionAttribute as CFString,
            positionValue
        ) == .success
    }

    func raise(_ window: WindowIdentity, completion: @escaping @Sendable (Bool) -> Void) {
        guard window.processID != ProcessInfo.processInfo.processIdentifier else {
            completion(false)
            return
        }

        queue.async {
            completion(AXUIElementPerformAction(window.accessibilityElement, kAXRaiseAction as CFString) == .success)
        }
    }

    func close(_ window: WindowIdentity, completion: @escaping @Sendable (Bool) -> Void) {
        guard window.processID != ProcessInfo.processInfo.processIdentifier else {
            completion(false)
            return
        }

        queue.async {
            guard let button = self.axElement(self.attribute(window.accessibilityElement, kAXCloseButtonAttribute)) else {
                completion(false)
                return
            }
            completion(AXUIElementPerformAction(button, kAXPressAction as CFString) == .success)
        }
    }

    func minimize(_ window: WindowIdentity, completion: @escaping @Sendable (Bool) -> Void) {
        guard window.processID != ProcessInfo.processInfo.processIdentifier else {
            completion(false)
            return
        }

        queue.async {
            completion(AXUIElementSetAttributeValue(
                window.accessibilityElement,
                kAXMinimizedAttribute as CFString,
                kCFBooleanTrue
            ) == .success)
        }
    }

    /// Focuses a window that may belong to a background app.
    ///
    /// `kAXRaiseAction` alone only reorders the window inside its own app, so the
    /// app has to come forward too. `NSRunningApplication.activate()` can't do that
    /// from an app that isn't already active — since macOS 14 activation requires
    /// the active app to yield first — so the app is brought forward through AX
    /// instead, which works for any trusted accessibility client.
    func focus(_ window: WindowIdentity, completion: @escaping @Sendable (Bool) -> Void) {
        guard window.processID != ProcessInfo.processInfo.processIdentifier else {
            completion(false)
            return
        }

        queue.async {
            let element = window.accessibilityElement
            let app = AXUIElementCreateApplication(window.processID)
            AXUIElementSetMessagingTimeout(app, self.messagingTimeout)

            // Make the window the app's focused window before the app comes
            // forward, otherwise activating it raises whichever window it last had.
            AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
            AXUIElementPerformAction(element, kAXRaiseAction as CFString)
            let frontmost = AXUIElementSetAttributeValue(app, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
            completion(frontmost == .success)
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
