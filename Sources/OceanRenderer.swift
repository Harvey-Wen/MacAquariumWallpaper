import AppKit
import MetalKit
import QuartzCore
import simd

enum OceanRenderError: Error, LocalizedError {
    case unavailable(String)
    var errorDescription: String? {
        switch self { case .unavailable(let message): return message }
    }
}

private struct FishUniforms {
    var viewport: SIMD4<Float>
    var placement: SIMD4<Float>
    var motion: SIMD4<Float>
    var kind: SIMD4<Float>
    var appearance: SIMD4<Float>
}

private struct EffectUniforms {
    var viewport: SIMD4<Float>
    var placement: SIMD4<Float>
    var style: SIMD4<Float>
    var travel: SIMD4<Float> = .zero
    var atmosphere: SIMD4<Float> = .zero
}

final class OceanRenderer: NSObject, MTKViewDelegate {
    var frame = OceanFrame.empty
    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let fishPipeline: MTLRenderPipelineState
    private let effectPipeline: MTLRenderPipelineState
    private let wavePipeline: MTLRenderPipelineState
    private let compositePipeline: MTLRenderPipelineState
    private var targets: (scene: MTLTexture, msaa: MTLTexture, depth: MTLTexture, waves: MTLTexture, output: MTLTexture)?
    private let fishDepth: MTLDepthStencilState
    private let effectDepth: MTLDepthStencilState
    private var meshes: [FishSpecies: (MTLBuffer, Int)] = [:]
    private let sampleCount: Int
    private let environment: MTLTexture
    private let waterDistance: MTLTexture
    private let fallbackDrawing: MTLTexture
    private var drawings: [UUID: MTLTexture] = [:]
    private(set) var lastGPUSeconds: Double = 0

