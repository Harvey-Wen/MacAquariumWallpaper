import AppKit

@MainActor final class OceanAppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var desktop: DesktopController?
    private var statusItem: NSStatusItem?
    private var launchError: String?

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
            controller.start()
        } catch {
            launchError = "无法启动：\(error.localizedDescription)"
            NSLog("池塘：%@", error.localizedDescription)
        }
        rebuildMenu(menu)
    }

    func menuWillOpen(_ menu: NSMenu) { rebuildMenu(menu) }

    private func rebuildMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        let title = NSMenuItem(title: desktop?.status ?? launchError ?? "正在启动…", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())
        if let desktop {
            add(menu, "显示池塘", #selector(toggleEnabled), checked: desktop.enabled)
            add(menu, desktop.paused ? "继续游动" : "暂停游动", #selector(togglePaused))
            add(menu, "鼠标互动", #selector(toggleInteraction), checked: desktop.interactive)
            let weather = NSMenuItem(title: "天气", action: nil, keyEquivalent: "")
            let choices = NSMenu()
            for (title, value) in [("晴天", PondWeather.sunny), ("雨天", PondWeather.rainy)] {
                let option = NSMenuItem(title: title, action: #selector(setWeather(_:)), keyEquivalent: "")
                option.target = self; option.representedObject = value.rawValue
                option.state = desktop.weather == value ? .on : .off
                choices.addItem(option)
            }
            weather.submenu = choices; menu.addItem(weather)
            menu.addItem(.separator())
            let hint = NSMenuItem(title: "点击池水产生涟漪 · 附近锦鲤暂时散开", action: nil, keyEquivalent: "")
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
