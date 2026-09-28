import Foundation

@main struct DiagnosticsTests {
    static func main() {
        let timings = PerformanceTimings()
        precondition(timings.snapshot["samples"] as? Int == 0)
        precondition(JSONSerialization.isValidJSONObject(timings.snapshot))
        for value in 0..<1000 { timings.record(Double(value)) }
        timings.record(.nan)
        timings.record(-1)
        let result = timings.snapshot
        precondition(JSONSerialization.isValidJSONObject(result))
        precondition(result["samples"] as? Int == 300)
        precondition(result["totalSamples"] as? Int == 1000)
        precondition(result["p95MS"] as? Double == 984)
        precondition(result["maxMS"] as? Double == 999)
        precondition(result["over50MS"] as? Int == 949)
        let concurrent = PerformanceTimings()
        DispatchQueue.concurrentPerform(iterations: 1000) { _ in concurrent.record(33.333) }
        precondition(concurrent.snapshot["totalSamples"] as? Int == 1000)
        precondition(concurrent.snapshot["samples"] as? Int == 300)
        concurrent.record(120)
        precondition(concurrent.snapshot["over50MS"] as? Int == 1)
        print("PASS: bounded rolling timings, long frames, invalid samples and concurrent GPU recording")
    }
}
