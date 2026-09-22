import Foundation
import simd

enum FishSpecies: Int, CaseIterable {
    case silver, clown, tang, butterfly, manta
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
}

struct Ripple {
    var position: SIMD2<Float>
    var age: Float
    var strength: Float
}

struct CurrentStroke {
    var position: SIMD2<Float>
    var velocity: SIMD2<Float>
    var age: Float
}

struct OceanFrame {
    var size: SIMD2<Float>
    var time: Float
    var fish: [FishState]
    var ripples: [Ripple]
    var currents: [CurrentStroke]
    var waterStrength: Float

    static let empty = OceanFrame(size: SIMD2(1440, 900), time: 0, fish: [], ripples: [], currents: [], waterStrength: 0.45)
}
