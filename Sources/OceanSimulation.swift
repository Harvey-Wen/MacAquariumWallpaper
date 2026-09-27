import Foundation
import simd

final class OceanSimulation {
    private(set) var fish: [FishState]
    private(set) var ripples: [Ripple] = []
    private(set) var leaves: [PondLeaf] = []
    private(set) var time: Float = 0
    private(set) var size: SIMD2<Float>
    var weather: PondWeather = .sunny

    private var elapsedTime: Double = 0
    private var nextRainTime = 8.0 / 60
    private var nextLeafTime = 48.0 / 60
    private var nextLeafID = 0
    private var weatherAmount: Float = 0
    private var generator: SeededGenerator

    init(size: SIMD2<Float>, seed: UInt64 = 42) {
        self.size = Self.validSize(size)
        generator = SeededGenerator(seed: seed)
        fish = Self.makeFish(in: self.size, generator: &generator)
    }

    func update(deltaTime: Float) {
        guard deltaTime.isFinite, deltaTime > 0 else { return }
        let elapsed = min(deltaTime, 1)
        let count = max(1, Int(ceil(Double(elapsed) * 60 - 0.000_001)))
        let step = elapsed / Float(count)
        for _ in 0..<count { integrate(step: step) }
    }

    func click(at position: SIMD2<Float>) {
        guard PondGeometry.contains(position, size: size) else { return }
        addRipple(at: position, strength: 1, source: .click)
        addRipple(at: position, strength: 0.48, source: .click, age: -0.12)
        for index in fish.indices {
            let offset = fish[index].position - position
            let distance = simd_length(offset)
            let influence = max(0, 1 - distance / 160)
            guard influence > 0 else { continue }
            let away = unit(offset, fallback: perpendicular(fish[index].velocity))
            fish[index].panic = min(1, max(fish[index].panic, influence))
            fish[index].velocity = limited(fish[index].velocity + away * (78 * influence), to: 175)
        }
    }

    func resize(to newSize: SIMD2<Float>) {
        let next = Self.validSize(newSize)
        guard next != size else { return }
        let oldScale = max(size.x / PondGeometry.imageSize.x, size.y / PondGeometry.imageSize.y)
        let newScale = max(next.x / PondGeometry.imageSize.x, next.y / PondGeometry.imageSize.y)
        let ratio = newScale / oldScale
        for index in fish.indices {
            let uv = PondGeometry.uv(for: fish[index].position, size: size)
            fish[index].position = PondGeometry.point(for: uv, size: next)
            fish[index].velocity *= ratio
            fish[index].length *= ratio
        }
        for index in ripples.indices {
            ripples[index].position = PondGeometry.point(for: PondGeometry.uv(for: ripples[index].position, size: size), size: next)
        }
        for index in leaves.indices {
            leaves[index].position = PondGeometry.point(for: PondGeometry.uv(for: leaves[index].position, size: size), size: next)
            leaves[index].velocity *= ratio
            leaves[index].length *= ratio
        }
        size = next
        for index in fish.indices { contain(&fish[index]) }
    }

    func frame(waterStrength: Float) -> OceanFrame {
        OceanFrame(size: size, time: elapsedTime, fish: fish, ripples: ripples,
                   waterStrength: waterStrength, leaves: leaves, weatherAmount: weatherAmount)
    }

    private func integrate(step: Float) {
        elapsedTime += Double(step)
        time = Float(elapsedTime)
        weatherAmount += ((weather == .rainy ? 1 : 0) - weatherAmount) * min(1, step * 1.8)
        if weatherAmount < 0.0001 { weatherAmount = 0 }

        ageRipples(step: step)
        while elapsedTime + 0.000_001 >= nextRainTime {
            if weather == .rainy { spawnRain() }
            nextRainTime += 8.0 / 60
        }
        while elapsedTime + 0.000_001 >= nextLeafTime {
            spawnLeaf()
            nextLeafTime += 168.0 / 60
        }
        updateLeaves(step: step)
        updateFish(step: step)
    }

