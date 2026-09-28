import AppKit

@main struct InputTests {
    static func main() {
        var checks = 0
        func check(_ value: @autoclosure () -> Bool, _ message: String) {
            guard value() else { fatalError(message) }
            checks += 1
        }
        let screen = CGRect(x: -1440, y: -200, width: 1440, height: 900)
        let usable = screen.insetBy(dx: 0, dy: 30)
        let window = CGRect(x: -1200, y: 100, width: 500, height: 400)
        let geometry = DesktopInputGeometry(screenFrame: screen, visibleFrame: usable,
                                            blockingRects: [window], valid: true)
        check(geometry.containsDesktop(CGPoint(x: -1300, y: 0)), "visible desktop accepts input")
        check(!geometry.containsDesktop(CGPoint(x: -1000, y: 300)), "normal window excludes input")
        check(!geometry.containsDesktop(CGPoint(x: -1300, y: 695)), "menu region excludes input")
        check(!geometry.containsDesktop(CGPoint(x: 10, y: 0)), "other screen excludes input")
        check(geometry.localPoint(CGPoint(x: -1300, y: 0)) == SIMD2<Float>(140, 200), "negative screen coordinates")
        check(DesktopInputGeometry.appKitRect(CGRect(x: 10, y: 80, width: 300, height: 200), primaryTop: 900)
              == CGRect(x: 10, y: 620, width: 300, height: 200), "CG to AppKit coordinates")
        var missing = geometry; missing.valid = false
        check(!missing.containsDesktop(CGPoint(x: -1300, y: 0)), "unknown geometry rejects interaction")

        let ownPID: pid_t = 42
        func record(owner: String, pid: Int, layer: Int, bounds: CGRect, alpha: Float = 1) -> [String: Any] {
            [kCGWindowOwnerName as String: owner, kCGWindowOwnerPID as String: pid,
             kCGWindowLayer as String: layer, kCGWindowAlpha as String: alpha,
             kCGWindowBounds as String: bounds.dictionaryRepresentation]
        }
        let display = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let appBounds = CGRect(x: 20, y: 100, width: 300, height: 250)
        let records = [
            record(owner: "Finder", pid: 1, layer: -2147483603, bounds: display),
            record(owner: "Finder", pid: 1, layer: 0, bounds: appBounds),
            record(owner: "MacAquariumWallpaper", pid: 42, layer: -2147483622, bounds: display),
            record(owner: "Dock", pid: 2, layer: 20, bounds: display),
            record(owner: "Dock", pid: 2, layer: 20, bounds: CGRect(x: 400, y: 840, width: 600, height: 60)),
            record(owner: "Safari", pid: 3, layer: 0, bounds: display, alpha: 0)
        ]
        let snapshot = DesktopWindowSnapshot.parse(records: records, screenFrame: display,
                                                   primaryTop: 900, ownPID: ownPID)
        check(snapshot.valid, "normal desktop snapshot remains available")
        check(snapshot.blockingRects.count == 2, "Finder file windows and actual Dock block; known Dock host does not")
        check(snapshot.blockingRects.contains(CGRect(x: 20, y: 550, width: 300, height: 250)), "Finder files are not treated as desktop")
        check(snapshot.blockedEventPIDs.contains(2), "Dock event targets are rejected even when its transparent host is ignored")
        let editorBounds = CGRect(x: 500, y: 200, width: 760, height: 560)
        let withEditor = DesktopWindowSnapshot.parse(records: records + [
            record(owner: "MacAquariumWallpaper", pid: 42, layer: 0, bounds: editorBounds)
        ], screenFrame: display, primaryTop: 900, ownPID: ownPID)
        let editorGeometry = DesktopInputGeometry(screenFrame: display, visibleFrame: display,
            blockingRects: withEditor.blockingRects, blockedEventPIDs: withEditor.blockedEventPIDs, valid: withEditor.valid)
        check(!editorGeometry.containsDesktop(CGPoint(x: 800, y: 500)), "painting window blocks pond hover beneath it")
        check(editorGeometry.containsDesktop(CGPoint(x: 1350, y: 500)), "water outside painting window remains interactive")
        check(!editorGeometry.containsDesktop(CGPoint(x: 1350, y: 500), eventTargetPID: 42), "own controls cannot create pond clicks")
        check(!DesktopWindowSnapshot.parse(records: [], screenFrame: display, primaryTop: 900, ownPID: ownPID).valid,
              "empty window snapshots fail closed")
        var malformed = records
        malformed.append([kCGWindowOwnerPID as String: 9, kCGWindowLayer as String: 0])
        check(!DesktopWindowSnapshot.parse(records: malformed, screenFrame: display,
                                           primaryTop: 900, ownPID: ownPID).valid,
              "malformed window records fail closed")
        let systemOverlay = records + [record(owner: "WindowManager", pid: 4, layer: 20, bounds: display)]
        let suppressed = DesktopWindowSnapshot.parse(records: systemOverlay, screenFrame: display,
                                                      primaryTop: 900, ownPID: ownPID)
        check(!suppressed.valid && suppressed.status.contains("系统界面"),
              "ambiguous full-screen system UI suppresses input")
        let geometryWithTargets = DesktopInputGeometry(screenFrame: display, visibleFrame: display,
                                                       blockingRects: snapshot.blockingRects,
                                                       blockedEventPIDs: snapshot.blockedEventPIDs, valid: true)
        check(geometryWithTargets.containsDesktop(CGPoint(x: 1000, y: 300), eventTargetPID: 1),
              "Finder desktop target remains interactive")
        check(!geometryWithTargets.containsDesktop(CGPoint(x: 1000, y: 300), eventTargetPID: 2),
              "system host event target is not desktop interaction")
        check(!DesktopEventPolicy.allows(CGPoint(x: 1000, y: 300), targetPID: nil,
                                         geometry: geometryWithTargets),
              "events without a target PID fail closed")
        let unavailable = DesktopInputReadiness(monitorInstalled: false, geometryValid: true,
                                                geometryStatus: "桌面输入可用")
        check(!unavailable.available && unavailable.status.contains("监听"),
              "missing event monitor is explicitly unavailable")

        var gesture = DesktopGesture()
        check(!gesture.drag(isDesktop: true), "drag from another app cannot start ocean gesture")
        check(gesture.down(isDesktop: true), "desktop click begins gesture")
        check(gesture.drag(isDesktop: true), "desktop drag continues")
        check(!gesture.drag(isDesktop: false), "entering app ends gesture")
        check(!gesture.drag(isDesktop: true), "cannot resume cancelled drag")
        check(!gesture.down(isDesktop: false), "app click rejected")
        _ = gesture.down(isDesktop: true); gesture.end()
        check(!gesture.drag(isDesktop: true), "mouse release ends drag")
        print("PASS: \(checks) input geometry and gesture checks")
    }
}
