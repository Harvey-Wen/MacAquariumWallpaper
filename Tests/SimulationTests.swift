import Foundation
import simd

private struct TestFailure: Error, CustomStringConvertible { let description: String }
private func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw TestFailure(description: message) }
}

@main
private enum SimulationTests {
    static func main() throws {
        try snowIsRandomAndTransitionsFromTop()
        try snowSettlesMeltsAndClearsLocally()
        try precipitationResizesAndStaysBounded()
        try pointerAvoidanceDoesNotWaitForWaves()
        try pointerSweepAffectsFishAlongItsPath()
        try pointerStillnessAndReentryKeepFishCalm()
        try pointerSamplingKeepsResponseConsistent()
        try weatherModesTransitionAndStayDry()
        try populationAndShoreline()
        try waterClicksAndFalloff()
        try dispersiveMotionWavesAndRainBudget()
        try motionSourcesFollowPathAndResize()
        try pointerMovementIsQuietAndBounded()
        try pointerReentryAndJumpDoNotBridge()
        try pointerAvoidanceIsVisibleAndLocal()
        try pointerWavesMoveLeaves()
        try repeatedClicksRecover()
        try rainIsLocalAndMild()
        try rainPreservesClickPanicAndFallsOffLocally()
        try leavesLandFloatMoveAndExpire()
        try cornerLeavesAndExpandedRain()
        try shorelineContainsWholeFish()
        try resizeAndAspectMapping()
        try frameRateEquivalence()
        try jitteredFrameTimingPreservesEvents()
        try frameSnapshot()
        print("SimulationTests: 26 passed")
    }

    private static func snowIsRandomAndTransitionsFromTop() throws {
        let sim = OceanSimulation(size: SIMD2(1600, 1000), seed: 78)
        sim.weather = .snowy
        for _ in 0..<30 { sim.update(deltaTime: 1 / 30) }
        let first = sim.frame(waterStrength: 0.45).precipitation
        try expect(first.count > 15 && first.allSatisfy { $0.kind == .snow && $0.position.y > 880 }, "new snow enters from above, never appears across the whole screen")
        try expect(Set(first.map { Int($0.velocity.y) }).count > 15 && Set(first.map { Int($0.frequency * 100) }).count > 15,
                   "flakes have independent speeds and sway rather than shared grid layers")
        let xs = first.map { $0.origin.x }.sorted()
        let gaps = zip(xs, xs.dropFirst()).map { $1 - $0 }
        try expect(gaps.min()! < 10 && gaps.max()! > 80, "random origins allow clusters and gaps")
        for _ in 0..<450 { sim.update(deltaTime: 1 / 30) }
        let before = sim.frame(waterStrength: 0.45)
        try expect(before.precipitation.contains { $0.position.y < 400 }, "old snow reaches the lower pond")
        sim.weather = .rainy
        try expect(sim.frame(waterStrength: 0.45).precipitation == before.precipitation, "weather selection preserves every in-flight flake without advancing paused state")
        sim.update(deltaTime: 1 / 30)
        let mixed = sim.frame(waterStrength: 0.45).precipitation
        for flake in before.precipitation where flake.duration - flake.age > 0.1 {
            let next = mixed.first { $0.id == flake.id }
            try expect(next != nil && next!.opacity == flake.opacity && simd_distance(next!.position,flake.position) < 6,
                       "existing snow continues its own path and opacity during the rain switch")
        }
        try expect(mixed.contains { $0.kind == .rain } && mixed.filter { $0.kind == .rain }.allSatisfy { $0.position.y > 970 },
                   "new rain arrives only at the top while old snow continues below")
        for weather in [PondWeather.cloudy, .snowy, .overcast, .rainy, .sunny] {
            let old = sim.frame(waterStrength: 0.45).precipitation
            sim.weather = weather
            try expect(sim.frame(waterStrength: 0.45).precipitation == old, "rapid switching never clears in-flight weather")
            sim.update(deltaTime: 0.1)
        }
        for _ in 0..<1500 { sim.update(deltaTime: 1 / 30) }
        try expect(sim.frame(waterStrength: 0.45).precipitation.isEmpty, "dry weather eventually drains all precipitation")
    }

