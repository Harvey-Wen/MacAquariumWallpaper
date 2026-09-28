import AppKit

@main struct BackdropTests {
    @MainActor static func main() {
        _ = NSApplication.shared
        Task { @MainActor in
            do { try await runTests(); exit(0) }
            catch { fputs("FAIL: \(error)\n", stderr); exit(1) }
        }
        NSApp.run()
    }

    @MainActor static func runTests() async throws {
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
        try await a.apply(screen: screen, key: "A") { try Data("A".utf8).write(to: $0) }
        let journal = directory.appendingPathComponent("ownership.json")
        let saved = try Data(contentsOf: journal)
        var rejected = false
        do {
            let b = try helper()
            try await b.apply(screen: screen, key: "B") { try Data("B".utf8).write(to: $0) }
            let bImage = current
            try await a.restoreAll()
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
        try await b.apply(screen: screen, key: "B") { try Data("B".utf8).write(to: $0) }
        let bImage = current
        let bJournal = try Data(contentsOf: journal)
        do { try await a.restoreAll(); preconditionFailure("released owner cannot write") } catch { }
        let untouched = try Data(contentsOf: journal)
        precondition(bJournal == untouched && FileManager.default.fileExists(atPath: bImage.path))
        try await b.restoreAll()
        precondition(current == original)
        b.releaseOwnership()
        // Missing original metadata must never delete the active orphan or invent a backup.
        let orphan = directory.appendingPathComponent("pond-orphan.png")
        try Data("orphan".utf8).write(to: orphan)
        current = orphan
        let c = try helper()
        do { try await c.apply(screen: screen, key: "C") { _ in }; preconditionFailure("missing backup") } catch { }
        precondition(FileManager.default.fileExists(atPath: orphan.path))
        try await asyncPaths(screen: screen)
        print("PASS: competing owner rejected before journal read, active image and backup preserved")
    }
    @MainActor static func asyncPaths(screen: NSScreen) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("pond-async-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let original = URL(fileURLWithPath: "/async-original.heic")
        let choice = URL(fileURLWithPath: "/user-choice.heic")
        var current = original
        var sets = 0
        let owner = try DesktopBackdrop(directory: root, readImage: { _ in current }, readOptions: { _ in [:] },
            setImage: { url, _, _ in current = url; sets += 1 })
        var started = false
        var valid = true
        let stale = Task { @MainActor in
            try await owner.apply(screen: screen, key: "stale", isCurrent: { valid }) { url in
                started = true
                try await Task.sleep(nanoseconds: 60_000_000)
                try Data("stale".utf8).write(to: url)
            }
        }
        while !started { await Task.yield() }
        do { try await owner.restoreAll(); preconditionFailure("concurrent restore must be refused") } catch { }
        valid = false
        try await stale.value
        precondition(sets == 0 && current == original, "superseded export never applies")
        started = false
        let cancelled = Task { @MainActor in
            try await owner.apply(screen: screen, key: "cancel") { url in
                try Data("partial".utf8).write(to: url)
                started = true
                try await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
        while !started { await Task.yield() }
        cancelled.cancel()
        do { try await cancelled.value; preconditionFailure("cancelled render") } catch is CancellationError { }
        let generated = try FileManager.default.contentsOfDirectory(atPath: root.path).filter { $0.hasSuffix(".png") }
        precondition(generated.isEmpty && sets == 0, "cancel removes only its unpublished file")
        do {
            try await owner.apply(screen: screen, key: "user-change") { url in
                try Data("race".utf8).write(to: url)
                await Task.yield()
                current = choice
            }
            preconditionFailure("user change must surface")
        } catch { }
        precondition(current == choice && sets == 0)
        try await owner.restoreAll()
        current = original
        try await owner.apply(screen: screen, key: "valid") { try Data("valid".utf8).write(to: $0) }
        try await owner.restoreAll()
        precondition(current == original && sets == 2)
        owner.releaseOwnership()

        var queued: URL?
        let delayed = try DesktopBackdrop(directory: root, readImage: { _ in current }, readOptions: { _ in [:] },
            setImage: { url, _, _ in queued = url })
        var heartbeats = 0
        let heartbeat = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000)
                heartbeats += 1
            }
        }
        do { try await delayed.apply(screen: screen, key: "timeout") { try Data("late".utf8).write(to: $0) }; preconditionFailure("timeout") } catch { }
        heartbeat.cancel()
        precondition(heartbeats > 50, "confirmation waiting must leave the main actor responsive")
        current = queued! // The system completes after the caller's timeout.
        let restoring = Task { @MainActor in try await delayed.restoreAll() }
        while queued != original { await Task.yield() }
        current = original
        try await restoring.value
        print("PASS: stale export, reentrancy, cancellation, external change, late timeout and nonblocking confirmation (\(heartbeats) heartbeats)")
    }

}
