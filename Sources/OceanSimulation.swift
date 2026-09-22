import Foundation
import simd

final class OceanSimulation {
    private(set) var fish: [FishState]
    private(set) var ripples: [Ripple] = []
    private(set) var currents: [CurrentStroke] = []
    private(set) var time: Float = 0
    private(set) var size: SIMD2<Float>

    private var pointerPosition: SIMD2<Float>?
    private var dragPosition: SIMD2<Float>?
    private var elapsedTime: Double = 0

    init(size: SIMD2<Float>, seed: UInt64 = 42) {
        self.size = Self.validSize(size)
        var generator = SeededGenerator(seed: seed)
        fish = Self.makeFish(in: self.size, generator: &generator)
    }

    func update(deltaTime: Float) {
        guard deltaTime.isFinite, deltaTime > 0 else { return }
        let elapsed = min(deltaTime, 1)
        let stepCount = max(1, Int(ceil(Double(elapsed) * 60 - 0.000_001)))
        let step = elapsed / Float(stepCount)
        for _ in 0..<stepCount {
            integrate(step: step)
        }
    }

    func pointerMoved(to position: SIMD2<Float>?) {
        pointerPosition = position.map { clamped($0) }
    }

    func click(at position: SIMD2<Float>) {
        let point = clamped(position)
        ripples.append(Ripple(position: point, age: 0, strength: 1))
        ripples.append(Ripple(position: point, age: -0.13, strength: 0.55))
        if ripples.count > 16 {
            ripples.removeFirst(ripples.count - 16)
        }

        let radius = max(220, min(size.x, size.y) * 0.38)
        for index in fish.indices {
            let offset = fish[index].position - point
            let distance = simd_length(offset)
            let falloff = max(0, 1 - distance / radius)
            guard falloff > 0 else { continue }
            let away = normalized(offset, fallback: perpendicular(to: fish[index].velocity))
            fish[index].panic = min(1, max(fish[index].panic, falloff))
            fish[index].velocity += away * (105 * falloff)
            constrainVelocity(&fish[index])
        }
    }

    func drag(to position: SIMD2<Float>) {
        let point = clamped(position)
        pointerPosition = point
        guard let previous = dragPosition else {
            dragPosition = point
            return
        }

        let displacement = point - previous
        let distance = simd_length(displacement)
        guard distance > 0.5 else { return }
        let direction = displacement / distance
        let sampleCount = max(1, min(8, Int(ceil(distance / 28))))
        for sample in 1...sampleCount {
            let fraction = Float(sample) / Float(sampleCount)
            let samplePosition = previous + displacement * fraction
            currents.append(CurrentStroke(position: samplePosition, velocity: direction * min(260, 80 + distance * 2), age: 0))
        }
        if currents.count > 48 {
            currents.removeFirst(currents.count - 48)
        }

        disturbFish(along: previous, to: point, direction: direction)
        dragPosition = point
    }

    func endDrag() {
        dragPosition = nil
    }

    func resize(to newSize: SIMD2<Float>) {
        let nextSize = Self.validSize(newSize)
        guard nextSize != size else { return }
        let scale = nextSize / size
        for index in fish.indices {
            fish[index].position *= scale
            fish[index].velocity *= scale
        }
        for index in ripples.indices {
            ripples[index].position *= scale
        }
        for index in currents.indices {
            currents[index].position *= scale
            currents[index].velocity *= scale
        }
        pointerPosition = pointerPosition.map { $0 * scale }
        dragPosition = nil
        size = nextSize
    }

    func frame(waterStrength: Float) -> OceanFrame {
        OceanFrame(
            size: size,
            time: time,
            fish: fish,
            ripples: ripples,
            currents: currents,
            waterStrength: waterStrength
        )
    }

