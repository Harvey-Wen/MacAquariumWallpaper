import AppKit
import MetalKit

private enum ListTestError: Error { case rejected }

@main struct FishListWindowTests {
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.accessory)
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            precondition(condition(), message); checks += 1
        }
        func settle() { RunLoop.main.run(until: Date().addingTimeInterval(0.15)) }
        let simulation = OceanSimulation(size: SIMD2(1600, 1000))
        let renderer = try OceanRenderer(view: MTKView(), shaderURL: URL(fileURLWithPath: "Resources/Ocean.metal"))
        let drawing = FishDrawing(id: UUID(uuidString: "A1234567-0000-0000-0000-000000000001")!,
            strokes: [FishStroke(points: [FishPoint(x: 0.35, y: 0.5), FishPoint(x: 0.6, y: 0.5)],
                color: FishColor(red: 0.9, green: 0.1, blue: 0.06), width: 0.22, erasing: false)])
        let blue = FishDrawing(id: UUID(uuidString: "B1234567-0000-0000-0000-000000000002")!,
            strokes: [], baseColor: FishColor(red: 0.05, green: 0.4, blue: 0.95))
        try renderer.registerDrawing(drawing)
        try renderer.registerDrawing(blue)
        simulation.addCustomFish(appearanceID: drawing.id)
        simulation.addCustomFish(appearanceID: blue.id)
        var deleted: [FishIdentity] = []
        var reject = false
        var addRequests = 0
        var controller: FishListWindowController!
        controller = FishListWindowController(readFish: { simulation.fish }, preview: renderer.fishPreview,
            onDelete: { identity in
                if reject { throw ListTestError.rejected }
                deleted.append(identity)
                simulation.removeFish(identity: identity)
            }, onAdd: { addRequests += 1 })
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        controller.window!.layoutIfNeeded()
        settle()
        check(controller.table.numberOfRows == 32 && controller.emptyLabel.isHidden, "all default and custom fish are listed")
        check(controller.countLabel.stringValue == "共 32 条 · 默认锦鲤 30 条 · 手绘鱼 2 条", "mixed counts are accurate")
        check(controller.fish[0].identity == .custom(drawing.id), "hand-drawn fish appear first")
        let thumbnail = controller.table.view(atColumn: 0, row: 0, makeIfNecessary: true) as! NSImageView
        check(thumbnail.image != nil && thumbnail.toolTip == nil, "actual fish thumbnail is displayed")
        check(controller.table.enclosingScrollView!.documentVisibleRect.height < controller.table.bounds.height, "long list scrolls")
        let output = URL(fileURLWithPath: ".build/fish-list-validation")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        func snapshot(_ name: String) throws {
            let content = controller.window!.contentView!
            content.layoutSubtreeIfNeeded()
            let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds)!
            content.cacheDisplay(in: content.bounds, to: bitmap)
            let composite = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: bitmap.pixelsWide,
                pixelsHigh: bitmap.pixelsHigh, bitsPerSample: 8, samplesPerPixel: 4,
                hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: composite)
            let rect = NSRect(x: 0, y: 0, width: bitmap.pixelsWide, height: bitmap.pixelsHigh)
            controller.window!.backgroundColor.setFill()
            rect.fill()
            let captured = NSImage(size: rect.size)
            captured.addRepresentation(bitmap)
            captured.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
            NSGraphicsContext.restoreGraphicsState()
            try composite.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name))
        }
        try snapshot("fish-list.png")
        if CommandLine.arguments.contains("--fixture") { NSApp.run(); return }
        func deleteButton(_ identity: FishIdentity) -> FishDeleteButton {
            let row = controller.fish.firstIndex { $0.identity == identity }!
            controller.table.scrollRowToVisible(row)
            let cell = controller.table.view(atColumn: 2, row: row, makeIfNecessary: true)!
            return cell.subviews.compactMap { $0 as? FishDeleteButton }.first!
        }
        func respond(_ response: NSApplication.ModalResponse) {
            let sheet = controller.window!.attachedSheet!
            controller.window!.endSheet(sheet, returnCode: response)
            settle()
        }
        deleteButton(.builtIn(12)).performClick(nil)
        check(controller.window!.attachedSheet != nil && deleted.isEmpty, "delete first asks for confirmation")
        respond(.alertSecondButtonReturn)
        check(deleted.isEmpty && controller.table.numberOfRows == 32, "cancel leaves fish unchanged")
        deleteButton(.builtIn(12)).performClick(nil)
        respond(.alertFirstButtonReturn)
        check(deleted == [.builtIn(12)] && controller.table.numberOfRows == 31, "confirmed delete targets exact default fish")
        check(controller.fish.contains { $0.identity.name == "锦鲤 14" }, "neighbor numbering remains stable")
        deleteButton(.custom(drawing.id)).performClick(nil)
        respond(.alertFirstButtonReturn)
        check(deleted.last == .custom(drawing.id) && controller.table.numberOfRows == 30, "custom button uses UUID identity")
        reject = true
        deleteButton(.custom(blue.id)).performClick(nil)
        respond(.alertFirstButtonReturn)
        check(controller.table.numberOfRows == 30 && controller.window!.attachedSheet != nil,
              "failed delete retains row and displays an error")
        respond(.alertFirstButtonReturn)
        reject = false
        simulation.addCustomFish(appearanceID: UUID())
        controller.reload()
        check(controller.table.numberOfRows == 31 && controller.countLabel.stringValue.contains("手绘鱼 2 条"), "list refresh includes newly added fish")
        controller.window!.close()
        simulation.removeFish(identity: .builtIn(0))
        controller.showWindow(nil)
        check(controller.table.numberOfRows == 30, "reopening refreshes current fish")
        controller.window!.setContentSize(NSSize(width: 560, height: 360))
        controller.window!.layoutIfNeeded()
        settle()
        let lastRow = controller.table.numberOfRows - 1
        controller.table.scrollRowToVisible(lastRow)
        let lastButton = deleteButton(controller.fish[lastRow].identity)
        let buttonRect = lastButton.convert(lastButton.bounds, to: controller.window!.contentView)
        check(controller.window!.contentView!.bounds.contains(buttonRect), "delete action stays visible in smaller window")
        for fish in simulation.fish { simulation.removeFish(identity: fish.identity) }
        controller.reload()
        settle()
        check(controller.table.numberOfRows == 0 && !controller.emptyLabel.isHidden, "empty pond has a clear empty state")
        check(controller.countLabel.stringValue.contains("共 0 条"), "empty count is accurate")
        controller.addButton.performClick(nil)
        check(addRequests == 1, "empty state still allows drawing a new fish")
        try snapshot("empty-list.png")
        controller.window!.close()
        print("PASS: \(checks) fish list window checks")
    }
}
