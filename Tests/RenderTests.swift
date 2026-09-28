import AppKit
import MetalKit
import ImageIO

@main struct RenderTests {
    static func delta(_ a: [UInt8], _ b: [UInt8]) -> Double {
        Double(zip(a,b).reduce(0) { $0 + abs(Int($1.0)-Int($1.1)) }) / Double(a.count * 255)
    }
    static func weatherModes(renderer: OceanRenderer, sunny: OceanFrame, output: URL) throws {
        let snowfall = OceanSimulation(size: sunny.size, seed: 42)
        snowfall.weather = .snowy
        for _ in 0..<1050 { snowfall.update(deltaTime: 1.0/30) }
        let snowFrame = snowfall.frame(waterStrength: 0.45)
        var samples: [[UInt8]] = []
        for weather in [PondWeather.sunny, .snowy, .overcast, .cloudy] {
            var frame = sunny; frame.atmosphere = weather.atmosphere
            if weather == .snowy { frame.precipitation = snowFrame.precipitation; frame.surfaceSnow = snowFrame.surfaceSnow }
            let bytes = try renderer.renderRGBA(frame: frame,width: 800,height: 500)
            precondition(stride(from: 3,to: bytes.count,by: 4).allSatisfy { bytes[$0] == 255 })
            for previous in samples { precondition(delta(previous,bytes) > 0.003, "Weather must be visibly distinct") }
            samples.append(bytes)
            try renderer.writePNG(frame: frame,width: 1600,height: 1000,to: output.appendingPathComponent("pond-\(weather.rawValue).png"))
        }
        var still = OceanFrame.empty; still.size = sunny.size; still.atmosphere = PondWeather.overcast.atmosphere
        let overcast = try renderer.renderRGBA(frame: still,width: 800,height: 500)
        precondition(overcast.contains { $0 > 0 }, "Atmosphere-only frame is visible")
        still.time = 10
        let overcastLater = try renderer.renderRGBA(frame: still,width: 800,height: 500)
        precondition(overcast == overcastLater, "Overcast contains no precipitation or moving cloud shadows")
        still.atmosphere = PondWeather.cloudy.atmosphere; still.time = 0
        let clouds = try renderer.renderRGBA(frame: still,width: 800,height: 500)
        still.time = 10
        let movingClouds = try renderer.renderRGBA(frame: still,width: 800,height: 500)
        precondition(delta(clouds,movingClouds) > 0.001, "Broken cloud shadows drift")
        let cloudPeriod = 2 * Double.pi / 0.025
        still.time = cloudPeriod - 0.0001
        let cloudBefore = try renderer.renderRGBA(frame: still,width: 800,height: 500)
        still.time = cloudPeriod + 0.0001
        let cloudAfter = try renderer.renderRGBA(frame: still,width: 800,height: 500)
        precondition(delta(cloudBefore,cloudAfter) < 0.00001, "Cloud phase wraps continuously")
        still.atmosphere = PondWeather.snowy.atmosphere
        still.precipitation = snowFrame.precipitation
        let snow = try renderer.renderRGBA(frame: still,width: 1600,height: 1000)
        let pausedSnow = try renderer.renderRGBA(frame: still,width: 1600,height: 1000)
        precondition(snow == pausedSnow, "Pause freezes snow exactly")
        snowfall.update(deltaTime: 1.0/30)
        still.precipitation = snowfall.frame(waterStrength: 0.45).precipitation
        let snowLater = try renderer.renderRGBA(frame: still,width: 1600,height: 1000)
        var foliage = 0, water = 0
        for y in stride(from: 0,to: 1000,by: 2) { for x in stride(from: 0,to: 1600,by: 2) {
            let i=(y*1600+x)*4
            if (0..<3).contains(where: { abs(Int(snow[i+$0])-Int(snowLater[i+$0])) > 3 }) {
                if PondGeometry.contains(SIMD2(Float(x),1000-Float(y)),size: still.size) { water += 1 }
                else { foliage += 1 }
            }
        }}
        precondition(foliage > 100 && water > 100, "Snow moves across branches and water")
        still.time = 256 * 10000
        let longSnow = try renderer.renderRGBA(frame: still,width: 1600,height: 1000)
        precondition(snowLater == longSnow, "Snow positions do not depend on a wrapping global shader clock")
        var deposited = still; deposited.precipitation = []; deposited.surfaceSnow = snowFrame.surfaceSnow
        let deposits = try renderer.renderRGBA(frame: deposited,width: 1600,height: 1000)
        var melted = deposited; melted.surfaceSnow = []
        let noDeposits = try renderer.renderRGBA(frame: melted,width: 1600,height: 1000)
        precondition(delta(deposits,noDeposits) > 0.0001, "Accumulated snow visibly rests on the water")
        for y in stride(from: 0,to: 1000,by: 3) { for x in stride(from: 0,to: 1600,by: 3) {
            if PondGeometry.signedDistance(at: SIMD2(Float(x),1000-Float(y)),size: still.size) < -5 {
                let i=(y*1600+x)*4
                precondition(Array(deposits[i..<i+4]) == Array(noDeposits[i..<i+4]), "Surface snow excludes branches")
            }
        }}
        let beforeSwitch = snowfall.frame(waterStrength: 0.45)
        let switchPixels = try renderer.renderRGBA(frame: beforeSwitch,width: 1600,height: 1000)
        snowfall.weather = .rainy
        let selectedPixels = try renderer.renderRGBA(frame: snowfall.frame(waterStrength: 0.45),width: 1600,height: 1000)
        precondition(switchPixels == selectedPixels, "Weather choice never replaces visible particles immediately")
        for tick in 0..<45 {
            snowfall.update(deltaTime: 1.0/30)
            if tick == 0 || tick == 14 || tick == 44 {
                try renderer.writePNG(frame: snowfall.frame(waterStrength: 0.45),width: 1600,height: 1000,
                    to: output.appendingPathComponent("pond-snow-to-rain-\(tick).png"))
            }
        }
        let mixed = snowfall.frame(waterStrength: 0.45)
        precondition(mixed.precipitation.contains { $0.kind == .snow } && mixed.precipitation.contains { $0.kind == .rain })
        if CommandLine.arguments.contains("--preview") {
            let url=output.appendingPathComponent("pond-snow-to-rain.gif")
            let destination=CGImageDestinationCreateWithURL(url as CFURL,"com.compuserve.gif" as CFString,90,nil)!
            CGImageDestinationSetProperties(destination,[kCGImagePropertyGIFDictionary:[kCGImagePropertyGIFLoopCount:0]] as CFDictionary)
            let preview = OceanSimulation(size: SIMD2(1600,1000),seed: 42); preview.weather = .snowy
            for _ in 0..<1050 { preview.update(deltaTime: 1.0/30) }
            for index in 0..<90 {
                if index == 30 { preview.weather = .rainy }
                preview.update(deltaTime: 1.0/15)
                let bytes=try renderer.renderRGBA(frame: preview.frame(waterStrength: 0.45),width: 960,height: 600)
                let image=CGImage(width:960,height:600,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:3840,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.premultipliedLast.rawValue),provider:CGDataProvider(data:Data(bytes) as CFData)!,decode:nil,shouldInterpolate:true,intent:.defaultIntent)!
                CGImageDestinationAddImage(destination,image,[kCGImagePropertyGIFDictionary:[kCGImagePropertyGIFDelayTime:0.067]] as CFDictionary)
            }
            precondition(CGImageDestinationFinalize(destination))
        }
        for weather in [PondWeather.snowy, .overcast, .cloudy] {
            var frame = sunny; frame.size = SIMD2(1512,982); frame.atmosphere = weather.atmosphere
            if weather == .snowy { frame.precipitation = snowFrame.precipitation; frame.surfaceSnow = snowFrame.surfaceSnow }
            var timings: [Double] = []
            for index in 0..<20 {
                frame.time += 1.0/30
                _ = try renderer.renderRGBA(frame: frame,width: 3024,height: 1964)
                if index >= 5 { timings.append(renderer.lastGPUSeconds * 1000) }
            }
            timings.sort()
            precondition(timings[14] < 1000/30, "New weather fits the GPU frame budget")
            print("GPU \(weather.rawValue) 3024x1964: median \(timings[7]) ms; max \(timings[14]) ms.")
        }
        print("PASS five-weather visuals, snow over \(foliage) foliage / \(water) water samples, accumulation, smooth rain handoff, pause and long-running snow/cloud motion.")
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
        try weatherModes(renderer: renderer, sunny: sunny, output: output)
        var noFish = sunny; noFish.fish = []; noFish.leaves = []; noFish.ripples = []
        let plain = try renderer.renderRGBA(frame: noFish,width: 1600,height: 1000)
        precondition(delta(pixels,plain)>0.0001)
        try renderer.writePNG(frame: noFish,width: 1600,height: 1000,to: output.appendingPathComponent("pond-no-fish.png"))
        var click = sunny
        click.ripples = [Ripple(position: SIMD2(1150,450),age: 0.65,strength: 1.5)]
        try renderer.writePNG(frame: click,width: 1600,height: 1000,to: output.appendingPathComponent("pond-click.png"))
        // Signed relief, directionality, refraction of fish, cache resizing and expiry.
        var wake = noFish
        wake.ripples = [Ripple(position: SIMD2(850,500),age: 0.3,strength: 0.65,source: .motion,travel: SIMD2(100,0))]
        let horizontal = try renderer.renderRGBA(frame: wake,width: 1600,height: 1000)
        try renderer.writePNG(frame: wake,width: 1600,height: 1000,to: output.appendingPathComponent("pond-cursor-wake.png"))
        var bright=0, dark=0
        for i in stride(from: 0,to: plain.count,by: 4) {
            let relief=(0..<3).reduce(0) { $0 + Int(horizontal[i+$1])-Int(plain[i+$1]) }
            if relief > 5 { bright += 1 }; if relief < -5 { dark += 1 }
        }
        precondition(bright > 100 && dark > 100, "Wakes need signed lit/dark relief")
        wake.ripples[0].travel = SIMD2(0,100)
        let vertical = try renderer.renderRGBA(frame: wake,width: 1600,height: 1000)
        precondition(delta(horizontal,vertical)>0.00001, "Motion direction must change wake orientation")
        func wakeExtent(_ bytes: [UInt8]) -> (Double,Double) {
            var xx=0.0, yy=0.0
            for y in 350..<650 { for x in 700..<1000 {
                let i=(y*1600+x)*4
                let weight=Double((0..<3).reduce(0) { $0 + abs(Int(bytes[i+$1])-Int(plain[i+$1])) })
                xx += weight*pow(Double(x)-850,2); yy += weight*pow(Double(y)-500,2)
            }}
            return (xx,yy)
        }
        let h = wakeExtent(horizontal), v = wakeExtent(vertical)
        precondition(h.0 > h.1*2 && v.1 > v.0*2, "Wake must follow its finite travel strip, not stamp circles")
        var refracted = wake
        refracted.fish = [FishState(id: 1,species: .koi,position: SIMD2(842,465),velocity: .zero,heading: 0,length: 95,depth: 0.3,phase: 0,panic: 0)]
        let wetFish = try renderer.renderRGBA(frame: refracted,width: 1600,height: 1000)
        refracted.ripples = []
        let dryFish = try renderer.renderRGBA(frame: refracted,width: 1600,height: 1000)
        var refractedSamples=0
        for y in 490..<590 { for x in 780..<910 {
            let i=(y*1600+x)*4
            var changed = false
            for c in 0..<3 {
                let fishChange = Int(wetFish[i+c]) - Int(dryFish[i+c])
                let backgroundChange = Int(vertical[i+c]) - Int(plain[i+c])
                if abs(fishChange - backgroundChange) > 4 { changed = true }
            }
            if changed { refractedSamples += 1 }
        }}
        precondition(refractedSamples > 30, "Wave must refract underwater fish as well as background")
        let frozenWake = try renderer.renderRGBA(frame: wake,width: 1600,height: 1000)
        precondition(frozenWake == vertical)
        _ = try renderer.renderRGBA(frame: wake,width: 900,height: 700)
        let resizedBack = try renderer.renderRGBA(frame: wake,width: 1600,height: 1000)
        precondition(resizedBack == vertical, "Target recreation preserves mapping and frame identity")
        for dimensions in [(800,500),(1200,750)] {
            let base = try renderer.renderRGBA(frame: noFish,width: dimensions.0,height: dimensions.1)
            let displaced = try renderer.renderRGBA(frame: wake,width: dimensions.0,height: dimensions.1)
            var localChanges = 0
            for y in 0..<dimensions.1 { for x in 0..<dimensions.0 {
                let i=(y*dimensions.0+x)*4
                if (0..<3).contains(where: { base[i+$0] != displaced[i+$0] }) {
                    let point = SIMD2<Float>((Float(x)+0.5)*1600/Float(dimensions.0),1000-(Float(y)+0.5)*1000/Float(dimensions.1))
                    precondition(abs(point.x-850)<85 && point.y>350 && point.y<550, "Refraction must preserve bottom-left point mapping at every backing size")
                    localChanges += 1
                }
            }}
            precondition(localChanges>100)
        }
        wake.ripples[0].age = 2.3
        let expiredWake = try renderer.renderRGBA(frame: wake,width: 1600,height: 1000)
        precondition(expiredWake == plain, "Expired wake leaves no painted residue")
        print("PASS signed wake: \(bright) bright / \(dark) dark; \(refractedSamples) refracted fish samples, oriented strip, deterministic resize and expiry.")
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
        var changedWater = 0, foliageChecked = 0, rainBright = 0, rainDark = 0
        for y in stride(from: 0,to: 1000,by: 2) { for x in stride(from: 0,to: 1600,by: 2) {
            let distance = PondGeometry.signedDistance(at: SIMD2(Float(x)+0.5,999.5-Float(y)),size: rainy.size)
            let i = (y*1600+x)*4
            let same = (0..<4).allSatisfy { withRain[i+$0] == withoutRain[i+$0] }
            if distance < -5 { precondition(same, "Rain impacts must leave foliage unchanged"); foliageChecked += 1 }
            if distance > 5 && !same {
                changedWater += 1
                let signed = (0..<3).reduce(0) { $0 + Int(withRain[i+$1]) - Int(withoutRain[i+$1]) }
                if signed > 3 { rainBright += 1 }; if signed < -3 { rainDark += 1 }
            }
        }}
        precondition(foliageChecked > 1000)
        precondition(rainBright > 50 && rainDark > 50, "Rain relief must contain both lit and dark slopes")
        var expiredRain = rainImpacts
        for i in expiredRain.ripples.indices { expiredRain.ripples[i].age = 1.4 }
        let expiredRainPixels = try renderer.renderRGBA(frame: expiredRain,width: 1600,height: 1000)
        precondition(expiredRainPixels == withoutRain, "Rain waves must fully expire")
        precondition(changedWater > 100, "Rain impacts must visibly change water independently of dimming")
        print("PASS rain impacts: \(rainImpacts.ripples.count) active, \(changedWater) changed water samples; land unchanged.")
        var wet = noFish; wet.weatherAmount = 1
        let wetPixels = try renderer.renderRGBA(frame: wet,width: 1600,height: 1000)
        precondition(delta(plain,wetPixels)>0.005)
        let drops = OceanSimulation(size: noFish.size, seed: 8); drops.weather = .rainy
        for _ in 0..<180 { drops.update(deltaTime: 1.0/30) }
        var rainOnly = OceanFrame.empty; rainOnly.size = noFish.size
        rainOnly.precipitation = drops.frame(waterStrength: 0).precipitation
        let frozenRain = try renderer.renderRGBA(frame: rainOnly,width: 1600,height: 1000)
        let pausedRain = try renderer.renderRGBA(frame: rainOnly,width: 1600,height: 1000)
        precondition(frozenRain.contains { $0 != 0 } && frozenRain == pausedRain, "Particle-only rain renders and pauses exactly")
        drops.update(deltaTime: 1.0/30)
        rainOnly.precipitation = drops.frame(waterStrength: 0).precipitation
        let nextRain = try renderer.renderRGBA(frame: rainOnly,width: 1600,height: 1000)
        precondition(delta(frozenRain,nextRain)>0.00001, "Individual rain drops move between simulated frames")
        rainOnly.precipitation = []
        let dryEmpty = try renderer.renderRGBA(frame: rainOnly,width: 1600,height: 1000)
        precondition(dryEmpty.allSatisfy { $0 == 0 }, "Drained particle-only frame is transparent")
        print("PASS independent atmospheric rain particles, frozen snapshots and empty cleanup.")
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
        let primary = OceanSimulation(size: SIMD2(1512,982),seed: 42)
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
        // Fully occupied independent budgets: rain must not evict interaction,
        // and the completed GPU frame must remain within the same native budget.
        var storm = benchmark
        storm.ripples = (0..<96).map { i in
            Ripple(position: SIMD2(350+Float(i%12)*70,250+Float(i/12)*60),
                   age: 0.15+Float(i%12)*0.09,strength: i<72 ? 0.24 : (i%2 == 0 ? 1 : 0.34),
                   source: i<72 ? .rain : (i%2 == 0 ? .click : .motion),travel: i%2 == 0 ? .zero : SIMD2(60,20))
        }
        var stormTimings: [Double] = []
        for i in 0..<35 {
            storm.time += 1.0/30
            _ = try renderer.renderRGBA(frame: storm,width: 3024,height: 1964)
            if i>=5 { stormTimings.append(renderer.lastGPUSeconds*1000) }
        }
        stormTimings.sort()
        print("GPU 96 disturbances (72 rain + 24 click/motion), 1512x982 points / 3024x1964 pixels: median \(stormTimings[15]) ms; p95 \(stormTimings[28]) ms; max \(stormTimings.last!) ms.")
        precondition(stormTimings[28]<1000/30)
        if CommandLine.arguments.contains("--preview") {
            for motion in [false,true] {
                let name = motion ? "pond-cursor-preview" : "pond-preview"
                let url=output.appendingPathComponent("\(name).gif")
                let destination=CGImageDestinationCreateWithURL(url as CFURL,"com.compuserve.gif" as CFString,60,nil)!
                CGImageDestinationSetProperties(destination,[kCGImagePropertyGIFDictionary:[kCGImagePropertyGIFLoopCount:0]] as CFDictionary)
                let preview = OceanSimulation(size: SIMD2(1512,982),seed: 42)
                preview.weather = motion ? .sunny : .rainy
                for _ in 0..<240 { preview.update(deltaTime: 1.0/30) }
                for index in 0..<60 {
                    preview.update(deltaTime: 1.0/15)
                    if motion && index < 35 { preview.trackPointer(SIMD2(490+Float(index)*10,480+sin(Float(index)*0.12)*55)) }
                    let frame = preview.frame(waterStrength: 0.45)
                    if index % 15 == 0 || index == 59 {
                        try renderer.writePNG(frame: frame,width: 1512,height: 982,to: output.appendingPathComponent("\(name)-frame-\(index).png"))
                    }
                    let bytes=try renderer.renderRGBA(frame: frame,width: 1512,height: 982)
                    let data=Data(bytes) as CFData
                    let image=CGImage(width:1512,height:982,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:6048,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.premultipliedLast.rawValue),provider:CGDataProvider(data:data)!,decode:nil,shouldInterpolate:true,intent:.defaultIntent)!
                    CGImageDestinationAddImage(destination,image,[kCGImagePropertyGIFDictionary:[kCGImagePropertyGIFDelayTime:0.067]] as CFDictionary)
                }
                precondition(CGImageDestinationFinalize(destination))
            }
        }
        print("Outputs: \(output.path)")
    }
}
