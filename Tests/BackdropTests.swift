import AppKit

@main struct BackdropTests {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        if let index = CommandLine.arguments.firstIndex(of: "--lock-child") {
            do {
                let owner = try DesktopBackdrop(directory: URL(fileURLWithPath: CommandLine.arguments[index + 1]), readImage: { _ in nil }, readOptions: { _ in [:] }, setImage: { _, _, _ in })
                withExtendedLifetime(owner) { }
                exit(0)
            } catch { exit(23) }
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("pond-lock-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let screen = NSScreen.screens[0]
        let original = URL(fileURLWithPath: "/original-test.heic")
        var current = original
        func helper() throws -> DesktopBackdrop {
            try DesktopBackdrop(directory: directory, readImage: { _ in current }, readOptions: { _ in [:] },
                setImage: { url, _, _ in current = url })
        }
        let a = try helper()
        try a.apply(screen: screen, key: "A") { try Data("A".utf8).write(to: $0) }
        let journal = directory.appendingPathComponent("ownership.json")
        let saved = try Data(contentsOf: journal)
        var rejected = false
        do {
            let b = try helper()
            try b.apply(screen: screen, key: "B") { try Data("B".utf8).write(to: $0) }
            let bImage = current
            try a.restoreAll()
            print("REPRO: currentStillB=\(current == bImage) activeImageExists=\(FileManager.default.fileExists(atPath: bImage.path)) journal=\(String(data: try Data(contentsOf: journal), encoding: .utf8)!)")
        } catch { rejected = true }
        guard rejected else { throw NSError(domain: "Regression", code: 1, userInfo: [NSLocalizedDescriptionKey: "second owner was admitted; old exit deletes the active image"]) }
        let after = try Data(contentsOf: journal)
        precondition(after == saved)
        precondition(FileManager.default.fileExists(atPath: current.path))
        let child = Process()
        child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        child.arguments = ["--lock-child", directory.path]
        try child.run(); child.waitUntilExit()
        precondition(child.terminationStatus == 23, "cross-process conflict must be rejected")
        a.releaseOwnership() // Simulate process death: OS closes its descriptor, journal survives.
        let b = try helper()
        try b.apply(screen: screen, key: "B") { try Data("B".utf8).write(to: $0) }
        let bImage = current
        let bJournal = try Data(contentsOf: journal)
        do { try a.restoreAll(); preconditionFailure("released owner cannot write") } catch { }
        let untouched = try Data(contentsOf: journal)
        precondition(bJournal == untouched && FileManager.default.fileExists(atPath: bImage.path))
        try b.restoreAll()
        precondition(current == original)
        b.releaseOwnership()
        // Missing original metadata must never delete the active orphan or invent a backup.
        let orphan = directory.appendingPathComponent("pond-orphan.png")
        try Data("orphan".utf8).write(to: orphan)
        current = orphan
        let c = try helper()
        do { try c.apply(screen: screen, key: "C") { _ in }; preconditionFailure("missing backup") } catch { }
        precondition(FileManager.default.fileExists(atPath: orphan.path))
        print("PASS: competing owner rejected before journal read, active image and backup preserved")
    }
}
