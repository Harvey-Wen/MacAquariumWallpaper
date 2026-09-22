import Foundation
import simd

private struct TestFailure: Error, CustomStringConvertible {
    let description: String
}

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() {
        throw TestFailure(description: message)
    }
}

private func isFinite(_ value: SIMD2<Float>) -> Bool {
    value.x.isFinite && value.y.isFinite
}

@main
private enum SimulationTests {
    static func main() throws {
        try testInitialPopulationAndSeed()
        try testClickFalloffAndRippleLimit()
        try testDragEndsAndDecays()
        try testLongRunningBounds()
        try testResizeScalesCoordinates()
        try testFrameSnapshot()
        print("SimulationTests: 6 passed")
    }

    private static func testInitialPopulationAndSeed() throws {
        let first = OceanSimulation(size: SIMD2(1440, 900), seed: 7)
        let second = OceanSimulation(size: SIMD2(1440, 900), seed: 7)

        try expect(first.fish.count == 29, "expected 29 fish")
        let counts = Dictionary(grouping: first.fish, by: \.species).mapValues(\.count)
        try expect(counts[.silver] == 18, "expected 18 silver fish")
        try expect(counts[.clown] == 4, "expected 4 clown fish")
        try expect(counts[.tang] == 3, "expected 3 tang fish")
        try expect(counts[.butterfly] == 3, "expected 3 butterfly fish")
        try expect(counts[.manta] == 1, "expected one manta")
        try expect(first.fish.map(\.position) == second.fish.map(\.position), "same seed must reproduce positions")
        try expect(first.fish.filter { $0.species == .manta }.allSatisfy { (200...300).contains($0.length) }, "manta size should be 200...300 points at desktop scale")
        try expect(first.fish.filter { $0.species != .manta }.allSatisfy { (60...130).contains($0.length) }, "small and medium fish should be 60...130 points at desktop scale")
    }

    private static func testClickFalloffAndRippleLimit() throws {
        let simulation = OceanSimulation(size: SIMD2(1200, 800), seed: 19)
        let origin = simulation.fish[0].position
        let farIndex = simulation.fish.indices.max {
            simd_distance(simulation.fish[$0].position, origin) < simd_distance(simulation.fish[$1].position, origin)
        }!

        simulation.click(at: origin)

        try expect(simulation.fish[0].panic > simulation.fish[farIndex].panic, "click panic must decrease with distance")
        try expect(simulation.ripples.count == 2, "a click should create two soft ripples")
        for _ in 0..<40 { simulation.click(at: origin) }
        try expect(simulation.ripples.count <= 16, "ripples must be capped")
    }

    private static func testDragEndsAndDecays() throws {
        let simulation = OceanSimulation(size: SIMD2(1000, 700), seed: 3)
        simulation.drag(to: SIMD2(200, 300))
        simulation.drag(to: SIMD2(280, 330))
        simulation.drag(to: SIMD2(360, 360))
        try expect(!simulation.currents.isEmpty, "drag should create current strokes")
        try expect(simulation.currents.count <= 48, "current strokes must be capped")

        simulation.endDrag()
        for _ in 0..<240 { simulation.update(deltaTime: 1 / 60) }
        try expect(simulation.currents.isEmpty, "ended drag currents should decay away")
        try expect(simulation.fish.allSatisfy { $0.panic < 0.15 }, "fish should recover after disturbance")
    }

    private static func testLongRunningBounds() throws {
        let size = SIMD2<Float>(1280, 720)
        let simulation = OceanSimulation(size: size, seed: 41)
        simulation.pointerMoved(to: SIMD2(640, 360))
        simulation.click(at: SIMD2(500, 300))
        for step in 0..<3_600 {
            if step == 90 { simulation.pointerMoved(to: nil) }
            simulation.update(deltaTime: 1 / 60)
        }

        for fish in simulation.fish {
            try expect(isFinite(fish.position) && isFinite(fish.velocity), "fish state must remain finite")
            try expect(fish.position.x >= 0 && fish.position.x <= size.x, "fish x must remain bounded")
            try expect(fish.position.y >= 0 && fish.position.y <= size.y, "fish y must remain bounded")
            try expect(fish.heading.isFinite && fish.panic.isFinite, "heading and panic must remain finite")
            try expect(fish.panic < 0.02, "panic should return to rest")
        }
    }

    private static func testResizeScalesCoordinates() throws {
        let simulation = OceanSimulation(size: SIMD2(800, 600), seed: 11)
        let before = simulation.fish.map(\.position)
        simulation.pointerMoved(to: SIMD2(400, 300))
        simulation.drag(to: SIMD2(100, 120))
        simulation.drag(to: SIMD2(180, 180))
        simulation.resize(to: SIMD2(1600, 900))

        for index in before.indices {
            let expected = before[index] * SIMD2<Float>(2, 1.5)
            try expect(simd_distance(simulation.fish[index].position, expected) < 0.01, "resize should scale fish positions")
        }
        try expect(simulation.size == SIMD2<Float>(1600, 900), "resize should publish the new size")
        try expect(simulation.currents.allSatisfy { $0.position.x <= 1600 && $0.position.y <= 900 }, "resize should keep effects in bounds")
    }

    private static func testFrameSnapshot() throws {
        let simulation = OceanSimulation(size: SIMD2(900, 600), seed: 5)
        simulation.update(deltaTime: 0.25)
        let frame = simulation.frame(waterStrength: 0.7)
        try expect(frame.size == simulation.size, "frame size should match simulation")
        try expect(frame.time == simulation.time, "frame time should match simulation")
        try expect(frame.fish.count == 29, "frame should contain all fish")
        try expect(frame.waterStrength == 0.7, "frame should preserve requested water strength")
    }
}
