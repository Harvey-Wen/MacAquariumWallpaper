import AppKit
import Darwin

/// A durable undo journal for the main display's static menu-bar backing image.
@MainActor final class DesktopBackdrop {
    struct Record: Codable {
        var display: String
        var original: URL
        var options: Data
        // Both the old and pending image remain owned across a crash during replacement.
        var images: [URL]
        var pending: Bool?
    }

    let directory: URL
    private let readImage: (NSScreen) -> URL?
    private let readOptions: (NSScreen) -> [NSWorkspace.DesktopImageOptionKey: Any]?
    private let setImage: (URL, NSScreen, [NSWorkspace.DesktopImageOptionKey: Any]) throws -> Void
    private var lockFD: Int32 = -1
    private var records: [Record] = []
    private var operationActive = false
    private var recovered = false
    private(set) var lastRecoveryResult = "notAttempted"
    private(set) var lastFailure: String?
    private var missingOriginal = false
    var ownershipState: String {
        if lockFD < 0 { return "released" }
        if missingOriginal { return "missingOriginal" }
        if records.contains(where: { $0.pending == true }) { return "pending" }
        if !records.isEmpty { return "owned" }
        if !overridden.isEmpty { return "externalChoice" }
        return "idle"
    }
    var journalRecordCount: Int { records.count }
    private var overridden = Set<String>()
    private var appliedKey: String?
    private var journal: URL { directory.appendingPathComponent("ownership.json") }

