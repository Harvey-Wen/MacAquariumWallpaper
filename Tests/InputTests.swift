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
            record(owner: "MacAquariumWallpaper", pid: 42, layer: 0, bounds: display),
            record(owner: "Dock", pid: 2, layer: 20, bounds: display),
            record(owner: "Dock", pid: 2, layer: 20, bounds: CGRect(x: 400, y: 840, width: 600, height: 60)),
            record(owner: "Safari", pid: 3, layer: 0, bounds: display, alpha: 0)
        ]
        let exclusions = DesktopInputGeometry.blockers(from: records, screenFrame: display, primaryTop: 900, ownPID: ownPID)
        check(exclusions.count == 2, "Finder file windows and actual Dock block; wallpaper/own/transparent hosts do not")
        check(exclusions.contains(CGRect(x: 20, y: 550, width: 300, height: 250)), "Finder files are not treated as desktop")

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
