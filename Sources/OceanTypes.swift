import Foundation
import simd

enum FishSpecies: Int, CaseIterable {
    case koi
}

enum PondWeather: String { case sunny, rainy }
enum DisturbanceKind: Int { case click, rain, leaf, motion }
enum LeafStage: Int { case falling, floating, grounded }

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
}

struct Ripple {
    var position: SIMD2<Float>
    var age: Float
    var strength: Float
    var source: DisturbanceKind = .click
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

struct OceanFrame {
    var size: SIMD2<Float>
    var time: Double
    var fish: [FishState]
    var ripples: [Ripple]
    var waterStrength: Float
    var leaves: [PondLeaf] = []
    var weatherAmount: Float = 0

    static let empty = OceanFrame(size: SIMD2(1440, 900), time: 0, fish: [], ripples: [], waterStrength: 0)
}