    private static func snowSettlesMeltsAndClearsLocally() throws {
        let swept = OceanSimulation(size: SIMD2(1600, 1000), seed: 9)
        let calm = OceanSimulation(size: swept.size, seed: 9)
        swept.weather = .snowy; calm.weather = .snowy
        for _ in 0..<900 { swept.update(deltaTime: 1 / 30); calm.update(deltaTime: 1 / 30) }
        let snow = swept.frame(waterStrength: 0.45).surfaceSnow
        try expect(snow.count > 100 && snow.allSatisfy { PondGeometry.contains($0.position, size: swept.size) }, "snow gradually accumulates only on water")
        let target = snow.first { $0.age < $0.lifetime - 2 && PondGeometry.contains($0.position,size: swept.size,margin: 60) }!
        swept.trackPointer(target.position - SIMD2(25,0))
        swept.trackPointer(target.position + SIMD2(25,0))
        let marked = swept.frame(waterStrength: 0.45).surfaceSnow
        try expect(marked.first { $0.id == target.id }!.clearing, "pointer sweep melts snow along the segment")
        try expect(marked.filter { $0.clearing }.allSatisfy { simd_distance($0.position,target.position) < 65 }, "clearing stays local")
        for _ in 0..<45 { swept.update(deltaTime: 1 / 30); calm.update(deltaTime: 1 / 30) }
        try expect(!swept.frame(waterStrength: 0.45).surfaceSnow.contains { $0.id == target.id }
                   && calm.frame(waterStrength: 0.45).surfaceSnow.contains { $0.id == target.id }, "swept patch fades out sooner than untouched snow")
        let untouched = calm.frame(waterStrength: 0.45).surfaceSnow
        calm.trackPointer(target.position); calm.trackPointer(target.position); calm.trackPointer(nil)
        calm.trackPointer(target.position + SIMD2(200,0))
        calm.trackPointer(target.position - SIMD2(200,0))
        try expect(calm.frame(waterStrength: 0.45).surfaceSnow == untouched, "stillness, re-entry and pointer jumps do not sweep snow")
        swept.weather = .sunny
        for _ in 0..<2100 { swept.update(deltaTime: 1 / 30) }
        try expect(swept.frame(waterStrength: 0.45).surfaceSnow.isEmpty, "all old snow melts naturally after snowfall stops")
    }

    private static func precipitationResizesAndStaysBounded() throws {
        let sim = OceanSimulation(size: SIMD2(1600,1000), seed: 91)
        sim.weather = .snowy
        for _ in 0..<1800 {
            sim.update(deltaTime: 1 / 30)
            let frame = sim.frame(waterStrength: 0.45)
            try expect(frame.precipitation.count <= 1600 && frame.surfaceSnow.count <= 1200, "long snow has bounded particle and surface counts")
        }
        let before = sim.frame(waterStrength: 0.45)
        sim.resize(to: SIMD2(1920,1200))
        let after = sim.frame(waterStrength: 0.45)
        try expect(zip(before.precipitation,after.precipitation).allSatisfy { simd_distance($0.position * 1.2,$1.position) < 0.01 }, "resize maps live precipitation without restarting it")
        try expect(zip(before.surfaceSnow,after.surfaceSnow).allSatisfy { simd_distance($0.position * 1.2,$1.position) < 0.01 }, "resize maps accumulated snow")
    }

    private static func weatherModesTransitionAndStayDry() throws {
        try expect(PondWeather.allCases.map(\.title) == ["晴天", "雨天", "下雪", "阴天", "多云"], "all five weather choices have distinct labels")
        for weather in [PondWeather.snowy, .overcast, .cloudy] {
            let sim = OceanSimulation(size: SIMD2(1600, 1000), seed: 7)
            sim.weather = .rainy
            for _ in 0..<90 { sim.update(deltaTime: 1 / 30) }
            let before = sim.frame(waterStrength: 0.45)
            sim.weather = weather
            try expect(sim.frame(waterStrength: 0.45).atmosphere == before.atmosphere, "choosing weather does not advance a paused frame")
            sim.update(deltaTime: 1 / 30)
            let first = sim.frame(waterStrength: 0.45)
            try expect(simd_length(first.atmosphere) > 0 && simd_length(first.atmosphere) < 0.1 && first.weatherAmount > 0.8,
                       "new weather fades in while old rain fades out")
            for _ in 0..<240 { sim.update(deltaTime: 1 / 30) }
            let settled = sim.frame(waterStrength: 0.45)
            try expect(simd_distance(settled.atmosphere, weather.atmosphere) < 0.001 && settled.weatherAmount == 0,
                       "each weather reaches its own target and fully removes rain")
            try expect(!sim.ripples.contains { $0.source == .rain }, "snow, overcast and clouds do not spawn rain impacts")
            sim.weather = .sunny
            for _ in 0..<240 { sim.update(deltaTime: 1 / 30) }
            try expect(sim.frame(waterStrength: 0.45).atmosphere == .zero, "sunny clears all atmospheric effects")
        }
        let fast = OceanSimulation(size: SIMD2(1600, 1000)), slow = OceanSimulation(size: SIMD2(1600, 1000))
        for weather in PondWeather.allCases {
            fast.weather = weather; slow.weather = weather
            for _ in 0..<60 { fast.update(deltaTime: 1 / 30) }
            for _ in 0..<10 { slow.update(deltaTime: 0.2) }
            try expect(simd_distance(fast.frame(waterStrength: 0.45).atmosphere, slow.frame(waterStrength: 0.45).atmosphere) < 0.001,
                       "weather transitions agree across frame rates and sequential changes")
        }
    }

