import Foundation

/// Ten seconds at 30 FPS. Recording is constant-time; percentiles are computed only
/// when diagnostics are requested. The lock also permits Metal completion callbacks.
final class PerformanceTimings {
    private let lock = NSLock()
    private var samples = [Double](repeating: 0, count: 300)
    private var index = 0
    private var count = 0
    private var total = 0
    private var over50MS = 0
    private var last = 0.0

    func record(_ milliseconds: Double) {
        guard milliseconds.isFinite && milliseconds >= 0 else { return }
        lock.lock(); defer { lock.unlock() }
        samples[index] = milliseconds
        index = (index + 1) % samples.count
        count = min(count + 1, samples.count)
        total += 1
        if milliseconds > 50 { over50MS += 1 }
        last = milliseconds
    }

    var latest: Double { lock.lock(); defer { lock.unlock() }; return last }

    var snapshot: [String: Any] {
        lock.lock()
        let values = Array(samples.prefix(count))
        let total = total, over50MS = over50MS
        lock.unlock()
        let sorted = values.sorted()
        let maximum: Double = sorted.last ?? 0
        return ["samples": values.count, "totalSamples": total, "over50MS": over50MS,
                "meanMS": values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count),
                "p95MS": sorted.isEmpty ? 0 : sorted[max(0, Int(ceil(Double(sorted.count) * 0.95)) - 1)],
                "maxMS": maximum]
    }
}
