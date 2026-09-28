import AppKit
import MetalKit

@main struct CustomFishRenderTests {
    static func main() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let view = MTKView(frame: NSRect(x: 0, y: 0, width: 1600, height: 1000))
        view.isPaused = true
        let renderer = try OceanRenderer(view: view, shaderURL: root.appendingPathComponent("Resources/Ocean.metal"))
        let first = drawing(tail: FishColor(red: 1, green: 0.02, blue: 0.02), head: FishColor(red: 0.02, green: 0.08, blue: 1))
        let second = drawing(tail: FishColor(red: 0.02, green: 1, blue: 0.02), head: FishColor(red: 1, green: 0.02, blue: 0.02))
        let width = 1600, height = 1000
        var frame = OceanFrame(size: SIMD2(1600, 1000), time: 0, fish: [], ripples: [], waterStrength: 0.01)
        func fish(_ id: Int, _ x: Float, _ drawingID: UUID?) -> FishState {
            FishState(id: id, species: .koi, position: SIMD2(x, 500), velocity: .zero,
                      heading: 0, length: 300, depth: 0.15, phase: 0, panic: 0,
                      customAppearanceID: drawingID)
        }
        func render() throws -> [UInt8] { try renderer.renderRGBA(frame: frame, width: width, height: height) }
        func rgb(_ bytes: [UInt8], _ x: Int, _ y: Int) -> [Int] {
            let i = (y * width + x) * 4
            return (0..<3).map { Int(bytes[i + $0]) }
        }
        func dominant(_ bytes: [UInt8], _ x: Int, _ y: Int, _ channel: Int) -> Bool {
            let color = rgb(bytes, x, y)
            return color[channel] > color[(channel + 1) % 3] + 12 && color[channel] > color[(channel + 2) % 3] + 12
        }
        frame.fish = [fish(1, 800, nil)]
        let original = try render()
        try renderer.registerDrawing(first)
        try renderer.registerDrawing(second)
        let registeredDefault = try render()
        precondition(registeredDefault == original, "registration must leave default fish pixels unchanged")
        frame.fish[0].customAppearanceID = first.id
        let painted = try render()
        precondition(painted != original, "a registered drawing must paint the fish")
        precondition(dominant(painted, 764, 500, 0), "red tail must face left at heading zero")
        precondition(dominant(painted, 854, 500, 2), "blue head must face right at heading zero")
        let upper = rgb(painted, 800, 480), lower = rgb(painted, 800, 520)
        precondition(upper[0] > upper[2] + 12 && upper[1] > upper[2] + 12, "upper yellow dot must use top-down image UV")
        precondition(lower[0] > lower[1] + 12 && lower[2] > lower[1] + 12, "lower magenta dot must use top-down image UV")
        frame.fish[0].heading = .pi / 2
        frame.fish[0].phase = 1.4
        let turned = try render()
        precondition(dominant(turned, 800, 536, 0), "red tail must turn with the fish")
        precondition(dominant(turned, 800, 446, 2), "blue head must turn with the fish")
        let turnedUpper = rgb(turned, 780, 500), turnedLower = rgb(turned, 820, 500)
        precondition(turnedUpper[0] > turnedUpper[2] + 12 && turnedUpper[1] > turnedUpper[2] + 12,
                     "upper dot must rotate to the left of the fish")
        precondition(turnedLower[0] > turnedLower[1] + 12 && turnedLower[2] > turnedLower[1] + 12,
                     "lower dot must rotate to the right of the fish")
        frame.fish = [fish(1, 550, first.id), fish(2, 1050, second.id)]
        let paired = try render()
        precondition(dominant(paired, 514, 500, 0) && dominant(paired, 604, 500, 2), "first fish must retain its own texture")
        precondition(dominant(paired, 1014, 500, 1) && dominant(paired, 1104, 500, 0), "second fish must retain its own texture")
        try renderer.writePNG(frame: frame, width: width, height: height,
                              to: root.appendingPathComponent(".build/custom-fish-render.png"))
        frame.fish = [fish(1, 800, UUID())]
        let missing = try render()
        precondition(missing == original, "missing texture must use original appearance")
        frame.fish[0].customAppearanceID = first.id
        renderer.removeDrawing(id: first.id)
        let removed = try render()
        precondition(removed == original, "removing a drawing must restore original appearance")
        var blueBase = first, greenBase = second
        blueBase.baseColor = FishColor(red: 0.05, green: 0.15, blue: 0.95)
        greenBase.baseColor = FishColor(red: 0.1, green: 0.9, blue: 0.08)
        try renderer.registerDrawing(blueBase)
        try renderer.registerDrawing(greenBase)
        frame.fish = [fish(1, 550, first.id), fish(2, 1050, second.id)]
        let coloredBases = try render()
        precondition(dominant(coloredBases, 575, 490, 2) && dominant(coloredBases, 1075, 490, 1), "each fish renders its selected base color")
        precondition(dominant(coloredBases, 514, 500, 0) && dominant(coloredBases, 1104, 500, 0), "base colors preserve red painted markings")
        try renderer.writePNG(frame: frame, width: width, height: height,
                              to: root.appendingPathComponent(".build/custom-fish-base-color.png"))
        print("PASS custom fish rendering: selected base colors, oriented markings, independent textures, unchanged default and safe fallback")
    }

    static func drawing(tail: FishColor, head: FishColor) -> FishDrawing {
        let tailStroke = FishStroke(points: [FishPoint(x: 0.40, y: 0.30), FishPoint(x: 0.40, y: 0.70)],
                                    color: tail, width: 0.15, erasing: false)
        let headStroke = FishStroke(points: [FishPoint(x: 0.65, y: 0.30), FishPoint(x: 0.65, y: 0.70)],
                                    color: head, width: 0.15, erasing: false)
        let upper = FishStroke(points: [FishPoint(x: 0.50, y: 0.39)],
                               color: FishColor(red: 1, green: 1, blue: 0), width: 0.10, erasing: false)
        let lower = FishStroke(points: [FishPoint(x: 0.50, y: 0.61)],
                               color: FishColor(red: 1, green: 0, blue: 1), width: 0.10, erasing: false)
        return FishDrawing(id: UUID(), strokes: [tailStroke, headStroke, upper, lower])
    }
}
