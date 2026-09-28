import AppKit

final class FishPaletteButton: NSButton {
    var swatchColor: NSColor = .red { didSet { needsDisplay = true } }
    var isSelected = false { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        let circle = bounds.insetBy(dx: 3, dy: 3)
        swatchColor.setFill()
        NSBezierPath(ovalIn: circle).fill()
        (isSelected ? NSColor.labelColor : NSColor.separatorColor).setStroke()
        let outline = NSBezierPath(ovalIn: circle.insetBy(dx: isSelected ? -2 : 0, dy: isSelected ? -2 : 0))
        outline.lineWidth = isSelected ? 2 : 1
        outline.stroke()
    }
}

final class FishDrawingWindowController: NSWindowController, NSWindowDelegate {
    private let onAdd: (FishDrawing) throws -> Void
    private(set) var drawing = FishDrawing(id: UUID(), strokes: [])
    private(set) var canvas: FishDrawingCanvas!
    private(set) var nameField: NSTextField!
    private(set) var colorWell: NSColorWell!
    private(set) var baseColorWell: NSColorWell!
    private(set) var widthSlider: NSSlider!
    private(set) var eraseButton: NSButton!
    private(set) var undoButton: NSButton!
    private(set) var clearButton: NSButton!
    private(set) var cancelButton: NSButton!
    private(set) var addButton: NSButton!
    private(set) var paletteButtons: [FishPaletteButton] = []
    private(set) var basePaletteButtons: [FishPaletteButton] = []
    private var selectedColor = NSColor.systemRed
    private var erasing = false

