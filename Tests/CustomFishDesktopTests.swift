import AppKit
import MetalKit

@main struct CustomFishDesktopTests {
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.accessory)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("pond-custom-integration-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FishDrawingStore(directory: root.appendingPathComponent("drawings"))
        let original = URL(fileURLWithPath: "/test-original.heic")
        var current = original
        func backdrop(_ name: String) throws -> DesktopBackdrop {
            try DesktopBackdrop(directory: root.appendingPathComponent(name),
                readImage: { _ in current }, readOptions: { _ in [:] }, setImage: { url, _, _ in current = url })
        }
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ label: String) {
            precondition(condition(), label); checks += 1
        }
        let controller = try DesktopController(shaderURL: URL(fileURLWithPath: "Resources/Ocean.metal"),
            backdrop: backdrop("backdrop"), drawingStore: store)
        controller.paused = true
        controller.enabled = false
        let before = controller.simulation.fish
        let drawing = FishDrawing(id: UUID(), strokes: [FishStroke(
            points: [FishPoint(x: 0.5, y: 0.4), FishPoint(x: 0.5, y: 0.6)],
            color: FishColor(red: 0.9, green: 0.12, blue: 0.1), width: 0.06, erasing: false)])
        try controller.addCustomFish(drawing)
        check(controller.simulation.fish.count == before.count + 1, "one fish is added")
        check(Array(controller.simulation.fish.dropLast()).map(\.position) == before.map(\.position), "existing fish positions retained")
        check(controller.enabled && controller.window.isVisible && controller.paused, "add reveals hidden pond without unpausing")
        check(store.load().drawings == [drawing], "successful add persists exact drawing")
        check(current != original && controller.backdropError == nil, "custom fish refreshes static backdrop")
        let firstBackdrop = current
        try controller.addCustomFish(drawing)
        check(controller.simulation.fish.count == before.count + 1 && current == firstBackdrop, "retry does not duplicate saved fish")
        controller.stop()
        check(current == original, "mock backdrop restored")

        let restarted = try DesktopController(shaderURL: URL(fileURLWithPath: "Resources/Ocean.metal"),
            backdrop: backdrop("restart"), drawingStore: store)
        check(restarted.simulation.fish.count == before.count + 1, "restart restores one custom fish")
        check(restarted.simulation.fish.last?.customAppearanceID == drawing.id, "restored appearance matches saved identity")
        check(restarted.customFishErrors.isEmpty, "valid store loads without warning")
        restarted.stop()

        try Data("broken".utf8).write(to: root.appendingPathComponent("drawings/invalid.json"))
        let damaged = try DesktopController(shaderURL: URL(fileURLWithPath: "Resources/Ocean.metal"),
            backdrop: backdrop("damaged"), drawingStore: store)
        check(damaged.simulation.fish.count == before.count + 1 && !damaged.customFishErrors.isEmpty,
              "corrupt record warns while valid fish loads")
        damaged.stop()

        let blocked = root.appendingPathComponent("blocked")
        try Data("not a directory".utf8).write(to: blocked)
        let failing = try DesktopController(shaderURL: URL(fileURLWithPath: "Resources/Ocean.metal"),
            backdrop: backdrop("failure-backdrop"), drawingStore: FishDrawingStore(directory: blocked))
        let beforeFailure = failing.simulation.fish.count
        do { try failing.addCustomFish(drawing); preconditionFailure("write failure must be reported") }
        catch { checks += 1 }
        check(failing.simulation.fish.count == beforeFailure, "failed save leaves pond unchanged")
        let retainedFile = try Data(contentsOf: blocked)
        check(retainedFile == Data("not a directory".utf8), "failed save retains existing file")
        failing.stop()
        print("PASS: \(checks) custom fish desktop integration checks (isolated storage and backdrop)")
    }
}
