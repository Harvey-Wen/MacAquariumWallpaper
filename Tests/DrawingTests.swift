import Foundation
import simd

@main struct DrawingTests {
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FishDrawingStore(directory: directory)
        let first = FishDrawing(id: UUID(), strokes: [FishStroke(points: [FishPoint(x: 0.5, y: 0.5)], color: FishColor(red: 1, green: 0, blue: 0), width: 0.04, erasing: false)])
        let second = FishDrawing(id: UUID(), strokes: [])
        try store.save(first)
        try store.save(second)
        var loaded = store.load()
        try expect(loaded.errors.isEmpty && Set(loaded.drawings.map(\.id)) == Set([first.id, second.id]), "separate drawings round trip")
        try expect(loaded.drawings.first(where: { $0.id == first.id }) == first, "stroke data round trips")

        let legacyDirectory = directory.appendingPathComponent("legacy")
        try FileManager.default.createDirectory(at: legacyDirectory, withIntermediateDirectories: true)
        let legacyID = UUID()
        try Data("{\"id\":\"\(legacyID.uuidString)\",\"strokes\":[]}".utf8)
            .write(to: legacyDirectory.appendingPathComponent(legacyID.uuidString + ".json"))
        let legacy = FishDrawingStore(directory: legacyDirectory).load()
        try expect(legacy.errors.isEmpty && legacy.drawings.count == 1 &&
            legacy.drawings[0].resolvedBaseColor == FishColor(red: 1, green: 1, blue: 1),
            "old JSON without baseColor uses white")

        let blue = FishColor(red: 0, green: 0, blue: 1)
        var painted = first
        painted.baseColor = blue
        painted.strokes.append(FishStroke(points: [FishPoint(x: 0.65, y: 0.5)],
            color: FishColor(red: 1, green: 0, blue: 0), width: 0.04, erasing: false))
        try store.save(painted)
        try expect(store.load().drawings.first(where: { $0.id == first.id }) == painted, "base color persists")

        var invalidBase = painted
        invalidBase.baseColor = FishColor(red: 1.1, green: 0, blue: 0)
        do { try store.save(invalidBase); throw TestError.failed("invalid base was saved") }
        catch FishDrawingError.invalidDrawing {}
        try expect(store.load().drawings.first(where: { $0.id == first.id }) == painted,
            "invalid base does not overwrite valid record")

        func pixel(_ drawing: FishDrawing, _ u: Float, _ v: Float) throws -> [UInt8] {
            let image = try require(drawing.rasterizedImage(width: 240, height: 120), "raster image")
            let bytes = try require(image.dataProvider?.data as Data?, "raster bytes")
            let x = Int(u * Float(image.width)), y = Int(v * Float(image.height))
            return Array(bytes[(y * image.width + x) * 4..<(y * image.width + x) * 4 + 4])
        }
        try expect(try pixel(painted, 0.58, 0.5)[2] > 200, "unpainted body uses blue base")
        try expect(try pixel(painted, 0.65, 0.5)[0] > 200 && pixel(painted, 0.65, 0.5)[2] < 100,
            "red strokes remain red over blue base")
        let erase = FishStroke(points: [FishPoint(x: 0.5, y: 0.5)],
            color: FishColor(red: 0, green: 0, blue: 0), width: 0.04, erasing: true)
        painted.strokes.append(erase)
        try expect(try pixel(painted, 0.5, 0.5)[2] > 200 && pixel(painted, 0.5, 0.5)[0] < 100,
            "erase returns to blue base")
        painted.baseColor = FishColor(red: 0, green: 1, blue: 0)
        try expect(try pixel(painted, 0.5, 0.5)[1] > 200 && pixel(painted, 0.5, 0.5)[2] < 100,
            "changing base recolors erased areas")
        try expect(try pixel(painted, 0.65, 0.5)[0] > 200 && pixel(painted, 0.65, 0.5)[1] < 100,
            "changing base preserves colored strokes")

        let corruptURL = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension("json")
        try Data("{ broken".utf8).write(to: corruptURL)
        loaded = store.load()
        try expect(loaded.drawings.count == 2 && loaded.errors.count == 1, "a corrupt record does not hide valid drawings")
        try expect(FileManager.default.fileExists(atPath: corruptURL.path), "corrupt record is preserved")

        let invalidFile = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension("json")
        let invalidRecord = FishDrawing(id: UUID(uuidString: invalidFile.deletingPathExtension().lastPathComponent)!,
            strokes: [FishStroke(points: [FishPoint(x: -0.1, y: 0.5)],
                color: FishColor(red: 1, green: 0, blue: 0), width: 0.04, erasing: false)])
        try JSONEncoder().encode(invalidRecord).write(to: invalidFile)
        loaded = store.load()
        try expect(loaded.drawings.count == 2 && loaded.errors.count == 2, "decoded out-of-range points are rejected")
        try expect(FileManager.default.fileExists(atPath: invalidFile.path), "invalid record is preserved")