    private static func populationAndShoreline() throws {
        let a = OceanSimulation(size: SIMD2(1600, 1000), seed: 7)
        let b = OceanSimulation(size: SIMD2(1600, 1000), seed: 7)
        try expect(a.fish.count == 30 && Set(a.fish.map(\.id)).count == 30, "pond needs 30 uniquely identified koi")
        try expect(a.fish.allSatisfy { $0.species == .koi }, "all fish should be koi")
        try expect(a.fish.map(\.position) == b.fish.map(\.position), "seed must reproduce positions")
        try expect(a.fish.allSatisfy { PondGeometry.contains($0.position, size: a.size, margin: $0.length * 0.5) }, "initial fish need whole-body clearance")
        try expect(!PondGeometry.contains(SIMD2(5, 5), size: a.size), "lower-left land should stay land")
        try expect(PondGeometry.contains(SIMD2(800, 500), size: a.size), "center should be water")
        for uv: SIMD2<Float> in [SIMD2(0.5, 0.005), SIMD2(0.5, 0.995), SIMD2(0.005, 0.5), SIMD2(0.995, 0.5), SIMD2(0.5, 0.86), SIMD2(0.1, 0.4)] {
            try expect(PondGeometry.contains(PondGeometry.point(for: uv, size: a.size), size: a.size), "edges, former peninsula and reflections are water")
        }
        for uv: SIMD2<Float> in [SIMD2(0.02, 0.02), SIMD2(0.97, 0.04), SIMD2(0.03, 0.94), SIMD2(0.96, 0.96)] {
            try expect(!PondGeometry.contains(PondGeometry.point(for: uv, size: a.size), size: a.size), "opaque corner foliage is excluded")
        }
        try expect(a.fish.contains { $0.position.y < 220 } && a.fish.contains { $0.position.y > 780 }, "fish use newly opened upper and lower water")

    }

    private static func waterClicksAndFalloff() throws {
        let sim = OceanSimulation(size: SIMD2(1600, 1000), seed: 7)
        sim.click(at: SIMD2(5, 5))
        try expect(sim.ripples.isEmpty, "land click creates no ripple")
        let hit = sim.fish[0].position
        let far = sim.fish.indices.max { simd_distance(sim.fish[$0].position, hit) < simd_distance(sim.fish[$1].position, hit) }!
        sim.click(at: hit)
        try expect(sim.fish[0].panic > 0, "near fish scatters")
        try expect(sim.fish[0].panic > sim.fish[far].panic, "click influence falls with distance")
        try expect(sim.ripples.allSatisfy { $0.source == .click && PondGeometry.contains($0.position, size: sim.size) }, "click ripples stay in water")
    }

    private static func repeatedClicksRecover() throws {
        let sim = OceanSimulation(size: SIMD2(1600, 1000), seed: 7)
        let hit = sim.fish[0].position
        for _ in 0..<100 { sim.click(at: hit) }
        try expect(sim.ripples.count <= 24, "click effects must be bounded")
        for _ in 0..<180 { sim.update(deltaTime: 1 / 30) }
        try expect(sim.fish.allSatisfy { $0.position.x.isFinite && $0.position.y.isFinite && simd_length($0.velocity) < 240 }, "click storm remains finite and bounded")
        try expect(sim.fish.allSatisfy { $0.panic < 0.05 }, "fish recover after clicks")
    }