    private func updateFish(step: Float) {
        let old = fish
        for index in old.indices {
            var state = old[index]
            let forward = unit(state.velocity, fallback: SIMD2(1, 0))
            let desiredSpeed: Float = 39 + Float(state.id % 7) * 2.5 + state.panic * 65
            var acceleration = forward * ((desiredSpeed - simd_length(state.velocity)) * 1.7)
            let wander = sin(time * (0.43 + Float(state.id % 5) * 0.06) + Float(state.id) * 1.73)
            acceleration += perpendicular(forward) * wander * 13

            var separation = SIMD2<Float>.zero
            for other in old where other.id != state.id {
                let offset = state.position - other.position
                let distance = simd_length(offset)
                let spacing = (state.length + other.length) * 0.55
                if distance > 0.001 && distance < spacing {
                    separation += offset / distance * (1 - distance / spacing)
                }
            }
            acceleration += limited(separation * 38, to: 55)

            // Only a small subset of koi notices a nearby floating leaf.
            if state.id % 5 == 0 {
                for leaf in leaves where leaf.stage == .floating {
                    let offset = leaf.position - state.position
                    let distance = simd_length(offset)
                    if distance > 20 && distance < 115 {
                        acceleration += offset / distance * (1 - distance / 115) * 10
                    }
                }
            }

            let margin = state.length * 0.5 + 5
            let room = PondGeometry.signedDistance(at: state.position, size: size) - margin
            if room < 115 {
                let inward = PondGeometry.inwardNormal(at: state.position, size: size)
                let outwardSpeed = max(0, -simd_dot(state.velocity, inward))
                acceleration += inward * ((1 - max(0, room) / 115) * 100 + outwardSpeed * 2.4)
            }
            acceleration = limited(acceleration, to: 150)
            state.velocity = limited(state.velocity + acceleration * step, to: 175)
            state.position += state.velocity * step
            contain(&state)
            state.heading = atan2(state.velocity.y, state.velocity.x)
            if state.heading < 0 { state.heading += 2 * .pi }
            state.phase = (state.phase + step * (4.2 + simd_length(state.velocity) * 0.015))
                .truncatingRemainder(dividingBy: 2 * .pi)
            state.panic *= exp(-step / 1.0)
            if state.panic < 0.0001 { state.panic = 0 }
            fish[index] = state
        }
    }

    private func contain(_ state: inout FishState) {
        let margin = state.length * 0.5 + 0.5
        for _ in 0..<5 {
            let room = PondGeometry.signedDistance(at: state.position, size: size)
            if room >= margin { break }
            let inward = PondGeometry.inwardNormal(at: state.position, size: size)
            state.position += inward * (margin - room + 0.5)
            let outward = simd_dot(state.velocity, inward)
            if outward < 0 { state.velocity -= inward * outward * 1.4 }
        }
    }

    private func ageRipples(step: Float) {
        for index in ripples.indices { ripples[index].age += step }
        ripples.removeAll { $0.age > ($0.source == .rain ? 1.4 : 2.3) }
    }

    private func addRipple(at position: SIMD2<Float>, strength: Float, source: DisturbanceKind, age: Float = 0) {
        guard PondGeometry.contains(position, size: size) else { return }
        ripples.append(Ripple(position: position, age: age, strength: strength, source: source))
        if ripples.count > 24 { ripples.removeFirst(ripples.count - 24) }
    }

    private func spawnRain() {
        guard let point = randomWaterPoint(margin: 8) else { return }
        addRipple(at: point, strength: 0.19, source: .rain)
        for index in fish.indices {
            let offset = fish[index].position - point
            let distance = simd_length(offset)
            if distance < 70 {
                let influence = 1 - distance / 70
                fish[index].panic = max(fish[index].panic, min(0.28, influence * 0.16))
                fish[index].velocity += unit(offset, fallback: SIMD2(1, 0)) * influence * 6
            }
        }
    }

    private func spawnLeaf() {
        // Tree canopy hangs over the north bank at these source-image positions.
        let anchors: [SIMD2<Float>] = [SIMD2(390, 195), SIMD2(550, 200), SIMD2(755, 190)]
        let anchor = anchors[nextLeafID % anchors.count]
        let imagePoint = anchor + SIMD2(generator.float(in: -25...25), generator.float(in: -10...20))
        let uv = imagePoint / PondGeometry.imageSize
        let point = PondGeometry.point(for: uv, size: size)
        guard PondGeometry.contains(point, size: size, margin: 12) else { return }
        let scale = max(size.x / 1600, size.y / 1000)
        leaves.append(PondLeaf(id: nextLeafID, position: point, velocity: SIMD2(generator.float(in: -5...5), -generator.float(in: 5...10)) * scale,
                               age: 0, rotation: generator.float(in: 0...(2 * .pi)), length: generator.float(in: 12...19) * scale,
                               stage: .falling, fallDuration: generator.float(in: 0.7...1.15), opacity: 1))
        nextLeafID += 1
        if leaves.count > 12 { leaves.removeFirst(leaves.count - 12) }
    }

