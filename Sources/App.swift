import AppKit

@MainActor final class OceanAppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var desktop: DesktopController?
    private var statusItem: NSStatusItem?
    private var launchError: String?
    private var drawingWindow: FishDrawingWindowController?
    private var fishListWindow: FishListWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "fish", accessibilityDescription: "池塘")
        item.button?.toolTip = "池塘 · 锦鲤与水波"
        item.button?.setAccessibilityLabel("池塘")
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
        do {
            guard let shaderURL = Bundle.main.url(forResource: "Ocean", withExtension: "metal") else {
                throw NSError(domain: "Ocean", code: 2, userInfo: [NSLocalizedDescriptionKey: "缺少池塘渲染资源，请重新构建应用"])
            }
            let controller = try DesktopController(shaderURL: shaderURL)
            let args = CommandLine.arguments
            if let index = args.firstIndex(of: "--diagnostics"), args.indices.contains(index + 1) {
                controller.diagnosticURL = URL(fileURLWithPath: args[index + 1])
            }
            desktop = controller
            controller.onFishChanged = { [weak self] in self?.fishListWindow?.reload() }
            controller.weather = .rainy
            controller.start()
        } catch {
            launchError = "无法启动：\(error.localizedDescription)"
            NSLog("池塘：%@", error.localizedDescription)
        }
        rebuildMenu(menu)
    }

    func menuWillOpen(_ menu: NSMenu) { rebuildMenu(menu) }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showFishList()
        return false
    }

    private func rebuildMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        let title = NSMenuItem(title: desktop?.status ?? launchError ?? "正在启动…", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())
        if let desktop {
            add(menu, "画一条鱼…", #selector(drawFish), key: "n")
            add(menu, "鱼的列表…", #selector(showFishList), key: "l")
            if let error = desktop.defaultFishError {
                let warning = NSMenuItem(title: "默认鱼的删除记录未能载入", action: nil, keyEquivalent: "")
                warning.toolTip = error
                warning.isEnabled = false; menu.addItem(warning)
            }
            if !desktop.customFishErrors.isEmpty {
                let warning = NSMenuItem(title: "部分手绘鱼未能载入（\(desktop.customFishErrors.count)）", action: nil, keyEquivalent: "")
                warning.toolTip = desktop.customFishErrors.joined(separator: "\n")
                warning.isEnabled = false; menu.addItem(warning)
            }
            menu.addItem(.separator())
            add(menu, "显示池塘", #selector(toggleEnabled), checked: desktop.enabled)
            add(menu, desktop.paused ? "继续游动" : "暂停游动", #selector(togglePaused))
            add(menu, "鼠标互动", #selector(toggleInteraction), checked: desktop.interactive)
            let weather = NSMenuItem(title: "天气", action: nil, keyEquivalent: "")
            let choices = NSMenu()
            for value in PondWeather.allCases {
                let option = NSMenuItem(title: value.title, action: #selector(setWeather(_:)), keyEquivalent: "")
                option.target = self; option.representedObject = value.rawValue
                option.state = desktop.weather == value ? .on : .off
                choices.addItem(option)
            }
            weather.submenu = choices; menu.addItem(weather)
            menu.addItem(.separator())
            let hint = NSMenuItem(title: "滑过池水泛起轻波 · 点击会激起更明显的涟漪", action: nil, keyEquivalent: "")
            hint.isEnabled = false; menu.addItem(hint)
            if desktop.interactive {
                let unavailable = NSMenuItem(title: desktop.input.status, action: nil, keyEquivalent: "")
                unavailable.isEnabled = false; menu.addItem(unavailable)
            }
            menu.addItem(.separator())
        }
        add(menu, "退出池塘", #selector(quit), key: "q")
    }

    private func add(_ menu: NSMenu, _ title: String, _ action: Selector, checked: Bool = false, key: String = "") {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self; item.state = checked ? .on : .off; menu.addItem(item)
    }

    @objc private func toggleEnabled() { desktop?.enabled.toggle() }
    @objc private func drawFish() {
        guard let desktop else { return }
        if drawingWindow == nil {
            drawingWindow = FishDrawingWindowController(onAdd: desktop.addCustomFish)
        }
        drawingWindow?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc private func showFishList() {
        guard let desktop else { return }
        if fishListWindow == nil {
            fishListWindow = FishListWindowController(readFish: { desktop.simulation.fish },
                preview: desktop.renderer.fishPreview, onDelete: desktop.removeFish,
                onAdd: { [weak self] in self?.drawFish() })
        }
        fishListWindow?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc private func togglePaused() { desktop?.paused.toggle() }
    @objc private func toggleInteraction() { desktop?.interactive.toggle() }
    @objc private func setWeather(_ sender: NSMenuItem) {
        if let value = sender.representedObject as? String,
           let weather = PondWeather(rawValue: value) { desktop?.weather = weather }
    }
    @objc private func quit() { NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) { desktop?.stop() }
}

@main struct OceanApplication {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = OceanAppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