    init(onAdd: @escaping (FishDrawing) throws -> Void) {
        self.onAdd = onAdd
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 600),
                              styleMask: [.titled, .closable, .miniaturizable],
                              backing: .buffered, defer: false)
        window.title = "画一条锦鲤"
        window.center()
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        buildContent(in: window)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(sender)
    }

    private func buildContent(in window: NSWindow) {
        let root = NSView(frame: window.contentView!.bounds)
        root.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = root

        let title = NSTextField(labelWithString: "画一条自己的锦鲤")
        title.font = .systemFont(ofSize: 21, weight: .semibold)
        let hint = NSTextField(labelWithString: "选择鱼身底色，再画上花纹；鱼鳍和眼睛会保留。")
        hint.font = .systemFont(ofSize: 12)
        hint.textColor = .secondaryLabelColor
        let heading = NSStackView(views: [title, hint])
        heading.orientation = .vertical
        heading.alignment = .leading
        heading.spacing = 5

        let nameLabel = NSTextField(labelWithString: "名字")
        nameLabel.font = .systemFont(ofSize: 12)
        nameField = NSTextField(string: "")
        nameField.placeholderString = "给它起个名字（选填）"
        nameField.setAccessibilityLabel("鱼的名字")
        nameField.widthAnchor.constraint(equalToConstant: 200).isActive = true
        let nameTools = NSStackView(views: [nameLabel, nameField!])
        nameTools.orientation = .horizontal
        nameTools.alignment = .centerY
        nameTools.spacing = 10

        canvas = FishDrawingCanvas(frame: .zero)
        canvas.translatesAutoresizingMaskIntoConstraints = false
        canvas.setAccessibilityLabel("锦鲤绘画画布")
        canvas.onStroke = { [weak self] stroke in
            self?.drawing.strokes.append(stroke)
            self?.updateButtons()
        }
        canvas.currentTool = { [weak self] in
            guard let self else { return nil }
            let color = self.selectedColor.usingColorSpace(.deviceRGB) ?? .red
            return (FishColor(red: Float(color.redComponent), green: Float(color.greenComponent), blue: Float(color.blueComponent)),
                    Float(self.widthSlider.doubleValue), self.erasing)
        }
        canvas.strokes = drawing.strokes

        let (palette, brushButtons) = makePalette([
            ("红色", .systemRed), ("橙色", .systemOrange), ("黄色", .systemYellow),
            ("蓝色", .systemBlue), ("黑色", .black), ("白色", .white),
            ("绿色", .systemGreen), ("青色", .systemTeal), ("紫色", .systemPurple),
            ("粉色", .systemPink), ("棕色", .systemBrown), ("灰色", .systemGray)
        ], label: "画笔", action: #selector(selectPalette(_:)))
        paletteButtons = brushButtons
        colorWell = NSColorWell(frame: NSRect(x: 0, y: 0, width: 40, height: 28))
        colorWell.color = selectedColor
        colorWell.target = self
        colorWell.action = #selector(selectCustomColor(_:))
        colorWell.setAccessibilityLabel("画笔颜色")
        colorWell.toolTip = "自选画笔颜色"
        palette.addArrangedSubview(colorWell)

        widthSlider = NSSlider(value: 0.025, minValue: 0.008, maxValue: 0.075, target: self, action: nil)
        widthSlider.setAccessibilityLabel("笔触粗细")
        widthSlider.widthAnchor.constraint(equalToConstant: 130).isActive = true
        let widthLabel = NSTextField(labelWithString: "粗细")
        widthLabel.font = .systemFont(ofSize: 12)

        eraseButton = makeButton("橡皮", action: #selector(toggleEraser(_:)))
        eraseButton.setButtonType(.toggle)
        eraseButton.setAccessibilityLabel("橡皮擦")
        undoButton = makeButton("撤销", action: #selector(undo(_:)))
        undoButton.keyEquivalent = "z"
        undoButton.keyEquivalentModifierMask = .command
        clearButton = makeButton("清空", action: #selector(clear(_:)))
        let brushLabel = NSTextField(labelWithString: "画笔颜色")
        brushLabel.font = .systemFont(ofSize: 12)
        let brushTools = NSStackView(views: [brushLabel, palette])
        brushTools.orientation = .horizontal
        brushTools.alignment = .centerY
        brushTools.spacing = 12
        let tools = NSStackView(views: [widthLabel, widthSlider, eraseButton, undoButton, clearButton])
        tools.orientation = .horizontal
        tools.alignment = .centerY
        tools.spacing = 12

        cancelButton = makeButton("取消", action: #selector(cancel(_:)))
        cancelButton.keyEquivalent = "\u{1b}"
        addButton = makeButton("加入池塘", action: #selector(addToPond(_:)))
        addButton.bezelStyle = .rounded
        addButton.keyEquivalent = "\r"
        let footer = NSStackView(views: [cancelButton, addButton])
        footer.orientation = .horizontal
        footer.spacing = 10
        footer.alignment = .centerY

        baseColorWell = NSColorWell(frame: NSRect(x: 0, y: 0, width: 40, height: 28))
        baseColorWell.color = .white
        baseColorWell.target = self
        baseColorWell.action = #selector(selectBaseColor(_:))
        baseColorWell.setAccessibilityLabel("鱼身底色")
        baseColorWell.toolTip = "自选鱼身底色"
        let (basePalette, bodyButtons) = makePalette([
            ("白色", .white), ("黄色", .systemYellow), ("橙色", .systemOrange),
            ("红色", .systemRed), ("粉色", .systemPink), ("绿色", .systemGreen),
            ("蓝色", .systemBlue), ("黑色", .black)
        ], label: "底色", action: #selector(selectBasePalette(_:)))
        basePaletteButtons = bodyButtons
        basePalette.addArrangedSubview(baseColorWell)
        let baseLabel = NSTextField(labelWithString: "鱼身底色")
        baseLabel.font = .systemFont(ofSize: 12)
        let baseTools = NSStackView(views: [baseLabel, basePalette])
        baseTools.orientation = .horizontal
        baseTools.alignment = .centerY
        baseTools.spacing = 12

        for view in [heading, nameTools, canvas!, brushTools, tools, baseTools, footer] {
            view.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(view)
        }
        NSLayoutConstraint.activate([
            heading.topAnchor.constraint(equalTo: root.topAnchor, constant: 22),
            heading.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 28),
            nameTools.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -28),
            nameTools.centerYAnchor.constraint(equalTo: heading.centerYAnchor),
            canvas.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 17),
            canvas.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 28),
            canvas.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -28),
            canvas.heightAnchor.constraint(equalToConstant: 338),
            brushTools.topAnchor.constraint(equalTo: canvas.bottomAnchor, constant: 15),
            brushTools.leadingAnchor.constraint(equalTo: canvas.leadingAnchor),
            tools.leadingAnchor.constraint(equalTo: canvas.leadingAnchor),
            tools.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
            baseTools.leadingAnchor.constraint(equalTo: canvas.leadingAnchor),
            baseTools.topAnchor.constraint(equalTo: brushTools.bottomAnchor, constant: 8),
            footer.trailingAnchor.constraint(equalTo: canvas.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -19)
        ])
        updateButtons()
    }

    private func makePalette(_ colors: [(String, NSColor)], label: String, action: Selector) -> (NSStackView, [FishPaletteButton]) {
        let palette = NSStackView()
        palette.orientation = .horizontal
        palette.spacing = 7
        let buttons = colors.enumerated().map { index, entry in
            let button = FishPaletteButton(frame: NSRect(x: 0, y: 0, width: 28, height: 28))
            button.title = ""
            button.isBordered = false
            button.swatchColor = entry.1
            button.isSelected = index == 0
            button.target = self
            button.action = action
            button.setAccessibilityLabel("\(label)：\(entry.0)")
            button.toolTip = entry.0
            button.widthAnchor.constraint(equalToConstant: 28).isActive = true
            button.heightAnchor.constraint(equalToConstant: 28).isActive = true
            palette.addArrangedSubview(button)
            return button
        }
        return (palette, buttons)
    }

    private func makeButton(_ title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        return button
    }

    @objc private func selectPalette(_ sender: FishPaletteButton) {
        selectedColor = sender.swatchColor
        colorWell.color = selectedColor
        erasing = false
        updateButtons()
        for button in paletteButtons {
            button.isSelected = button === sender
        }
    }

    @objc private func selectCustomColor(_ sender: NSColorWell) {
        selectedColor = sender.color
        erasing = false
        updateButtons()
        for button in paletteButtons {
            button.isSelected = false
        }
    }

    @objc private func selectBaseColor(_ sender: NSColorWell) {
        guard let color = sender.color.usingColorSpace(.deviceRGB) else { return }
        drawing.baseColor = FishColor(red: Float(color.redComponent), green: Float(color.greenComponent), blue: Float(color.blueComponent))
        canvas.baseColor = drawing.resolvedBaseColor
        for button in basePaletteButtons {
            button.isSelected = false
        }
    }

    @objc private func selectBasePalette(_ sender: FishPaletteButton) {
        baseColorWell.color = sender.swatchColor
        selectBaseColor(baseColorWell)
        sender.isSelected = true
    }

    @objc private func toggleEraser(_ sender: Any?) {
        erasing.toggle()
        updateButtons()
    }

    @objc private func undo(_ sender: Any?) {
        guard !drawing.strokes.isEmpty else { return }
        drawing.strokes.removeLast()
        canvas.strokes = drawing.strokes
        updateButtons()
    }

    @objc private func clear(_ sender: Any?) {
        drawing.strokes.removeAll()
        canvas.resetActiveStroke()
        canvas.strokes = []
        updateButtons()
    }

    @objc private func cancel(_ sender: Any?) { window?.close() }

    @objc private func addToPond(_ sender: Any?) {
        window?.makeFirstResponder(nil)
        let name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        drawing.name = name.isEmpty ? nil : name
        do {
            try onAdd(drawing)
            window?.close()
        } catch {
            guard let window else { return }
            NSAlert(error: error).beginSheetModal(for: window)
        }
    }

    private func updateButtons() {
        undoButton?.isEnabled = !drawing.strokes.isEmpty
        clearButton?.isEnabled = !drawing.strokes.isEmpty
        eraseButton?.state = erasing ? .on : .off
        canvas?.strokes = drawing.strokes
    }

    func windowWillClose(_ notification: Notification) {
        drawing = FishDrawing(id: UUID(), strokes: [])
        nameField.stringValue = ""
        baseColorWell.color = .white
        for (index, button) in basePaletteButtons.enumerated() {
            button.isSelected = index == 0
        }
        canvas.baseColor = drawing.resolvedBaseColor
        canvas.resetActiveStroke()
        erasing = false
        updateButtons()
    }
}

final class FishDrawingCanvas: NSView {
    var baseColor = FishColor(red: 1, green: 1, blue: 1) { didSet { inkLayer = nil; needsDisplay = true } }
    var strokes: [FishStroke] = [] {
        didSet {
            // Completing one stroke extends the cached layer. Undo, replacement and
            // clear rebuild from the authoritative editable stroke data.
            if strokes.count != oldValue.count + 1 || !strokes.starts(with: oldValue) { inkLayer = nil }
            needsDisplay = true
        }
    }
    private var inkLayer: CGLayer?
    private var inkSize = CGSize.zero
    private var inkScale = CGSize.zero
    private var cachedStrokeCount = 0
    private(set) var inkCacheRebuilds = 0
    var onStroke: ((FishStroke) -> Void)?
    var currentTool: (() -> (FishColor, Float, Bool)?)?
    private(set) var activeStroke: FishStroke?
    private var bodyPath: CGPath?
    private var finPaths: [CGPath] = []
    private var bodySize = CGSize.zero
    private var leftCanvas = false
    private var dragTool: (FishColor, Float, Bool)?

    override var acceptsFirstResponder: Bool { true }

    func resetActiveStroke() {
        activeStroke = nil
        dragTool = nil
        leftCanvas = false
        needsDisplay = true
    }

    private func cachedBodyPath() -> CGPath {
        if bodyPath == nil || bodySize != bounds.size {
            bodyPath = FishDrawing.bodyPath(width: Int(bounds.width), height: Int(bounds.height))
            let finOutlines = (0..<3).map { _ in CGMutablePath() }
            let vertices = FishMesh(species: .koi).vertices
            for index in stride(from: 0, to: vertices.count, by: 3) {
                let material = Int(vertices[index].detail.x)
                guard (1...3).contains(material) else { continue }
                let path = finOutlines[material - 1]
                for offset in 0..<3 {
                    let vertex = vertices[index + offset].position
                    let point = CGPoint(x: CGFloat((vertex.x + 0.6) / 1.2) * bounds.width,
                                        y: CGFloat((vertex.y + 0.3) / 0.6) * bounds.height)
                    if offset == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
                path.closeSubpath()
            }
            finPaths = finOutlines
            bodySize = bounds.size
        }
        return bodyPath!
    }

    private func imagePoint(_ point: FishPoint) -> CGPoint {
        CGPoint(x: CGFloat(point.x) * bounds.width, y: (1 - CGFloat(point.y)) * bounds.height)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext, bounds.width > 0, bounds.height > 0 else { return }
        let rect = bounds
        context.setFillColor(NSColor(calibratedRed: 0.09, green: 0.25, blue: 0.21, alpha: 1).cgColor)
        context.fill(rect)
        drawFins(in: context)
        let path = cachedBodyPath()
        context.addPath(path)
        context.setFillColor(CGColor(red: CGFloat(baseColor.red), green: CGFloat(baseColor.green), blue: CGFloat(baseColor.blue), alpha: 1))
        context.fillPath()
        context.saveGState()
        context.addPath(path)
        context.clip()
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        drawCompletedStrokes(in: context)
        if let activeStroke { draw(activeStroke, in: context) }
        context.endTransparencyLayer()
        context.restoreGState()
        context.addPath(path)
        context.setStrokeColor(NSColor(calibratedWhite: 0.67, alpha: 1).cgColor)
        context.setLineWidth(1)
        context.strokePath()
        drawEyes(in: context)
    }

    private func drawCompletedStrokes(in context: CGContext) {
        let transform = context.ctm
        let scale = CGSize(width: hypot(transform.a, transform.b), height: hypot(transform.c, transform.d))
        if inkLayer == nil || inkSize != bounds.size || inkScale != scale {
            inkLayer = CGLayer(context, size: bounds.size, auxiliaryInfo: nil)
            inkSize = bounds.size
            inkScale = scale
            cachedStrokeCount = 0
            inkCacheRebuilds += 1
        }
        guard let inkLayer, let ink = inkLayer.context else {
            for stroke in strokes { draw(stroke, in: context) }
            return
        }
        for stroke in strokes.dropFirst(cachedStrokeCount) { draw(stroke, in: ink) }
        cachedStrokeCount = strokes.count
        // Keep cached and active ink inside one transparency layer: an active
        // eraser clears old ink and reveals the current body color beneath it.
        context.draw(inkLayer, at: .zero)
    }

    private func draw(_ stroke: FishStroke, in context: CGContext) {
        guard let first = stroke.points.first else { return }
        context.setBlendMode(stroke.erasing ? .clear : .normal)
        context.setStrokeColor(CGColor(red: CGFloat(stroke.color.red), green: CGFloat(stroke.color.green), blue: CGFloat(stroke.color.blue), alpha: 1))
        context.setFillColor(CGColor(red: CGFloat(stroke.color.red), green: CGFloat(stroke.color.green), blue: CGFloat(stroke.color.blue), alpha: 1))
        let width = CGFloat(stroke.width) * bounds.height
        context.setLineWidth(width)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        if stroke.points.count == 1 {
            let point = imagePoint(first)
            context.fillEllipse(in: CGRect(x: point.x - width / 2, y: point.y - width / 2, width: width, height: width))
        } else {
            context.beginPath()
            context.move(to: imagePoint(first))
            for point in stroke.points.dropFirst() { context.addLine(to: imagePoint(point)) }
            context.strokePath()
        }
        context.setBlendMode(.normal)
    }

    private func drawFins(in context: CGContext) {
        _ = cachedBodyPath()
        for (index, path) in finPaths.enumerated() {
            context.addPath(path)
            context.setFillColor(NSColor(calibratedWhite: 0.95, alpha: index == 2 ? 0.45 : 0.62).cgColor)
            context.fillPath()
        }
    }

    private func drawEyes(in context: CGContext) {
        for y: CGFloat in [0.395, 0.605] {
            let center = CGPoint(x: bounds.width * 0.775, y: bounds.height * (1 - y))
            let radius = max(3, bounds.height * 0.012)
            context.setFillColor(NSColor.black.cgColor)
            context.fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        }
    }

    private func point(from event: NSEvent) -> FishPoint? {
        let location = convert(event.locationInWindow, from: nil)
        guard bounds.contains(location), cachedBodyPath().contains(location) else { return nil }
        return FishPoint(x: Float(location.x / bounds.width), y: Float(1 - location.y / bounds.height))
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        guard let point = point(from: event), let tool = currentTool?() else { return }
        dragTool = tool
        activeStroke = FishStroke(points: [point], color: tool.0, width: tool.1, erasing: tool.2)
        leftCanvas = false
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let tool = dragTool else { return }
        guard let point = point(from: event) else {
            if !leftCanvas, let stroke = activeStroke {
                activeStroke = nil
                onStroke?(stroke)
            }
            leftCanvas = true
            needsDisplay = true
            return
        }
        if leftCanvas {
            activeStroke = FishStroke(points: [point], color: tool.0, width: tool.1, erasing: tool.2)
            leftCanvas = false
        } else if var stroke = activeStroke, stroke.points.last != point {
            stroke.points.append(point)
            activeStroke = stroke
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        let completed = activeStroke
        activeStroke = nil
        dragTool = nil
        leftCanvas = false
        if let completed { onStroke?(completed) }
        needsDisplay = true
    }
}
