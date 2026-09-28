import AppKit
import MetalKit

final class OceanWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

final class TransparentMetalView: MTKView {
    override var isOpaque: Bool { false }
}

@MainActor final class DesktopController {
    let window: OceanWindow
    let view: TransparentMetalView
    let renderer: OceanRenderer
    let simulation: OceanSimulation
    let input: DesktopInput
    var enabled = true { didSet { updateActivity(); updateBackdrop() } }
    var paused = false { didSet { updateActivity() } }
    var interactive = true { didSet { updateActivity() } }
    var weather: PondWeather {
        get { simulation.weather }
        set {
            simulation.weather = newValue
            // The next animation tick presents the transition. Exporting a system
            // wallpaper here blocks that tick and triggers a desktop refresh.
            writeDiagnostics()
        }
    }
    var diagnosticURL: URL?
    private let backdrop: DesktopBackdrop
    private let drawingStore: FishDrawingStore
    var onFishChanged: (() -> Void)?
    private(set) var defaultFishError: String?
    private(set) var customFishErrors: [String] = []
    private(set) var backdropError: String?
    private(set) var sleeping = false
    private var locked = false
    private(set) var frameCount = 0
    private(set) var meanFrameMS = 0.0
    private var timer: Timer?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var previousTime = ProcessInfo.processInfo.systemUptime
    private var lastDiagnostic = 0.0
    private var displayID: CGDirectDisplayID = 0
    private let cpuTimings = PerformanceTimings()
    private let frameIntervals = PerformanceTimings()
    private let backdropExportTimings = PerformanceTimings()
    private(set) var backdropLastFailure: String?
    private var backdropRevision = 0
    private var backdropTask: Task<Void, Never>?
    private var stopping = false
    private var stopCompletion: (() -> Void)?

    var reducedMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    var animating: Bool { enabled && !paused && !sleeping && !locked && !reducedMotion }
    var status: String {
        if let backdropError { return "桌面背景错误：\(backdropError)" }
        let scene = "\(simulation.fish.count) 条锦鲤 · \(weather.title)"
        if !enabled { return "池塘已关闭 · \(scene)" }
        if locked { return "屏幕已锁定 · \(scene)" }
        if sleeping { return "屏幕休眠 · \(scene)" }
        if reducedMotion { return "减少动态效果 · \(scene)" }
        if paused { return "已暂停 · \(scene)" }
        return "\(scene) · 主屏 30 FPS"
    }

