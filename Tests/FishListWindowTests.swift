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
        simulation.addCustomFish(appearanceID: drawing.id, name: "小锦 🐟")
        simulation.addCustomFish(appearanceID: blue.id, name: "小蓝")
        var deleted: [FishIdentity] = []
        var reject = false
        var addRequests = 0
        var controller: FishListWindowController!
        controller = FishListWindowController(readFish: { simulation.fish }, preview: renderer.fishPreview,
            onDelete: { identity in
                if reject { throw ListTestError.rejected }
                deleted.append(identity)
                simulation.removeFish(identity: identity)
            }, onRename: { identity, name in
                if reject { throw ListTestError.rejected }
                let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                simulation.renameFish(identity: identity, name: trimmed.isEmpty ? nil : trimmed)
            }, onAdd: { addRequests += 1 })
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        controller.window!.layoutIfNeeded()
        settle()
        check(controller.table.numberOfRows == 32 && controller.emptyLabel.isHidden, "all default and custom fish are listed")
        check(controller.countLabel.stringValue == "共 32 条 · 默认锦鲤 30 条 · 手绘鱼 2 条", "mixed counts are accurate")
        check(controller.fish[0].identity == .custom(drawing.id), "hand-drawn fish appear first")
        let nameCell = controller.table.view(atColumn: 1, row: 0, makeIfNecessary: true) as! NSTableCellView
        check(nameCell.textField?.stringValue == "小锦 🐟", "list shows the saved fish name")
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
        func actionButton(_ identity: FishIdentity, title: String) -> FishActionButton {
            let row = controller.fish.firstIndex { $0.identity == identity }!
            controller.table.scrollRowToVisible(row)
            let cell = controller.table.view(atColumn: 2, row: row, makeIfNecessary: true)!
            return cell.subviews.compactMap { $0 as? FishActionButton }.first { $0.title == title }!
        }
        func deleteButton(_ identity: FishIdentity) -> FishActionButton { actionButton(identity, title: "删除") }
        func respond(_ response: NSApplication.ModalResponse) {
            let sheet = controller.window!.attachedSheet!
            controller.window!.endSheet(sheet, returnCode: response)
            settle()
        }
        func editField(_ view: NSView) -> NSTextField? {
            if let field = view as? NSTextField, field.isEditable { return field }
            return view.subviews.compactMap { editField($0) }.first
        }
        actionButton(.builtIn(4), title: "改名").performClick(nil)
        let defaultField = editField(controller.window!.attachedSheet!.contentView!)!
        check(defaultField.stringValue.isEmpty && defaultField.placeholderString == "锦鲤 05", "rename starts with current name or default placeholder")
        defaultField.stringValue = "小黄"
        respond(.alertSecondButtonReturn)
        check(controller.fish.first { $0.identity == .builtIn(4) }?.displayName == "锦鲤 05", "cancel rename preserves name")
        actionButton(.builtIn(4), title: "改名").performClick(nil)
        editField(controller.window!.attachedSheet!.contentView!)!.stringValue = "小黄"
        respond(.alertFirstButtonReturn)
        check(controller.fish.first { $0.identity == .builtIn(4) }?.displayName == "小黄", "default rename updates list")
        actionButton(.custom(blue.id), title: "改名").performClick(nil)
        check(editField(controller.window!.attachedSheet!.contentView!)!.stringValue == "小蓝", "rename pre-fills saved custom name")
        editField(controller.window!.attachedSheet!.contentView!)!.stringValue = "小锦 🐟"
        respond(.alertFirstButtonReturn)
        check(controller.fish[1].displayName == controller.fish[0].displayName && controller.fish[1].identity != controller.fish[0].identity,
              "same names preserve independent identities")
        reject = true
        actionButton(.custom(blue.id), title: "改名").performClick(nil)
        editField(controller.window!.attachedSheet!.contentView!)!.stringValue = "未保存"
        respond(.alertFirstButtonReturn)
        check(controller.fish[1].displayName == "小锦 🐟" && controller.window!.attachedSheet != nil, "rename failure retains old name and explains failure")
        respond(.alertFirstButtonReturn)
        reject = false
        actionButton(.custom(blue.id), title: "改名").performClick(nil)
        editField(controller.window!.attachedSheet!.contentView!)!.stringValue = ""
        respond(.alertFirstButtonReturn)
        check(controller.fish[1].displayName == FishIdentity.custom(blue.id).name, "cleared name returns to fixed identifier")
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
        simulation.addCustomFish(appearanceID: UUID(), name: String(repeating: "很长的鱼名字", count: 30))
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
        controller.table.scrollRowToVisible(1)
        controller.window!.layoutIfNeeded()
        settle()
        let longNameCell = controller.table.view(atColumn: 1, row: 1, makeIfNecessary: true) as! NSTableCellView
        longNameCell.layoutSubtreeIfNeeded()
        check(longNameCell.textField!.frame.maxX <= longNameCell.bounds.maxX + 1,
              "long names fit the name column without hiding deletion")
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
