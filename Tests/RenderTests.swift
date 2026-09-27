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
        var sunny = simulation.frame(waterStrength: 0.45)
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
        precondition(delta(plain,ripplePixels)>0)
        simulation.weather = .rainy
        for _ in 0..<240 { simulation.update(deltaTime: 1.0/30) }
        let rainy = simulation.frame(waterStrength: 0.45)
        try renderer.writePNG(frame: rainy,width: 1600,height: 1000,to: output.appendingPathComponent("pond-rainy.png"))
        var wet = noFish; wet.weatherAmount = 1
        let wetPixels = try renderer.renderRGBA(frame: wet,width: 1600,height: 1000)
        precondition(delta(plain,wetPixels)>0.005)
        // Same leaf over a fish: surface pixels must cover the underwater animal.
        var layers = noFish; layers.waterStrength = 0.45
        let center = SIMD2<Float>(800,500)
        layers.leaves = [PondLeaf(id: 1,position: center,velocity: .zero,age: 1,rotation: 0,length: 60,stage: .floating,fallDuration: 1,opacity: 1)]
        let leafOnly = try renderer.renderRGBA(frame: layers,width: 1600,height: 1000)
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
        var timings: [Double]=[]
        for i in 0..<35 {
            sunny.time += 1.0/30
            _ = try renderer.renderRGBA(frame: sunny,width: 3024,height: 1964)
            if i>=5 { timings.append(renderer.lastGPUSeconds*1000) }
        }
        timings.sort()
        print("PASS opacity, empty, mesh, fish difference, \(landChecked) unchanged land samples, weather, surface leaf ordering, seven-day continuity and 3 aspect ratios.")
        print("GPU \(view.device!.name) 3024x1964: median \(timings[15]) ms; p95 \(timings[28]) ms; max \(timings.last!) ms (30 measured frames).")
        precondition(timings[28]<1000/30)
        if CommandLine.arguments.contains("--preview") {
            let url=output.appendingPathComponent("pond-preview.gif")
            let destination=CGImageDestinationCreateWithURL(url as CFURL,"com.compuserve.gif" as CFString,60,nil)!
            CGImageDestinationSetProperties(destination,[kCGImagePropertyGIFDictionary:[kCGImagePropertyGIFLoopCount:0]] as CFDictionary)
            for _ in 0..<60 {
                simulation.update(deltaTime: 1.0/15)
                let bytes=try renderer.renderRGBA(frame: simulation.frame(waterStrength: 0.45),width: 800,height: 500)
                let data=Data(bytes) as CFData
                let image=CGImage(width:800,height:500,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:3200,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.premultipliedLast.rawValue),provider:CGDataProvider(data:data)!,decode:nil,shouldInterpolate:true,intent:.defaultIntent)!
                CGImageDestinationAddImage(destination,image,[kCGImagePropertyGIFDictionary:[kCGImagePropertyGIFDelayTime:0.067]] as CFDictionary)
            }
            precondition(CGImageDestinationFinalize(destination))
        }
        print("Outputs: \(output.path)")
    }
}
