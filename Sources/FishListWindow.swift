import AppKit

final class FishActionButton: NSButton {
    var fishIdentity: FishIdentity?
}

final class FishListWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private let readFish: () -> [FishState]
    private let preview: (FishState) throws -> NSImage
    private let onDelete: (FishIdentity) throws -> Void
    private let onRename: (FishIdentity, String) throws -> Void
    private let onAdd: () -> Void
    private var previews: [FishIdentity: NSImage] = [:]
    private(set) var fish: [FishState] = []
    let table = NSTableView()
    let countLabel = NSTextField(labelWithString: "")
    let emptyLabel = NSTextField(labelWithString: "池塘里还没有鱼\n画一条喜欢的鱼，放进池塘吧。")
    let addButton = NSButton(title: "画一条鱼…", target: nil, action: nil)

    init(readFish: @escaping () -> [FishState], preview: @escaping (FishState) throws -> NSImage,
         onDelete: @escaping (FishIdentity) throws -> Void,
         onRename: @escaping (FishIdentity, String) throws -> Void, onAdd: @escaping () -> Void) {
        self.readFish = readFish
        self.preview = preview
        self.onDelete = onDelete
        self.onRename = onRename
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
        let note = NSTextField(labelWithString: "名字可以随时修改。删除后，重新启动也不会恢复。")
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
        for (id, width) in [("preview", 140.0), ("name", 244.0), ("actions", 148.0)] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            column.width = width
            column.minWidth = id == "name" ? 180 : width
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
            view.setAccessibilityLabel("\(item.displayName)的外观")
            return view
        case "name":
            let cell = NSTableCellView()
            let name = NSTextField(labelWithString: item.displayName)
            name.font = .systemFont(ofSize: 14, weight: .medium)
            name.lineBreakMode = .byTruncatingTail
            name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            let source = NSTextField(labelWithString: item.customAppearanceID == nil ? "默认锦鲤" : "手绘新增 · \(item.identity.storageKey.prefix(8))")
            source.font = .systemFont(ofSize: 12)
            source.textColor = .secondaryLabelColor
            cell.textField = name
            for label in [name, source] {
                label.translatesAutoresizingMaskIntoConstraints = false
                cell.addSubview(label)
                label.leadingAnchor.constraint(equalTo: cell.leadingAnchor).isActive = true
                label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8).isActive = true
            }
            NSLayoutConstraint.activate([
                name.centerYAnchor.constraint(equalTo: cell.centerYAnchor, constant: -11),
                source.topAnchor.constraint(equalTo: name.bottomAnchor, constant: 5)
            ])
            cell.toolTip = "\(item.displayName)\n\(item.identity.storageKey)"
            return cell
        case "actions":
            let cell = NSView()
            let rename = FishActionButton(title: "改名", target: self, action: #selector(renameFish(_:)))
            let delete = FishActionButton(title: "删除", target: self, action: #selector(deleteFish(_:)))
            for button in [rename, delete] {
                button.bezelStyle = .rounded
                button.fishIdentity = item.identity
                button.setAccessibilityLabel("\(button.title)\(item.displayName)")
                button.translatesAutoresizingMaskIntoConstraints = false
                cell.addSubview(button)
                button.centerYAnchor.constraint(equalTo: cell.centerYAnchor).isActive = true
            }
            NSLayoutConstraint.activate([
                rename.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                delete.leadingAnchor.constraint(equalTo: rename.trailingAnchor, constant: 6)
            ])
            return cell
        default: return nil
        }
    }

    @objc private func addFish() { onAdd() }

    @objc private func renameFish(_ sender: FishActionButton) {
        guard let identity = sender.fishIdentity, let item = fish.first(where: { $0.identity == identity }),
              let window, window.attachedSheet == nil else { return }
        let alert = NSAlert()
        alert.messageText = "给这条鱼改名"
        alert.informativeText = "修改后会自动保存。留空可恢复为默认编号。"
        let field = NSTextField(string: item.name ?? "")
        field.placeholderString = item.identity.name
        field.setAccessibilityLabel("鱼的名字")
        field.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "取消")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            do {
                try self.onRename(identity, field.stringValue)
                self.reload()
            } catch { self.showError("未能修改名字", message: "原来的名字仍然保留。\n\(error.localizedDescription)") }
        }
        alert.window.makeFirstResponder(field)
        field.selectText(nil)
    }

    private func showError(_ title: String, message: String) {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "好")
        alert.beginSheetModal(for: window)
    }

    @objc private func deleteFish(_ sender: FishActionButton) {
        guard let identity = sender.fishIdentity, let item = fish.first(where: { $0.identity == identity }),
              let window, window.attachedSheet == nil else { return }
        let alert = NSAlert()
        let name = String(item.displayName.prefix(80)) + (item.displayName.count > 80 ? "…" : "")
        alert.messageText = "删除“\(name)”？"
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
                self.showError("未能删除这条鱼", message: "鱼仍保留在池塘中。\n\(error.localizedDescription)")
            }
        }
    }
}