    private static func dispersiveMotionWavesAndRainBudget() throws {
        let ripple = Ripple(position: SIMD2(800,500),age: 0.3,strength: 0.34,source: .motion)
        let right = OceanSimulation.motionWaveForce(at: ripple.position + SIMD2(15,0),ripple: ripple)
        let up = OceanSimulation.motionWaveForce(at: ripple.position + SIMD2(0,15),ripple: ripple)
        let left = OceanSimulation.motionWaveForce(at: ripple.position - SIMD2(15,0),ripple: ripple)
        try expect(simd_length(right) > 0.1, "a motion source emits a curved wave in front as well as behind")
        try expect(simd_distance(up,SIMD2(-right.y,right.x)) < 0.0001 && simd_distance(left,-right) < 0.0001,
                   "each motion impulse expands radially about its original position")
        try expect(OceanSimulation.motionWaveForce(at: ripple.position,ripple: ripple) == .zero, "wave center stays finite and still")
        func forceRadius(age: Float) -> Float {
            var sample = ripple; sample.age = age
            var weightedRadius: Float = 0, totalWeight: Float = 0
            for radius in 1...150 {
                let weight = simd_length(OceanSimulation.motionWaveForce(at: ripple.position + SIMD2(Float(radius),0),ripple: sample))
                weightedRadius += weight * Float(radius); totalWeight += weight
            }
            return weightedRadius / totalWeight
        }
        try expect(forceRadius(age: 0.8) > forceRadius(age: 0.25) * 2, "released rings keep expanding after the pointer moves away")
        var expired = ripple; expired.age = 2.3
        try expect(OceanSimulation.motionWaveForce(at: ripple.position + SIMD2(100,0),ripple: expired) == .zero, "released rings fully dissipate")
        // Deep-water dispersion: long waves occupy the outer part of an impulse.
        func crossings(_ radii: ClosedRange<Int>) -> Int {
            var sample = ripple; sample.age = 1
            var previous: Float = 0, count = 0
            for radius in radii {
                let value = OceanSimulation.motionWaveForce(at: ripple.position + SIMD2(Float(radius),0),ripple: sample).x
                if value * previous < 0 { count += 1 }
                previous = value
            }
            return count
        }
        try expect(crossings(30...65) >= crossings(65...100) * 2 && crossings(65...100) > 0,
                   "outer crests must be farther apart than inner crests; equal-speed stamped rings are not dispersive")
        let sim = OceanSimulation(size: SIMD2(1600,1000),seed: 7)
        sim.weather = .rainy
        for _ in 0..<180 { sim.update(deltaTime: 1/30) }
        sim.click(at: SIMD2(800,500))
        for _ in 0..<60 { sim.update(deltaTime: 1/30) }
        try expect(sim.ripples.filter { $0.source == .rain }.count >= 35, "random steady rain sustains dense water impacts within its bounded budget")
        try expect(sim.ripples.filter { $0.source == .click }.count == 2, "dense rain must not evict active click waves")
        try expect(sim.ripples.count <= 96, "rain and interaction retain finite independent budgets")
    }

    private static func motionSourcesFollowPathAndResize() throws {
        let sim = OceanSimulation(size: SIMD2(1600,1000), seed: 7)
        sim.trackPointer(SIMD2(700,500))
        sim.update(deltaTime: 0.2)
        sim.trackPointer(SIMD2(730,520))
        try expect(sim.ripples[0].position == SIMD2(730,520), "accepted motion leaves a wave source on the path")
        sim.update(deltaTime: 0.2)
        sim.trackPointer(SIMD2(730,550))
        try expect(sim.ripples[0].position == SIMD2(730,520) && sim.ripples[1].position == SIMD2(730,550),
                   "turning keeps old sources anchored to the earlier path")
        try expect(sim.ripples[0].age > sim.ripples[1].age, "older sources propagate farther behind the pointer")
        try expect(sim.ripples[0].travel == SIMD2(30,20) && sim.ripples[1].travel == SIMD2(0,30),
                   "a turn retains two historical source segments, not a rotated wake")
        let whole = Ripple(position: SIMD2(800,500),age: 0.5,strength: 0.34,source: .motion,
                           travel: SIMD2(24,0),duration: 0.16)
        var first = whole; first.position.x -= 12; first.age += 0.08; first.travel.x = 12; first.duration = 0.08
        var second = whole; second.travel.x = 12; second.duration = 0.08
        var error: Float = 0, energy: Float = 0
        for x in stride(from: Float(730),through: 850,by: 5) {
            let point = SIMD2(x,Float(520))
            let unsplit = OceanSimulation.motionWaveForce(at: point,ripple: whole)
            let split = OceanSimulation.motionWaveForce(at: point,ripple: first) + OceanSimulation.motionWaveForce(at: point,ripple: second)
            error += simd_length_squared(unsplit - split); energy += simd_length_squared(split)
        }
        try expect(sqrt(error / energy) < 0.02, "continuous source integration must not depend on pointer segment boundaries")
        sim.resize(to: SIMD2(1920,1200))
        try expect(simd_distance(sim.ripples[0].travel,SIMD2(36,24)) < 0.001, "resize scales historical segments")
        try expect(simd_distance(sim.ripples[0].position, SIMD2(876,624)) < 0.001, "resize maps released wave origins with scene geometry")
        let count = sim.ripples.count
        sim.trackPointer(SIMD2(900,600))
        try expect(sim.ripples.count == count, "resize resets pointer baseline")
        sim.click(at: SIMD2(900,600))
        try expect(sim.ripples.suffix(2).allSatisfy { $0.source == .click }, "clicks retain independent radial impulses")
    }