    private func updateLeaves(step: Float) {
        for index in leaves.indices {
            var leaf = leaves[index]
            leaf.age += step
            if leaf.stage == .falling {
                leaf.rotation = (leaf.rotation + step * 0.33).truncatingRemainder(dividingBy: 2 * .pi)
                leaf.position += leaf.velocity * step
                if leaf.age >= leaf.fallDuration {
                    leaf.stage = .floating
                    leaf.velocity *= 0.25
                    addRipple(at: leaf.position, strength: 0.35, source: .leaf)
                }
            } else if leaf.stage == .floating {
                var wave = SIMD2<Float>.zero
                for ripple in ripples where ripple.age >= 0 {
                    let offset = leaf.position - ripple.position
                    let distance = simd_length(offset)
                    let radius = ripple.age * 95
                    if distance > 0.001 && abs(distance - radius) < 70 {
                        let falloff = 1 - abs(distance - radius) / 70
                        let amplitude = ripple.strength * falloff * 13
                        wave += (offset / distance) * amplitude
                    }
                }
                let acrossLeaf = SIMD2(-sin(leaf.rotation), cos(leaf.rotation))
                let waveTurn = max(-0.24, min(0.24, simd_dot(acrossLeaf, wave) * 0.04))
                leaf.rotation = (leaf.rotation + step * (0.33 + waveTurn)).truncatingRemainder(dividingBy: 2 * .pi)
                let drift = SIMD2(sin(time * 0.53 + Float(leaf.id)), cos(time * 0.41 + Float(leaf.id))) * 1.8
                leaf.velocity = limited(leaf.velocity * exp(-step * 0.9) + (wave + drift) * step, to: 16)
                let candidate = leaf.position + leaf.velocity * step
                if PondGeometry.contains(candidate, size: size, margin: leaf.length * 0.4) {
                    leaf.position = candidate
                } else {
                    leaf.stage = .grounded
                    leaf.velocity = .zero
                }
            }
            leaf.opacity = min(1, max(0, (16 - leaf.age) / 2))
            leaves[index] = leaf
        }
        leaves.removeAll { $0.age >= 16 }
    }

    private func randomWaterPoint(margin: Float) -> SIMD2<Float>? {
        for _ in 0..<24 {
            let uv = SIMD2(generator.float(in: 0.12...0.92), generator.float(in: 0.16...0.76))
            let point = PondGeometry.point(for: uv, size: size)
            if PondGeometry.contains(point, size: size, margin: margin) { return point }
        }
        return nil
    }

    private static func makeFish(in size: SIMD2<Float>, generator: inout SeededGenerator) -> [FishState] {
        let scale = max(size.x / 1600, size.y / 1000)
        var result: [FishState] = []
        result.reserveCapacity(30)
        for id in 0..<30 {
            let length = generator.float(in: 48...76) * scale
            var position = PondGeometry.point(for: SIMD2(0.5, 0.5), size: size)
            for _ in 0..<100 {
                let uv = SIMD2(generator.float(in: 0.19...0.87), generator.float(in: 0.23...0.72))
                let candidate = PondGeometry.point(for: uv, size: size)
                if PondGeometry.contains(candidate, size: size, margin: length * 0.5 + 20) {
                    position = candidate
                    break
                }
            }
            let angle = generator.float(in: 0...(2 * .pi))
            let direction = SIMD2(cos(angle), sin(angle))
            result.append(FishState(id: id, species: .koi, position: position, velocity: direction * generator.float(in: 34...52) * scale,
                                    heading: angle, length: length, depth: generator.float(in: 0.25...0.8),
                                    phase: generator.float(in: 0...(2 * .pi)), panic: 0))
        }
        return result
    }

    private static func validSize(_ size: SIMD2<Float>) -> SIMD2<Float> {
        SIMD2(max(1, size.x.isFinite ? size.x : 1), max(1, size.y.isFinite ? size.y : 1))
    }
}

private struct SeededGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        return value ^ (value >> 31)
    }
    mutating func float(in range: ClosedRange<Float>) -> Float {
        range.lowerBound + (range.upperBound - range.lowerBound) * Float(next() >> 40) / Float(1 << 24)
    }
}

private func unit(_ value: SIMD2<Float>, fallback: SIMD2<Float>) -> SIMD2<Float> {
    let length = simd_length(value)
    if length.isFinite && length > 0.0001 { return value / length }
    let fallbackLength = simd_length(fallback)
    return fallbackLength > 0.0001 ? fallback / fallbackLength : SIMD2(1, 0)
}

private func limited(_ value: SIMD2<Float>, to limit: Float) -> SIMD2<Float> {
    let length = simd_length(value)
    return length.isFinite && length > limit ? value * (limit / length) : value
}

private func perpendicular(_ value: SIMD2<Float>) -> SIMD2<Float> { SIMD2(-value.y, value.x) }
