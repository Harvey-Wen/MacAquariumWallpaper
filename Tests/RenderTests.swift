import AppKit
import MetalKit
import ImageIO

@main struct RenderTests {
    static func delta(_ a: [UInt8], _ b: [UInt8]) -> Double {
        Double(zip(a,b).reduce(0) { $0 + abs(Int($1.0)-Int($1.1)) }) / Double(a.count * 255)
    }
    static func main() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let output = root.appendingPathComponent(".build/render-validation")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let view = MTKView(frame: NSRect(x: 0,y: 0,width: 1600,height: 1000)); view.isPaused = true
        let renderer = try OceanRenderer(view: view, shaderURL: root.appendingPathComponent("Resources/Ocean.metal"))
        do {
            _ = try OceanRenderer(view: MTKView(), shaderURL: output.appendingPathComponent("missing/Ocean.metal"))
            preconditionFailure("Missing environment must fail initialization")
        } catch { precondition(error.localizedDescription.contains("PondEnvironment.png")) }
        let mesh = FishMesh(species: .koi)
        precondition(mesh.vertices.count > 1000 && mesh.vertices.count % 3 == 0)
        precondition(mesh.vertices.allSatisfy { v in (0..<4).allSatisfy { v.position[$0].isFinite && v.normal[$0].isFinite && v.detail[$0].isFinite } })
        let empty = try renderer.renderRGBA(frame: .empty,width: 320,height: 200)
        precondition(empty.allSatisfy { $0 == 0 })
        let simulation = OceanSimulation(size: SIMD2(1600,1000),seed: 42)
        for _ in 0..<180 { simulation.update(deltaTime: 1.0/30) }
        let sunny = simulation.frame(waterStrength: 0.45)
        let pixels = try renderer.renderRGBA(frame: sunny,width: 1600,height: 1000)
        precondition(stride(from: 3,to: pixels.count,by: 4).allSatisfy { pixels[$0] == 255 })
        try renderer.writePNG(frame: sunny,width: 1600,height: 1000,to: output.appendingPathComponent("pond-sunny.png"))
        var noFish = sunny; noFish.fish = []; noFish.leaves = []; noFish.ripples = []
        let plain = try renderer.renderRGBA(frame: noFish,width: 1600,height: 1000)
        precondition(delta(pixels,plain)>0.0001)
        try renderer.writePNG(frame: noFish,width: 1600,height: 1000,to: output.appendingPathComponent("pond-no-fish.png"))
        var click = sunny
        click.ripples = [Ripple(position: SIMD2(1150,450),age: 0.65,strength: 1.5)]
        try renderer.writePNG(frame: click,width: 1600,height: 1000,to: output.appendingPathComponent("pond-click.png"))
        var landRipple = noFish
        landRipple.ripples = [Ripple(position: SIMD2(200,750),age: 1.0,strength: 1.8)]
        let ripplePixels = try renderer.renderRGBA(frame: landRipple,width: 1600,height: 1000)
        var landChecked = 0
        for y in stride(from: 0,to: 1000,by: 3) { for x in stride(from: 0,to: 1600,by: 3) {
            if PondGeometry.signedDistance(at: SIMD2(Float(x)+0.5,999.5-Float(y)),size: noFish.size)<(-5) {
                let i=(y*1600+x)*4
                precondition(Array(plain[i..<i+4]) == Array(ripplePixels[i..<i+4])); landChecked += 1
            }
        }}
        precondition(landChecked > 1000, "Foliage exclusion must exercise real samples")
        precondition(delta(plain,ripplePixels)>0)
        var foliageFish = noFish
        foliageFish.fish = [FishState(id: 1,species: .koi,position: SIMD2(100,900),velocity: .zero,heading: 0,length: 160,depth: 0.5,phase: 0,panic: 0),
                            FishState(id: 2,species: .koi,position: SIMD2(800,140),velocity: .zero,heading: 0,length: 160,depth: 0.5,phase: 0,panic: 0)]
        let fishMaskPixels = try renderer.renderRGBA(frame: foliageFish,width: 1600,height: 1000)
        var changedFishWater = 0
        for y in stride(from: 0,to: 1000,by: 3) { for x in stride(from: 0,to: 1600,by: 3) {
            let distance = PondGeometry.signedDistance(at: SIMD2(Float(x)+0.5,999.5-Float(y)),size: noFish.size)
            let i=(y*1600+x)*4
            let same = (0..<4).allSatisfy { plain[i+$0] == fishMaskPixels[i+$0] }
            if distance < -5 { precondition(same, "Fish cannot paint over opaque foliage") }
            if distance > 5 && !same { changedFishWater += 1 }
        }}
        precondition(changedFishWater > 100, "Fish must render in former bottom peninsula water")
        simulation.weather = .rainy
        for _ in 0..<240 { simulation.update(deltaTime: 1.0/30) }
        let rainy = simulation.frame(waterStrength: 0.45)
        try renderer.writePNG(frame: rainy,width: 1600,height: 1000,to: output.appendingPathComponent("pond-rainy.png"))
        // Hold weather and every other layer fixed: isolate actual rain impacts.
        var rainImpacts = rainy
        rainImpacts.ripples = rainy.ripples.filter { $0.source == .rain }
        precondition(rainImpacts.ripples.count >= 3)
        let withRain = try renderer.renderRGBA(frame: rainImpacts,width: 1600,height: 1000)
        var withoutImpacts = rainImpacts; withoutImpacts.ripples = []
        let withoutRain = try renderer.renderRGBA(frame: withoutImpacts,width: 1600,height: 1000)
        var changedWater = 0, foliageChecked = 0
        for y in stride(from: 0,to: 1000,by: 2) { for x in stride(from: 0,to: 1600,by: 2) {
            let distance = PondGeometry.signedDistance(at: SIMD2(Float(x)+0.5,999.5-Float(y)),size: rainy.size)
            let i = (y*1600+x)*4
            let same = (0..<4).allSatisfy { withRain[i+$0] == withoutRain[i+$0] }
            if distance < -5 { precondition(same, "Rain impacts must leave foliage unchanged"); foliageChecked += 1 }
            if distance > 5 && !same { changedWater += 1 }
        }}
        precondition(foliageChecked > 1000)
        precondition(changedWater > 100, "Rain impacts must visibly change water independently of dimming")
        print("PASS rain impacts: \(rainImpacts.ripples.count) active, \(changedWater) changed water samples; land unchanged.")
        var wet = noFish; wet.weatherAmount = 1
        let wetPixels = try renderer.renderRGBA(frame: wet,width: 1600,height: 1000)
        precondition(delta(plain,wetPixels)>0.005)
        // Disable water movement and all visible actors to isolate atmospheric rain.
        var streaks = noFish; streaks.waterStrength = 0
        streaks.time = 604800
        let dryStill = try renderer.renderRGBA(frame: streaks,width: 1600,height: 1000)
        streaks.time += 1.0/30
        let dryLater = try renderer.renderRGBA(frame: streaks,width: 1600,height: 1000)
        precondition(dryStill.allSatisfy { $0 == 0 }, "Empty dry frame must remain transparent")
        precondition(dryStill == dryLater, "Dry weather must have no atmospheric streak motion")
        streaks.weatherAmount = 1
        streaks.time = 604800
        let frozenRain = try renderer.renderRGBA(frame: streaks,width: 1600,height: 1000)
        precondition(frozenRain.contains { $0 != 0 }, "Rain-only frame must render without placeholder actors")
        let pausedRain = try renderer.renderRGBA(frame: streaks,width: 1600,height: 1000)
        precondition(frozenRain == pausedRain, "Paused frame must freeze rain exactly")
        streaks.time += 1.0/30
        let nextRain = try renderer.renderRGBA(frame: streaks,width: 1600,height: 1000)
        var landStreaks = 0, waterStreaks = 0
        for y in stride(from: 0,to: 1000,by: 2) { for x in stride(from: 0,to: 1600,by: 2) {
            let i=(y*1600+x)*4
            if (0..<3).contains(where: { frozenRain[i+$0] != nextRain[i+$0] }) {
                let d=PondGeometry.signedDistance(at: SIMD2(Float(x)+0.5,999.5-Float(y)),size: streaks.size)
                if d < -5 { landStreaks += 1 }
                if d > 5 { waterStreaks += 1 }
            }
        }}
        precondition(landStreaks > 100 && waterStreaks > 100, "Atmospheric rain must move over both foliage and water")
        var lastRain = nextRain
        for step in 2...12 {
            streaks.time = 604800 + Double(step)/30
            let next = try renderer.renderRGBA(frame: streaks,width: 1600,height: 1000)
            let d = delta(lastRain,next); precondition(d > 0.00001 && d < 0.005); lastRain = next
        }
        streaks.time = 604802 - 0.0001
        let wrapBefore = try renderer.renderRGBA(frame: streaks,width: 1600,height: 1000)
        streaks.time = 604802 + 0.0001
        let wrapAfter = try renderer.renderRGBA(frame: streaks,width: 1600,height: 1000)
        precondition(delta(wrapBefore,wrapAfter) < delta(frozenRain,nextRain)*0.1, "Rain period must wrap without a visible reset")
        streaks.time = 604800
        let daySeven = try renderer.renderRGBA(frame: streaks,width: 1600,height: 1000)
        streaks.time = 0
        let firstDay = try renderer.renderRGBA(frame: streaks,width: 1600,height: 1000)
        precondition(daySeven == firstDay, "Rain phase must retain precision at day seven")
        print("PASS atmospheric rain: \(landStreaks) changed land samples, \(waterStreaks) water samples; dry/paused static, day-seven motion and wrap continuous.")
        // Same leaf over a fish: surface pixels must cover the underwater animal.
        var layers = noFish; layers.waterStrength = 0.45
        let center = SIMD2<Float>(800,500)
        layers.leaves = [PondLeaf(id: 1,position: center,velocity: .zero,age: 1,rotation: 0,length: 60,stage: .floating,fallDuration: 1,opacity: 1)]
        let leafOnly = try renderer.renderRGBA(frame: layers,width: 1600,height: 1000)
        var falling = layers
        falling.leaves[0].stage = .falling
        falling.leaves[0].age = 0
        let highLeaf = try renderer.renderRGBA(frame: falling,width: 1600,height: 1000)
        falling.leaves[0].age = 0.999
        let landingLeaf = try renderer.renderRGBA(frame: falling,width: 1600,height: 1000)
        let fullDescent = delta(highLeaf,leafOnly)
        precondition(fullDescent > 0.000001)
        precondition(delta(landingLeaf,leafOnly) < fullDescent * 0.01, "Leaf size must converge smoothly before landing")
        layers.fish = [FishState(id: 1,species: .koi,position: center,velocity: .zero,heading: 0,length: 160,depth: 0.5,phase: 0,panic: 0)]
        let leafFish = try renderer.renderRGBA(frame: layers,width: 1600,height: 1000)
        var pose = layers; pose.leaves = []; pose.waterStrength = 0
        pose.fish[0].phase = 2 * .pi - 0.002
        let poseBefore = try renderer.renderRGBA(frame: pose,width: 800,height: 500)
        pose.fish[0].phase = 0.002
        let poseAfter = try renderer.renderRGBA(frame: pose,width: 800,height: 500)
        precondition(delta(poseBefore,poseAfter)<0.0001)
        pose.fish[0].phase = 1.5
        let moving = try renderer.renderRGBA(frame: pose,width: 800,height: 500)
        precondition(delta(moving,poseAfter)>0.00001)
        pose.fish[0].heading = .pi / 2 - 0.002
        let turnBefore = try renderer.renderRGBA(frame: pose,width: 800,height: 500)
        pose.fish[0].heading = .pi / 2 + 0.002
        let turnAfter = try renderer.renderRGBA(frame: pose,width: 800,height: 500)
        precondition(delta(turnBefore,turnAfter)<0.0001)
        let centerIndex=(500*1600+800)*4
        precondition(Array(leafOnly[centerIndex..<centerIndex+3]) == Array(leafFish[centerIndex..<centerIndex+3]))
        precondition(delta(leafOnly,leafFish)>0)
        try renderer.writePNG(frame: layers,width: 1600,height: 1000,to: output.appendingPathComponent("pond-layer-check.png"))
        // Continuous wrapped phases retain per-frame movement after a week.
        noFish.time = 604800
        var previous = try renderer.renderRGBA(frame: noFish,width: 640,height: 400)
        for step in 1...12 {
            noFish.time = 604800 + Double(step)/30
            let next = try renderer.renderRGBA(frame: noFish,width: 640,height: 400)
            let d = delta(previous,next); precondition(d>0 && d<0.005); previous=next
        }
        for frequency in [0.21,0.17] {
            let boundary=ceil(604800*frequency/(2 * .pi))*(2 * .pi)/frequency
            noFish.time=boundary-1.0/60
            let a=try renderer.renderRGBA(frame: noFish,width: 640,height: 400)
            noFish.time=boundary+1.0/60
            let b = try renderer.renderRGBA(frame: noFish,width: 640,height: 400)
            precondition(delta(a,b)<0.005)
        }
        for size: SIMD2<Float> in [SIMD2(1200,1200),SIMD2(1800,900),SIMD2(900,1400)] {
            let sample=OceanSimulation(size: size,seed: 42).frame(waterStrength: 0.45)
            let bytes=try renderer.renderRGBA(frame: sample,width: Int(size.x),height: Int(size.y))
            precondition(stride(from: 3,to: bytes.count,by: 4).allSatisfy { bytes[$0]==255 })
            try renderer.writePNG(frame: sample,width: Int(size.x),height: Int(size.y),to: output.appendingPathComponent("pond-\(Int(size.x))x\(Int(size.y)).png"))
        }
        let primary = OceanSimulation(size: SIMD2(3024,1964),seed: 42)
        for _ in 0..<180 { primary.update(deltaTime: 1.0/30) }
        try renderer.writePNG(frame: primary.frame(waterStrength: 0.45),width: 3024,height: 1964,to: output.appendingPathComponent("pond-primary-sunny.png"))
        primary.weather = .rainy
        for _ in 0..<240 { primary.update(deltaTime: 1.0/30) }
        var benchmark = primary.frame(waterStrength: 0.45)
        try renderer.writePNG(frame: benchmark,width: 3024,height: 1964,to: output.appendingPathComponent("pond-primary-rainy.png"))
        var timings: [Double]=[]
        for i in 0..<35 {
            benchmark.time += 1.0/30
            _ = try renderer.renderRGBA(frame: benchmark,width: 3024,height: 1964)
            if i>=5 { timings.append(renderer.lastGPUSeconds*1000) }
        }
        timings.sort()
        print("PASS opacity, empty, mesh, fish difference, \(landChecked) unchanged land samples, weather, surface leaf ordering, seven-day continuity and 3 aspect ratios.")
        print("GPU \(view.device!.name) 3024x1964 rainy: median \(timings[15]) ms; p95 \(timings[28]) ms; max \(timings.last!) ms (30 measured frames).")
        precondition(timings[28]<1000/30)
        if CommandLine.arguments.contains("--preview") {
            let url=output.appendingPathComponent("pond-preview.gif")
            let destination=CGImageDestinationCreateWithURL(url as CFURL,"com.compuserve.gif" as CFString,60,nil)!
            CGImageDestinationSetProperties(destination,[kCGImagePropertyGIFDictionary:[kCGImagePropertyGIFLoopCount:0]] as CFDictionary)
            for index in 0..<60 {
                primary.update(deltaTime: 1.0/15)
                if index % 15 == 0 || index == 59 {
                    try renderer.writePNG(frame: primary.frame(waterStrength: 0.45),width: 1512,height: 982,to: output.appendingPathComponent("preview-frame-\(index).png"))
                }
                let bytes=try renderer.renderRGBA(frame: primary.frame(waterStrength: 0.45),width: 756,height: 491)
                let data=Data(bytes) as CFData
                let image=CGImage(width:756,height:491,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:3024,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.premultipliedLast.rawValue),provider:CGDataProvider(data:data)!,decode:nil,shouldInterpolate:true,intent:.defaultIntent)!
                CGImageDestinationAddImage(destination,image,[kCGImagePropertyGIFDictionary:[kCGImagePropertyGIFDelayTime:0.067]] as CFDictionary)
            }
            precondition(CGImageDestinationFinalize(destination))
        }
        print("Outputs: \(output.path)")
    }
}
