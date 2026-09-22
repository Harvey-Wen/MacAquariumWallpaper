import AppKit
import MetalKit

@main struct DesktopTests {
    @MainActor static func main() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let screens = NSScreen.screens
        let before = screens.map { NSWorkspace.shared.desktopImageURL(for: $0) }
        let controller = try DesktopController(shaderURL: URL(fileURLWithPath: "Resources/Ocean.metal"))
        var count = 0
        func check(_ condition: @autoclosure () -> Bool, _ label: String) {
            guard condition() else { fatalError(label) }
            count += 1
        }
        func advance(_ seconds: Double = 0.16) { RunLoop.current.run(until: Date(timeIntervalSinceNow: seconds)) }
        controller.start(); advance()
        check(controller.window.isVisible, "overlay visible")
        check(controller.window.ignoresMouseEvents, "overlay passes input through")
        check(!controller.window.isOpaque && !controller.view.isOpaque && controller.view.layer?.isOpaque == false, "all native alpha layers transparent")
        check(!controller.window.canBecomeKey && !controller.window.canBecomeMain, "overlay cannot steal focus")
        check(controller.window.level.rawValue > CGWindowLevelForKey(.desktopWindow)
              && controller.window.level.rawValue < CGWindowLevelForKey(.desktopIconWindow), "between wallpaper and icons")
        check(controller.window.frame == screens[0].frame, "full main screen")
        check(controller.simulation.fish.count == 29, "all fish present")
        let frameCount = controller.frameCount
        controller.paused = true; advance()
        check(controller.frameCount == frameCount && controller.window.isVisible, "pause keeps still image")
        check(!controller.input.enabled, "pause stops input")
        controller.enabled = false
        check(!controller.window.isVisible, "disable hides overlay")
        controller.enabled = true
        check(controller.window.isVisible && controller.paused, "re-enable retains pause")
        controller.paused = false; advance()
        if !controller.reducedMotion { check(controller.frameCount > frameCount, "resume renders") }
        controller.interactive = false
        check(!controller.input.enabled, "interaction switch")
        controller.interactive = true
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
        check(controller.sleeping && !controller.window.isVisible, "sleep hides and stops")
        controller.paused = true
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
        check(!controller.sleeping && controller.paused && controller.window.isVisible, "wake respects paused state")
        let rect = controller.window.frame
        controller.screenChanged()
        check(controller.window.frame == rect, "unchanged display stable")
        controller.stop()
        check(!controller.window.isVisible, "shutdown removes overlay")
        let after = screens.map { NSWorkspace.shared.desktopImageURL(for: $0) }
        check(before == after, "system wallpaper URLs unchanged")
        print("PASS: \(count) native desktop and lifecycle checks")
    }
}