    private func integrate(step: Float) {
        elapsedTime += Double(step)
        time = Float(elapsedTime)
        updateEffects(step: step)

        let previous = fish
        var next = previous
        for index in previous.indices {
            var state = previous[index]
            let parameters = Self.parameters(for: state.species)
            let normalSpeed = parameters.speed * (0.88 + 0.18 * sin(state.phase))
            let targetSpeed = normalSpeed * (1 + 1.55 * state.panic)
            let forward = normalized(state.velocity, fallback: SIMD2(1, 0))
            let side = perpendicular(to: forward)

            var acceleration = forward * ((targetSpeed - simd_length(state.velocity)) * 1.9)
            let wander = Float(sin(elapsedTime * Double(parameters.wanderRate) + Double(state.phase)))
            acceleration += side * wander * parameters.wanderForce
            acceleration += schoolingForce(for: index, states: previous)
            acceleration += interactionForce(for: state)

            let accelerationLimit = parameters.maxAcceleration * (1 + state.panic)
            acceleration = limited(acceleration, to: accelerationLimit * 0.58)
            acceleration += edgeForce(for: state, maximumAcceleration: accelerationLimit)
            acceleration = limited(acceleration, to: accelerationLimit)
            state.velocity += acceleration * step

            let speed = simd_length(state.velocity)
            let maximumSpeed = parameters.speed * (1.28 + 1.7 * state.panic)
            let minimumSpeed = parameters.speed * 0.4
            if speed > maximumSpeed {
                state.velocity *= maximumSpeed / speed
            } else if speed < minimumSpeed {
                state.velocity = normalized(state.velocity, fallback: forward) * minimumSpeed
            }

            state.position += state.velocity * step
            contain(&state)
            let targetHeading = atan2(state.velocity.y, state.velocity.x)
            state.heading = approachedAngle(state.heading, targetHeading, maximumChange: parameters.turnRate * step)
                .truncatingRemainder(dividingBy: 2 * .pi)
            state.phase = (state.phase + step * (parameters.tailRate + speed * 0.012))
                .truncatingRemainder(dividingBy: 2 * .pi)
            state.panic *= exp(-step / 1.35)
            if state.panic < 0.0001 { state.panic = 0 }
            next[index] = state
        }
        fish = next
    }

    private func updateEffects(step: Float) {
        for index in ripples.indices {
            ripples[index].age += step
        }
        ripples.removeAll { $0.age > 2.6 }

        for index in currents.indices {
            currents[index].age += step
            currents[index].position += currents[index].velocity * step * 0.06
        }
        currents.removeAll { $0.age > 2.4 }
    }

    private func schoolingForce(for index: Int, states: [FishState]) -> SIMD2<Float> {
        let state = states[index]
        let schooling: (radius: Float, cohesion: Float, alignment: Float)
        switch state.species {
        case .silver:
            schooling = (max(165, state.length * 2.35), 7, 15)
        case .butterfly:
            schooling = (max(135, state.length * 1.35), 2, 4)
        case .clown, .tang, .manta:
            schooling = (0, 0, 0)
        }
        var center = SIMD2<Float>.zero
        var velocity = SIMD2<Float>.zero
        var neighborCount: Float = 0
        var separation = SIMD2<Float>.zero

        for otherIndex in states.indices where otherIndex != index {
            let other = states[otherIndex]
            let offset = state.position - other.position
            let distanceSquared = simd_length_squared(offset)
            guard distanceSquared > 0.001 else { continue }
            let distance = sqrt(distanceSquared)
            let sameSilverSchool = state.species == .silver && other.species == .silver
            let separationScale: Float = sameSilverSchool ? 0.42 : 0.55
            let separationDistance = max(44, (state.length + other.length) * separationScale)
            if distance < separationDistance {
                let strength = 1 - distance / separationDistance
                separation += (offset / distance) * strength
            }
            if other.species == state.species && distance < schooling.radius {
                center += other.position
                velocity += normalized(other.velocity, fallback: SIMD2(1, 0))
                neighborCount += 1
            }
        }

        let separationStrength: Float = state.species == .silver ? 118 : 158
        var result = separation * separationStrength
        if neighborCount > 0 {
            center /= neighborCount
            velocity /= neighborCount
            let cohesion = normalized(center - state.position, fallback: .zero)
            let alignment = normalized(velocity, fallback: .zero)
            result += cohesion * schooling.cohesion + alignment * schooling.alignment
        }
        return result
    }

    private func edgeForce(for state: FishState, maximumAcceleration: Float) -> SIMD2<Float> {
        let bodyInset = min(min(size.x, size.y) * 0.24, max(16, state.length * 0.48))
        var force = SIMD2<Float>.zero
        force.x = axisEdgeForce(position: state.position.x, velocity: state.velocity.x, extent: size.x, bodyInset: bodyInset, maximumAcceleration: maximumAcceleration)
        force.y = axisEdgeForce(position: state.position.y, velocity: state.velocity.y, extent: size.y, bodyInset: bodyInset, maximumAcceleration: maximumAcceleration)
        return force
    }

    private func axisEdgeForce(
        position: Float,
        velocity: Float,
        extent: Float,
        bodyInset: Float,
        maximumAcceleration: Float
    ) -> Float {
        let lowerSpeed = max(0, -velocity)
        let upperSpeed = max(0, velocity)
        let lowerMargin = bodyInset + 36 + lowerSpeed * lowerSpeed / (2 * maximumAcceleration) * 1.45
        let upperMargin = bodyInset + 36 + upperSpeed * upperSpeed / (2 * maximumAcceleration) * 1.45
        if position < lowerMargin {
            let proximity = 1 - max(0, position - bodyInset) / max(1, lowerMargin - bodyInset)
            let braking = lowerSpeed * lowerSpeed / (2 * max(4, position - bodyInset)) * 1.35
            return min(maximumAcceleration, braking + maximumAcceleration * (0.28 + 0.72 * proximity * proximity))
        }
        if position > extent - upperMargin {
            let proximity = 1 - max(0, extent - bodyInset - position) / max(1, upperMargin - bodyInset)
            let braking = upperSpeed * upperSpeed / (2 * max(4, extent - bodyInset - position)) * 1.35
            return -min(maximumAcceleration, braking + maximumAcceleration * (0.28 + 0.72 * proximity * proximity))
        }
        return 0
    }

