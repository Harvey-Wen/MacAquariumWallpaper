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
            color: FishColor(red: 0.9, green: 0.12, blue: 0.1), width: 0.06, erasing: false)], name: "小锦 🐟")
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
        check(restarted.simulation.fish.last?.displayName == "小锦 🐟", "saved name is restored for the list")
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

        let deletionStore = FishDrawingStore(directory: root.appendingPathComponent("deletion-drawings"))
        let deleting = try DesktopController(shaderURL: URL(fileURLWithPath: "Resources/Ocean.metal"),
            backdrop: backdrop("deletion-backdrop"), drawingStore: deletionStore)
        deleting.paused = true
        var changes = 0
        deleting.onFishChanged = { changes += 1 }
        try deleting.addCustomFish(drawing)
        var second = FishDrawing(id: UUID(), strokes: [], baseColor: FishColor(red: 0, green: 0.3, blue: 1), name: drawing.name)
        try deleting.addCustomFish(second)
        check(changes == 2, "each successful add notifies list")
        let beforeRename = deleting.simulation.fish.map(\.position)
        let backdropBeforeRename = current
        try deleting.renameFish(identity: .builtIn(4), name: " 小黄 ")
        try deleting.renameFish(identity: .custom(drawing.id), name: "小红 🐟")
        try deleting.renameFish(identity: .custom(second.id), name: "小红 🐟")
        second.name = "小红 🐟"
        check(deleting.simulation.fish.first { $0.identity == .builtIn(4) }?.displayName == "小黄", "default fish can be renamed")
        check(deleting.simulation.fish.last?.displayName == second.name && changes == 5, "custom names update and notify list")
        check(deleting.simulation.fish.map(\.position) == beforeRename && current == backdropBeforeRename && deleting.paused,
              "rename does not move fish, change backdrop or unpause")
        let survivors = deleting.simulation.fish.filter { $0.identity != .builtIn(12) }
        let beforeDefaultRemoval = current
        try deleting.removeFish(identity: .builtIn(12))
        check(deleting.simulation.fish.map(\.identity) == survivors.map(\.identity), "only target default fish removed")
        check(deleting.simulation.fish.map(\.position) == survivors.map(\.position), "survivors do not jump on deletion")
        check(current != beforeDefaultRemoval && deleting.backdropError == nil, "default removal refreshes backdrop")
        check(deleting.paused && deleting.enabled, "delete preserves pause and visibility")
        try deleting.removeFish(identity: .custom(drawing.id))
        check(deletionStore.load().drawings == [second], "custom deletion retains other drawings")
        check(deleting.simulation.fish.last?.displayName == second.name, "same-named fish is not removed by mistake")
        check(changes == 7, "successful deletes notify list")
        try deleting.removeFish(identity: .custom(drawing.id))
        check(changes == 7, "stale identity is a harmless no-op")
        deleting.enabled = false
        try deleting.removeFish(identity: .builtIn(29))
        check(!deleting.enabled && !deleting.window.isVisible && deleting.paused && current == original,
              "delete while hidden keeps pond hidden and background restored")
        deleting.stop()

        let afterDeletion = try DesktopController(shaderURL: URL(fileURLWithPath: "Resources/Ocean.metal"),
            backdrop: backdrop("deletion-restart"), drawingStore: deletionStore)
        check(afterDeletion.simulation.fish.count == 29, "restart respects both default and custom removals")
        check(!afterDeletion.simulation.fish.contains { $0.identity == .builtIn(12) || $0.identity == .builtIn(29) || $0.identity == .custom(drawing.id) },
              "deleted identities never reappear on restart")
        check(afterDeletion.simulation.fish.last?.identity == .custom(second.id), "surviving custom fish retains stable identity")
        check(afterDeletion.simulation.fish.last?.displayName == second.name &&
              afterDeletion.simulation.fish.first { $0.identity == .builtIn(4) }?.displayName == "小黄", "both types of renamed fish survive restart")
        try afterDeletion.renameFish(identity: .builtIn(4), name: " \n ")
        try afterDeletion.renameFish(identity: .custom(second.id), name: "")
        check(afterDeletion.simulation.fish.first { $0.identity == .builtIn(4) }?.displayName == "锦鲤 05" &&
              afterDeletion.simulation.fish.last?.displayName == FishIdentity.custom(second.id).name,
              "blank name restores stable fallback for both types")
        let clearedState = try deletionStore.defaultFishState()
        check(clearedState.names[4] == nil, "clearing default name is persisted")
        afterDeletion.enabled = false
        afterDeletion.paused = true
        for fish in afterDeletion.simulation.fish { try afterDeletion.removeFish(identity: fish.identity) }
        check(afterDeletion.simulation.fish.isEmpty && deletionStore.load().drawings.isEmpty, "entire pond can be emptied")
        try afterDeletion.addCustomFish(drawing)
        check(afterDeletion.simulation.fish.count == 1 && afterDeletion.simulation.fish[0].identity == .custom(drawing.id),
              "new custom fish can be added after deleting all fish")
        afterDeletion.stop()

        let stateURL = deletionStore.directory.appendingPathComponent("state/default-fish.json")
        try Data("broken".utf8).write(to: stateURL)
        let corrupt = try DesktopController(shaderURL: URL(fileURLWithPath: "Resources/Ocean.metal"),
            backdrop: backdrop("corrupt-state"), drawingStore: deletionStore)
        corrupt.enabled = false
        check(corrupt.defaultFishError != nil, "invalid deletion record is surfaced")
        var failedChanges = 0
        corrupt.onFishChanged = { failedChanges += 1 }
        let beforeDeleteFailure = corrupt.simulation.fish.map(\.identity)
        do { try corrupt.removeFish(identity: .builtIn(0)); preconditionFailure("corrupt state must block deletion") }
        catch { checks += 1 }
        check(corrupt.simulation.fish.map(\.identity) == beforeDeleteFailure && failedChanges == 0,
              "persistence failure leaves fish and list unchanged")
        do { try corrupt.renameFish(identity: .builtIn(0), name: "保存失败"); preconditionFailure("corrupt state must block rename") }
        catch { checks += 1 }
        check(corrupt.simulation.fish.first?.displayName == "锦鲤 01" && failedChanges == 0, "failed rename preserves default name")
        let savedDrawings = root.appendingPathComponent("saved-drawings")
        try FileManager.default.moveItem(at: deletionStore.directory, to: savedDrawings)
        try Data("blocked".utf8).write(to: deletionStore.directory)
        do { try corrupt.removeFish(identity: .custom(drawing.id)); preconditionFailure("blocked storage must fail") }
        catch { checks += 1 }
        check(corrupt.simulation.fish.map(\.identity) == beforeDeleteFailure && failedChanges == 0,
              "failed custom deletion retains fish")
        do { try corrupt.renameFish(identity: .custom(drawing.id), name: "保存失败"); preconditionFailure("blocked storage must block rename") }
        catch { checks += 1 }
        check(corrupt.simulation.fish.last?.displayName == drawing.name && failedChanges == 0, "failed rename preserves custom name")
        corrupt.stop()
        print("PASS: \(checks) custom fish desktop integration checks (isolated storage and backdrop)")
    }
}
