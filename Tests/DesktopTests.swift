import AppKit
import MetalKit

@main struct DesktopTests {
    @MainActor static func main() {
        _ = NSApplication.shared
        Task { @MainActor in
            do { try await runTests(); exit(0) }
            catch { fputs("FAIL: \(error)\n", stderr); exit(1) }
        }
        NSApp.run()
    }

    @MainActor static func runTests() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        if CommandLine.arguments.contains("--weather-only") {
            try await weatherTransitionTests()
            return
        }
        let screens = NSScreen.screens
        let realWallpaper = CommandLine.arguments.contains("--real-wallpaper")
        // Real acceptance is explicit and also excludes legacy apps without a lock.
        if realWallpaper && !NSRunningApplication.runningApplications(withBundleIdentifier: "local.macaquariumwallpaper.app").isEmpty {
            throw NSError(domain: "DesktopTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "请先正常退出池塘，再运行真实壁纸验收"])
        }
        let beforeOptions = screens.map { NSWorkspace.shared.desktopImageOptions(for: $0)! }
        let before = screens.map { NSWorkspace.shared.desktopImageURL(for: $0) }
        let drawingsDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("pond-drawings-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: drawingsDirectory) }
        var images = Dictionary(uniqueKeysWithValues: screens.map { (DesktopBackdrop.displayIdentifier($0), NSWorkspace.shared.desktopImageURL(for: $0)!) })
        var options = Dictionary(uniqueKeysWithValues: screens.map { (DesktopBackdrop.displayIdentifier($0), NSWorkspace.shared.desktopImageOptions(for: $0)!) })
        let readImage: (NSScreen) -> URL? = { screen in realWallpaper ? NSWorkspace.shared.desktopImageURL(for: screen) : images[DesktopBackdrop.displayIdentifier(screen)] }
        let readOptions: (NSScreen) -> [NSWorkspace.DesktopImageOptionKey: Any]? = { screen in realWallpaper ? NSWorkspace.shared.desktopImageOptions(for: screen) : options[DesktopBackdrop.displayIdentifier(screen)] }
        let backdrop = try realWallpaper ? DesktopBackdrop() : DesktopBackdrop(directory: drawingsDirectory.appendingPathComponent("backdrop"), readImage: readImage, readOptions: readOptions, setImage: { url, screen, value in
            images[DesktopBackdrop.displayIdentifier(screen)] = url
            options[DesktopBackdrop.displayIdentifier(screen)] = value
        })
        let controller = try DesktopController(shaderURL: URL(fileURLWithPath: "Resources/Ocean.metal"),
            backdrop: backdrop, drawingStore: FishDrawingStore(directory: drawingsDirectory))
        defer { controller.stop() }
        var count = 0
        func check(_ condition: @autoclosure () -> Bool, _ label: String) {
            guard condition() else { controller.stop(); fatalError(label) }
            count += 1
        }
        func advance(_ seconds: Double = 0.16) { RunLoop.current.run(until: Date(timeIntervalSinceNow: seconds)) }
        controller.start(); await controller.waitForBackdrop(); advance()
        let sunnyBackdrop = readImage(screens[0])!
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
        let rainyBackdrop = readImage(screens[0])!
        check(rainyBackdrop == sunnyBackdrop && controller.backdropError == nil, "weather retains system backing")
        check(FileManager.default.fileExists(atPath: sunnyBackdrop.path), "stable backing remains available")
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
        let pausedPrecipitation = controller.simulation.frame(waterStrength: 0.45).precipitation
        controller.paused = true; advance()
        let motionBeforePause = controller.simulation.ripples.filter { $0.source == .motion }.count
        controller.simulation.trackPointer(pointerCenter + SIMD2(15, 0))
        check(controller.simulation.ripples.filter { $0.source == .motion }.count == motionBeforePause,
              "pause clears pointer trail before resume")
        check(readImage(screens[0]) == rainyBackdrop, "pause retains backing")
        check(controller.frameCount == frameCount && controller.window.isVisible, "pause keeps still image")
        check(controller.simulation.time == pausedTime && controller.simulation.fish.map(\.position) == pausedFish
              && controller.simulation.leaves.map(\.position) == pausedLeaves, "pause freezes fish and leaves")
        controller.weather = .sunny; advance()
        check(controller.simulation.weather == .sunny && controller.status.contains("晴天"), "weather selection works while paused")
        check(controller.simulation.time == pausedTime
              && controller.simulation.frame(waterStrength: 0.45).weatherAmount == pausedWeatherAmount, "pause freezes rain transition")
        let frozenAtmosphere = controller.simulation.frame(waterStrength: 0.45).atmosphere
        let previousBackdrop = readImage(screens[0])!
        let previousPNG = try Data(contentsOf: previousBackdrop)
        for weather in [PondWeather.snowy, .overcast, .cloudy] {
            controller.weather = weather; advance()
            let nextBackdrop = readImage(screens[0])!
            let nextPNG = try Data(contentsOf: nextBackdrop)
            check(controller.weather == weather && controller.status.contains(weather.title), "new weather reaches native status")
            check(controller.backdropError == nil && nextBackdrop == previousBackdrop && nextPNG == previousPNG,
                  "new weather retains native backing without a desktop refresh")
            check(FileManager.default.fileExists(atPath: previousBackdrop.path), "weather switching retains the backing file")
            check(controller.simulation.time == pausedTime && controller.simulation.frame(waterStrength: 0.45).atmosphere == frozenAtmosphere,
                  "paused weather selection leaves simulation and atmosphere frozen")
        }
        controller.weather = .sunny
        check(controller.simulation.frame(waterStrength: 0.45).precipitation == pausedPrecipitation,
              "paused weather changes preserve every airborne particle")
        check(!controller.input.enabled, "pause stops input")
        controller.enabled = false
        await controller.waitForBackdrop()
        check(readImage(screens[0]) == before[0], "disable restores original image")
        check(NSDictionary(dictionary: readOptions(screens[0])!).isEqual(to: beforeOptions[0]), "disable restores original options exactly")
        check(!controller.window.isVisible, "disable hides overlay")
        controller.enabled = true
        await controller.waitForBackdrop()
        check(controller.window.isVisible && controller.paused, "re-enable retains pause")
        controller.paused = false; advance()
        if !controller.reducedMotion { check(controller.frameCount > frameCount, "resume renders") }
        if !controller.reducedMotion {
            check(controller.simulation.frame(waterStrength: 0.45).weatherAmount < pausedWeatherAmount, "sunny transition resumes")
        }
        controller.interactive = false
        check(!controller.input.enabled, "interaction switch")
        let queries = controller.input.geometryQueryCount
        advance(0.4)
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        controller.input.refresh(screen: screens[0], force: true)
        check(controller.input.geometryQueryCount == queries, "disabled interaction performs no window geometry queries")
        controller.interactive = true
        if !controller.reducedMotion {
            check(controller.input.geometryQueryCount > queries, "re-enabling refreshes stale geometry immediately")
        }
        let preSleepImage = readImage(screens[0])
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
        check(readImage(screens[0]) == preSleepImage, "sleep retains backing")
        check(controller.sleeping && !controller.window.isVisible, "sleep hides and stops")
        controller.paused = true
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
        check(!controller.sleeping && controller.paused && controller.window.isVisible, "wake respects paused state")
        let rect = controller.window.frame
        controller.screenChanged()
        check(controller.window.frame == rect, "unchanged display stable")
        controller.stop()
        await controller.waitForBackdrop()
        check(!controller.window.isVisible, "shutdown removes overlay")
        let after = screens.map { readImage($0) }
        check(before == after, "stop restores all original wallpaper URLs")
        check(screens.enumerated().allSatisfy { index, screen in
            NSDictionary(dictionary: readOptions(screen)!).isEqual(to: beforeOptions[index])
        }, "stop restores all original options exactly")
        try await journalTests(screen: screens[0], check: { check($0, $1) })
        print("PASS: \(count) native desktop and lifecycle checks")
    }

    @MainActor static func weatherTransitionTests() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("pond-weather-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let original = URL(fileURLWithPath: "/weather-test-original.heic")
        var current = original
        var reads = 0
        var sets = 0
        let backdrop = try DesktopBackdrop(directory: root.appendingPathComponent("backdrop"),
            readImage: { _ in reads += 1; return current }, readOptions: { _ in [:] },
            setImage: { url, _, _ in sets += 1; current = url })
        let controller = try DesktopController(shaderURL: URL(fileURLWithPath: "Resources/Ocean.metal"),
            backdrop: backdrop, drawingStore: FishDrawingStore(directory: root.appendingPathComponent("fish")))
        defer { controller.stop() }
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ label: String) throws {
            guard condition() else { throw NSError(domain: "WeatherTransitionTest", code: 1,
                userInfo: [NSLocalizedDescriptionKey: label]) }
            checks += 1
        }
        func advance(_ seconds: Double) { RunLoop.current.run(until: Date(timeIntervalSinceNow: seconds)) }
        controller.start()
        await controller.waitForBackdrop()
        let backing = current
        let originalSets = sets
        let originalReads = reads
        let selectedAt = ProcessInfo.processInfo.systemUptime
        controller.weather = .rainy
        let selectionMS = (ProcessInfo.processInfo.systemUptime - selectedAt) * 1000
        print("Weather selection: \(String(format: "%.3f", selectionMS)) ms; system image changes: \(sets - originalSets)")
        try check(current == backing && sets == originalSets && reads == originalReads,
                  "weather selection must not read, render or replace the system backing")
        advance(0.3)
        let count = controller.frameCount
        let time = controller.simulation.time
        var maxSelectionMS = selectionMS
        for previous in PondWeather.allCases {
            controller.weather = previous
            advance(0.04)
            for next in PondWeather.allCases {
                let before = controller.simulation.frame(waterStrength: 0.45)
                let fish = controller.simulation.fish.map(\.position)
                let start = ProcessInfo.processInfo.systemUptime
                controller.weather = next
                maxSelectionMS = max(maxSelectionMS, (ProcessInfo.processInfo.systemUptime - start) * 1000)
                let after = controller.simulation.frame(waterStrength: 0.45)
                try check(after.time == before.time && after.atmosphere == before.atmosphere
                          && after.precipitation == before.precipitation && after.surfaceSnow == before.surfaceSnow
                          && controller.simulation.fish.map(\.position) == fish,
                          "rapid selection preserves the current scene until the next animation frame")
                try check(controller.weather == next && controller.status.contains(next.title), "selected weather reaches menu status")
            }
        }
        try check(current == backing && sets == originalSets && reads == originalReads,
                  "all weather pairs avoid system wallpaper work")
        if !controller.reducedMotion {
            try check(controller.frameCount > count && controller.simulation.time > time,
                      "animation continues across successive selections")
        }
        controller.screenChanged()
        try check(current == backing && sets == originalSets, "unchanged screen notification does not apply a deferred weather backdrop")
        controller.paused = true
        let frozen = controller.simulation.frame(waterStrength: 0.45)
        for weather in PondWeather.allCases { controller.weather = weather }
        advance(0.1)
        let still = controller.simulation.frame(waterStrength: 0.45)
        try check(still.time == frozen.time && still.atmosphere == frozen.atmosphere
                  && still.precipitation == frozen.precipitation && still.surfaceSnow == frozen.surfaceSnow,
                  "paused selection keeps the entire weather scene frozen")
        try check(current == backing && sets == originalSets, "paused selection retains the menu bar backing")
        controller.paused = false
        advance(0.12)
        if !controller.reducedMotion {
            try check(controller.simulation.frame(waterStrength: 0.45).time > frozen.time, "resume continues from the frozen scene")
        }
        controller.enabled = false
        await controller.waitForBackdrop()
        let disabledSets = sets
        controller.weather = .snowy
        try check(current == original && sets == disabledSets && !controller.window.isVisible,
                  "hidden weather selection leaves the original wallpaper alone")
        controller.enabled = true
        await controller.waitForBackdrop()
        try check(current != original && sets == disabledSets + 1 && controller.backdropError == nil,
                  "explicit re-enable still creates a pond backing")
        controller.stop()
        await controller.waitForBackdrop()
        try check(current == original, "stop restores the original backing")
        print("PASS: \(checks) weather transition checks; max selection \(String(format: "%.3f", maxSelectionMS)) ms")
    }