    private func interactionForce(for state: FishState) -> SIMD2<Float> {
        var force = SIMD2<Float>.zero
        if let pointerPosition {
            let offset = state.position - pointerPosition
            let distance = simd_length(offset)
            let radius: Float = state.species == .manta ? 190 : 145
            if distance < radius {
                force += normalized(offset, fallback: perpendicular(to: state.velocity)) * (1 - distance / radius) * 105
            }
        }

        for current in currents where current.age >= 0 {
            let offset = state.position - current.position
            let distance = simd_length(offset)
            let radius: Float = 105
            guard distance < radius else { continue }
            let life = max(0, 1 - current.age / 2.4)
            let across = normalized(perpendicular(to: current.velocity), fallback: SIMD2(0, 1))
            let side: Float = simd_dot(offset, across) >= 0 ? 1 : -1
            force += across * side * (1 - distance / radius) * life * 76
        }
        return force
    }

    private func disturbFish(along start: SIMD2<Float>, to end: SIMD2<Float>, direction: SIMD2<Float>) {
        let segment = end - start
        let segmentLengthSquared = max(0.001, simd_length_squared(segment))
        for index in fish.indices {
            let projection = min(1, max(0, simd_dot(fish[index].position - start, segment) / segmentLengthSquared))
            let nearest = start + segment * projection
            let offset = fish[index].position - nearest
            let distance = simd_length(offset)
            let radius: Float = fish[index].species == .manta ? 180 : 125
            guard distance < radius else { continue }
            let falloff = 1 - distance / radius
            let across = normalized(offset, fallback: perpendicular(to: direction))
            fish[index].velocity += (across * 58 + direction * 18) * falloff
            fish[index].panic = min(0.7, max(fish[index].panic, falloff * 0.55))
            constrainVelocity(&fish[index])
        }
    }

    private func contain(_ state: inout FishState) {
        if state.position.x < 0 {
            state.position.x = 0
            state.velocity.x = max(4, abs(state.velocity.x) * 0.2)
        } else if state.position.x > size.x {
            state.position.x = size.x
            state.velocity.x = -max(4, abs(state.velocity.x) * 0.2)
        }
        if state.position.y < 0 {
            state.position.y = 0
            state.velocity.y = max(4, abs(state.velocity.y) * 0.2)
        } else if state.position.y > size.y {
            state.position.y = size.y
            state.velocity.y = -max(4, abs(state.velocity.y) * 0.2)
        }
    }

    private func clamped(_ point: SIMD2<Float>) -> SIMD2<Float> {
        guard point.x.isFinite, point.y.isFinite else { return size * 0.5 }
        return simd_clamp(point, .zero, size)
    }

    private func constrainVelocity(_ state: inout FishState) {
        let parameters = Self.parameters(for: state.species)
        let maximumSpeed = parameters.speed * (1.28 + 1.7 * state.panic)
        guard state.velocity.x.isFinite, state.velocity.y.isFinite else {
            state.velocity = SIMD2(parameters.speed, 0)
            return
        }
        state.velocity = limited(state.velocity, to: maximumSpeed)
        let maximumAcceleration = parameters.maxAcceleration * (1 + state.panic)
        let bodyInset = min(min(size.x, size.y) * 0.24, max(16, state.length * 0.48))
        let leftRoom = max(0, state.position.x - bodyInset)
        let rightRoom = max(0, size.x - bodyInset - state.position.x)
        let bottomRoom = max(0, state.position.y - bodyInset)
        let topRoom = max(0, size.y - bodyInset - state.position.y)
        state.velocity.x = max(state.velocity.x, -sqrt(2 * maximumAcceleration * leftRoom / 1.45))
        state.velocity.x = min(state.velocity.x, sqrt(2 * maximumAcceleration * rightRoom / 1.45))
        state.velocity.y = max(state.velocity.y, -sqrt(2 * maximumAcceleration * bottomRoom / 1.45))
        state.velocity.y = min(state.velocity.y, sqrt(2 * maximumAcceleration * topRoom / 1.45))
    }

