import AppKit

final class FishDeleteButton: NSButton {
    var fishIdentity: FishIdentity?
}

final class FishListWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private let readFish: () -> [FishState]
    private let preview: (FishState) throws -> NSImage
    private let onDelete: (FishIdentity) throws -> Void
    private let onAdd: () -> Void
    private var previews: [FishIdentity: NSImage] = [:]
    private(set) var fish: [FishState] = []
    let table = NSTableView()
    let countLabel = NSTextField(labelWithString: "")
    let emptyLabel = NSTextField(labelWithString: "池塘里还没有鱼\n画一条喜欢的鱼，放进池塘吧。")
    let addButton = NSButton(title: "画一条鱼…", target: nil, action: nil)

    init(readFish: @escaping () -> [FishState], preview: @escaping (FishState) throws -> NSImage,
         onDelete: @escaping (FishIdentity) throws -> Void, onAdd: @escaping () -> Void) {
        self.readFish = readFish
        self.preview = preview
        self.onDelete = onDelete
        self.onAdd = onAdd
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 570),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "鱼的列表"
        window.minSize = NSSize(width: 560, height: 360)
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        buildContent(in: window)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func showWindow(_ sender: Any?) {
        reload()
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(sender)
    }

    func reload() {
        let current = readFish()
        fish = current.filter { $0.customAppearanceID != nil } + current.filter { $0.customAppearanceID == nil }
        let identities = Set(fish.map(\.identity))
        previews = previews.filter { identities.contains($0.key) }
        let custom = fish.filter { $0.customAppearanceID != nil }.count
        countLabel.stringValue = "共 \(fish.count) 条 · 默认锦鲤 \(fish.count - custom) 条 · 手绘鱼 \(custom) 条"
        emptyLabel.isHidden = !fish.isEmpty
        table.gridStyleMask = fish.isEmpty ? [] : .solidHorizontalGridLineMask
        table.reloadData()
    }

    private func buildContent(in window: NSWindow) {
        let content = NSView()
        window.contentView = content
        let heading = NSTextField(labelWithString: "池塘里的鱼")
        heading.font = .systemFont(ofSize: 22, weight: .semibold)
        countLabel.font = .systemFont(ofSize: 13)
        countLabel.textColor = .secondaryLabelColor
        let note = NSTextField(labelWithString: "按花纹找到想移除的鱼。删除后，重新启动也不会恢复。")
        note.font = .systemFont(ofSize: 12)
        note.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.font = .systemFont(ofSize: 15)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.maximumNumberOfLines = 2
        addButton.bezelStyle = .rounded
        addButton.target = self
        addButton.action = #selector(addFish)

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .bezelBorder
        table.headerView = nil
        table.rowHeight = 76
        table.intercellSpacing = NSSize(width: 8, height: 0)
        table.style = .fullWidth
        table.allowsColumnReordering = false
        table.dataSource = self
        table.delegate = self
        table.setAccessibilityLabel("池塘鱼列表")
        for (id, width) in [("preview", 148.0), ("name", 294.0), ("delete", 100.0)] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            column.width = width
            column.minWidth = id == "name" ? 220 : width
            column.resizingMask = id == "name" ? .autoresizingMask : []
            table.addTableColumn(column)
        }
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        scroll.documentView = table
        for view in [heading, countLabel, scroll, emptyLabel, note, addButton] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        NSLayoutConstraint.activate([
            heading.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            heading.topAnchor.constraint(equalTo: content.topAnchor, constant: 22),
            countLabel.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
            countLabel.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 8),
            scroll.topAnchor.constraint(equalTo: countLabel.bottomAnchor, constant: 20),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            scroll.bottomAnchor.constraint(equalTo: note.topAnchor, constant: -14),
            emptyLabel.centerXAnchor.constraint(equalTo: scroll.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scroll.centerYAnchor),
            note.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
            note.bottomAnchor.constraint(equalTo: addButton.topAnchor, constant: -12),
            addButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            addButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -18)
        ])
    }

    func numberOfRows(in tableView: NSTableView) -> Int { fish.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let item = fish[row]
        switch tableColumn?.identifier.rawValue {
        case "preview":
            let view = NSImageView()
            view.imageScaling = .scaleProportionallyDown
            if let image = previews[item.identity] { view.image = image }
            else {
                do {
                    let image = try preview(item)
                    previews[item.identity] = image
                    view.image = image
                } catch {
                    view.image = NSImage(systemSymbolName: "fish", accessibilityDescription: "预览暂不可用")
                    view.toolTip = "预览暂不可用：\(error.localizedDescription)"
                }
            }
            view.setAccessibilityLabel("\(item.identity.name)的外观")
            return view
        case "name":
            let name = NSTextField(labelWithString: item.identity.name)
            name.font = .systemFont(ofSize: 14, weight: .medium)
            let source = NSTextField(labelWithString: item.customAppearanceID == nil ? "默认锦鲤" : "手绘新增")
            source.font = .systemFont(ofSize: 12)
            source.textColor = .secondaryLabelColor
            let stack = NSStackView(views: [name, source])
            stack.orientation = .vertical
            stack.alignment = .leading
            stack.spacing = 5
            stack.edgeInsets = NSEdgeInsets(top: 16, left: 0, bottom: 16, right: 0)
            stack.toolTip = item.identity.storageKey
            return stack
        case "delete":
            let cell = NSView()
            let button = FishDeleteButton(title: "删除", target: self, action: #selector(deleteFish(_:)))
            button.bezelStyle = .rounded
            button.fishIdentity = item.identity
            button.contentTintColor = .systemRed
            button.setAccessibilityLabel("删除\(item.identity.name)")
            button.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(button)
            NSLayoutConstraint.activate([
                button.centerXAnchor.constraint(equalTo: cell.centerXAnchor),
                button.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
            return cell
        default: return nil
        }
    }

    @objc private func addFish() { onAdd() }

    @objc private func deleteFish(_ sender: FishDeleteButton) {
        guard let identity = sender.fishIdentity, fish.contains(where: { $0.identity == identity }),
              let window, window.attachedSheet == nil else { return }
        let alert = NSAlert()
        alert.messageText = "删除“\(identity.name)”？"
        alert.informativeText = "这条鱼会从池塘移除，重新启动后也不会恢复。"
        alert.addButton(withTitle: "删除").hasDestructiveAction = true
        alert.addButton(withTitle: "取消")
        alert.buttons[0].keyEquivalent = ""
        alert.buttons[1].keyEquivalent = "\r"
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            do {
                try self.onDelete(identity)
                self.reload()
            } catch {
                let failure = NSAlert()
                failure.messageText = "未能删除这条鱼"
                failure.informativeText = "鱼仍保留在池塘中。\n\(error.localizedDescription)"
                failure.addButton(withTitle: "好")
                failure.beginSheetModal(for: window)
            }
        }
    }
}
