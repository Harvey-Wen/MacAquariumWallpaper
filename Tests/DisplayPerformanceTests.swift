import AppKit
import MetalKit

@main struct DisplayPerformanceTests {
    @MainActor static func main() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let screen = NSScreen.screens[0]
        let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.isOpaque = false
        window.backgroundColor = .clear
        let view = MTKView(frame: NSRect(origin: .zero, size: screen.frame.size))
        let renderer = try OceanRenderer(view: view, shaderURL: URL(fileURLWithPath: "Resources/Ocean.metal"))
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        window.contentView = view
        let simulation = OceanSimulation(size: SIMD2(Float(screen.frame.width), Float(screen.frame.height)), seed: 42)
        simulation.weather = .rainy
        for _ in 0..<180 { simulation.update(deltaTime: 1.0 / 30) }
        let baseline = renderer.allocatedBytesForProbe
        window.orderFrontRegardless()
        var ticks = 0
        var previous = ProcessInfo.processInfo.systemUptime
        var cpu: [Double] = [], gpu: [Double] = [], intervals: [Double] = []
        func summary(_ name: String, _ samples: [Double]) {
            let a = samples.sorted()
            print(String(format: "%@: median %.3f ms; p95 %.3f ms; max %.3f ms", name, a[a.count / 2], a[Int(Double(a.count) * 0.95)], a.last!))
        }
        let tick: @MainActor () -> Void = {
                autoreleasepool {
                    let start = ProcessInfo.processInfo.systemUptime
                    let interval = (start - previous) * 1000
                    previous = start
                    simulation.update(deltaTime: 1.0 / 30)
                    renderer.frame = simulation.frame(waterStrength: 0.45)
                    view.draw()
                    if ticks >= 30 {
                        cpu.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
                        intervals.append(interval)
                        #if METRICS
                        gpu.append(renderer.displayGPUTimings.latest)
                        #else
                        gpu.append(renderer.lastGPUSeconds * 1000)
                        #endif
                    }
                    ticks += 1
                    if ticks == 150 {
                        summary("DISPLAY_CPU", cpu); summary("DISPLAY_GPU", gpu); summary("DISPLAY_INTERVAL", intervals)
                        var usage = rusage(); getrusage(RUSAGE_SELF, &usage)
                        print(String(format: "DISPLAY_METAL baseline %.2f MiB; steady %.2f MiB; delta %.2f MiB; process peak RSS %.2f MiB", Double(baseline)/1048576, Double(renderer.allocatedBytesForProbe)/1048576, Double(renderer.allocatedBytesForProbe-baseline)/1048576, Double(usage.ru_maxrss)/1048576))
                        print("DISPLAY_LONG_FRAMES \(intervals.filter { $0 > 50 }.count) / \(intervals.count); pixels \(view.drawableSize); no readback, no wallpaper changes")
                        exit(0)
                    }
                }
        }
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { _ in MainActor.assumeIsolated { tick() } }
        RunLoop.main.add(timer, forMode: .common)
        app.run()
    }
}

private extension OceanRenderer {
    var allocatedBytesForProbe: Int { MTLCreateSystemDefaultDevice()!.currentAllocatedSize }
}
