import AppKit

private enum WindowTestError: Error { case rejected }

private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fatalError(message) }
}

private func mouse(_ canvas: FishDrawingCanvas, _ type: NSEvent.EventType, x: CGFloat, y: CGFloat) {
    let location = canvas.convert(NSPoint(x: canvas.bounds.width * x, y: canvas.bounds.height * (1 - y)), to: nil)
    let event = NSEvent.mouseEvent(with: type, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                   windowNumber: canvas.window!.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    switch type {
    case .leftMouseDown: canvas.mouseDown(with: event)
    case .leftMouseDragged: canvas.mouseDragged(with: event)
    case .leftMouseUp: canvas.mouseUp(with: event)
    default: fatalError("unsupported event")
    }
}

private func paint(_ canvas: FishDrawingCanvas, x: CGFloat = 0.5, y: CGFloat = 0.5) {
    mouse(canvas, .leftMouseDown, x: x, y: y)
    mouse(canvas, .leftMouseDragged, x: x + 0.05, y: y)
    mouse(canvas, .leftMouseUp, x: x + 0.05, y: y)
}

@main
struct DrawingWindowTests {
    static func main() {
        _ = NSApplication.shared
        var submitted: FishDrawing?
        var attempts = 0
        let controller = FishDrawingWindowController { drawing in
            attempts += 1
            if attempts == 1 { throw WindowTestError.rejected }
            submitted = drawing
        }
        controller.showWindow(nil)
        controller.window!.layoutIfNeeded()
        check(controller.canvas.bounds.width > 600, "canvas layout")
        let red = controller.paletteButtons[0]
        let blue = controller.paletteButtons[3]
        let white = controller.paletteButtons.first { $0.toolTip == "白色" }!
        let baseWhite = controller.basePaletteButtons.first { $0.toolTip == "白色" }!
        let baseBlue = controller.basePaletteButtons.first { $0.toolTip == "蓝色" }!
        let baseGreen = controller.basePaletteButtons.first { $0.toolTip == "绿色" }!
        check(baseWhite.isSelected, "white base preset selected initially")
        let root = controller.window!.contentView!
        for control in controller.paletteButtons + controller.basePaletteButtons + [controller.addButton!, controller.clearButton!] {
            check(root.bounds.contains(control.convert(control.bounds, to: root)), "palette and actions stay inside window")
        }
        let brushRow = red.superview!.superview!
        let baseRow = baseWhite.superview!.superview!
        let actionRow = controller.eraseButton.superview!
        check(!brushRow.convert(brushRow.bounds, to: root).intersects(baseRow.convert(baseRow.bounds, to: root)), "palettes have separate rows")
        check(!baseRow.convert(baseRow.bounds, to: root).intersects(actionRow.convert(actionRow.bounds, to: root)), "base palette does not overlap actions")
        let redBitmap = red.bitmapImageRepForCachingDisplay(in: red.bounds)!
        let blueBitmap = blue.bitmapImageRepForCachingDisplay(in: blue.bounds)!
        red.cacheDisplay(in: red.bounds, to: redBitmap)
        blue.cacheDisplay(in: blue.bounds, to: blueBitmap)
        let redCenter = redBitmap.colorAt(x: redBitmap.pixelsWide / 2, y: redBitmap.pixelsHigh / 2)!.usingColorSpace(.deviceRGB)!
        let blueCenter = blueBitmap.colorAt(x: blueBitmap.pixelsWide / 2, y: blueBitmap.pixelsHigh / 2)!.usingColorSpace(.deviceRGB)!
        check(redCenter.redComponent > redCenter.blueComponent + 0.3, "red swatch visibly filled")
        check(blueCenter.blueComponent > blueCenter.redComponent + 0.3, "blue swatch visibly filled")
        paint(controller.canvas)
        check(controller.drawing.strokes.count == 1, "paint commits a stroke")
        check(controller.drawing.strokes[0].points.count == 2, "drag records both points")
        check(abs(controller.drawing.strokes[0].points[0].x - 0.5) < 0.01, "canvas stores normalized UV")
        check(controller.undoButton.isEnabled, "undo enabled after paint")

        controller.undoButton.performClick(nil)
        check(controller.drawing.strokes.isEmpty, "undo removes paint")
        check(!controller.undoButton.isEnabled, "undo disabled when empty")

        controller.eraseButton.performClick(nil)
        paint(controller.canvas)
        check(controller.drawing.strokes.last!.erasing, "eraser commits clear stroke")
        controller.undoButton.performClick(nil)
        check(controller.drawing.strokes.isEmpty, "undo removes eraser stroke")
        controller.eraseButton.performClick(nil)
        paint(controller.canvas)
        check(!controller.drawing.strokes.last!.erasing, "paint works after eraser")

        mouse(controller.canvas, .leftMouseDown, x: 0.5, y: 0.5)
        mouse(controller.canvas, .leftMouseDragged, x: 0.6, y: 0.5)
        mouse(controller.canvas, .leftMouseDragged, x: 1.1, y: 0.5)
        mouse(controller.canvas, .leftMouseDragged, x: 0.5, y: 0.5)
        mouse(controller.canvas, .leftMouseUp, x: 0.5, y: 0.5)
        check(controller.drawing.strokes.count == 3, "leave and reenter makes separate strokes")
        check(controller.drawing.strokes[2].points.count == 1, "reentry begins with dot and no connecting line")

        controller.clearButton.performClick(nil)
        check(controller.drawing.strokes.isEmpty, "clear removes all strokes")
        controller.eraseButton.performClick(nil)
        baseBlue.performClick(nil)
        check(controller.eraseButton.state == .on, "base preset leaves brush tool unchanged")
        check(baseBlue.isSelected && !baseWhite.isSelected, "base preset updates selection ring")
        check(controller.baseColorWell.color == baseBlue.swatchColor, "base preset updates custom color well")
        white.performClick(nil)
        paint(controller.canvas)
        check(controller.drawing.strokes[0].color == FishColor(red: 1, green: 1, blue: 1), "white preset paints white")
        check(!controller.drawing.strokes[0].erasing && controller.eraseButton.state == .off, "white preset exits eraser")
        let whiteBitmap = controller.canvas.bitmapImageRepForCachingDisplay(in: controller.canvas.bounds)!
        controller.canvas.cacheDisplay(in: controller.canvas.bounds, to: whiteBitmap)
        let whitePixel = whiteBitmap.colorAt(x: whiteBitmap.pixelsWide / 2, y: whiteBitmap.pixelsHigh / 2)!.usingColorSpace(.deviceRGB)!
        check(whitePixel.redComponent > 0.95 && whitePixel.greenComponent > 0.95 && whitePixel.blueComponent > 0.95, "white paint covers colored fish")
        let paintedStrokes = controller.drawing.strokes
        baseGreen.performClick(nil)
        check(controller.drawing.strokes == paintedStrokes && white.isSelected, "base preset preserves strokes and brush selection")
        check(controller.drawing.resolvedBaseColor.green > controller.drawing.resolvedBaseColor.blue, "green base preset changes fish color")
        controller.clearButton.performClick(nil)
        check(baseGreen.isSelected && controller.drawing.resolvedBaseColor == controller.canvas.baseColor, "clear retains selected base")
        controller.baseColorWell.color = NSColor(calibratedRed: 0.1, green: 0.3, blue: 0.85, alpha: 1)
        _ = controller.baseColorWell.target?.perform(controller.baseColorWell.action, with: controller.baseColorWell)
        check(!controller.basePaletteButtons.contains { $0.isSelected }, "custom base clears preset selection")
        let bodyBlue = controller.drawing.resolvedBaseColor
        check(bodyBlue.blue > 0.7 && controller.canvas.baseColor == bodyBlue, "base selection updates draft and canvas")
        let canvasBitmap = controller.canvas.bitmapImageRepForCachingDisplay(in: controller.canvas.bounds)!
        controller.canvas.cacheDisplay(in: controller.canvas.bounds, to: canvasBitmap)
        let bodyPixel = canvasBitmap.colorAt(x: canvasBitmap.pixelsWide / 2, y: canvasBitmap.pixelsHigh / 2)!.usingColorSpace(.deviceRGB)!
        check(bodyPixel.blueComponent > bodyPixel.redComponent + 0.3, "base selection visibly recolors fish")
        controller.widthSlider.doubleValue = 0.05
        controller.colorWell.color = NSColor(calibratedRed: 0.2, green: 0.4, blue: 0.6, alpha: 1)
        _ = controller.colorWell.target?.perform(controller.colorWell.action, with: controller.colorWell)
        check(!controller.paletteButtons.contains { $0.isSelected }, "custom brush clears preset selection")
        paint(controller.canvas)
        controller.baseColorWell.color = NSColor(calibratedRed: 0.2, green: 0.8, blue: 0.15, alpha: 1)
        _ = controller.baseColorWell.target?.perform(controller.baseColorWell.action, with: controller.baseColorWell)
        let bodyGreen = controller.drawing.resolvedBaseColor
        check(controller.drawing.strokes.count == 1 && bodyGreen.green > 0.7, "changing base keeps painted strokes")
        check(abs(controller.drawing.strokes[0].width - 0.05) < 0.001, "width slider changes brush width")
        let expectedBlue = Float(controller.colorWell.color.usingColorSpace(.deviceRGB)!.blueComponent)
        check(abs(controller.drawing.strokes[0].color.blue - expectedBlue) < 0.01, "custom color changes paint")
        controller.nameField.stringValue = "  小锦 🐟  "
        controller.addButton.performClick(nil)
        check(attempts == 1, "add invokes callback")
        check(controller.drawing.strokes.count == 1, "callback failure preserves draft")
        check(controller.drawing.resolvedBaseColor == bodyGreen, "callback failure preserves base color")
        check(controller.drawing.name == "小锦 🐟" && controller.nameField.stringValue == "  小锦 🐟  ", "callback failure preserves typed name")
        if let sheet = controller.window!.attachedSheet { controller.window!.endSheet(sheet) }
        controller.addButton.performClick(nil)
        check(attempts == 2, "retry invokes callback")
        check(submitted?.strokes.count == 1, "retry submits preserved draft")
        check(submitted?.resolvedBaseColor == bodyGreen, "add submits selected base color")
        check(submitted?.name == "小锦 🐟", "add submits trimmed Unicode name")
        check(controller.nameField.stringValue.isEmpty && controller.drawing.name == nil, "new fish resets name")
        check(controller.drawing.strokes.isEmpty, "success resets next draft")
        check(controller.drawing.resolvedBaseColor == FishColor(red: 1, green: 1, blue: 1)
              && controller.canvas.baseColor == controller.drawing.resolvedBaseColor, "new fish resets base to white")
        check(baseWhite.isSelected && controller.basePaletteButtons.filter { $0.isSelected }.count == 1, "new fish resets white base selection ring")

        controller.showWindow(nil)
        controller.nameField.stringValue = "取消的草稿"
        paint(controller.canvas)
        controller.cancelButton.performClick(nil)
        controller.showWindow(nil)
        check(controller.drawing.strokes.isEmpty, "cancel/close resets draft")
        check(controller.nameField.stringValue.isEmpty, "cancel clears draft name")
        paint(controller.canvas)
        mouse(controller.canvas, .leftMouseDown, x: 0.5, y: 0.5)
        mouse(controller.canvas, .leftMouseDragged, x: 0.55, y: 0.5)
        check(controller.canvas.activeStroke != nil, "drag has transient ink")
        controller.clearButton.performClick(nil)
        check(controller.canvas.activeStroke == nil, "clear removes transient ink")
        mouse(controller.canvas, .leftMouseUp, x: 0.55, y: 0.5)
        check(controller.drawing.strokes.isEmpty, "clear prevents pending drag commit")
        mouse(controller.canvas, .leftMouseDown, x: 0.5, y: 0.5)
        mouse(controller.canvas, .leftMouseDragged, x: 0.55, y: 0.5)
        controller.cancelButton.performClick(nil)
        controller.showWindow(nil)
        check(controller.canvas.activeStroke == nil, "reopen has no transient ink")
        check(controller.drawing.strokes.isEmpty, "reopen has no committed ink")
        paint(controller.canvas)
        check(controller.drawing.strokes.count == 1, "new stroke independent after reopen")
        controller.nameField.stringValue = "  \n  "
        controller.addButton.performClick(nil)
        check(submitted?.name == nil, "blank name is optional")
        print("DrawingWindowTests passed")
    }
}
