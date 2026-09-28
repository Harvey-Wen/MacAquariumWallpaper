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
        if let index = CommandLine.arguments.firstIndex(of: "--crash-child") {
            var current = URL(fileURLWithPath: "/original-test.heic")
            let owner = try DesktopBackdrop(directory: URL(fileURLWithPath: CommandLine.arguments[index + 1]),
                readImage: { _ in current }, readOptions: { _ in [:] }, setImage: { url, _, _ in current = url })
            try await owner.apply(screen: NSScreen.screens[0], key: "crash") { try Data("crash".utf8).write(to: $0) }
            exit(37) // No restoration or deinit: the OS alone releases this process's lock.
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
        precondition(b.lastRecoveryResult == "restored")
        precondition(current == original)
        b.releaseOwnership()
        let crashDirectory = directory.appendingPathComponent("crash")
        let crash = Process()
        crash.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        crash.arguments = ["--crash-child", crashDirectory.path]
        try crash.run(); crash.waitUntilExit()
        precondition(crash.terminationStatus == 37)
        let crashRecords = try JSONDecoder().decode([DesktopBackdrop.Record].self, from: Data(contentsOf: crashDirectory.appendingPathComponent("ownership.json")))
        current = crashRecords[0].images[0]
        let recovered = try DesktopBackdrop(directory: crashDirectory, readImage: { _ in current }, readOptions: { _ in [:] }, setImage: { url, _, _ in current = url })
        try await recovered.restoreAll()
        precondition(current == original && recovered.lastRecoveryResult == "restored", "OS releases dead process ownership and next process recovers its journal")
        recovered.releaseOwnership()
        // Missing original metadata must never delete the active orphan or invent a backup.
        let orphan = directory.appendingPathComponent("pond-orphan.png")
        try Data("orphan".utf8).write(to: orphan)
        current = orphan
        let c = try helper()
        precondition(c.lastRecoveryResult == "notAttempted")
        do { try await c.apply(screen: screen, key: "C") { _ in }; preconditionFailure("missing backup") } catch { }
        precondition(FileManager.default.fileExists(atPath: orphan.path))
        precondition(c.lastRecoveryResult == "missingOriginal" && c.ownershipState == "missingOriginal")
        precondition(c.lastFailure != nil)
        current = original
        try await c.restoreAll()
        precondition(c.lastRecoveryResult == "nothingToRestore" && c.lastFailure != nil, "empty journal is not successful recovery and never erases failure history")
        let unreadableDirectory = directory.appendingPathComponent("unreadable")
        let unreadable = try DesktopBackdrop(directory: unreadableDirectory, readImage: { _ in nil }, readOptions: { _ in [:] }, setImage: { _, _, _ in })
        let unknownActive = unreadableDirectory.appendingPathComponent("pond-unknown.png")
        try Data("unknown".utf8).write(to: unknownActive)
        do { try await unreadable.restoreAll() } catch { }
        guard FileManager.default.fileExists(atPath: unknownActive.path) else {
            throw NSError(domain: "Regression", code: 1, userInfo: [NSLocalizedDescriptionKey: "unreadable current wallpaper must prevent cleanup of a possibly active image"])
        }
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
        queued = nil
        let cancelledConfirmation = Task { @MainActor in
            try await delayed.apply(screen: screen, key: "cancel-confirmation") { try Data("pending".utf8).write(to: $0) }
        }
        while queued == nil { await Task.yield() }
        let pendingFile = queued!
        cancelledConfirmation.cancel()
        do { try await cancelledConfirmation.value; preconditionFailure("cancelled confirmation") } catch is CancellationError { }
        precondition(delayed.ownershipState == "pending" && FileManager.default.fileExists(atPath: pendingFile.path), "cancellation after system request retains durable undo")
        try await delayed.restoreAll()
        precondition(queued == original && delayed.lastRecoveryResult == "restored")
        queued = nil
        let pendingOverride = Task { @MainActor in
            try await delayed.apply(screen: screen, key: "override-pending") { try Data("pending".utf8).write(to: $0) }
        }
        while queued == nil { await Task.yield() }
        pendingOverride.cancel()
        do { try await pendingOverride.value } catch is CancellationError { }
        current = choice
        try await delayed.restoreAll()
        guard queued == choice else {
            throw NSError(domain: "Regression", code: 1, userInfo: [NSLocalizedDescriptionKey: "late system request must be superseded by the user's current choice before releasing recovery"])
        }
        precondition(current == choice && delayed.lastRecoveryResult == "externalChoicePreserved")
        print("PASS: stale export, reentrancy, cancellation, external change, late timeout and nonblocking confirmation (\(heartbeats) heartbeats)")
    }

}
