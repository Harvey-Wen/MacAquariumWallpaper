import AppKit

struct DesktopInputGeometry {
    var screenFrame: CGRect
    var visibleFrame: CGRect
    var blockingRects: [CGRect]
    var valid: Bool

    func containsDesktop(_ point: CGPoint) -> Bool {
        valid && screenFrame.contains(point) && visibleFrame.contains(point)
            && !blockingRects.contains { $0.contains(point) }
    }

    func localPoint(_ point: CGPoint) -> SIMD2<Float> {
        SIMD2(Float(point.x - screenFrame.minX), Float(point.y - screenFrame.minY))
    }

    static func appKitRect(_ rect: CGRect, primaryTop: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryTop - rect.maxY, width: rect.width, height: rect.height)
    }

    static func blockers(from records: [[String: Any]], screenFrame: CGRect,
                         primaryTop: CGFloat, ownPID: pid_t) -> [CGRect] {
        records.compactMap { record in
            guard let pid = record[kCGWindowOwnerPID as String] as? Int,
                  pid != Int(ownPID),
                  let level = record[kCGWindowLayer as String] as? Int, level >= 0,
                  ((record[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1) > 0,
                  let dictionary = record[kCGWindowBounds as String] as? [String: Any],
                  let cgRect = CGRect(dictionaryRepresentation: dictionary as CFDictionary),
                  cgRect.width > 1, cgRect.height > 1 else { return nil }
            let rect = appKitRect(cgRect, primaryTop: primaryTop)
            guard rect.intersects(screenFrame) else { return nil }
            let owner = record[kCGWindowOwnerName as String] as? String ?? ""
            // These system processes also own full-screen transparent event hosts.
            // Their compact panels and actual Dock still participate in hit testing.
            let systemHost = ["Dock", "WindowManager", "Window Server", "Control Center", "Notification Center", "SystemUIServer"].contains(owner)
            let intersection = rect.intersection(screenFrame)
            if systemHost && intersection.width * intersection.height >= screenFrame.width * screenFrame.height * 0.95 {
                return nil
            }
            return rect
        }
    }
}

struct DesktopGesture {
    private(set) var active = false
    mutating func down(isDesktop: Bool) -> Bool { active = isDesktop; return active }
    mutating func drag(isDesktop: Bool) -> Bool { active = active && isDesktop; return active }
    mutating func end() { active = false }
}

@MainActor final class DesktopInput {
    var onClick: ((SIMD2<Float>) -> Void)?
    var onDrag: ((SIMD2<Float>) -> Void)?
    var onEnd: (() -> Void)?
    var enabled = true {
        didSet { if !enabled { endGesture() } }
    }
    private(set) var clickCount = 0
    private(set) var dragCount = 0
    private(set) var rejectedCount = 0
    private(set) var geometry: DesktopInputGeometry
    private var monitor: Any?
    private var gesture = DesktopGesture()
    private var lastRefresh: TimeInterval = 0
    private var primaryTop: CGFloat

    init(screen: NSScreen) {
        primaryTop = NSScreen.screens.first?.frame.maxY ?? screen.frame.maxY
        geometry = DesktopInputGeometry(screenFrame: screen.frame, visibleFrame: screen.visibleFrame,
                                         blockingRects: [], valid: false)
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            MainActor.assumeIsolated { self?.receive(event) }
        }
        refresh(screen: screen, force: true)
    }

    func refresh(screen: NSScreen, force: Bool = false) {
        let now = ProcessInfo.processInfo.systemUptime
        guard force || now - lastRefresh > 0.15 else { return }
        lastRefresh = now
        primaryTop = NSScreen.screens.first?.frame.maxY ?? screen.frame.maxY
        geometry.screenFrame = screen.frame
        geometry.visibleFrame = screen.visibleFrame
        guard let records = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] else {
            geometry.valid = false; endGesture(); return
        }
        geometry.blockingRects = DesktopInputGeometry.blockers(from: records, screenFrame: screen.frame,
                                                               primaryTop: primaryTop, ownPID: ProcessInfo.processInfo.processIdentifier)
        geometry.valid = true
    }

    func hover() -> SIMD2<Float>? {
        // State polling only ends a gesture if mouse-up was delivered to our own menu.
        // Clicks are always sourced from event notifications, never polling edges.
        if gesture.active && NSEvent.pressedMouseButtons & 1 == 0 { endGesture() }
        let point = NSEvent.mouseLocation
        guard enabled, geometry.containsDesktop(point) else { return nil }
        return geometry.localPoint(point)
    }

    private func receive(_ event: NSEvent) {
        guard enabled else { return }
        if event.type == .leftMouseUp { endGesture(); return }
        if let screen = NSScreen.screens.first { refresh(screen: screen, force: event.type == .leftMouseDown) }
        guard let cgPoint = event.cgEvent?.location else { endGesture(); return }
        let point = CGPoint(x: cgPoint.x, y: primaryTop - cgPoint.y)
        let allowed = geometry.containsDesktop(point)
        if event.type == .leftMouseDown {
            if gesture.down(isDesktop: allowed) { clickCount += 1; onClick?(geometry.localPoint(point)) }
            else { rejectedCount += 1; onEnd?() }
        } else if event.type == .leftMouseDragged {
            if gesture.drag(isDesktop: allowed) { dragCount += 1; onDrag?(geometry.localPoint(point)) }
            else { onEnd?() }
        }
    }

    func endGesture() { gesture.end(); onEnd?() }
    func stop() {
        endGesture()
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