    init(directory: URL? = nil,
         readImage: @escaping (NSScreen) -> URL? = { NSWorkspace.shared.desktopImageURL(for: $0) },
         readOptions: @escaping (NSScreen) -> [NSWorkspace.DesktopImageOptionKey: Any]? = { NSWorkspace.shared.desktopImageOptions(for: $0) },
         setImage: @escaping (URL, NSScreen, [NSWorkspace.DesktopImageOptionKey: Any]) throws -> Void = {
             try NSWorkspace.shared.setDesktopImageURL($0, for: $1, options: $2)
         }) throws {
        let usesSystemDirectory = directory == nil
        // The production path is shared by every checkout, not relative to its executable.
        let directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("local.macaquariumwallpaper.app/DesktopBackdrop", isDirectory: true)
        self.directory = directory.resolvingSymlinksInPath()
        self.readImage = readImage; self.readOptions = readOptions; self.setImage = setImage
        // Migration guard for old builds that predate the filesystem lock.
        if usesSystemDirectory && NSRunningApplication.runningApplications(withBundleIdentifier: "local.macaquariumwallpaper.app")
            .contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            throw failure("另一个池塘实例正在运行，请先正常退出它")
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fd = open(self.directory.appendingPathComponent("owner.lock").path, O_CREAT | O_RDWR | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw failure("无法打开背景所有权锁") }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            Darwin.close(fd)
            throw failure("另一个池塘实例正在管理桌面背景")
        }
        lockFD = fd
        do {
            if FileManager.default.fileExists(atPath: journal.path) {
                records = try JSONDecoder().decode([Record].self, from: Data(contentsOf: journal))
            }
        } catch { releaseOwnership(); throw error }
    }

    deinit { if lockFD >= 0 { Darwin.close(lockFD) } }

    // Only after work has drained (or in crash-recovery tests). Never unlink the lock
    // file: a new inode would let two processes hold apparently exclusive locks.
    func releaseOwnership() {
        precondition(!operationActive, "Drain background work before releasing ownership")
        if lockFD >= 0 { Darwin.close(lockFD); lockFD = -1 }
    }

    private func requireOwnership() throws {
        guard lockFD >= 0 else { throw failure("背景所有权已释放，拒绝旧实例操作") }
    }

    static func displayIdentifier(_ screen: NSScreen) -> String {
        let number = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as! NSNumber).uint32Value
        let uuid = CGDisplayCreateUUIDFromDisplayID(number)!.takeRetainedValue()
        return CFUUIDCreateString(nil, uuid) as String
    }

    private func save(_ updated: [Record]) throws {
        try requireOwnership()
        try JSONEncoder().encode(updated).write(to: journal, options: .atomic)
        records = updated
    }

    private func clean() throws {
        try requireOwnership()
        // Even an orphaned active pond image must survive when its original is unknown.
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }
        let active = try screens.map { screen -> URL in
            guard let current = readImage(screen) else { throw failure("无法确认当前桌面背景，保留生成图片") }
            return current
        }
        let retained = Set((records.flatMap(\.images) + active).map { $0.resolvingSymlinksInPath().path })
        for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        where url.lastPathComponent.hasPrefix("pond-") && url.pathExtension == "png" && !retained.contains(url.resolvingSymlinksInPath().path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    @discardableResult private func restore(_ saved: Record, on screen: NSScreen) async throws -> Bool {
        var record = saved
        guard let current = readImage(screen) else { throw failure("无法读取当前桌面背景，保留恢复记录") }
        // A timed-out request may still be queued in the system. Reassert the
        // original even if readback has not yet advanced to the pending image.
        let owned = record.images.contains(current) || (record.pending == true && current == record.original)
        if !owned && record.pending == true {
            // The user chose another image while our earlier request was still
            // queued. Persist that explicit choice, then reassert it after the
            // pending request; a crash here must recover the user's newer choice.
            guard current.resolvingSymlinksInPath().deletingLastPathComponent() != directory,
                  let options = readOptions(screen) else { throw failure("无法确认用户新背景，保留待恢复记录") }
            let raw = Dictionary(uniqueKeysWithValues: options.map { ($0.key.rawValue, $0.value) })
            record.original = current
            record.options = try NSKeyedArchiver.archivedData(withRootObject: raw, requiringSecureCoding: true)
            try save(records.filter { $0.display != record.display } + [record])
        }
        if owned || record.pending == true {
            let classes: [AnyClass] = [NSDictionary.self, NSString.self, NSNumber.self, NSColor.self, NSArray.self, NSData.self, NSURL.self]
            guard let raw = try NSKeyedUnarchiver.unarchivedObject(ofClasses: classes, from: record.options) as? [String: Any] else {
                throw failure("无法读取原桌面选项，保留恢复记录")
            }
            let options = Dictionary(uniqueKeysWithValues: raw.map { (NSWorkspace.DesktopImageOptionKey(rawValue: $0.key), $0.value) })
            try setImage(record.original, screen, options)
            guard try await waitForImage(record.original, screen: screen) else { throw failure("系统未确认恢复原桌面背景") }
        }
        try save(records.filter { $0.display != record.display })
        try clean()
        return owned
    }

    /// Missing displays retain their journal entries until they become available again.
    func restoreAll(screens: [NSScreen] = NSScreen.screens) async throws {
        try beginOperation()
        defer { operationActive = false }
        try await restoreRecords(screens: screens)
    }

    private func beginOperation() throws {
        try requireOwnership()
        guard !operationActive else { throw failure("背景操作尚未完成") }
        operationActive = true
    }

    private func restoreRecords(screens: [NSScreen] = NSScreen.screens) async throws {
        appliedKey = nil
        overridden.removeAll()
        var restored = 0, external = 0
        do {
            let ownedImages = Set(records.flatMap(\.images))
            missingOriginal = screens.compactMap(readImage).contains {
                $0.resolvingSymlinksInPath().deletingLastPathComponent() == directory && !ownedImages.contains($0)
            }
            guard !missingOriginal else {
                lastRecoveryResult = "missingOriginal"
                throw failure("池塘背景缺少原背景恢复记录，未执行恢复")
            }
            for record in records {
                if let screen = screens.first(where: { Self.displayIdentifier($0) == record.display }) {
                    if try await restore(record, on: screen) { restored += 1 } else { external += 1 }
                }
            }
            try clean()
            lastRecoveryResult = !records.isEmpty ? "waitingForDisplay" :
                restored > 0 ? "restored" : external > 0 ? "externalChoicePreserved" : "nothingToRestore"
        } catch {
            if !missingOriginal { lastRecoveryResult = "failed" }
            lastFailure = error.localizedDescription
            throw error
        }
    }

    func apply(screen: NSScreen, key: String, isCurrent: () -> Bool = { true },
               render: (URL) async throws -> Void) async throws {
        try beginOperation()
        defer { operationActive = false }
        do {
            if !recovered {
                try await restoreRecords()
                recovered = true
            }
            let identifier = Self.displayIdentifier(screen)
            // Moving the primary display restores any formerly affected display first.
            for record in records where record.display != identifier {
                if let previous = NSScreen.screens.first(where: { Self.displayIdentifier($0) == record.display }) {
                    try await restore(record, on: previous)
                }
            }
            guard !overridden.contains(identifier) else { return }
            guard let current = readImage(screen) else { throw failure("无法备份当前桌面背景") }
            var record: Record
            if let existing = records.first(where: { $0.display == identifier }) {
                // A timed-out system request can still complete. Do not discard its
                // ownership or enqueue another replacement before explicit restoration.
                guard existing.pending != true else {
                    throw failure("上次背景更改尚待恢复，请先关闭再开启池塘")
                }
                guard existing.images.contains(current) else {
                    overridden.insert(identifier)
                    try await restore(existing, on: screen) // Releases ownership without changing the user's image.
                    appliedKey = nil
                    return
                }
                if appliedKey == key { return }
                record = existing
                record.images = [current]
                try save(records.filter { $0.display != identifier } + [record])
                try clean()
            } else {
                guard current.resolvingSymlinksInPath().deletingLastPathComponent() != directory else {
                    missingOriginal = true
                    throw failure("池塘背景缺少原背景恢复记录，未再次替换")
                }
                guard let options = readOptions(screen) else { throw failure("无法备份原桌面选项") }
                let raw = Dictionary(uniqueKeysWithValues: options.map { ($0.key.rawValue, $0.value) })
                let data = try NSKeyedArchiver.archivedData(withRootObject: raw, requiringSecureCoding: true)
                record = Record(display: identifier, original: current, options: data, images: [], pending: false)
            }
            let next = directory.appendingPathComponent("pond-\(UUID().uuidString).png")
            do { try await render(next); try Task.checkCancellation() }
            catch { try? FileManager.default.removeItem(at: next); throw error }
            guard readImage(screen) == current else {
                overridden.insert(identifier)
                try FileManager.default.removeItem(at: next)
                throw failure("生成期间桌面背景已改变，保留你的选择")
            }
            guard isCurrent() else {
                try FileManager.default.removeItem(at: next)
                return
            }
            record.images.append(next)
            record.pending = true
            // Persist before calling the system: a crash on either side can still be undone.
            do { try save(records.filter { $0.display != identifier } + [record]) }
            catch { try? FileManager.default.removeItem(at: next); throw error }
            try setImage(next, screen, [.imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue, .allowClipping: true])
            guard try await waitForImage(next, screen: screen) else { throw failure("系统未确认池塘桌面背景") }
            record.images = [next]
            record.pending = false
            try save(records.filter { $0.display != identifier } + [record])
            appliedKey = key
            try clean()
        } catch {
            lastFailure = error.localizedDescription
            throw error
        }
    }

    // NSWorkspace returns before its read API catches up (observed on macOS 15).
    // Keep the journal until acknowledgment; avoid running a nested UI event loop.
    private func waitForImage(_ url: URL, screen: NSScreen) async throws -> Bool {
        let deadline = ProcessInfo.processInfo.systemUptime + 2
        repeat {
            if readImage(screen) == url { return true }
            try await Task.sleep(nanoseconds: 20_000_000)
        } while ProcessInfo.processInfo.systemUptime < deadline
        return readImage(screen) == url
    }

    private func failure(_ message: String) -> NSError {
        NSError(domain: "DesktopBackdrop", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
