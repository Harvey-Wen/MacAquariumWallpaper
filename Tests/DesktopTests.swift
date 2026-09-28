import AppKit
import MetalKit

@main struct DesktopTests {
    @MainActor static func main() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let screens = NSScreen.screens
        let beforeOptions = screens.map { NSWorkspace.shared.desktopImageOptions(for: $0)! }
        let before = screens.map { NSWorkspace.shared.desktopImageURL(for: $0) }
        let drawingsDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("pond-drawings-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: drawingsDirectory) }
        let controller = try DesktopController(shaderURL: URL(fileURLWithPath: "Resources/Ocean.metal"),
            drawingStore: FishDrawingStore(directory: drawingsDirectory))
        defer { controller.stop() }
        var count = 0
        func check(_ condition: @autoclosure () -> Bool, _ label: String) {
            guard condition() else { controller.stop(); fatalError(label) }
            count += 1
        }
        func advance(_ seconds: Double = 0.16) { RunLoop.current.run(until: Date(timeIntervalSinceNow: seconds)) }
        controller.start(); advance()
        let sunnyBackdrop = NSWorkspace.shared.desktopImageURL(for: screens[0])!
        check(controller.backdropError == nil && sunnyBackdrop != before[0], "native sunny backdrop applied")
        let bitmap = NSBitmapImageRep(data: try Data(contentsOf: sunnyBackdrop))!
        let pixels = screens[0].convertRectToBacking(screens[0].frame).size
        check(bitmap.pixelsWide == Int(pixels.width) && bitmap.pixelsHigh == Int(pixels.height), "backdrop uses exact screen backing size")
        check(controller.window.isVisible, "overlay visible")
        check(controller.window.ignoresMouseEvents, "overlay passes input through")
        check(!controller.window.isOpaque && !controller.view.isOpaque && controller.view.layer?.isOpaque == true,
              "pass-through window with opaque pond backing layer")
        check(!controller.window.canBecomeKey && !controller.window.canBecomeMain, "overlay cannot steal focus")
        check(controller.window.level.rawValue > CGWindowLevelForKey(.desktopWindow)
              && controller.window.level.rawValue < CGWindowLevelForKey(.desktopIconWindow), "between wallpaper and icons")
        check(controller.window.frame == screens[0].frame, "full main screen")
        check(controller.simulation.fish.count == 30, "all koi present")
        check(controller.weather == .sunny && controller.status.contains("30 条锦鲤") && controller.status.contains("晴天"), "live koi and sunny status")
        controller.weather = .rainy; advance(1.1)
        let rainyBackdrop = NSWorkspace.shared.desktopImageURL(for: screens[0])!
        check(rainyBackdrop != sunnyBackdrop && controller.backdropError == nil, "weather replaces system backing")
        check(!FileManager.default.fileExists(atPath: sunnyBackdrop.path), "superseded frame cleaned")
        check(controller.simulation.weather == .rainy && controller.status.contains("雨天"), "rainy control reaches simulation and status")
        if !controller.reducedMotion {
            check(controller.simulation.frame(waterStrength: 0.45).weatherAmount > 0, "rain transitions during animation")
        }
        let frameCount = controller.frameCount
        let pointerCenter = controller.simulation.size * 0.5
        controller.simulation.trackPointer(pointerCenter)
        controller.simulation.update(deltaTime: 0.2)
        let pausedTime = controller.simulation.time
        let pausedFish = controller.simulation.fish.map(\.position)
        let pausedLeaves = controller.simulation.leaves.map(\.position)
        if !controller.reducedMotion { check(!pausedLeaves.isEmpty, "falling leaf reached desktop scene") }
        let pausedWeatherAmount = controller.simulation.frame(waterStrength: 0.45).weatherAmount
        controller.paused = true; advance()
        let motionBeforePause = controller.simulation.ripples.filter { $0.source == .motion }.count
        controller.simulation.trackPointer(pointerCenter + SIMD2(15, 0))
        check(controller.simulation.ripples.filter { $0.source == .motion }.count == motionBeforePause,
              "pause clears pointer trail before resume")
        check(NSWorkspace.shared.desktopImageURL(for: screens[0]) == rainyBackdrop, "pause retains backing")
        check(controller.frameCount == frameCount && controller.window.isVisible, "pause keeps still image")
        check(controller.simulation.time == pausedTime && controller.simulation.fish.map(\.position) == pausedFish
              && controller.simulation.leaves.map(\.position) == pausedLeaves, "pause freezes fish and leaves")
        controller.weather = .sunny; advance()
        check(controller.simulation.weather == .sunny && controller.status.contains("晴天"), "weather selection works while paused")
        check(controller.simulation.time == pausedTime
              && controller.simulation.frame(waterStrength: 0.45).weatherAmount == pausedWeatherAmount, "pause freezes rain transition")
        check(!controller.input.enabled, "pause stops input")
        controller.enabled = false
        check(NSWorkspace.shared.desktopImageURL(for: screens[0]) == before[0], "disable restores original image")
        check(NSDictionary(dictionary: NSWorkspace.shared.desktopImageOptions(for: screens[0])!).isEqual(to: beforeOptions[0]), "disable restores original options exactly")
        check(!controller.window.isVisible, "disable hides overlay")
        controller.enabled = true
        check(controller.window.isVisible && controller.paused, "re-enable retains pause")
        controller.paused = false; advance()
        if !controller.reducedMotion { check(controller.frameCount > frameCount, "resume renders") }
        if !controller.reducedMotion {
            check(controller.simulation.frame(waterStrength: 0.45).weatherAmount < pausedWeatherAmount, "sunny transition resumes")
        }
        controller.interactive = false
        check(!controller.input.enabled, "interaction switch")
        controller.interactive = true
        let preSleepImage = NSWorkspace.shared.desktopImageURL(for: screens[0])
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
        check(NSWorkspace.shared.desktopImageURL(for: screens[0]) == preSleepImage, "sleep retains backing")
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
        check(before == after, "stop restores all original wallpaper URLs")
        check(screens.enumerated().allSatisfy { index, screen in
            NSDictionary(dictionary: NSWorkspace.shared.desktopImageOptions(for: screen)!).isEqual(to: beforeOptions[index])
        }, "stop restores all original options exactly")
        try journalTests(screen: screens[0], check: { check($0, $1) })
        print("PASS: \(count) native desktop and lifecycle checks")
    }