    private static func pointerMovementIsQuietAndBounded() throws {
        let sim = OceanSimulation(size: SIMD2(1600, 1000), seed: 7)
        let start = SIMD2<Float>(700, 500)
        sim.trackPointer(start)
        sim.update(deltaTime: 0.2)
        try expect(sim.ripples.isEmpty, "first hover and stillness are quiet")
        sim.trackPointer(start + SIMD2(8, 0))
        try expect(sim.ripples.isEmpty, "small displacement is quiet")
        sim.trackPointer(start + SIMD2(16, 0))
        try expect(sim.ripples.count == 1 && sim.ripples[0].source == .motion, "button-free movement makes a motion ripple")
        try expect(sim.ripples[0].strength < 0.48, "motion is weaker than either click ring")
        sim.trackPointer(start + SIMD2(32, 0))
        try expect(sim.ripples.count == 1, "time gate prevents adjacent motion samples")
        for _ in 0..<30 { sim.update(deltaTime: 1 / 30); sim.trackPointer(start + SIMD2(32, 0)) }
        try expect(sim.ripples.filter { $0.source == .motion }.count == 1, "stationary pointer does not repeat ripples")
        for index in 0..<600 {
            sim.update(deltaTime: 1 / 300)
            sim.trackPointer(SIMD2(720 + Float(index % 60), 500))
        }
        try expect(sim.ripples.count <= 24, "dense motion keeps ripple cap")
        try expect(sim.ripples.filter { $0.source == .motion }.count <= 17, "simulation-time throttle limits motion events")
        try expect(sim.fish.allSatisfy { $0.panic <= 0.65 && simd_length($0.velocity) <= 175.001 }, "dense motion keeps bounded fish response below click panic")
    }

    private static func pointerReentryAndJumpDoNotBridge() throws {
        let sim = OceanSimulation(size: SIMD2(1600, 1000), seed: 7)
        let center = SIMD2<Float>(700, 500)
        sim.trackPointer(center)
        sim.update(deltaTime: 0.2)
        sim.trackPointer(nil)
        sim.trackPointer(center + SIMD2(40, 0))
        try expect(sim.ripples.isEmpty, "nil gap and re-entry establish a quiet baseline")
        sim.update(deltaTime: 0.2)
        sim.trackPointer(SIMD2(5, 5))
        sim.trackPointer(center + SIMD2(80, 0))
        try expect(sim.ripples.isEmpty, "foliage gap and re-entry establish a quiet baseline")
        sim.update(deltaTime: 0.2)
        sim.trackPointer(center + SIMD2(350, 0))
        try expect(sim.ripples.isEmpty, "large jump does not draw a trail")
        sim.update(deltaTime: 0.2)
        sim.trackPointer(center + SIMD2(365, 0))
        try expect(sim.ripples.count == 1 && sim.ripples[0].position == center + SIMD2(365, 0), "movement after jump starts locally")
        sim.resetPointer()
        sim.update(deltaTime: 0.2)
        sim.trackPointer(center)
        try expect(sim.ripples.count == 1, "lifecycle reset makes next sample quiet")
    }

    private static func pointerAvoidanceDoesNotWaitForWaves() throws {
        let sim = OceanSimulation(size: SIMD2(1600, 1000), seed: 7)
        let before = sim.fish[0]
        sim.trackPointer(before.position + SIMD2(8, 12))
        sim.trackPointer(before.position + SIMD2(0, 12))
        try expect(sim.ripples.isEmpty, "short movement stays below the wave distance/time gates")
        try expect(sim.fish[0].panic > 0.5, "near fish visibly reacts before the next wave is due")
        try expect(sim.fish[0].velocity.y < before.velocity.y - 15, "fish turns away from the moving pointer")
        for _ in 0..<180 { sim.update(deltaTime: 1 / 30) }
        try expect(sim.fish.allSatisfy { $0.panic < 0.01 }, "fish recover after the pointer stops")
    }

    private static func pointerSweepAffectsFishAlongItsPath() throws {
        let sim = OceanSimulation(size: SIMD2(1600, 1000), seed: 7)
        let target = sim.fish.firstIndex { PondGeometry.contains($0.position, size: sim.size, margin: 150) }!
        let hit = sim.fish[target].position
        let before = sim.fish[target].velocity
        sim.trackPointer(hit + SIMD2(-65, 20))
        sim.trackPointer(hit + SIMD2(65, 20))
        try expect(sim.fish[target].panic > 0.5, "fish near the middle of a fast sweep receives the nearby path influence")
        try expect(sim.fish[target].velocity.y < before.y - 30, "fish escapes away from the swept path")
        try expect(sim.fish.allSatisfy { simd_length($0.velocity) <= 175.001 }, "fast sweeps retain the speed limit")
    }

    private static func pointerStillnessAndReentryKeepFishCalm() throws {
        let sim = OceanSimulation(size: SIMD2(1600, 1000), seed: 7)
        let calm = OceanSimulation(size: sim.size, seed: 7)
        let hit = sim.fish[0].position
        sim.trackPointer(hit)
        for _ in 0..<30 {
            sim.update(deltaTime: 1 / 30); calm.update(deltaTime: 1 / 30)
            sim.trackPointer(hit)
        }
        sim.trackPointer(nil)
        sim.trackPointer(sim.fish[0].position)
        sim.trackPointer(SIMD2(5, 5))
        sim.trackPointer(sim.fish[0].position)
        sim.trackPointer(sim.fish.first { simd_distance($0.position, sim.fish[0].position) > 200 }!.position)
        sim.resetPointer()
        sim.trackPointer(hit)
        try expect(sim.fish.map(\.velocity) == calm.fish.map(\.velocity) && sim.fish.allSatisfy { $0.panic == 0 },
                   "stationary hover, filtered re-entry, large jumps and lifecycle resets do not disturb fish")
    }

