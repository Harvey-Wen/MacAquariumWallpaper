import AppKit
import MetalKit

@main struct PerformanceProbe {
    static func now() -> Double { ProcessInfo.processInfo.systemUptime }
    static func summary(_ title: String, _ times: [Double]) {
        let a = times.sorted()
        print(String(format: "%@: median %.3f ms; p95 %.3f ms; max %.3f ms", title, a[a.count/2], a[min(a.count-1, Int(Double(a.count)*0.95))], a.last!))
    }
    @MainActor static func main() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let view = MTKView(frame: NSRect(x: 0, y: 0, width: 1512, height: 982))
        var start = now()
        let renderer = try OceanRenderer(view: view, shaderURL: URL(fileURLWithPath: "Resources/Ocean.metal"))
        print(String(format: "RENDERER_INIT %.3f ms", (now()-start)*1000))
        let device = view.device!
        print("DEVICE \(device.name) sampleCount=\(view.sampleCount)")
        let baseline = device.currentAllocatedSize
        let simulation = OceanSimulation(size: SIMD2(1512,982))
        simulation.weather = .rainy
        for _ in 0..<180 { simulation.update(deltaTime: 1.0/30) }
        let frame = simulation.frame(waterStrength: 0.45)
        _ = try renderer.renderRGBA(frame: frame, width: 3024, height: 1964)
        print(String(format: "OFFSCREEN_ALLOC baseline %.2f MiB; after %.2f MiB; delta %.2f MiB", Double(baseline)/1048576, Double(device.currentAllocatedSize)/1048576, Double(device.currentAllocatedSize-baseline)/1048576))
        var warm: [Double] = [], switched: [Double] = [], thumbnails: [Double] = []
        for _ in 0..<8 {
            start = now()
            _ = try renderer.renderRGBA(frame: frame, width: 3024, height: 1964)
            warm.append((now()-start)*1000)
            start = now()
            _ = try renderer.fishPreview(frame.fish[0])
            thumbnails.append((now()-start)*1000)
            start = now()
            _ = try renderer.renderRGBA(frame: frame, width: 3024, height: 1964)
            switched.append((now()-start)*1000)
        }
        summary("READBACK_WARM", warm)
        summary("THUMBNAIL", thumbnails)
        summary("READBACK_AFTER_THUMBNAIL", switched)
        let png = FileManager.default.temporaryDirectory.appendingPathComponent("pond-review-\(UUID()).png")
        defer { try? FileManager.default.removeItem(at: png) }
        var exports: [Double] = []
        for _ in 0..<3 {
            start = now()
            try renderer.writePNG(frame: frame, width: 3024, height: 1964, to: png)
            exports.append((now()-start)*1000)
        }
        summary("FULL_PNG_EXPORT", exports)
        if let screen = NSScreen.screens.first {
            let input = DesktopInput(screen: screen)
            defer { input.stop() }
            var queries: [Double] = []
            for _ in 0..<30 {
                start = now(); input.refresh(screen: screen, force: true)
                queries.append((now()-start)*1000)
            }
            summary("WINDOW_GEOMETRY_QUERY", queries)
        }
        for count in [32,128,512] {
            let sim = OceanSimulation(size: SIMD2(1512,982))
            for _ in 30..<count { sim.addCustomFish(appearanceID: UUID()) }
            var times: [Double] = []
            for i in 0..<210 {
                start = now(); sim.update(deltaTime: 1.0/30)
                if i>=30 { times.append((now()-start)*1000) }
            }
            summary("SIMULATION_\(count)_FISH", times)
        }
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 704, pixelsHigh: 338, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 704*4, bitsPerPixel: 32)!
        let canvas = FishDrawingCanvas(frame: NSRect(x: 0,y: 0,width: 704,height: 338))
        let points = (0..<100).map { FishPoint(x: 0.3+Float($0)*0.004, y: 0.5+sin(Float($0)*0.2)*0.08) }
        for count in [10,100,500] {
            canvas.strokes = (0..<count).map { _ in FishStroke(points: points, color: FishColor(red: 1,green: 0.3,blue: 0.1), width: 0.025, erasing: false) }
            var times: [Double] = []
            for i in 0..<12 {
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
                start = now(); canvas.draw(canvas.bounds)
                if i>=2 { times.append((now()-start)*1000) }
                NSGraphicsContext.restoreGraphicsState()
            }
            summary("CANVAS_\(count)_STROKES", times)
        }
    }
}
