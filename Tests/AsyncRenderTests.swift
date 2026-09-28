import AppKit
import MetalKit

@main struct AsyncRenderTests {
    @MainActor static func main() {
        _ = NSApplication.shared
        Task { @MainActor in
            do { try await run(); exit(0) }
            catch { fputs("FAIL: \(error)\n", stderr); exit(1) }
        }
        NSApp.run()
    }

    @MainActor static func run() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("pond-async-render-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let renderer = try OceanRenderer(view: MTKView(), shaderURL: URL(fileURLWithPath: "Resources/Ocean.metal"))
        let simulation = OceanSimulation(size: SIMD2(1512, 982), seed: 42)
        simulation.weather = .snowy
        for _ in 0..<1050 { simulation.update(deltaTime: 1.0 / 30) }
        var frames: [OceanFrame] = []
        var expected: [Data] = []
        for index in 0..<6 {
            simulation.weather = index % 2 == 0 ? .rainy : .snowy
            simulation.update(deltaTime: 0.3)
            let frame = simulation.frame(waterStrength: 0.45)
            frames.append(frame)
            let url = root.appendingPathComponent("reference-\(index).png")
            try renderer.writePNG(frame: frame, width: 800, height: 500, to: url)
            expected.append(try Data(contentsOf: url))
        }
        let jobs = frames.enumerated().map { index, frame in
            Task { @MainActor in
                let url = root.appendingPathComponent("async-\(index).png")
                try await renderer.writePNGAsync(frame: frame, width: 800, height: 500, to: url)
                return try Data(contentsOf: url)
            }
        }
        for (index, job) in jobs.enumerated() {
            let png = try await job.value
            precondition(png == expected[index], "overlapping GPU uploads and CPU exports must match their snapshots")
        }
        precondition(renderer.particleBufferAllocations <= 3, "at most three in-flight upload buffers")
        var beats = 0
        let intervals = PerformanceTimings()
        var previous = ProcessInfo.processInfo.systemUptime
        let heartbeat = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000)
                let now = ProcessInfo.processInfo.systemUptime
                intervals.record((now - previous) * 1000)
                previous = now
                beats += 1
            }
        }
        let exportStart = ProcessInfo.processInfo.systemUptime
        try await renderer.writePNGAsync(frame: frames[0], width: 3024, height: 1964, to: root.appendingPathComponent("full.png"))
        let exportMS = (ProcessInfo.processInfo.systemUptime - exportStart) * 1000
        heartbeat.cancel()
        await heartbeat.value
        print("FULL_ASYNC_EXPORT \(exportMS) ms; MAIN_ACTOR_INTERVAL \(intervals.snapshot)")
        do {
            try await renderer.writePNGAsync(frame: frames[0], width: 128, height: 64, to: root)
            preconditionFailure("writing PNG to a directory must fail")
        } catch { }
        do {
            try await renderer.writePNGAsync(frame: frames[0], width: 0, height: 64, to: root)
            preconditionFailure("invalid export dimensions must fail")
        } catch { }
        let submission = renderer.exportSubmissionTimings.snapshot
        print("EXPORT_MAIN_SUBMISSION \(submission)")
        precondition(beats > 10, "full-size export leaves main actor responsive")
        print("PASS: 6 overlapping exports exactly match PNG snapshots; bounded GPU uploads; full export \(beats) main-actor heartbeats")
    }
}
