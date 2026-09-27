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
    var enabled = true { didSet { updateBackdrop(); updateActivity() } }
    var paused = false { didSet { updateActivity() } }
    var interactive = true { didSet { updateActivity() } }
    var weather: PondWeather {
        get { simulation.weather }
        set {
            let changed = simulation.weather != newValue
            simulation.weather = newValue
            if changed { updateBackdrop() }
            if enabled && !sleeping && !locked { render() }
            writeDiagnostics()
        }
    }
    var diagnosticURL: URL?
    private let backdrop: DesktopBackdrop
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

    var reducedMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    var animating: Bool { enabled && !paused && !sleeping && !locked && !reducedMotion }
    var status: String {
        if let backdropError { return "桌面背景错误：\(backdropError)" }
        let scene = "\(simulation.fish.count) 条锦鲤 · \(weather == .rainy ? "雨天" : "晴天")"
        if !enabled { return "池塘已关闭 · \(scene)" }
        if locked { return "屏幕已锁定 · \(scene)" }
        if sleeping { return "屏幕休眠 · \(scene)" }
        if reducedMotion { return "减少动态效果 · \(scene)" }
        if paused { return "已暂停 · \(scene)" }
        return "\(scene) · 主屏 30 FPS"
    }

    init(shaderURL: URL, backdrop: DesktopBackdrop? = nil) throws {
        self.backdrop = try backdrop ?? DesktopBackdrop()
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
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name,
                         action: @escaping (DesktopController) -> Void) {
        let observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if let self { action(self) } }
        }
        observers.append((center, observer))
    }

    func start() { updateBackdrop(); updateActivity() }

    private func updateBackdrop() {
        do {
            if enabled, let screen = NSScreen.screens.first {
                let pixels = screen.convertRectToBacking(screen.frame).size
                let key = "\(DesktopBackdrop.displayIdentifier(screen))-\(pixels.width)x\(pixels.height)-\(weather.rawValue)"
                try backdrop.apply(screen: screen, key: key) { url in
                    var frame = simulation.frame(waterStrength: 0.45)
                    frame.weatherAmount = weather == .rainy ? 1 : 0
                    try renderer.writePNG(frame: frame, width: Int(pixels.width), height: Int(pixels.height), to: url)
                }
            } else if !enabled {
                try backdrop.restoreAll()
            }
            backdropError = nil
        } catch {
            backdropError = error.localizedDescription
            NSLog("池塘桌面背景：%@", error.localizedDescription)
        }
    }

    private func updateActivity() {
        timer?.invalidate(); timer = nil
        simulation.resetPointer()
        input.enabled = animating && interactive
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
        let delta = Float(min(start - previousTime, 1.0))
        previousTime = start
        if let screen = NSScreen.screens.first { input.refresh(screen: screen) }
        simulation.update(deltaTime: delta)
        simulation.trackPointer(input.hover())
        render()
        frameCount += 1
        meanFrameMS += ((ProcessInfo.processInfo.systemUptime - start) * 1000 - meanFrameMS) / Double(frameCount)
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

    func stop() {
        simulation.resetPointer()
        do { try backdrop.restoreAll(); backdropError = nil }
        catch { backdropError = error.localizedDescription; NSLog("池塘桌面背景恢复：%@", error.localizedDescription) }
        writeDiagnostics()
        timer?.invalidate(); timer = nil
        input.stop()
        for (center, observer) in observers { center.removeObserver(observer) }
        observers.removeAll()
        window.orderOut(nil)
        window.close()
    }

    func writeDiagnostics() {
        guard let diagnosticURL else { return }
        let dictionary: [String: Any] = [
            "backdropError": backdropError ?? "",
            "status": status, "frames": frameCount, "meanCPUFrameMS": meanFrameMS,
            "enabled": enabled, "paused": paused, "interactive": interactive,
            "visible": window.isVisible, "mousePassThrough": window.ignoresMouseEvents,
            "opaque": window.isOpaque, "level": window.level.rawValue,
            "fish": simulation.fish.count, "ripples": simulation.ripples.count,
            "motionRipples": simulation.ripples.filter { $0.source == .motion }.count,
            "leaves": simulation.leaves.count, "weather": weather.rawValue,
            "weatherAmount": simulation.frame(waterStrength: 0.45).weatherAmount,
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