    @MainActor static func journalTests(screen: NSScreen, check: (Bool, String) -> Void) async throws {
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
        try await first.apply(screen: screen, key: "sunny", render: render)
        let firstImage = current
        try await first.apply(screen: screen, key: "sunny", render: render)
        check(sets == 1 && current == firstImage, "same backing is not regenerated")
        current = userChoice
        try await first.apply(screen: screen, key: "rainy", render: render)
        try await first.apply(screen: screen, key: "sunny", render: render)
        try await first.restoreAll()
        check(current == userChoice && sets == 1, "user override survives weather and stop")
        current = original; options = originalOptions
        try await first.apply(screen: screen, key: "sunny", render: render)
        first.releaseOwnership()
        let recovered = try helper() // Simulates another executable using the same stable journal.
        try await recovered.restoreAll()
        check(current == original && NSDictionary(dictionary: options).isEqual(to: originalOptions), "new helper restores crash journal and color options")
        try await recovered.apply(screen: screen, key: "sunny", render: render)
        failSet = true
        do { try await recovered.restoreAll(); check(false, "restore failure must surface") }
        catch { check(true, "restore failure surfaces") }
        let saved = try JSONDecoder().decode([DesktopBackdrop.Record].self, from: Data(contentsOf: directory.appendingPathComponent("ownership.json")))
        check(saved.count == 1 && saved[0].original == original, "failed restoration retains original recovery record")
        failSet = false
        recovered.releaseOwnership()
        try await helper().restoreAll()
        check(current == original, "next launch retries failed restoration")
        let bounded = try helper()
        try await bounded.apply(screen: screen, key: "sunny", render: render)
        for index in 0..<6 { try await bounded.apply(screen: screen, key: "weather-\(index)", render: render) }
        let generated = try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasSuffix(".png") }
        check(generated.count == 1, "weather updates retain only one generated frame")
        failSet = true
        for index in 0..<4 {
            do { try await bounded.apply(screen: screen, key: "failed-\(index)", render: render); check(false, "apply failure must surface") }
            catch { check(true, "apply failure surfaces") }
        }
        check(try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasSuffix(".png") }.count == 2, "failed replacements retain at most current and pending frame")
        failSet = false
        try await bounded.restoreAll(screens: [])
        check(current != original, "disconnected display retains ownership")
        try await bounded.restoreAll()
        check(try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasSuffix(".png") }.isEmpty, "successful restoration cleans generated frames")
        bounded.releaseOwnership()
        let noOptions = try helper()
        options = [:]
        try await noOptions.apply(screen: screen, key: "sunny", render: render)
        try await noOptions.restoreAll()
        check(current == original && options.isEmpty, "empty public options are passed back unchanged")
        noOptions.releaseOwnership()
        let previousSets = sets
        options = originalOptions
        let missingOptions = try DesktopBackdrop(directory: directory, readImage: { _ in current }, readOptions: { _ in nil }, setImage: { _, _, _ in sets += 1 })
        do { try await missingOptions.apply(screen: screen, key: "sunny", render: render); check(false, "missing options must be rejected") }
        catch { check(sets == previousSets, "missing backup prevents system change") }
        missingOptions.releaseOwnership()
        var queued: URL?
        let delayed = try DesktopBackdrop(directory: directory, readImage: { _ in original }, readOptions: { _ in originalOptions }, setImage: { url, _, _ in queued = url == original ? nil : url })
        do { try await delayed.apply(screen: screen, key: "late", render: render); check(false, "late readback must surface") }
        catch { check(queued != nil, "timed out system request remains journaled") }
        try await delayed.restoreAll()
        check(queued == nil, "immediate disable reasserts original after unacknowledged apply")
        delayed.releaseOwnership()
        let renderRace = try helper()
        let setsBeforeRace = sets
        do {
            try await renderRace.apply(screen: screen, key: "first", render: { url in
                try render(url); current = userChoice
            })
            check(false, "first-render user change must surface")
        } catch { check(current == userChoice, "first-render user choice is preserved") }
        var renderedAgain = false
        try await renderRace.apply(screen: screen, key: "next-weather", render: { url in renderedAgain = true; try render(url) })
        check(!renderedAgain && sets == setsBeforeRace && current == userChoice, "first-render override suppresses subsequent weather replacement")
        try await renderRace.restoreAll()
        try await renderRace.apply(screen: screen, key: "explicit-enable", render: render)
        check(current != userChoice, "explicit disable and enable resets first-render override")
        try await renderRace.restoreAll()
        check(current == userChoice, "explicit re-enable backs up the user-selected image")
        current = original; options = originalOptions

        renderRace.releaseOwnership()
        var pendingImage: URL?
        var delayReplacement = false
        let lateReplacement = try DesktopBackdrop(directory: directory, readImage: { _ in current }, readOptions: { _ in originalOptions }, setImage: { url, _, _ in
            if delayReplacement { pendingImage = url } else { current = url }
        })
        try await lateReplacement.apply(screen: screen, key: "A", render: render)
        let imageA = current
        delayReplacement = true
        do { try await lateReplacement.apply(screen: screen, key: "B", render: render); check(false, "replacement timeout must surface") }
        catch { check(pendingImage != nil, "late replacement is outstanding") }
        var renderedC = false
        do {
            try await lateReplacement.apply(screen: screen, key: "C", render: { url in
                renderedC = true; current = pendingImage!; try render(url)
            })
            check(false, "retry must be refused while replacement is outstanding")
        } catch { check(!renderedC, "pending replacement prevents another render and request") }
        check(FileManager.default.fileExists(atPath: imageA.path) && FileManager.default.fileExists(atPath: pendingImage!.path), "retry retains both current and outstanding images")
        current = pendingImage! // The original timed-out request finally completes.
        delayReplacement = false
        try await lateReplacement.restoreAll()
        check(current == original, "late completion remains owned and restores original wallpaper")
        check(!FileManager.default.fileExists(atPath: imageA.path) && !FileManager.default.fileExists(atPath: pendingImage!.path), "late completion files clean only after restoration")
        noOptions.releaseOwnership()
        lateReplacement.releaseOwnership()
        let previousSetsAfterRaces = sets
        let unwritable = try helper()
        let journal = directory.appendingPathComponent("ownership.json")
        try FileManager.default.removeItem(at: journal)
        try FileManager.default.createDirectory(at: journal, withIntermediateDirectories: false)
        do { try await unwritable.apply(screen: screen, key: "sunny", render: render); check(false, "failed journal must be rejected") }
        catch { check(sets == previousSetsAfterRaces && current == original, "failed durable backup never replaces user wallpaper") }

    }
}
