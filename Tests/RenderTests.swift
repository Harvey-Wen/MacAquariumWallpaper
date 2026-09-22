import AppKit
import MetalKit
import simd

@main
struct RenderTests {
    static func main() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let output = root.appendingPathComponent(".build/render-validation")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let view = MTKView(frame: NSRect(x: 0, y: 0, width: 1440, height: 900))
        view.isPaused = true
        let renderer = try OceanRenderer(view: view, shaderURL: root.appendingPathComponent("Resources/Ocean.metal"))
        for species in FishSpecies.allCases {
            let mesh = FishMesh(species: species)
            precondition(mesh.vertices.count > 1_000 && mesh.vertices.count % 3 == 0)
            for vertex in mesh.vertices {
                precondition((0..<4).allSatisfy { vertex.position[$0].isFinite && vertex.normal[$0].isFinite && vertex.detail[$0].isFinite }, "Every mesh attribute must remain finite.")
            }
        }
        let empty = try renderer.renderRGBA(frame: .empty, width: 320, height: 200)
        precondition(empty.allSatisfy { $0 == 0 }, "An empty scene must preserve zero RGB and alpha.")
        var frame = OceanFrame(size: SIMD2(1440, 900), time: 3.2, fish: [], ripples: [], currents: [], waterStrength: 0.45)
        for i in 0..<18 {
            let row = i / 6, column = i % 6
            frame.fish.append(FishState(id: i, species: .silver,
                                       position: SIMD2(220 + Float(column) * 84 + Float(row) * 23, 550 + Float(row) * 65 + sin(Float(i) * 1.8) * 18),
                                       velocity: SIMD2(45, 4), heading: 0.13 + Float(i % 3) * 0.12,
                                       length: 72 + Float(i % 4) * 8, depth: Float(i % 5) * 0.17, phase: Float(i), panic: 0))
        }
        let positions: [SIMD2<Float>] = [SIMD2(260, 315), SIMD2(390, 245), SIMD2(565, 370), SIMD2(1090, 710),
                                         SIMD2(810, 630), SIMD2(965, 550), SIMD2(1170, 475),
                                         SIMD2(790, 280), SIMD2(940, 335), SIMD2(1100, 245), SIMD2(1135, 755)]
        let kinds: [FishSpecies] = [.clown, .clown, .clown, .clown, .tang, .tang, .tang, .butterfly, .butterfly, .butterfly, .manta]
        for i in positions.indices {
            let species = kinds[i]
            frame.fish.append(FishState(id: 18 + i, species: species, position: positions[i], velocity: SIMD2(30, 0),
                                       heading: i % 2 == 0 ? 0.12 : .pi - 0.2,
                                       length: species == .manta ? 230 : 135, depth: Float(i % 3) * 0.17, phase: Float(i), panic: 0))
        }
        frame.ripples = [Ripple(position: SIMD2(420, 440), age: 0.85, strength: 1)]
        frame.currents = (0..<8).map { CurrentStroke(position: SIMD2(900 + Float($0) * 19, 150 + Float($0) * 6), velocity: SIMD2(180, 45), age: Float($0) * 0.05) }
        let first = try renderer.renderRGBA(frame: frame, width: 1440, height: 900)
        let alpha = stride(from: 3, to: first.count, by: 4).map { first[$0] }
        let visible = alpha.filter { $0 > 0 }.count
        let clear = alpha.filter { $0 == 0 }.count
        let translucent = alpha.filter { $0 > 0 && $0 < 255 }.count
        precondition(visible > 10_000 && clear > alpha.count * 7 / 10, "Fish should be visible and most of the desktop fully clear.")
        precondition(translucent > 1_000, "Transparent fins, antialiasing and water should produce fractional alpha.")
        for index in stride(from: 0, to: first.count, by: 4) {
            precondition(first[index] <= first[index + 3] && first[index + 1] <= first[index + 3] && first[index + 2] <= first[index + 3], "Premultiplied output must not exceed alpha.")
        }
        try renderer.writePNG(frame: frame, width: 1440, height: 900, to: output.appendingPathComponent("ocean-transparent.png"))
        try renderer.writePNG(frame: frame, width: 1440, height: 900, to: output.appendingPathComponent("ocean-dark.png"), background: SIMD3(0.035, 0.07, 0.10))
        try renderer.writePNG(frame: frame, width: 1440, height: 900, to: output.appendingPathComponent("ocean-light.png"), background: SIMD3(0.92, 0.93, 0.89))
        frame.time += 0.57
        for index in frame.fish.indices { frame.fish[index].phase += 0.57 * 4.8 }
        let animated = try renderer.renderRGBA(frame: frame, width: 1440, height: 900)
        let changed = zip(first, animated).filter { $0 != $1 }.count
        precondition(changed > 1_000, "Mesh and water animation must vary over time.")
        // Keep effects disabled to prove each species, by itself, has a live silhouette.
        for species in FishSpecies.allCases {
            var sample = OceanFrame(size: SIMD2(480, 320), time: 1.0,
                                    fish: [FishState(id: 0, species: species, position: SIMD2(270, 170), velocity: SIMD2(35, 0), heading: 0.1, length: 330, depth: 0, phase: 0.7, panic: 0)], ripples: [], currents: [], waterStrength: 0)
            let a = try renderer.renderRGBA(frame: sample, width: 480, height: 320)
            sample.time += 0.6
            sample.fish[0].phase += 0.6 * 4.8
            let b = try renderer.renderRGBA(frame: sample, width: 480, height: 320)
            precondition(zip(a, b).filter { $0 != $1 }.count > 100, "Each species needs actual mesh animation.")
            try renderer.writePNG(frame: sample, width: 960, height: 640, to: output.appendingPathComponent("fish-\(species.rawValue).png"), background: SIMD3(0.08, 0.13, 0.16))
            // Fixed accumulated phase must not jump when speed changes late in a run.
            sample.time = 100_000
            sample.fish[0].velocity = SIMD2(190, 0)
            let late = try renderer.renderRGBA(frame: sample, width: 480, height: 320)
            precondition(b == late, "Elapsed time and instantaneous speed must not change an already integrated pose.")
            func relativePixelChange(_ before: [UInt8], _ after: [UInt8]) -> Double {
                let difference = zip(before, after).reduce(0) { $0 + abs(Int($1.0) - Int($1.1)) }
                let coverage = stride(from: 3, to: before.count, by: 4).reduce(0) { $0 + Int(before[$1]) }
                return Double(difference) / Double(max(1, coverage * 4))
            }
            sample.fish[0].phase = 2 * .pi - 0.002
            let wrapBefore = try renderer.renderRGBA(frame: sample, width: 480, height: 320)
            sample.fish[0].phase = 0.002
            let wrapAfter = try renderer.renderRGBA(frame: sample, width: 480, height: 320)
            precondition(relativePixelChange(wrapBefore, wrapAfter) < 0.025, "Phase wrapping must preserve continuous body and pectoral motion.")
            for heading: Float in [-Float.pi / 2, Float.pi / 2] {
                sample.fish[0].heading = heading - 0.0005
                let turnBefore = try renderer.renderRGBA(frame: sample, width: 480, height: 320)
                if species == .clown && heading > 0 {
                    try renderer.writePNG(frame: sample, width: 960, height: 640, to: output.appendingPathComponent("turn-before.png"), background: SIMD3(0.08, 0.13, 0.16))
                }
                sample.fish[0].heading = heading + 0.0005
                let turnAfter = try renderer.renderRGBA(frame: sample, width: 480, height: 320)
                let change = relativePixelChange(turnBefore, turnAfter)
                print("Continuous turn: species \(species.rawValue), heading \(heading), normalized pixel delta \(change)")
                fflush(stdout)
                precondition(change < 0.025, "Crossing a vertical heading must not mirror the full fish abruptly.")
                if species == .clown && heading > 0 {
                    try renderer.writePNG(frame: sample, width: 960, height: 640, to: output.appendingPathComponent("turn-after.png"), background: SIMD3(0.08, 0.13, 0.16))
                }
            }
        }
        let near = FishState(id: 1, species: .clown, position: SIMD2(160, 100), velocity: .zero, heading: 0, length: 200, depth: 0, phase: 0, panic: 0)
        let far = FishState(id: 2, species: .tang, position: SIMD2(160, 100), velocity: .zero, heading: 0, length: 260, depth: 0.9, phase: 0, panic: 0)
        var overlap = OceanFrame(size: SIMD2(320, 200), time: 0, fish: [near], ripples: [], currents: [], waterStrength: 0)
        let foreground = try renderer.renderRGBA(frame: overlap, width: 320, height: 200)
        overlap.fish = [near, far]
        let combined = try renderer.renderRGBA(frame: overlap, width: 320, height: 200)
        var checked = 0
        for index in stride(from: 0, to: foreground.count, by: 4) where foreground[index + 3] == 255 {
            for channel in 0..<3 { precondition(abs(Int(foreground[index + channel]) - Int(combined[index + channel])) <= 1, "Far fish must not cover opaque foreground pixels.") }
            checked += 1
        }
        precondition(checked > 1_000)
        print("PASS renderer: empty alpha = 0; 29 fish; visible \(visible), clear \(clear), translucent \(translucent); animation changed \(changed) bytes; premultiplied RGB valid; all five species animate.")
        print("PASS geometry: finite vertices for all species; depth ordering preserves \(checked) foreground pixels.")
        print("Samples: \(output.path)")
    }
}
