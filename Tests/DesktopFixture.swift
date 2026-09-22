import AppKit

@MainActor final class FixtureDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var label: NSTextField!
    var clicks = 0
    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect: NSRect(x: 200, y: 180, width: 680, height: 400),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "海洋桌面验证"
        window.backgroundColor = .windowBackgroundColor
        window.isReleasedWhenClosed = false
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 680, height: 400))
        content.autoresizingMask = [.width, .height]
        label = NSTextField(labelWithString: "普通应用窗口 · 点击测试")
        label.font = .systemFont(ofSize: 24, weight: .medium)
        label.frame = NSRect(x: 40, y: 285, width: 600, height: 40)
        content.addSubview(label)
        let instruction = NSTextField(wrappingLabelWithString: "此窗口用于确认海洋效果在普通应用下方，鼠标点击仍正常送达。完成验证后关闭。")
        instruction.frame = NSRect(x: 40, y: 205, width: 570, height: 55)
        instruction.font = .systemFont(ofSize: 17)
        content.addSubview(instruction)
        for (title, action, x) in [("测试点击", #selector(clicked), CGFloat(40)),
                                    ("切换全屏", #selector(fullscreen), CGFloat(220)),
                                    ("结束验证", #selector(quit), CGFloat(400))] {
            let button = NSButton(title: title, target: self, action: action)
            button.bezelStyle = .rounded
            button.frame = NSRect(x: x, y: 105, width: 160, height: 42)
            content.addSubview(button)
        }
        window.contentView = content
        let menu = NSMenu(), appMenu = NSMenuItem(), commands = NSMenu()
        let quit = NSMenuItem(title: "退出验证", action: #selector(quit), keyEquivalent: "q")
        quit.target = self; commands.addItem(quit); appMenu.submenu = commands; menu.addItem(appMenu)
        NSApp.mainMenu = menu
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc func clicked() { clicks += 1; label.stringValue = "点击已送达普通窗口：\(clicks) 次" }
    @objc func fullscreen() { window.toggleFullScreen(nil) }
    @objc func quit() { NSApp.terminate(nil) }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main struct FixtureApp {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = FixtureDelegate(); app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