    private static func pointerSamplingKeepsResponseConsistent() throws {
        func moved(rate: Int) -> FishState {
            let sim = OceanSimulation(size: SIMD2(1600, 1000), seed: 7)
            let hit = sim.fish[0].position
            sim.trackPointer(hit + SIMD2(-30, 20))
            for tick in 1...(rate / 2) {
                sim.update(deltaTime: 1 / Float(rate))
                sim.trackPointer(hit + SIMD2(-30 + 120 * Float(tick) / Float(rate), 20))
            }
            return sim.fish[0]
        }
        let a = moved(rate: 30), b = moved(rate: 60), c = moved(rate: 120)
        try expect(simd_distance(a.position, b.position) < 4 && simd_distance(a.position, c.position) < 4,
                   "the same pointer path has comparable effect at different sample rates")
        try expect(simd_distance(a.velocity, c.velocity) < 8, "more pointer samples do not multiply the impulse")
    }

    private static func pointerAvoidanceIsVisibleAndLocal() throws {
        let sim = OceanSimulation(size: SIMD2(1600, 1000), seed: 7)
        let calm = OceanSimulation(size: SIMD2(1600, 1000), seed: 7)
        let hit = sim.fish[0].position
        let far = sim.fish.firstIndex { simd_distance($0.position, hit) > 200 }!
        sim.trackPointer(hit + SIMD2(15, 0))
        sim.update(deltaTime: 0.2)
        calm.update(deltaTime: 0.2)
        sim.trackPointer(hit)
        try expect(sim.fish[0].panic > 0.5 && sim.fish[0].panic <= 0.65, "near fish visibly avoids motion")
        try expect(simd_distance(sim.fish[0].velocity, calm.fish[0].velocity) > 25, "nearby movement produces a visible change in swimming")
        try expect(sim.fish[far].panic == calm.fish[far].panic && sim.fish[far].velocity == calm.fish[far].velocity, "remote fish has no motion impulse")
        let motionPanic = sim.fish[0].panic
        sim.click(at: hit)
        let clickPanic = sim.fish[0].panic
        sim.update(deltaTime: 0.2)
        sim.trackPointer(hit + SIMD2(15, 0))
        try expect(clickPanic > motionPanic && sim.fish[0].panic > 0.7, "motion cannot lower stronger click panic")
    }

    private static func pointerWavesMoveLeaves() throws {
        let moved = OceanSimulation(size: SIMD2(1600, 1000), seed: 22)
        let calm = OceanSimulation(size: SIMD2(1600, 1000), seed: 22)
        for _ in 0..<180 { moved.update(deltaTime: 1 / 30); calm.update(deltaTime: 1 / 30) }
        let leaf = moved.leaves.first { $0.stage == .floating }!
        moved.trackPointer(leaf.position + SIMD2(18, 0))
        moved.update(deltaTime: 0.2); calm.update(deltaTime: 0.2)
        moved.trackPointer(leaf.position)
        try expect(moved.ripples.contains { $0.source == .motion }, "floating leaf receives a motion wave")
        for _ in 0..<30 { moved.update(deltaTime: 1 / 30); calm.update(deltaTime: 1 / 30) }
        let a = moved.leaves.first { $0.id == leaf.id }!
        let b = calm.leaves.first { $0.id == leaf.id }!
        try expect(simd_distance(a.position, b.position) > 0.01, "motion wave moves a floating leaf")
    }

    private static func rainIsLocalAndMild() throws {
        let rainy = OceanSimulation(size: SIMD2(1600, 1000), seed: 11)
        let dry = OceanSimulation(size: SIMD2(1600, 1000), seed: 11)
        rainy.weather = .rainy
        for _ in 0..<300 {
            rainy.update(deltaTime: 1 / 30)
            dry.update(deltaTime: 1 / 30)
        }
        try expect(rainy.ripples.contains { $0.source == .rain }, "rain produces water impacts")
        try expect(rainy.ripples.count <= 96, "rain ripples are capped")
        try expect(rainy.ripples.allSatisfy { PondGeometry.contains($0.position, size: rainy.size) && ($0.source != .rain || $0.strength < 1) }, "rain is water-only and weaker than clicks")
        try expect(rainy.fish.allSatisfy { $0.panic < 0.5 }, "rain cannot cause click-sized panic")
        try expect(zip(rainy.fish, dry.fish).contains { simd_distance($0.position, $1.position) > 0.1 }, "rain must actually affect nearby fish")
        rainy.weather = .sunny
        for _ in 0..<120 { rainy.update(deltaTime: 1 / 30) }
        try expect(!rainy.ripples.contains { $0.source == .rain }, "rain effects expire after weather stops")
        try expect(rainy.frame(waterStrength: 0.5).weatherAmount < 0.01, "rain amount fades away")
    }

