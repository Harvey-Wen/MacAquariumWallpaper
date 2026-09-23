import AppKit
import ImageIO
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
        var waterOnly = OceanFrame.empty
        waterOnly.size = SIMD2(640, 400)
        waterOnly.time = 3.2
        waterOnly.waterStrength = 0.45
        let waterPixels = try renderer.renderRGBA(frame: waterOnly, width: 640, height: 400)
        let waterAlpha = stride(from: 3, to: waterPixels.count, by: 4).map { waterPixels[$0] }
        print("Water-only visible pixels: \(waterAlpha.filter { $0 > 0 }.count)")
        fflush(stdout)
        precondition(waterAlpha.allSatisfy { $0 > 0 && $0 < 255 }, "Water must cover the viewport while keeping the wallpaper visible without any fish.")
        var strengths: [Double] = []
        for strength: Float in [0.25, 0.45, 0.75] {
            waterOnly.waterStrength = strength
            let pixels = try renderer.renderRGBA(frame: waterOnly, width: 640, height: 400)
            let alpha = stride(from: 3, to: pixels.count, by: 4).map { pixels[$0] }
            let meanAlpha = Double(alpha.reduce(0) { $0 + Int($1) }) / Double(alpha.count * 255)
            precondition(alpha.allSatisfy { $0 < 255 } && meanAlpha < 0.5, "Even strong water must leave the wallpaper visible and retain most of its average contribution.")
            validatePremultiplication(pixels)
            strengths.append(meanAlpha)
        }
        precondition(strengths[0] < strengths[1] && strengths[1] < strengths[2], "Each water-strength setting must visibly increase the environment contribution.")
        waterOnly.waterStrength = 0
        let disabledWater = try renderer.renderRGBA(frame: waterOnly, width: 640, height: 400)
        precondition(disabledWater.allSatisfy { $0 == 0 }, "Disabling water in a scene without content must restore zero RGB and alpha.")
        waterOnly.waterStrength = 0.45
        waterOnly.time += 0.57
        let animatedWater = try renderer.renderRGBA(frame: waterOnly, width: 640, height: 400)
        let waterChanged = zip(waterPixels, animatedWater).filter { $0 != $1 }.count
        precondition(waterChanged > 100, "The underwater environment must animate when all fish are hidden.")
        waterOnly.time = 3.2
        try renderer.writePNG(frame: waterOnly, width: 1440, height: 900, to: output.appendingPathComponent("water-only-dark.png"), background: SIMD3(0.035, 0.07, 0.10))
        try renderer.writePNG(frame: waterOnly, width: 1440, height: 900, to: output.appendingPathComponent("water-only-light.png"), background: SIMD3(0.92, 0.93, 0.89))
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
        precondition(visible == alpha.count && translucent > alpha.count / 2, "The environment must span the viewport while most pixels still transmit the wallpaper.")
        validatePremultiplication(first)
        try renderer.writePNG(frame: frame, width: 1440, height: 900, to: output.appendingPathComponent("ocean-transparent.png"))
        try renderer.writePNG(frame: frame, width: 1440, height: 900, to: output.appendingPathComponent("ocean-dark.png"), background: SIMD3(0.035, 0.07, 0.10))
        try renderer.writePNG(frame: frame, width: 1440, height: 900, to: output.appendingPathComponent("ocean-light.png"), background: SIMD3(0.92, 0.93, 0.89))
        try compositeBitmap(first, width: 1440, height: 900).representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("ocean-complex.png"))
        let waterSample = try renderer.renderRGBA(frame: waterOnly, width: 1440, height: 900)
        try compositeBitmap(waterSample, width: 1440, height: 900).representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("water-only-complex.png"))
        try compositeBitmap([UInt8](repeating: 0, count: first.count), width: 1440, height: 900).representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("background-reference.png"))
        if CommandLine.arguments.contains("--preview") {
            try writePreview(renderer: renderer, frame: waterOnly, to: output.appendingPathComponent("water-only-preview.gif"))
            try writePreview(renderer: renderer, frame: frame, to: output.appendingPathComponent("ocean-preview.gif"))
        }
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
        // No fish: only water, ripple and bubble pixels can change.
        let sevenDays = 7.0 * 24 * 60 * 60
        var water = OceanFrame(size: SIMD2(640, 400), time: sevenDays,
                               fish: [],
                               ripples: [Ripple(position: SIMD2(320, 200), age: 1, strength: 1.8)], currents: [], waterStrength: 1)
        var previous = try renderer.renderRGBA(frame: water, width: 640, height: 400)
        var minimumChanged = Int.max
        for step in 1...12 {
            water.time = sevenDays + Double(step) / 30
            let next = try renderer.renderRGBA(frame: water, width: 640, height: 400)
            let changedBytes = zip(previous, next).filter { $0 != $1 }.count
            precondition(changedBytes > 100, "Water must advance every 30 FPS frame after seven days, without Float-time plateaus.")
            minimumChanged = min(minimumChanged, changedBytes)
            previous = next
        }
        var largestBoundaryDelta = 0.0
        for frequency in [0.21, 0.17, 1.4] {
            let boundary = ceil(sevenDays * frequency / (2 * .pi)) * (2 * .pi) / frequency
            water.time = boundary - 1.0 / 60
            let before = try renderer.renderRGBA(frame: water, width: 640, height: 400)
            water.time = boundary + 1.0 / 60
            let after = try renderer.renderRGBA(frame: water, width: 640, height: 400)
            let difference = zip(before, after).reduce(0) { $0 + abs(Int($1.0) - Int($1.1)) }
            let coverage = stride(from: 3, to: before.count, by: 4).reduce(0) { $0 + Int(before[$1]) }
            let relativeDifference = Double(difference) / Double(max(1, coverage * 4))
            precondition(relativeDifference < 0.05, "Each water frequency must wrap continuously at its own phase boundary.")
            largestBoundaryDelta = max(largestBoundaryDelta, relativeDifference)
        }
        print("PASS long-running water: 12 consecutive 30 FPS steps at seven days each change at least \(minimumChanged) bytes; maximum phase-boundary delta \(largestBoundaryDelta).")
        print("PASS underwater environment: no fish, animated \(waterChanged) bytes; mean alpha at strengths 0.25/0.45/0.75 = \(strengths); disabled water RGBA = 0.")
        print("PASS renderer: empty alpha = 0; 29 fish; visible \(visible), clear \(clear), translucent \(translucent); animation changed \(changed) bytes; premultiplied RGB valid; all five species animate.")
        print("PASS geometry: finite vertices for all species; depth ordering preserves \(checked) foreground pixels.")
        print("Samples: \(output.path)")
    }

    static func validatePremultiplication(_ pixels: [UInt8]) {
        for index in stride(from: 0, to: pixels.count, by: 4) {
            precondition(pixels[index] <= pixels[index + 3] && pixels[index + 1] <= pixels[index + 3] && pixels[index + 2] <= pixels[index + 3], "Premultiplied output must not exceed alpha.")
        }
    }

    // A synthetic landscape exercises dark details, bright sky and multiple colors without reading the desktop.
    static func compositeBitmap(_ foreground: [UInt8], width: Int, height: Int) -> NSBitmapImageRep {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                                     samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                     bitmapFormat: .alphaNonpremultiplied, bytesPerRow: width * 4, bitsPerPixel: 32)!
        let pixels = bitmap.bitmapData!
        for y in 0..<height {
            for x in 0..<width {
                let u = Float(x) / Float(width), v = Float(y) / Float(height)
                var background = SIMD3<Float>(0.87 - u * 0.39, 0.69 + u * 0.05, 0.48 + u * 0.36) * (1 - v * 0.35)
                for layer in 0..<3 {
                    let level = Float(layer)
                    let ridge = 0.39 + level * 0.18 + sin(u * (7 + level * 3) + level) * 0.10 + sin(u * 23 + level) * 0.025
                    if v > ridge {
                        let detail = 0.025 * sin(u * 180 + v * 35) * sin(v * 140)
                        background = SIMD3<Float>(0.20 - level * 0.05, 0.33 - level * 0.075, 0.36 - level * 0.075) + SIMD3(repeating: detail)
                    }
                }
                let index = (y * width + x) * 4
                let alpha = Float(foreground[index + 3]) / 255
                for channel in 0..<3 {
                    pixels[index + channel] = UInt8(min(255, max(0, Float(foreground[index + channel]) + background[channel] * (1 - alpha) * 255)).rounded())
                }
                pixels[index + 3] = 255
            }
        }
        return bitmap
    }

    static func writePreview(renderer: OceanRenderer, frame: OceanFrame, to url: URL) throws {
        let width = 640, height = 400, fps = 15, frameCount = 10 * fps
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "com.compuserve.gif" as CFString, frameCount, nil) else {
            throw OceanRenderError.unavailable("无法创建动态预览。")
        }
        CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        for index in 0..<frameCount {
            let elapsed = Double(index) / Double(fps)
            var sample = frame
            sample.time += elapsed
            for fish in sample.fish.indices {
                sample.fish[fish].phase += Float(elapsed) * 4.8
                sample.fish[fish].position += sample.fish[fish].velocity * Float(elapsed)
            }
            for ripple in sample.ripples.indices { sample.ripples[ripple].age += Float(elapsed) }
            for current in sample.currents.indices { sample.currents[current].age += Float(elapsed) }
            let pixels = try renderer.renderRGBA(frame: sample, width: width, height: height)
            let image = compositeBitmap(pixels, width: width, height: height).cgImage!
            // GIF stores centiseconds; alternate 6/7-centisecond delays to preserve the full ten-second duration.
            let delay = (round(Double(index + 1) * 100 / Double(fps)) - round(Double(index) * 100 / Double(fps))) / 100
            CGImageDestinationAddImage(destination, image, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay]] as CFDictionary)
        }
        precondition(CGImageDestinationFinalize(destination), "Animated preview must encode successfully.")
        print("Preview: \(url.path) (10 seconds, 15 FPS)")
        fflush(stdout)
    }
}