    init(shaderURL: URL, backdrop: DesktopBackdrop? = nil, drawingStore: FishDrawingStore? = nil) throws {
        self.backdrop = try backdrop ?? DesktopBackdrop()
        self.drawingStore = drawingStore ?? FishDrawingStore(directory:
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("local.macaquariumwallpaper.app/CustomFish", isDirectory: true))
        guard let screen = NSScreen.screens.first else {
            throw NSError(domain: "Ocean", code: 1, userInfo: [NSLocalizedDescriptionKey: "未找到可用显示器"])
        }
        let bounds = screen.frame
        simulation = OceanSimulation(size: SIMD2(Float(bounds.width), Float(bounds.height)))
        window = OceanWindow(contentRect: bounds, styleMask: .borderless, backing: .buffered, defer: false)
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.ignoresMouseEvents = true
        window.hasShadow = false
        window.canHide = false
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.title = "池塘 · 桌面场景"
        view = TransparentMetalView(frame: NSRect(origin: .zero, size: bounds.size), device: MTLCreateSystemDefaultDevice())
        view.clearColor = MTLClearColorMake(0, 0, 0, 0)
        view.layer?.isOpaque = false
        view.layer?.backgroundColor = NSColor.clear.cgColor
        view.autoresizingMask = [.width, .height]
        renderer = try OceanRenderer(view: view, shaderURL: shaderURL)
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        view.delegate = renderer
        window.contentView = view
        window.setFrame(bounds, display: false)
        displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
        input = DesktopInput(screen: screen)
        input.onClick = { [weak self] point in self?.simulation.click(at: point) }
        input.onEnd = { [weak self] in self?.simulation.resetPointer() }
        observe(NotificationCenter.default, NSApplication.didChangeScreenParametersNotification) { $0.screenChanged() }
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.screensDidSleepNotification) { $0.sleeping = true; $0.updateActivity() }
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.screensDidWakeNotification) { $0.sleeping = false; $0.screenChanged(); $0.updateActivity() }
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.willSleepNotification) { $0.sleeping = true; $0.updateActivity() }
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.didWakeNotification) { $0.sleeping = false; $0.screenChanged(); $0.updateActivity() }
        observe(DistributedNotificationCenter.default(), Notification.Name("com.apple.screenIsLocked")) { $0.locked = true; $0.updateActivity() }
        observe(DistributedNotificationCenter.default(), Notification.Name("com.apple.screenIsUnlocked")) { $0.locked = false; $0.updateActivity() }
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.activeSpaceDidChangeNotification) { controller in
            controller.input.endGesture()
            if let screen = NSScreen.screens.first { controller.input.refresh(screen: screen, force: true) }
        }
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.didActivateApplicationNotification) { controller in
            if let screen = NSScreen.screens.first { controller.input.refresh(screen: screen, force: true) }
        }
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.accessibilityDisplayOptionsDidChangeNotification) { $0.updateActivity() }
        do {
            let saved = try self.drawingStore.defaultFishState()
            for id in saved.deleted { simulation.removeFish(identity: .builtIn(id)) }
            for (id, name) in saved.names { simulation.renameFish(identity: .builtIn(id), name: name) }
        } catch { defaultFishError = error.localizedDescription }
        let saved = self.drawingStore.load()
        customFishErrors = saved.errors
        for drawing in saved.drawings {
            do {
                try renderer.registerDrawing(drawing)
                simulation.addCustomFish(appearanceID: drawing.id, name: drawing.name)
            } catch { customFishErrors.append(error.localizedDescription) }
        }
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name,
                         action: @escaping (DesktopController) -> Void) {
        let observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if let self { action(self) } }
        }
        observers.append((center, observer))
    }

    func start() { updateActivity(); updateBackdrop() }

    func addCustomFish(_ drawing: FishDrawing) throws {
        guard !simulation.fish.contains(where: { $0.customAppearanceID == drawing.id }) else { return }
        try renderer.registerDrawing(drawing)
        do { try drawingStore.save(drawing) }
        catch { renderer.removeDrawing(id: drawing.id); throw error }
        simulation.addCustomFish(appearanceID: drawing.id, name: drawing.name)
        if !enabled { enabled = true }
        else { render(); writeDiagnostics(); updateBackdrop() }
        onFishChanged?()
    }

    func removeFish(identity: FishIdentity) throws {
        guard simulation.fish.contains(where: { $0.identity == identity }) else { return }
        switch identity {
        case .builtIn(let id):
            try drawingStore.removeDefaultFish(id: id)
            defaultFishError = nil
        case .custom(let id):
            try drawingStore.remove(id: id)
        }
        simulation.removeFish(identity: identity)
        if case .custom(let id) = identity { renderer.removeDrawing(id: id) }
        updateBackdrop()
        if enabled && !sleeping && !locked { render() }
        writeDiagnostics()
        onFishChanged?()
    }

    func renameFish(identity: FishIdentity, name: String) throws {
        guard simulation.fish.contains(where: { $0.identity == identity }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let savedName = trimmed.isEmpty ? nil : trimmed
        switch identity {
        case .builtIn(let id):
            try drawingStore.renameDefaultFish(id: id, name: savedName)
            defaultFishError = nil
        case .custom(let id):
            try drawingStore.rename(id: id, name: savedName)
        }
        simulation.renameFish(identity: identity, name: savedName)
        writeDiagnostics()
        onFishChanged?()
    }

    private func updateBackdrop() {
        backdropRevision += 1
        guard backdropTask == nil else { return }
        backdropTask = Task { @MainActor in
            // Coalesce changes made by the same UI action before capturing the scene.
            await Task.yield()
            while true {
                let revision = backdropRevision
                do {
                    if enabled && !stopping, let screen = NSScreen.screens.first {
                        let pixels = screen.convertRectToBacking(screen.frame).size
                        let fishIDs = simulation.fish.map { $0.identity.storageKey }.sorted().joined(separator: ",")
                        let key = "\(DesktopBackdrop.displayIdentifier(screen))-\(pixels.width)x\(pixels.height)-\(fishIDs)"
                        var frame = simulation.frame(waterStrength: 0.45)
                        frame.weatherAmount = weather == .rainy ? 1 : 0
                        frame.atmosphere = weather.atmosphere
                        try await backdrop.apply(screen: screen, key: key,
                            isCurrent: { self.backdropRevision == revision && self.enabled && !self.stopping }) { url in
                            let started = ProcessInfo.processInfo.systemUptime
                            defer { self.backdropExportTimings.record((ProcessInfo.processInfo.systemUptime - started) * 1000) }
                            try await self.renderer.writePNGAsync(frame: frame, width: Int(pixels.width), height: Int(pixels.height), to: url)
                        }
                    } else {
                        try await backdrop.restoreAll()
                    }
                    // A no-op restoration is not evidence that an earlier failure recovered.
                    if revision == backdropRevision && (backdrop.ownershipState == "owned" || backdrop.ownershipState == "externalChoice" ||
                        backdrop.lastRecoveryResult == "restored" || backdrop.lastRecoveryResult == "externalChoicePreserved") {
                        backdropError = nil
                    }
                } catch {
                    backdropError = error.localizedDescription
                    backdropLastFailure = error.localizedDescription
                    NSLog("池塘桌面背景：%@", error.localizedDescription)
                }
                writeDiagnostics()
                if revision == backdropRevision { break }
            }
            backdropTask = nil
            if stopping { backdrop.releaseOwnership() }
            writeDiagnostics()
            if stopping { stopCompletion?(); stopCompletion = nil }
        }
    }

    func waitForBackdrop() async {
        while let task = backdropTask { await task.value }
    }

    private func updateActivity() {
        timer?.invalidate(); timer = nil
        simulation.resetPointer()
        let wasInputEnabled = input.enabled
        input.enabled = animating && interactive
        if input.enabled && !wasInputEnabled, let screen = NSScreen.screens.first {
            input.refresh(screen: screen, force: true)
        }
        if !input.enabled { input.endGesture() }
        previousTime = ProcessInfo.processInfo.systemUptime
        if enabled && !sleeping && !locked {
            if !window.isVisible { window.orderFrontRegardless() }
            render()
        } else { window.orderOut(nil) }
        if animating {
            let tickTimer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
            RunLoop.main.add(tickTimer, forMode: .common)
            timer = tickTimer
        }
        writeDiagnostics()
    }

    private func tick() {
        let start = ProcessInfo.processInfo.systemUptime
        // Preserve elapsed time through ordinary slow frames; the simulation substeps it.
        // Lifecycle transitions reset previousTime, so sleep never produces a large jump.
        frameIntervals.record((start - previousTime) * 1000)
        let delta = Float(min(start - previousTime, 1.0))
        previousTime = start
        if input.enabled, let screen = NSScreen.screens.first { input.refresh(screen: screen) }
        simulation.update(deltaTime: delta)
        simulation.trackPointer(input.hover())
        render()
        frameCount += 1
        let elapsedMS = (ProcessInfo.processInfo.systemUptime - start) * 1000
        cpuTimings.record(elapsedMS)
        meanFrameMS += (elapsedMS - meanFrameMS) / Double(frameCount)
        if start - lastDiagnostic >= 1 { lastDiagnostic = start; writeDiagnostics() }
    }

    func render() {
        renderer.frame = simulation.frame(waterStrength: 0.45)
        view.draw()
    }

    func screenChanged() {
        simulation.resetPointer()
        guard let screen = NSScreen.screens.first else { window.orderOut(nil); return }
        let currentID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
        if currentID != displayID || window.frame != screen.frame {
            displayID = currentID
            input.endGesture()
            window.setFrame(screen.frame, display: true)
            simulation.resize(to: SIMD2(Float(screen.frame.width), Float(screen.frame.height)))
        }
        input.refresh(screen: screen, force: true)
        updateBackdrop()
        if enabled && !sleeping && !locked { render() }
    }

    func stop(completion: (() -> Void)? = nil) {
        guard !stopping else {
            if backdropTask == nil { completion?() }
            else if let completion { stopCompletion = completion }
            return
        }
        stopping = true
        stopCompletion = completion
        simulation.resetPointer()
        timer?.invalidate(); timer = nil
        input.stop()
        for (center, observer) in observers { center.removeObserver(observer) }
        observers.removeAll()
        window.orderOut(nil)
        window.close()
        // The running export drains first; its revision is now invalid. Restoration
        // then confirms the original before the application is allowed to terminate.
        updateBackdrop()
    }

    func writeDiagnostics() {
        guard let diagnosticURL else { return }
        let frame = simulation.frame(waterStrength: 0.45)
        let intervalMetrics = frameIntervals.snapshot
        let dictionary: [String: Any] = [
            "backdropError": backdropError ?? "",
            "backdropLastFailure": backdropLastFailure ?? backdrop.lastFailure ?? "",
            "backdropOwnership": backdrop.ownershipState,
            "backdropJournalRecords": backdrop.journalRecordCount,
            "backdropLastRecovery": backdrop.lastRecoveryResult,
            "backdropWorkPending": backdropTask != nil,
            "performance": ["displayCPU": cpuTimings.snapshot, "displayGPU": renderer.displayGPUTimings.snapshot,
                "frameIntervals": intervalMetrics, "offscreenGPU": renderer.offscreenGPUTimings.snapshot,
                "backgroundExport": backdropExportTimings.snapshot, "exportMainThreadSubmission": renderer.exportSubmissionTimings.snapshot],
            "longFrameCount": intervalMetrics["over50MS"] as? Int ?? 0,
            "metalAllocatedBytes": renderer.allocatedBytes,
            "desktopTargetAllocations": renderer.targetAllocations,
            "previewTargetAllocations": renderer.previewTargetAllocations,
            "particleBufferAllocations": renderer.particleBufferAllocations,
            "skippedGPUFrames": renderer.skippedGPUFrames,
            "geometryQueries": input.geometryQueryCount,
            "status": status, "frames": frameCount, "meanCPUFrameMS": meanFrameMS,
            "enabled": enabled, "paused": paused, "interactive": interactive,
            "visible": window.isVisible, "mousePassThrough": window.ignoresMouseEvents,
            "opaque": window.isOpaque, "level": window.level.rawValue,
            "fish": simulation.fish.count, "ripples": simulation.ripples.count,
            "customFish": simulation.fish.filter { $0.customAppearanceID != nil }.count,
            "customFishLoadErrors": customFishErrors.count,
            "defaultFishLoadError": defaultFishError ?? "",
            "motionRipples": simulation.ripples.filter { $0.source == .motion }.count,
            "leaves": simulation.leaves.count, "weather": weather.rawValue,
            "weatherAmount": frame.weatherAmount,
            "airborneSnow": frame.precipitation.filter { $0.kind == .snow }.count,
            "airborneRain": frame.precipitation.filter { $0.kind == .rain }.count,
            "surfaceSnow": frame.surfaceSnow.count,
            "clicks": input.clickCount,
            "drags": input.dragCount, "rejectedClicks": input.rejectedCount,
            "geometryValid": input.geometry.valid, "blockedWindows": input.geometry.blockingRects.count,
            "inputAvailable": input.available, "inputStatus": input.status,
            "screen": [window.frame.origin.x, window.frame.origin.y, window.frame.width, window.frame.height],
            "simulationTime": simulation.time
        ]
        if let data = try? JSONSerialization.data(withJSONObject: dictionary, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: diagnosticURL, options: .atomic)
        }
    }
}