    private static func rainPreservesClickPanicAndFallsOffLocally() throws {
        let rainy = OceanSimulation(size: SIMD2(1600, 1000), seed: 7)
        let dry = OceanSimulation(size: rainy.size, seed: 7)
        let overlap = OceanSimulation(size: rainy.size, seed: 7)
        let point = rainy.fish[0].position + SIMD2(10,0)
        let far = rainy.fish.firstIndex { simd_distance($0.position,point) > 180 }!
        overlap.click(at: overlap.fish[0].position)
        rainy.rainImpact(at: point, age: 0)
        overlap.rainImpact(at: point, age: 0)
        try expect(rainy.fish[0].panic > dry.fish[0].panic && rainy.fish[0].panic < 0.28, "landing rain creates only mild local panic")
        try expect(rainy.fish[far].panic == dry.fish[far].panic && rainy.fish[far].velocity == dry.fish[far].velocity, "distant koi has no rain impulse")
        try expect(overlap.fish[0].panic > 0.9, "rain must not reduce stronger click panic")
    }

    private static func leavesLandFloatMoveAndExpire() throws {
        let sim = OceanSimulation(size: SIMD2(1600, 1000), seed: 22)
        let calm = OceanSimulation(size: SIMD2(1600, 1000), seed: 22)
        for _ in 0..<180 {
            sim.update(deltaTime: 1 / 30)
            calm.update(deltaTime: 1 / 30)
        }
        try expect(!sim.leaves.isEmpty, "overhanging trees drop leaves")
        try expect(sim.leaves.contains { $0.stage == .floating }, "leaves land and float")
        try expect(sim.ripples.contains { $0.source == .leaf }, "landing makes a ripple")
        try expect(sim.leaves.count <= 12, "leaf count is bounded")
        let floating = sim.leaves.first { $0.stage == .floating }!
        let position = floating.position
        sim.click(at: position)
        for _ in 0..<30 {
            sim.update(deltaTime: 1 / 30)
            calm.update(deltaTime: 1 / 30)
        }
        guard let moved = sim.leaves.first(where: { $0.id == floating.id }),
              let undisturbed = calm.leaves.first(where: { $0.id == floating.id }) else {
            throw TestFailure(description: "selected floating leaf must survive the wave comparison")
        }
        try expect(simd_distance(position, moved.position) > 0.1, "floating leaves move")
        try expect(simd_distance(undisturbed.position, moved.position) > 0.1, "floating leaves respond to nearby waves")
        let angleDifference = abs(atan2(sin(moved.rotation - undisturbed.rotation), cos(moved.rotation - undisturbed.rotation)))
        try expect(angleDifference > 0.001 && angleDifference < 0.3, "waves gently rotate floating leaves")
        for _ in 0..<900 { sim.update(deltaTime: 1 / 30) }
        try expect(sim.leaves.allSatisfy { $0.age < 16 && $0.opacity >= 0 && $0.opacity <= 1 }, "old leaves expire and opacity stays valid")
    }

    private static func cornerLeavesAndExpandedRain() throws {
        let sim = OceanSimulation(size: SIMD2(1600, 1000), seed: 1)
        var origins = Set<Int>(), landings = Set<Int>()
        var rainNearEdges = Set<Int>()
        sim.weather = .rainy
        for _ in 0..<1800 {
            sim.update(deltaTime: 1 / 30)
            for leaf in sim.leaves {
                if leaf.stage == .falling && leaf.age < 0.04 {
                    origins.insert(leaf.id % 4)
                    try expect(!PondGeometry.contains(leaf.position, size: sim.size), "leaf begins on a real corner branch")
                    try expect(PondGeometry.contains(leaf.position + leaf.velocity * (leaf.fallDuration - leaf.age), size: sim.size, margin: leaf.length), "branch trajectory ends in adjoining water")
                }
                if leaf.stage == .floating {
                    landings.insert(leaf.id % 4)
                    try expect(PondGeometry.contains(leaf.position, size: sim.size), "floating leaf is on water")
                }
            }
            for ripple in sim.ripples {
                try expect(PondGeometry.contains(ripple.position, size: sim.size), "all landing/rain rings are on water")
                if ripple.source == .rain {
                    if ripple.position.x < 160 { rainNearEdges.insert(0) }
                    if ripple.position.x > 1440 { rainNearEdges.insert(1) }
                    if ripple.position.y < 100 { rainNearEdges.insert(2) }
                    if ripple.position.y > 900 { rainNearEdges.insert(3) }
                }
            }
            try expect(sim.leaves.count <= 12 && sim.ripples.count <= 96, "steady-state effects remain bounded")
        }
        try expect(origins.count == 4 && landings.count == 4, "all four branch paths spawn and land")
        try expect(rainNearEdges.count == 4, "rain reaches open water along every edge")
    }

