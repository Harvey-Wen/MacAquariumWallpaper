import AppKit

@main
final class DrawingEditorFixture: NSObject, NSApplicationDelegate {
    private var editor: FishDrawingWindowController?

    static func main() {
        let app = NSApplication.shared
        let delegate = DrawingEditorFixture()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let output = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("drawing-validation")
        editor = FishDrawingWindowController { drawing in
            try FishDrawingStore(directory: output).save(drawing)
        }
        editor?.showWindow(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