    private static func validSize(_ proposed: SIMD2<Float>) -> SIMD2<Float> {
        SIMD2(max(1, proposed.x.isFinite ? proposed.x : 1), max(1, proposed.y.isFinite ? proposed.y : 1))
    }

    private static func makeFish(in size: SIMD2<Float>, generator: inout SeededGenerator) -> [FishState] {
        let population: [(FishSpecies, Int)] = [
            (.silver, 18), (.clown, 4), (.tang, 3), (.butterfly, 3), (.manta, 1)
        ]
        let scale = min(1.3, max(0.65, min(size.x / 1440, size.y / 900)))
        var result: [FishState] = []
        result.reserveCapacity(29)

        for (species, count) in population {
            let parameters = parameters(for: species)
            for _ in 0..<count {
                let length = generator.float(in: parameters.lengthRange) * scale
                let inset = min(length * 0.55, min(size.x, size.y) * 0.2)
                let x = generator.float(in: inset...max(inset, size.x - inset))
                let y = generator.float(in: inset...max(inset, size.y - inset))
                let direction: Float = generator.bool() ? 1 : -1
                let vertical = generator.float(in: -0.28...0.28)
                let headingVector = normalized(SIMD2(direction, vertical), fallback: SIMD2(direction, 0))
                let speed = parameters.speed * generator.float(in: 0.82...1.12)
                let phase = generator.float(in: 0...(2 * .pi))
                result.append(FishState(
                    id: result.count,
                    species: species,
                    position: SIMD2(x, y),
                    velocity: headingVector * speed,
                    heading: atan2(headingVector.y, headingVector.x),
                    length: length,
                    depth: generator.float(in: 0.15...0.95),
                    phase: phase,
                    panic: 0
                ))
            }
        }
        return result
    }

    private static func parameters(for species: FishSpecies) -> SpeciesParameters {
        switch species {
        case .silver:
            SpeciesParameters(lengthRange: 60...84, speed: 67, maxAcceleration: 125, turnRate: 2.8, wanderRate: 0.72, wanderForce: 14, tailRate: 5.2)
        case .clown:
            SpeciesParameters(lengthRange: 76...104, speed: 43, maxAcceleration: 98, turnRate: 2.25, wanderRate: 0.9, wanderForce: 18, tailRate: 4.8)
        case .tang:
            SpeciesParameters(lengthRange: 98...128, speed: 51, maxAcceleration: 105, turnRate: 1.9, wanderRate: 0.55, wanderForce: 16, tailRate: 4.2)
        case .butterfly:
            SpeciesParameters(lengthRange: 88...118, speed: 47, maxAcceleration: 102, turnRate: 2.1, wanderRate: 0.64, wanderForce: 17, tailRate: 4.5)
        case .manta:
            SpeciesParameters(lengthRange: 220...290, speed: 30, maxAcceleration: 52, turnRate: 0.72, wanderRate: 0.32, wanderForce: 9, tailRate: 1.4)
        }
    }
}

private struct SpeciesParameters {
    var lengthRange: ClosedRange<Float>
    var speed: Float
    var maxAcceleration: Float
    var turnRate: Float
    var wanderRate: Float
    var wanderForce: Float
    var tailRate: Float
}

private struct SeededGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed &+ 0x9E3779B97F4A7C15
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        return value ^ (value >> 31)
    }

    mutating func float(in range: ClosedRange<Float>) -> Float {
        let unit = Float(next() >> 40) / Float(1 << 24)
        return range.lowerBound + (range.upperBound - range.lowerBound) * unit
    }

    mutating func bool() -> Bool {
        next() & 1 == 0
    }
}

private func normalized(_ vector: SIMD2<Float>, fallback: SIMD2<Float>) -> SIMD2<Float> {
    let lengthSquared = simd_length_squared(vector)
    if lengthSquared.isFinite, lengthSquared > 0.000001 {
        return vector / sqrt(lengthSquared)
    }
    let fallbackLengthSquared = simd_length_squared(fallback)
    guard fallbackLengthSquared.isFinite, fallbackLengthSquared > 0.000001 else { return .zero }
    return fallback / sqrt(fallbackLengthSquared)
}

private func limited(_ vector: SIMD2<Float>, to maximum: Float) -> SIMD2<Float> {
    let lengthSquared = simd_length_squared(vector)
    guard lengthSquared.isFinite else { return .zero }
    guard lengthSquared > maximum * maximum else { return vector }
    return vector * (maximum / sqrt(lengthSquared))
}

private func perpendicular(to vector: SIMD2<Float>) -> SIMD2<Float> {
    SIMD2(-vector.y, vector.x)
}

private func approachedAngle(_ current: Float, _ target: Float, maximumChange: Float) -> Float {
    var difference = remainder(target - current, 2 * .pi)
    difference = min(maximumChange, max(-maximumChange, difference))
    return current + difference
}
