import AppKit

@main struct CanvasCacheTests {
    static func main() throws {
        _ = NSApplication.shared
        let reference = CommandLine.arguments.contains("--record-reference")
        let directory = URL(fileURLWithPath: ".build/canvas-\(reference ? "before" : "after")")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let canvas = FishDrawingCanvas(frame: NSRect(x: 0, y: 0, width: 704, height: 338))
        let window = NSWindow(contentRect: canvas.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = canvas
        let red = FishColor(red: 0.9, green: 0.1, blue: 0.2)
        let blue = FishColor(red: 0.1, green: 0.3, blue: 0.9)
        canvas.currentTool = { (blue, 0.04, true) }
        func snapshot(_ name: String) throws {
            let width = Int(canvas.bounds.width), height = Int(canvas.bounds.height)
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: width * 4, bitsPerPixel: 32)!
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
            canvas.draw(canvas.bounds)
            NSGraphicsContext.restoreGraphicsState()
            let bytes = Data(bytes: bitmap.bitmapData!, count: width * height * 4)
            try bytes.write(to: directory.appendingPathComponent(name + ".rgba"))
            try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(name + ".png"))
            if !reference {
                let expected = try Data(contentsOf: URL(fileURLWithPath: ".build/canvas-before/\(name).rgba"))
                let maxDelta = zip(bytes, expected).map { abs(Int($0) - Int($1)) }.max()!
                let mean = Double(zip(bytes, expected).reduce(0) { $0 + abs(Int($1.0) - Int($1.1)) }) / Double(bytes.count)
                precondition(maxDelta <= 2 && mean < 0.02, "cache must preserve reference pixels: \(name) max=\(maxDelta) mean=\(mean)")
                print("CANVAS \(name) max=\(maxDelta) mean=\(mean)")
            }
        }
        let points = (0..<100).map { FishPoint(x: 0.3 + Float($0) * 0.004, y: 0.5 + sin(Float($0) * 0.2) * 0.08) }
        canvas.strokes = (0..<500).map { FishStroke(points: points, color: $0 % 2 == 0 ? red : blue, width: 0.025, erasing: $0 % 7 == 0) }
        try snapshot("complex")
        #if CACHE_METRICS
        let initialBuilds = canvas.inkCacheRebuilds
        #endif
        try snapshot("reuse")
        #if CACHE_METRICS
        precondition(canvas.inkCacheRebuilds == initialBuilds)
        #endif
        let event = NSEvent.mouseEvent(with: .leftMouseDown, location: CGPoint(x: 352, y: 169), modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        canvas.mouseDown(with: event)
        try snapshot("active-eraser")
        #if CACHE_METRICS
        precondition(canvas.inkCacheRebuilds == initialBuilds, "drag never replays completed strokes")
        #endif
        canvas.resetActiveStroke()
        canvas.baseColor = FishColor(red: 0.1, green: 0.8, blue: 0.3)
        try snapshot("base")
        canvas.strokes.append(FishStroke(points: [FishPoint(x: 0.5, y: 0.5)], color: red, width: 0.06, erasing: false))
        try snapshot("append")
        #if CACHE_METRICS
        precondition(canvas.inkCacheRebuilds == initialBuilds + 1, "append extends the layer rebuilt for base color")
        #endif
        canvas.strokes.removeLast()
        try snapshot("undo")
        canvas.setFrameSize(NSSize(width: 880, height: 422))
        try snapshot("resize")
        canvas.strokes = []
        try snapshot("clear")
        print("PASS: canvas complex/active eraser/base/append/undo/resize/clear reference scenes")
    }
}
