import Foundation
import simd

enum FishSpecies: Int, CaseIterable {
    case koi
}

enum PondWeather: String, CaseIterable {
    case sunny, rainy, snowy, overcast, cloudy

    var title: String {
        switch self {
        case .sunny: return "晴天"
        case .rainy: return "雨天"
        case .snowy: return "下雪"
        case .overcast: return "阴天"
        case .cloudy: return "多云"
        }
    }

    // Snow, uniform overcast and broken cloud cover transition independently of rain.
    var atmosphere: SIMD3<Float> {
        switch self {
        case .sunny, .rainy: return .zero
        case .snowy: return SIMD3(1, 0, 0)
        case .overcast: return SIMD3(0, 1, 0)
        case .cloudy: return SIMD3(0, 0, 1)
        }
    }
}
enum DisturbanceKind: Int { case click, rain, leaf, motion }
enum LeafStage: Int { case falling, floating, grounded }

enum FishIdentity: Hashable {
    case builtIn(Int)
    case custom(UUID)

    var name: String {
        switch self {
        case .builtIn(let id): return String(format: "锦鲤 %02d", id + 1)
        case .custom(let id): return "手绘鱼 \(id.uuidString.prefix(8))"
        }
    }

    var storageKey: String {
        switch self {
        case .builtIn(let id): return "default-\(id)"
        case .custom(let id): return id.uuidString
        }
    }
}

// All positions are screen points, with the origin at the screen's bottom left.
struct FishState {
    var id: Int
    var species: FishSpecies
    var position: SIMD2<Float>
    var velocity: SIMD2<Float>
    var heading: Float
    var length: Float
    var depth: Float
    var phase: Float
    var panic: Float
    var customAppearanceID: UUID? = nil
    var name: String? = nil

    var identity: FishIdentity { customAppearanceID.map(FishIdentity.custom) ?? .builtIn(id) }
    var displayName: String {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? identity.name : trimmed
    }
}

struct Ripple {
    var position: SIMD2<Float>
    var age: Float
    var strength: Float
    var source: DisturbanceKind = .click
    var travel: SIMD2<Float> = .zero
    var duration: Float = 0.12
}

struct PondLeaf {
    var id: Int
    var position: SIMD2<Float>
    var velocity: SIMD2<Float>
    var age: Float
    var rotation: Float
    var length: Float
    var stage: LeafStage
    var fallDuration: Float
    var opacity: Float
}

enum PrecipitationKind: Int { case rain, snow }

struct FallingPrecipitation: Equatable {
    var id: Int
    var kind: PrecipitationKind
    var origin: SIMD2<Float>
    var velocity: SIMD2<Float>
    var age: Float
    var landingY: Float
    var radius: Float
    var opacity: Float
    var sway: Float
    var frequency: Float
    var phase: Float

    var duration: Float { (origin.y - landingY) / -velocity.y }
    var position: SIMD2<Float> { position(at: age) }
    func position(at age: Float) -> SIMD2<Float> {
        origin + velocity * age + SIMD2(sway * (sin(age * frequency + phase) - sin(phase)), 0)
    }
}

struct SurfaceSnow: Equatable {
    var id: Int
    var position: SIMD2<Float>
    var radius: Float
    var age: Float
    var lifetime: Float
    var opacity: Float
    var phase: Float
    var clearing = false
}

struct OceanFrame {
    var size: SIMD2<Float>
    var time: Double
    var fish: [FishState]
    var ripples: [Ripple]
    var waterStrength: Float
    var leaves: [PondLeaf] = []
    var weatherAmount: Float = 0
    var atmosphere: SIMD3<Float> = .zero
    var precipitation: [FallingPrecipitation] = []
    var surfaceSnow: [SurfaceSnow] = []

    static let empty = OceanFrame(size: SIMD2(1440, 900), time: 0, fish: [], ripples: [], waterStrength: 0)
}