        let bad = FishDrawing(id: UUID(), strokes: [FishStroke(points: [FishPoint(x: 2, y: 0.5)], color: FishColor(red: 1, green: 0, blue: 0), width: 0.04, erasing: false)])
        do { try store.save(bad); throw TestError.failed("invalid normalized point was saved") } catch FishDrawingError.invalidDrawing {}
        do { try FishDrawingStore(directory: directory.appendingPathComponent(first.id.uuidString + ".json")).save(second); throw TestError.failed("write to file directory succeeded") } catch TestError.failed { throw TestError.failed("write failure not propagated") } catch {}

        let image = try require(first.rasterizedImage(width: 240, height: 120), "raster image")
        let bytes = try require(image.dataProvider?.data as Data?, "raster bytes")
        func pixel(_ u: Float, _ v: Float) -> [UInt8] {
            let x = Int(u * Float(image.width)), y = Int(v * Float(image.height))
            return Array(bytes[(y * image.width + x) * 4..<(y * image.width + x) * 4 + 4])
        }
        try expect(pixel(0.5, 0.5)[0] > 200 && pixel(0.5, 0.5)[1] < 100, "painted center is red")
        try expect(pixel(0.5, 0.1)[3] == 0, "outside body stays transparent")
        let erased = FishDrawing(id: UUID(), strokes: first.strokes + [FishStroke(points: [FishPoint(x: 0.5, y: 0.5)], color: FishColor(red: 0, green: 0, blue: 0), width: 0.02, erasing: true)])
        let erasedImage = try require(erased.rasterizedImage(width: 240, height: 120), "erased image")
        let erasedBytes = try require(erasedImage.dataProvider?.data as Data?, "erased bytes")
        let index = (60 * 240 + 120) * 4
        try expect(erasedBytes[index] > 220 && erasedBytes[index + 1] > 220 && erasedBytes[index + 2] > 220, "erase restores white")

        let simulation = OceanSimulation(size: SIMD2(1600, 1000), seed: 17)
        let before = simulation.fish
        simulation.addCustomFish(appearanceID: first.id)
        simulation.addCustomFish(appearanceID: first.id)
        try expect(simulation.fish.count == before.count + 1, "custom UUID is unique")
        try expect(Array(simulation.fish.dropLast()).map(\.position) == before.map(\.position), "existing fish positions remain unchanged")
        let custom = try require(simulation.fish.last, "custom fish")
        try expect(custom.customAppearanceID == first.id && PondGeometry.contains(custom.position, size: simulation.size, margin: custom.length * 0.5), "custom fish spawns in water")
        simulation.update(deltaTime: 1)
        try expect(simulation.fish.last!.position != custom.position, "custom fish moves")
        simulation.click(at: simulation.fish.last!.position)
        try expect(simulation.fish.last!.panic > 0, "custom fish responds to click")
        let survivor = simulation.fish[4]
        simulation.removeFish(identity: .builtIn(3))
        try expect(!simulation.fish.contains { $0.identity == .builtIn(3) }, "target default fish removed")
        try expect(simulation.fish.first { $0.identity == survivor.identity }?.position == survivor.position,
            "removing a neighbor preserves identity and position")
        simulation.removeFish(identity: .custom(first.id))
        try expect(!simulation.fish.contains { $0.customAppearanceID == first.id }, "target custom fish removed")
        for fish in simulation.fish { simulation.removeFish(identity: fish.identity) }
        try expect(simulation.fish.isEmpty, "all default fish can be removed")
        simulation.update(deltaTime: 1)
        simulation.addCustomFish(appearanceID: second.id)
        try expect(simulation.fish.count == 1 && simulation.fish[0].identity == .custom(second.id),
            "adding to empty pond keeps custom identity separate from default IDs")

        try store.removeDefaultFish(id: 3)
        try store.removeDefaultFish(id: 29)
        try store.removeDefaultFish(id: 3)
        try expect(try store.deletedDefaultFish() == Set([3, 29]), "default deletions persist without duplicates")
        try expect(store.load().drawings.count == 2, "default state is not scanned as a drawing")
        try store.remove(id: first.id)
        try expect(store.load().drawings.map(\.id) == [second.id], "only selected drawing is deleted")
        let secondURL = directory.appendingPathComponent(second.id.uuidString + ".json")
        let lowercaseURL = directory.appendingPathComponent(second.id.uuidString.lowercased() + ".json")
        try FileManager.default.moveItem(at: secondURL, to: lowercaseURL)
        try store.remove(id: second.id)
        try expect(store.load().drawings.isEmpty, "loaded lowercase UUID filename can be deleted")
        let stateURL = directory.appendingPathComponent("state/deleted-default-fish.json")
        let corruptState = Data("broken".utf8)
        try corruptState.write(to: stateURL)
        do { try store.removeDefaultFish(id: 4); throw TestError.failed("corrupt deletion state overwritten") }
        catch TestError.failed { throw TestError.failed("corrupt deletion state must fail") } catch {}
        try expect(try Data(contentsOf: stateURL) == corruptState, "corrupt deletion state is retained")
        print("Drawing tests passed (including persistent individual removal)")
    }

    static func expect(_ condition: Bool, _ message: String) throws { if !condition { throw TestError.failed(message) } }
    static func require<T>(_ value: T?, _ message: String) throws -> T { guard let value else { throw TestError.failed(message) }; return value }
    enum TestError: Error { case failed(String) }
}
