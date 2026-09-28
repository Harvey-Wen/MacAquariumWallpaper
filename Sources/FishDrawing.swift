import Foundation
import CoreGraphics

/// Normalized canvas coordinate: x grows right; y grows down.
/// Fish local x [-0.6, 0.6] maps to x [0, 1], and local y [-0.3, 0.3]
/// maps to downward y [1, 0].
struct FishPoint: Codable, Equatable {
    var x: Float
    var y: Float
}

/// RGB components in [0, 1].
struct FishColor: Codable, Equatable {
    var red: Float
    var green: Float
    var blue: Float
}

/// Width is a fraction of the canvas height; erasing restores the body base color.
struct FishStroke: Codable, Equatable {
    var points: [FishPoint]
    var color: FishColor
    var width: Float
    var erasing: Bool
}

struct FishDrawing: Codable, Equatable {
    var id: UUID
    var strokes: [FishStroke]
    var baseColor: FishColor? = nil
    var name: String? = nil

    var resolvedBaseColor: FishColor { baseColor ?? FishColor(red: 1, green: 1, blue: 1) }

    /// The silhouette is sampled once from the actual koi body mesh.
    private static let bodyOutline: [(Float, Float)] = {
        var widths: [Float: Float] = [:]
        for vertex in FishMesh(species: .koi).vertices where vertex.detail.x == 0 {
            let x = vertex.position.x
            widths[x] = max(widths[x] ?? 0, abs(vertex.position.y))
        }
        return widths.keys.sorted().map { ($0, widths[$0]!) }
    }()

    static func bodyPath(width: Int, height: Int) -> CGPath {
        let path = CGMutablePath()
        guard width > 0, height > 0, let first = bodyOutline.first else { return path }
        func point(_ x: Float, _ y: Float) -> CGPoint {
            CGPoint(x: CGFloat((x + 0.6) / 1.2) * CGFloat(width),
                    y: CGFloat((y + 0.3) / 0.6) * CGFloat(height))
        }
        path.move(to: point(first.0, first.1))
        for (x, halfWidth) in bodyOutline.dropFirst() { path.addLine(to: point(x, halfWidth)) }
        for (x, halfWidth) in bodyOutline.reversed() { path.addLine(to: point(x, -halfWidth)) }
        path.closeSubpath()
        return path
    }

    /// Transparent outside the koi body, base-colored inside; rows are top to bottom.
    func rasterizedImage(width: Int = 512, height: Int = 256) -> CGImage? {
        guard width > 0, height > 0, width <= 4096, height <= 4096,
              (try? validate()) != nil else { return nil }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return nil }
        context.setShouldAntialias(true)
        let path = Self.bodyPath(width: width, height: height)
        context.addPath(path)
        context.clip()
        let base = resolvedBaseColor
        context.setFillColor(CGColor(red: CGFloat(base.red), green: CGFloat(base.green), blue: CGFloat(base.blue), alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        for stroke in strokes where !stroke.points.isEmpty {
            let color = stroke.erasing ? base : stroke.color
            context.setStrokeColor(CGColor(red: CGFloat(color.red), green: CGFloat(color.green), blue: CGFloat(color.blue), alpha: 1))
            context.setFillColor(CGColor(red: CGFloat(color.red), green: CGFloat(color.green), blue: CGFloat(color.blue), alpha: 1))
            context.setLineWidth(CGFloat(stroke.width) * CGFloat(height))
            context.setLineCap(.round)
            context.setLineJoin(.round)
            let first = stroke.points[0]
            let start = CGPoint(x: CGFloat(first.x) * CGFloat(width), y: CGFloat(1 - first.y) * CGFloat(height))
            if stroke.points.count == 1 {
                context.fillEllipse(in: CGRect(x: start.x - CGFloat(stroke.width) * CGFloat(height) / 2,
                    y: start.y - CGFloat(stroke.width) * CGFloat(height) / 2,
                    width: CGFloat(stroke.width) * CGFloat(height), height: CGFloat(stroke.width) * CGFloat(height)))
            } else {
                context.beginPath()
                context.move(to: start)
                for point in stroke.points.dropFirst() {
                    context.addLine(to: CGPoint(x: CGFloat(point.x) * CGFloat(width), y: CGFloat(1 - point.y) * CGFloat(height)))
                }
                context.strokePath()
            }
        }
        return context.makeImage()
    }

    func validate() throws {
        guard strokes.count <= 10_000 else { throw FishDrawingError.invalidDrawing }
        if let baseColor {
            guard [baseColor.red, baseColor.green, baseColor.blue]
                .allSatisfy({ $0.isFinite && (0...1).contains($0) }) else {
                throw FishDrawingError.invalidDrawing
            }
        }
        for stroke in strokes {
            guard stroke.points.count <= 100_000,
                  stroke.width.isFinite, stroke.width > 0, stroke.width <= 1,
                  [stroke.color.red, stroke.color.green, stroke.color.blue].allSatisfy({ $0.isFinite && (0...1).contains($0) }),
                  stroke.points.allSatisfy({ $0.x.isFinite && $0.y.isFinite && (0...1).contains($0.x) && (0...1).contains($0.y) })
            else { throw FishDrawingError.invalidDrawing }
        }
    }
}

enum FishDrawingError: Error { case invalidDrawing }

struct FishDrawingStore {
    let directory: URL