    private static func shorelineContainsWholeFish() throws {
        let sim = OceanSimulation(size: SIMD2(1600, 1000), seed: 41)
        for tick in 0..<1800 {
            if tick % 12 == 0 { sim.click(at: sim.fish[tick / 12 % sim.fish.count].position) }
            sim.update(deltaTime: 1 / 30)
            for fish in sim.fish {
                try expect(PondGeometry.contains(fish.position, size: sim.size, margin: fish.length * 0.5 - 0.1), "whole fish must remain in water")
                try expect(fish.phase >= 0 && fish.phase < 2 * .pi && fish.heading.isFinite, "animation remains finite and wrapped")
            }
        }
    }

    private static func resizeAndAspectMapping() throws {
        let size = SIMD2<Float>(1600, 1000)
        let wide = SIMD2<Float>(1920, 1080)
        let point = SIMD2<Float>(820, 450)
        let uv = PondGeometry.uv(for: point, size: size)
        try expect(simd_distance(PondGeometry.point(for: uv, size: size), point) < 0.01, "native mapping round trips")
        let widePoint = PondGeometry.point(for: uv, size: wide)
        try expect(simd_distance(PondGeometry.uv(for: widePoint, size: wide), uv) < 0.0001, "aspect-fill mapping round trips")
        let sim = OceanSimulation(size: size, seed: 3)
        let before = sim.fish.map { PondGeometry.uv(for: $0.position, size: size) }
        sim.resize(to: wide)
        try expect(sim.fish.allSatisfy { PondGeometry.contains($0.position, size: wide, margin: $0.length * 0.5 - 0.1) }, "resize preserves whole-fish containment")
        try expect(zip(before, sim.fish).filter { simd_distance($0, PondGeometry.uv(for: $1.position, size: wide)) < 0.01 }.count >= 25, "resize preserves source-image position except fish corrected at cropped edges")
    }

    private static func frameRateEquivalence() throws {
        let fast = OceanSimulation(size: SIMD2(1600, 1000), seed: 13)
        let slow = OceanSimulation(size: SIMD2(1600, 1000), seed: 13)
        fast.weather = .rainy
        slow.weather = .rainy
        for _ in 0..<120 { fast.update(deltaTime: 1 / 30) }
        for _ in 0..<20 { slow.update(deltaTime: 1 / 5) }
        try expect(abs(fast.time - 4) < 0.001 && abs(slow.time - 4) < 0.001, "both frame rates consume full duration")
        try expect(zip(fast.fish, slow.fish).allSatisfy { simd_distance($0.position, $1.position) < 0.2 }, "30 and 5 FPS fish positions agree")
        try expect(fast.ripples.count == slow.ripples.count && fast.leaves.count == slow.leaves.count, "event counts agree across frame rates")
    }

    private static func jitteredFrameTimingPreservesEvents() throws {
        let exact = OceanSimulation(size: SIMD2(1600, 1000), seed: 22)
        let jittered = OceanSimulation(size: SIMD2(1600, 1000), seed: 22)
        exact.weather = .rainy
        jittered.weather = .rainy
        for _ in 0..<150 {
            exact.update(deltaTime: 1 / 30)
            exact.update(deltaTime: 1 / 30)
            jittered.update(deltaTime: 0.034)
            jittered.update(deltaTime: 2 / 30 - 0.034)
        }
        try expect(abs(exact.time - 10) < 0.001 && abs(jittered.time - 10) < 0.001, "both schedules consume ten seconds")
        try expect(exact.leaves.map(\.id) == jittered.leaves.map(\.id), "jitter does not accelerate leaf births")
        try expect(zip(exact.leaves, jittered.leaves).allSatisfy { $0.length == $1.length && $0.fallDuration == $1.fallDuration },
                   "jitter preserves seeded leaf choices")
        let exactRain = exact.ripples.filter { $0.source == .rain }
        let jitteredRain = jittered.ripples.filter { $0.source == .rain }
        try expect(exactRain.count == jitteredRain.count, "jitter does not accelerate rain impacts")
        try expect(Set(exactRain.map(\.position)) == Set(jitteredRain.map(\.position)), "jitter preserves seeded landing positions regardless of simultaneous landing order")
    }

    private static func frameSnapshot() throws {
        let sim = OceanSimulation(size: SIMD2(1600, 1000), seed: 5)
        sim.update(deltaTime: 0.25)
        let frame = sim.frame(waterStrength: 0.7)
        try expect(frame.size == sim.size && frame.fish.count == 30, "frame exposes the restored population")
        try expect(abs(frame.time - 0.25) < 0.0001 && frame.waterStrength == 0.7, "frame preserves time and strength")
        try expect(frame.leaves.count == sim.leaves.count && frame.weatherAmount == 0, "frame exposes leaves and weather")
    }
}
