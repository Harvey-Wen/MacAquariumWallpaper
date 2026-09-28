import AppKit

struct DesktopInputGeometry {
    var screenFrame: CGRect
    var visibleFrame: CGRect
    var blockingRects: [CGRect]
    var blockedEventPIDs: Set<Int> = []
    var valid: Bool

    func containsDesktop(_ point: CGPoint, eventTargetPID: Int? = nil) -> Bool {
        valid && screenFrame.contains(point) && visibleFrame.contains(point)
            && (eventTargetPID.map { !blockedEventPIDs.contains($0) } ?? true)
            && !blockingRects.contains { $0.contains(point) }
    }

    func localPoint(_ point: CGPoint) -> SIMD2<Float> {
        SIMD2(Float(point.x - screenFrame.minX), Float(point.y - screenFrame.minY))
    }

    static func appKitRect(_ rect: CGRect, primaryTop: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryTop - rect.maxY, width: rect.width, height: rect.height)
    }
}

struct DesktopWindowSnapshot {
    var blockingRects: [CGRect]
    var blockedEventPIDs: Set<Int>
    var valid: Bool
    var status: String

    private static let systemOwners: Set<String> = [
        "Dock", "WindowManager", "Window Server", "Control Center", "Control Centre",
        "Notification Center", "Notification Centre", "SystemUIServer"
    ]

    static func parse(records: [[String: Any]], screenFrame: CGRect,
                      primaryTop: CGFloat, ownPID: pid_t) -> DesktopWindowSnapshot {
        guard !records.isEmpty else {
            return DesktopWindowSnapshot(blockingRects: [], blockedEventPIDs: [], valid: false,
                                         status: "窗口信息暂不可用")
        }
        var blockers: [CGRect] = []
        var blockedPIDs = Set<Int>()
        for record in records {
            guard let pid = (record[kCGWindowOwnerPID as String] as? NSNumber)?.intValue,
                  let level = (record[kCGWindowLayer as String] as? NSNumber)?.intValue,
                  let alpha = (record[kCGWindowAlpha as String] as? NSNumber)?.doubleValue,
                  let dictionary = record[kCGWindowBounds as String] as? [String: Any],
                  let cgRect = CGRect(dictionaryRepresentation: dictionary as CFDictionary),
                  [cgRect.minX, cgRect.minY, cgRect.width, cgRect.height].allSatisfy(\.isFinite),
                  cgRect.width >= 0, cgRect.height >= 0 else {
                return DesktopWindowSnapshot(blockingRects: [], blockedEventPIDs: [], valid: false,
                                             status: "窗口信息不完整，交互暂不可用")
            }
            let owner = record[kCGWindowOwnerName as String] as? String ?? ""
            if systemOwners.contains(owner) || pid == Int(ownPID) { blockedPIDs.insert(pid) }
            guard level >= 0, alpha > 0,
                  cgRect.width > 1, cgRect.height > 1 else { continue }
            let rect = DesktopInputGeometry.appKitRect(cgRect, primaryTop: primaryTop)
            guard rect.intersects(screenFrame) else { continue }
            let intersection = rect.intersection(screenFrame)
            let nearFullScreen = intersection.width * intersection.height
                >= screenFrame.width * screenFrame.height * 0.95
            // Verified on the target system: Dock owns one persistent, transparent
            // layer-20 host. Its event PID is still rejected below. Any other large
            // system surface is ambiguous without AX and therefore fails closed.
            if owner == "Dock", level == 20, nearFullScreen { continue }
            if systemOwners.contains(owner), nearFullScreen {
                return DesktopWindowSnapshot(blockingRects: [], blockedEventPIDs: blockedPIDs,
                                             valid: false, status: "系统界面覆盖桌面，交互暂不可用")
            }
            blockers.append(rect)
        }
        return DesktopWindowSnapshot(blockingRects: blockers, blockedEventPIDs: blockedPIDs,
                                     valid: true, status: "桌面输入可用")
    }
}

struct DesktopInputReadiness {
    var monitorInstalled: Bool
    var geometryValid: Bool
    var geometryStatus: String

    var available: Bool { monitorInstalled && geometryValid }
    var status: String { monitorInstalled ? geometryStatus : "全局鼠标监听不可用" }
}

struct DesktopEventPolicy {
    static func allows(_ point: CGPoint, targetPID: Int?, geometry: DesktopInputGeometry) -> Bool {
        guard let targetPID else { return false }
        return geometry.containsDesktop(point, eventTargetPID: targetPID)
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
    private(set) var geometryQueryCount = 0
    private var primaryTop: CGFloat
    private var geometryStatus = "窗口信息暂不可用"
    private var eventStatus: String?

    var available: Bool { readiness.available }
    var status: String { available ? eventStatus ?? readiness.status : readiness.status }
    private var readiness: DesktopInputReadiness {
        DesktopInputReadiness(monitorInstalled: monitor != nil, geometryValid: geometry.valid,
                              geometryStatus: geometryStatus)
    }

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
        guard enabled else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard force || now - lastRefresh > 0.15 else { return }
        lastRefresh = now
        primaryTop = NSScreen.screens.first?.frame.maxY ?? screen.frame.maxY
        geometry.screenFrame = screen.frame
        geometry.visibleFrame = screen.visibleFrame
        geometryQueryCount += 1
        guard let records = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] else {
            geometry.valid = false; geometryStatus = "窗口信息暂不可用"; endGesture(); return
        }
        let snapshot = DesktopWindowSnapshot.parse(records: records, screenFrame: screen.frame,
                                                   primaryTop: primaryTop,
                                                   ownPID: ProcessInfo.processInfo.processIdentifier)
        geometry.blockingRects = snapshot.blockingRects
        geometry.blockedEventPIDs = snapshot.blockedEventPIDs
        geometry.valid = snapshot.valid
        geometryStatus = snapshot.status
        if !snapshot.valid { endGesture() }
    }

    func hover() -> SIMD2<Float>? {
        // State polling only ends a gesture if mouse-up was delivered to our own menu.
        // Clicks are always sourced from event notifications, never polling edges.
        if gesture.active && NSEvent.pressedMouseButtons & 1 == 0 { endGesture() }
        guard enabled else { return nil }
        let point = NSEvent.mouseLocation
        guard available, geometry.containsDesktop(point) else { return nil }
        return geometry.localPoint(point)
    }

    private func receive(_ event: NSEvent) {
        guard enabled else { return }
        if event.type == .leftMouseUp { endGesture(); return }
        if let screen = NSScreen.screens.first { refresh(screen: screen, force: event.type == .leftMouseDown) }
        guard let cgEvent = event.cgEvent else { endGesture(); return }
        let cgPoint = cgEvent.location
        let point = CGPoint(x: cgPoint.x, y: primaryTop - cgPoint.y)
        let target = cgEvent.getIntegerValueField(.eventTargetUnixProcessID)
        let targetPID = target > 0 ? Int(target) : nil
        eventStatus = targetPID == nil ? "事件目标不可用，本次交互已忽略" : nil
        let allowed = available && DesktopEventPolicy.allows(point, targetPID: targetPID, geometry: geometry)
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