    struct DefaultFishState: Codable {
        var deleted: Set<Int> = []
        var names: [Int: String] = [:]
    }

    private var defaultStateURL: URL { directory.appendingPathComponent("state/default-fish.json") }

    func defaultFishState() throws -> DefaultFishState {
        guard FileManager.default.fileExists(atPath: defaultStateURL.path) else { return DefaultFishState() }
        return try JSONDecoder().decode(DefaultFishState.self, from: Data(contentsOf: defaultStateURL))
    }

    func removeDefaultFish(id: Int) throws {
        var state = try defaultFishState()
        state.deleted.insert(id)
        try saveDefaultState(state)
    }

    func renameDefaultFish(id: Int, name: String?) throws {
        var state = try defaultFishState()
        state.names[id] = name
        try saveDefaultState(state)
    }

    private func saveDefaultState(_ state: DefaultFishState) throws {
        try FileManager.default.createDirectory(at: defaultStateURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try JSONEncoder().encode(state).write(to: defaultStateURL, options: .atomic)
    }

    private func drawingURLs(id: UUID) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).filter {
            $0.pathExtension.lowercased() == "json" &&
            $0.deletingPathExtension().lastPathComponent.lowercased() == id.uuidString.lowercased()
        }
    }

    func remove(id: UUID) throws {
        for url in try drawingURLs(id: id) { try FileManager.default.removeItem(at: url) }
    }

    func rename(id: UUID, name: String?) throws {
        guard let url = try drawingURLs(id: id).first else { throw CocoaError(.fileReadNoSuchFile) }
        var drawing = try JSONDecoder().decode(FishDrawing.self, from: Data(contentsOf: url))
        try drawing.validate()
        guard drawing.id == id else { throw FishDrawingError.invalidDrawing }
        drawing.name = name
        try JSONEncoder().encode(drawing).write(to: url, options: .atomic)
    }

    func save(_ drawing: FishDrawing) throws {
        try drawing.validate()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(drawing.id.uuidString).appendingPathExtension("json")
        try JSONEncoder().encode(drawing).write(to: url, options: .atomic)
    }

    func load() -> (drawings: [FishDrawing], errors: [String]) {
        guard FileManager.default.fileExists(atPath: directory.path) else { return ([], []) }
        var drawings: [FishDrawing] = []
        var errors: [String] = []
        do {
            let urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension.lowercased() == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
            for url in urls {
                do {
                    let drawing = try JSONDecoder().decode(FishDrawing.self, from: Data(contentsOf: url))
                    try drawing.validate()
                    guard url.deletingPathExtension().lastPathComponent.lowercased() == drawing.id.uuidString.lowercased() else {
                        throw FishDrawingError.invalidDrawing
                    }
                    drawings.append(drawing)
                } catch { errors.append("\(url.lastPathComponent): \(error.localizedDescription)") }
            }
        } catch { errors.append(error.localizedDescription) }
        return (drawings, errors)
    }
}