    init(view: MTKView, shaderURL: URL) throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw OceanRenderError.unavailable("这台 Mac 无法初始化 Metal 渲染。")
        }
        self.device = device
        self.queue = queue
        let samples = device.supportsTextureSampleCount(4) ? 4 : 1
        let environmentURL = shaderURL.deletingLastPathComponent().appendingPathComponent("PondEnvironment.png")
        do {
            environment = try MTKTextureLoader(device: device).newTexture(URL: environmentURL, options: [.SRGB: false, .origin: MTKTextureLoader.Origin.topLeft.rawValue])
        } catch { throw OceanRenderError.unavailable("无法加载池塘环境图 \(environmentURL.path)：\(error.localizedDescription)") }
        let maskDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r32Float, width: 800, height: 500, mipmapped: false)
        maskDescriptor.usage = .shaderRead
        guard let mask = device.makeTexture(descriptor: maskDescriptor) else { throw OceanRenderError.unavailable("无法创建共享岸线距离纹理。") }
        var distances = [Float](repeating: 0, count: 800 * 500)
        for y in 0..<500 { for x in 0..<800 {
            distances[y * 800 + x] = PondGeometry.signedDistance(at: SIMD2((Float(x) + 0.5) * 2, 1000 - (Float(y) + 0.5) * 2), size: PondGeometry.imageSize)
        }}
        distances.withUnsafeBytes { mask.replace(region: MTLRegionMake2D(0, 0, 800, 500), mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: 800 * 4) }
        waterDistance = mask
        let fallbackDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false)
        fallbackDescriptor.usage = .shaderRead
        guard let fallback = device.makeTexture(descriptor: fallbackDescriptor) else {
            throw OceanRenderError.unavailable("无法创建鱼类默认纹理。")
        }
        var white: [UInt8] = [255, 255, 255, 255]
        fallback.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: &white, bytesPerRow: 4)
        fallbackDrawing = fallback
        sampleCount = samples
        let source = try String(contentsOf: shaderURL, encoding: .utf8)
        let library = try device.makeLibrary(source: source, options: nil)
        func pipeline(_ vertex: String, _ fragment: String) throws -> MTLRenderPipelineState {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: vertex)
            descriptor.fragmentFunction = library.makeFunction(name: fragment)
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            descriptor.depthAttachmentPixelFormat = .depth32Float
            descriptor.rasterSampleCount = samples
            let attachment = descriptor.colorAttachments[0]!
            attachment.isBlendingEnabled = true
            attachment.sourceRGBBlendFactor = .one
            attachment.sourceAlphaBlendFactor = .one
            attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
            attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            return try device.makeRenderPipelineState(descriptor: descriptor)
        }
        fishPipeline = try pipeline("fishVertex", "fishFragment")
        effectPipeline = try pipeline("effectVertex", "effectFragment")
        compositePipeline = try pipeline("effectVertex", "waterFragment")
        let waveDescriptor = MTLRenderPipelineDescriptor()
        waveDescriptor.vertexFunction = library.makeFunction(name: "waveVertex")
        waveDescriptor.fragmentFunction = library.makeFunction(name: "waveFragment")
        waveDescriptor.colorAttachments[0].pixelFormat = .rgba16Float
        let blend = waveDescriptor.colorAttachments[0]!
        blend.isBlendingEnabled = true
        blend.sourceRGBBlendFactor = .one; blend.destinationRGBBlendFactor = .one
        blend.sourceAlphaBlendFactor = .one; blend.destinationAlphaBlendFactor = .one
        wavePipeline = try device.makeRenderPipelineState(descriptor: waveDescriptor)
        let depth = MTLDepthStencilDescriptor()
        depth.depthCompareFunction = .lessEqual
        depth.isDepthWriteEnabled = true
        guard let fishDepth = device.makeDepthStencilState(descriptor: depth) else {
            throw OceanRenderError.unavailable("无法创建鱼群深度缓冲。")
        }
        self.fishDepth = fishDepth
        depth.depthCompareFunction = .always
        depth.isDepthWriteEnabled = false
        guard let effectDepth = device.makeDepthStencilState(descriptor: depth) else {
            throw OceanRenderError.unavailable("无法创建水纹深度状态。")
        }
        self.effectDepth = effectDepth
        super.init()
        for species in FishSpecies.allCases {
            let mesh = FishMesh(species: species)
            guard let buffer = device.makeBuffer(bytes: mesh.vertices, length: mesh.vertices.count * MemoryLayout<FishVertex>.stride, options: .storageModeShared) else {
                throw OceanRenderError.unavailable("无法创建鱼类网格。")
            }
            meshes[species] = (buffer, mesh.vertices.count)
        }
        view.device = device
        view.colorPixelFormat = .bgra8Unorm
        view.depthStencilPixelFormat = .depth32Float
        view.sampleCount = sampleCount
        view.clearColor = MTLClearColorMake(0, 0, 0, 0)
        view.clearDepth = 1
        view.framebufferOnly = true
        view.wantsLayer = true
        view.layer?.isOpaque = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        if let metalLayer = view.layer as? CAMetalLayer {
            metalLayer.isOpaque = true
            metalLayer.backgroundColor = NSColor.clear.cgColor
        }
        view.delegate = self
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func registerDrawing(_ drawing: FishDrawing) throws {
        guard let image = drawing.rasterizedImage(width: 512, height: 256) else {
            throw OceanRenderError.unavailable("无法生成鱼类绘画纹理。")
        }
        drawings[drawing.id] = try MTKTextureLoader(device: device).newTexture(
            cgImage: image, options: [.SRGB: false, .origin: MTKTextureLoader.Origin.topLeft.rawValue])
    }

    func removeDrawing(id: UUID) { drawings.removeValue(forKey: id) }

    func fishPreview(_ fish: FishState) throws -> NSImage {
        var sample = fish
        sample.position = SIMD2(128, 64)
        sample.heading = 0
        sample.length = 180
        sample.depth = 0.15
        sample.phase = 0
        sample.panic = 0
        let frame = OceanFrame(size: SIMD2(256, 128), time: 0, fish: [sample], ripples: [], waterStrength: 0)
        let bytes = try renderRGBA(frame: frame, width: 256, height: 128, includeEnvironment: false)
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 256, pixelsHigh: 128,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 256 * 4, bitsPerPixel: 32),
            let pixels = bitmap.bitmapData else { throw OceanRenderError.unavailable("无法生成鱼的预览。") }
        bytes.withUnsafeBytes { pixels.update(from: $0.baseAddress!.assumingMemoryBound(to: UInt8.self), count: bytes.count) }
        let image = NSImage(size: NSSize(width: 128, height: 64))
        image.addRepresentation(bitmap)
        return image
    }

    func draw(in view: MTKView) {
        guard let pass = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let command = queue.makeCommandBuffer() else { return }
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        encode(frame, pass: pass, command: command)
        command.addCompletedHandler { [weak self] completed in self?.lastGPUSeconds = completed.gpuEndTime - completed.gpuStartTime }
        command.present(drawable)
        command.commit()
    }

    // Reuse render targets across display and export frames; only geometry changes allocate.
    private func prepareTargets(width: Int, height: Int) -> Bool {
        if let targets, targets.scene.width == width && targets.scene.height == height { return true }
        func texture(_ format: MTLPixelFormat, _ w: Int, _ h: Int, samples: Int = 1, shared: Bool = false) -> MTLTexture? {
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: w, height: h, mipmapped: false)
            d.usage = [.renderTarget, .shaderRead]
            d.storageMode = shared ? .shared : .private
            d.sampleCount = samples
            d.textureType = samples > 1 ? .type2DMultisample : .type2D
            return device.makeTexture(descriptor: d)
        }
        guard let scene = texture(.bgra8Unorm, width, height),
              let msaa = texture(.bgra8Unorm, width, height, samples: sampleCount),
              let depth = texture(.depth32Float, width, height, samples: sampleCount),
              let waves = texture(.rgba16Float, max(1, width / 2), max(1, height / 2)),
              let output = texture(.bgra8Unorm, width, height, shared: true) else { return false }
        targets = (scene, msaa, depth, waves, output)
        return true
    }

    private func encode(_ frame: OceanFrame, pass: MTLRenderPassDescriptor, command: MTLCommandBuffer,
                        includeEnvironment: Bool = true) {
        guard let destination = pass.colorAttachments[0].texture,
              prepareTargets(width: destination.width, height: destination.height), let targets else { return }
        guard frame.waterStrength > 0 || frame.weatherAmount > 0 || simd_length_squared(frame.atmosphere) > 0 || !frame.fish.isEmpty || !frame.ripples.isEmpty || !frame.leaves.isEmpty else {
            command.makeRenderCommandEncoder(descriptor: pass)?.endEncoding(); return
        }
        let scenePass = MTLRenderPassDescriptor()
        scenePass.colorAttachments[0].texture = sampleCount > 1 ? targets.msaa : targets.scene
        scenePass.colorAttachments[0].resolveTexture = sampleCount > 1 ? targets.scene : nil
        scenePass.colorAttachments[0].loadAction = .clear
        scenePass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        scenePass.colorAttachments[0].storeAction = sampleCount > 1 ? .multisampleResolve : .store
        scenePass.depthAttachment.texture = targets.depth
        scenePass.depthAttachment.loadAction = .clear
        scenePass.depthAttachment.clearDepth = 1
        guard var encoder = command.makeRenderCommandEncoder(descriptor: scenePass) else { return }
        func phase(_ frequency: Double) -> Float { Float((frame.time * frequency).truncatingRemainder(dividingBy: 2 * .pi)) }
        let viewport = SIMD4<Float>(max(frame.size.x, 1), max(frame.size.y, 1), phase(0.21), phase(0.17))
        let atmosphere = SIMD4<Float>(frame.atmosphere.x, frame.atmosphere.y, frame.atmosphere.z, phase(0.025))
        encoder.setCullMode(.none)
        encoder.setFragmentTexture(environment, index: 0)
        encoder.setFragmentTexture(waterDistance, index: 1)
        func effect(at position: SIMD2<Float>, radius: Float, angle: Float = 0, type: Float, age: Float = 0, strength: Float = 1, seed: Float = 0) {
            encoder.setRenderPipelineState(effectPipeline)
            encoder.setDepthStencilState(effectDepth)
            var uniforms = EffectUniforms(viewport: viewport, placement: SIMD4(position.x, position.y, radius, angle), style: SIMD4(type, age, strength, seed), atmosphere: atmosphere)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<EffectUniforms>.stride, index: 0)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<EffectUniforms>.stride, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        }
        if includeEnvironment {
            effect(at: frame.size * 0.5, radius: 1, type: 0, strength: frame.waterStrength, seed: frame.weatherAmount)
        }
        for fish in frame.fish.sorted(by: { $0.depth > $1.depth }) {
            guard let (buffer, count) = meshes[fish.species] else { continue }
            let drawing = fish.customAppearanceID.flatMap { drawings[$0] }
            for shadow in [true, false] {
                encoder.setRenderPipelineState(fishPipeline)
                encoder.setDepthStencilState(shadow ? effectDepth : fishDepth)
                var uniforms = FishUniforms(viewport: viewport,
                    placement: SIMD4(fish.position.x, fish.position.y, fish.length, min(max(fish.depth, 0), 1)),
                    motion: SIMD4(fish.heading, fish.phase, shadow ? 1 : 0, fish.panic),
                    kind: SIMD4(Float(fish.id), phase(0.21), phase(0.17), frame.waterStrength),
                    appearance: SIMD4(drawing == nil ? 0 : 1, 0, 0, 0))
                encoder.setVertexBuffer(buffer, offset: 0, index: 0)
                encoder.setVertexBytes(&uniforms, length: MemoryLayout<FishUniforms>.stride, index: 1)
                encoder.setFragmentBytes(&uniforms, length: MemoryLayout<FishUniforms>.stride, index: 0)
                encoder.setFragmentTexture(drawing ?? fallbackDrawing, index: 4)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: count)
            }
        }
        effect(at: frame.size * 0.5, radius: 1, type: 1, strength: frame.waterStrength)
        encoder.endEncoding()
        let wavePass = MTLRenderPassDescriptor()
        wavePass.colorAttachments[0].texture = targets.waves
        wavePass.colorAttachments[0].loadAction = .clear
        wavePass.colorAttachments[0].storeAction = .store
        guard let waveEncoder = command.makeRenderCommandEncoder(descriptor: wavePass) else { return }
        waveEncoder.setRenderPipelineState(wavePipeline)
        for ripple in frame.ripples.prefix(96) where ripple.age >= 0 && ripple.age < (ripple.source == .rain ? 1.4 : 2.3) {
            let radius = ripple.source == .motion ? simd_length(ripple.travel) + 70 : ripple.age * (ripple.source == .rain ? 45 : 65) + 28
            var u = EffectUniforms(viewport: viewport, placement: SIMD4(ripple.position.x, ripple.position.y, radius, 0),
                style: SIMD4(Float(ripple.source.rawValue), ripple.age, ripple.strength, 0),
                travel: SIMD4(ripple.travel.x, ripple.travel.y, 0, 0))
            waveEncoder.setVertexBytes(&u, length: MemoryLayout<EffectUniforms>.stride, index: 0)
            waveEncoder.setFragmentBytes(&u, length: MemoryLayout<EffectUniforms>.stride, index: 0)
            waveEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        }
        waveEncoder.endEncoding()
        guard let finalEncoder = command.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder = finalEncoder
        encoder.setFragmentTexture(environment, index: 0)
        encoder.setFragmentTexture(waterDistance, index: 1)
        encoder.setFragmentTexture(targets.scene, index: 2)
        encoder.setFragmentTexture(targets.waves, index: 3)
        encoder.setRenderPipelineState(compositePipeline)
        encoder.setDepthStencilState(effectDepth)
        var composite = EffectUniforms(viewport: viewport, placement: .zero, style: SIMD4(5, 0, 1, 0), atmosphere: atmosphere)
        encoder.setVertexBytes(&composite, length: MemoryLayout<EffectUniforms>.stride, index: 0)
        encoder.setFragmentBytes(&composite, length: MemoryLayout<EffectUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        for leaf in frame.leaves {
            let progress = min(1, max(0, leaf.age / max(leaf.fallDuration, 0.001)))
            let eased = progress * progress * (3 - 2 * progress)
            let scale: Float = leaf.stage == .falling ? 1 + 0.35 * (1 - eased) : 1
            effect(at: leaf.position, radius: leaf.length * scale, angle: leaf.rotation, type: 3, age: leaf.opacity, strength: Float(leaf.stage.rawValue), seed: Float(leaf.id))
        }
        if frame.weatherAmount > 0 {
            // Reduce Double time before Float conversion; frozen frames also freeze rain.
            effect(at: frame.size * 0.5, radius: 1, type: 4,
                   age: Float(frame.time.truncatingRemainder(dividingBy: 8)), strength: frame.weatherAmount)
        }
        if frame.atmosphere.x > 0 {
            effect(at: frame.size * 0.5, radius: 1, type: 6,
                   age: Float(frame.time.truncatingRemainder(dividingBy: 256)), strength: frame.atmosphere.x)
        }
        encoder.endEncoding()
    }

    /// Deterministic offscreen render; rows run top-to-bottom, bytes are premultiplied RGBA8.
    func renderRGBA(frame: OceanFrame, width: Int, height: Int, includeEnvironment: Bool = true) throws -> [UInt8] {
        guard width > 0, height > 0 else { throw OceanRenderError.unavailable("导出尺寸必须大于零。") }
        guard prepareTargets(width: width, height: height), let targets, let command = queue.makeCommandBuffer() else {
            throw OceanRenderError.unavailable("无法创建离屏画布。")
        }
        let output = targets.output, multisample = targets.msaa, depth = targets.depth
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = sampleCount > 1 ? multisample : output
        pass.colorAttachments[0].resolveTexture = sampleCount > 1 ? output : nil
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = sampleCount > 1 ? .multisampleResolve : .store
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        pass.depthAttachment.texture = depth
        pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.storeAction = .dontCare
        pass.depthAttachment.clearDepth = 1
        encode(frame, pass: pass, command: command, includeEnvironment: includeEnvironment)
        command.commit()
        command.waitUntilCompleted()
        if let error = command.error { throw error }
        lastGPUSeconds = command.gpuEndTime - command.gpuStartTime
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        output.getBytes(&bytes, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        for index in stride(from: 0, to: bytes.count, by: 4) { bytes.swapAt(index, index + 2) }
        return bytes
    }

    /// Export a transparent PNG, or an opaque sample composited over an RGB color (0...1).
    func writePNG(frame: OceanFrame, width: Int, height: Int, to url: URL,
                  background: SIMD3<Float>? = nil) throws {
        var bytes = try renderRGBA(frame: frame, width: width, height: height)
        for index in stride(from: 0, to: bytes.count, by: 4) {
            let alpha = Float(bytes[index + 3]) / 255
            for channel in 0..<3 {
                let value = Float(bytes[index + channel]) / 255
                if let background {
                    bytes[index + channel] = UInt8(min(255, max(0, (value + background[channel] * (1 - alpha)) * 255)).rounded())
                } else {
                    bytes[index + channel] = alpha > 0 ? UInt8(min(255, (value / alpha * 255)).rounded()) : 0
                }
            }
            if background != nil { bytes[index + 3] = 255 }
        }
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bitmapFormat: .alphaNonpremultiplied, bytesPerRow: width * 4, bitsPerPixel: 32), let pixels = bitmap.bitmapData else {
            throw OceanRenderError.unavailable("无法创建 PNG 图像。")
        }
        bytes.withUnsafeBytes { pixels.update(from: $0.baseAddress!.assumingMemoryBound(to: UInt8.self), count: bytes.count) }
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw OceanRenderError.unavailable("PNG 编码失败。") }
        try png.write(to: url)
    }
}