    @MainActor static func journalTests(screen: NSScreen, check: (Bool, String) -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("pond-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = URL(fileURLWithPath: "/original.heic")
        let userChoice = URL(fileURLWithPath: "/user-choice.heic")
        var current = original
        let originalOptions: [NSWorkspace.DesktopImageOptionKey: Any] = [.imageScaling: 3, .allowClipping: false, .fillColor: NSColor.systemBlue]
        var options = originalOptions
        var failSet = false
        var sets = 0
        func helper() throws -> DesktopBackdrop {
            try DesktopBackdrop(directory: directory, readImage: { _ in current }, readOptions: { _ in options }, setImage: { url, _, newOptions in
                if failSet { throw NSError(domain: "Test", code: 1) }
                sets += 1; current = url; options = newOptions
            })
        }
        func render(_ url: URL) throws { try Data("test".utf8).write(to: url) }
        let first = try helper()
        try first.apply(screen: screen, key: "sunny", render: render)
        let firstImage = current
        try first.apply(screen: screen, key: "sunny", render: render)
        check(sets == 1 && current == firstImage, "same backing is not regenerated")
        current = userChoice
        try first.apply(screen: screen, key: "rainy", render: render)
        try first.apply(screen: screen, key: "sunny", render: render)
        try first.restoreAll()
        check(current == userChoice && sets == 1, "user override survives weather and stop")
        current = original; options = originalOptions
        try first.apply(screen: screen, key: "sunny", render: render)
        let recovered = try helper() // Simulates another executable using the same stable journal.
        try recovered.restoreAll()
        check(current == original && NSDictionary(dictionary: options).isEqual(to: originalOptions), "new helper restores crash journal and color options")
        try recovered.apply(screen: screen, key: "sunny", render: render)
        failSet = true
        do { try recovered.restoreAll(); check(false, "restore failure must surface") }
        catch { check(true, "restore failure surfaces") }
        let saved = try JSONDecoder().decode([DesktopBackdrop.Record].self, from: Data(contentsOf: directory.appendingPathComponent("ownership.json")))
        check(saved.count == 1 && saved[0].original == original, "failed restoration retains original recovery record")
        failSet = false
        try helper().restoreAll()
        check(current == original, "next launch retries failed restoration")
        let bounded = try helper()
        try bounded.apply(screen: screen, key: "sunny", render: render)
        for index in 0..<6 { try bounded.apply(screen: screen, key: "weather-\(index)", render: render) }
        let generated = try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasSuffix(".png") }
        check(generated.count == 1, "weather updates retain only one generated frame")
        failSet = true
        for index in 0..<4 {
            do { try bounded.apply(screen: screen, key: "failed-\(index)", render: render); check(false, "apply failure must surface") }
            catch { check(true, "apply failure surfaces") }
        }
        check(try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasSuffix(".png") }.count == 2, "failed replacements retain at most current and pending frame")
        failSet = false
        try bounded.restoreAll(screens: [])
        check(current != original, "disconnected display retains ownership")
        try bounded.restoreAll()
        check(try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasSuffix(".png") }.isEmpty, "successful restoration cleans generated frames")
        let noOptions = try helper()
        options = [:]
        try noOptions.apply(screen: screen, key: "sunny", render: render)
        try noOptions.restoreAll()
        check(current == original && options.isEmpty, "empty public options are passed back unchanged")
        let previousSets = sets
        options = originalOptions
        let missingOptions = try DesktopBackdrop(directory: directory, readImage: { _ in current }, readOptions: { _ in nil }, setImage: { _, _, _ in sets += 1 })
        do { try missingOptions.apply(screen: screen, key: "sunny", render: render); check(false, "missing options must be rejected") }
        catch { check(sets == previousSets, "missing backup prevents system change") }
        var queued: URL?
        let delayed = try DesktopBackdrop(directory: directory, readImage: { _ in original }, readOptions: { _ in originalOptions }, setImage: { url, _, _ in queued = url == original ? nil : url })
        do { try delayed.apply(screen: screen, key: "late", render: render); check(false, "late readback must surface") }
        catch { check(queued != nil, "timed out system request remains journaled") }
        try delayed.restoreAll()
        check(queued == nil, "immediate disable reasserts original after unacknowledged apply")
        let renderRace = try helper()
        let setsBeforeRace = sets
        do {
            try renderRace.apply(screen: screen, key: "first", render: { url in
                try render(url); current = userChoice
            })
            check(false, "first-render user change must surface")
        } catch { check(current == userChoice, "first-render user choice is preserved") }
        var renderedAgain = false
        try renderRace.apply(screen: screen, key: "next-weather", render: { url in renderedAgain = true; try render(url) })
        check(!renderedAgain && sets == setsBeforeRace && current == userChoice, "first-render override suppresses subsequent weather replacement")
        try renderRace.restoreAll()
        try renderRace.apply(screen: screen, key: "explicit-enable", render: render)
        check(current != userChoice, "explicit disable and enable resets first-render override")
        try renderRace.restoreAll()
        check(current == userChoice, "explicit re-enable backs up the user-selected image")
        current = original; options = originalOptions

        var pendingImage: URL?
        var delayReplacement = false
        let lateReplacement = try DesktopBackdrop(directory: directory, readImage: { _ in current }, readOptions: { _ in originalOptions }, setImage: { url, _, _ in
            if delayReplacement { pendingImage = url } else { current = url }
        })
        try lateReplacement.apply(screen: screen, key: "A", render: render)
        let imageA = current
        delayReplacement = true
        do { try lateReplacement.apply(screen: screen, key: "B", render: render); check(false, "replacement timeout must surface") }
        catch { check(pendingImage != nil, "late replacement is outstanding") }
        var renderedC = false
        do {
            try lateReplacement.apply(screen: screen, key: "C", render: { url in
                renderedC = true; current = pendingImage!; try render(url)
            })
            check(false, "retry must be refused while replacement is outstanding")
        } catch { check(!renderedC, "pending replacement prevents another render and request") }
        check(FileManager.default.fileExists(atPath: imageA.path) && FileManager.default.fileExists(atPath: pendingImage!.path), "retry retains both current and outstanding images")
        current = pendingImage! // The original timed-out request finally completes.
        delayReplacement = false
        try lateReplacement.restoreAll()
        check(current == original, "late completion remains owned and restores original wallpaper")
        check(!FileManager.default.fileExists(atPath: imageA.path) && !FileManager.default.fileExists(atPath: pendingImage!.path), "late completion files clean only after restoration")
        let previousSetsAfterRaces = sets
        let unwritable = try helper()
        let journal = directory.appendingPathComponent("ownership.json")
        try FileManager.default.removeItem(at: journal)
        try FileManager.default.createDirectory(at: journal, withIntermediateDirectories: false)
        do { try unwritable.apply(screen: screen, key: "sunny", render: render); check(false, "failed journal must be rejected") }
        catch { check(sets == previousSetsAfterRaces && current == original, "failed durable backup never replaces user wallpaper") }

    }
}
