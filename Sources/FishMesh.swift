import Foundation
import simd

// Top-down koi: nose +x, paired fins across y, back toward +z.
struct FishVertex {
    var position: SIMD4<Float>
    var normal: SIMD4<Float>
    var detail: SIMD4<Float>
}

struct FishMesh {
    var vertices: [FishVertex] = []
    init(species: FishSpecies) {
        func v(_ p: SIMD3<Float>, _ n: SIMD3<Float>, _ material: Float, _ uv: SIMD2<Float> = .zero) -> FishVertex {
            FishVertex(position: SIMD4(p, 1), normal: SIMD4(n, 0), detail: SIMD4(material, 0, uv.x, uv.y))
        }
        func width(_ t: Float) -> Float {
            // Broad blunt head, strong shoulders, long tapered caudal peduncle.
            let knots: [Float] = [0.022, 0.035, 0.055, 0.079, 0.101, 0.112, 0.112, 0.103, 0.085, 0.062, 0]
            let s = min(9.999, max(0, t * 10)), i = Int(s)
            return knots[i] + (knots[i + 1] - knots[i]) * (s - Float(i))
        }
        func body(_ i: Int, _ j: Int) -> FishVertex {
            let t = Float(i) / 48, a = Float(j) / 24 * 2 * Float.pi
            let w = width(t), x = -0.31 + t * 0.77
            return v(SIMD3(x, w * sin(a), w * 0.58 * cos(a)), simd_normalize(SIMD3(0.15, sin(a), cos(a) * 1.7)), 0, SIMD2(x, sin(a)))
        }
        func fin(_ root: SIMD3<Float>, _ edge: [SIMD3<Float>], _ material: Float) {
            for i in 0..<(edge.count - 1) {
                vertices += [v(root, SIMD3(0,0,1), material, SIMD2(0,0)), v(edge[i], SIMD3(0,0,1), material, SIMD2(Float(i),1)), v(edge[i+1], SIMD3(0,0,1), material, SIMD2(Float(i+1),1))]
            }
        }
        fin(SIMD3(-0.29,0,0), [SIMD3(-0.54,0.13,0),SIMD3(-0.52,0.065,0),SIMD3(-0.43,0,0),SIMD3(-0.52,-0.065,0),SIMD3(-0.54,-0.13,0)], 1)
        for side: Float in [-1,1] {
            fin(SIMD3(0.16,side * 0.065,0), [SIMD3(0.11,side * 0.15,0),SIMD3(0.025,side * 0.205,0),SIMD3(-0.035,side * 0.18,0),SIMD3(-0.065,side * 0.105,0)], 2)
            fin(SIMD3(-0.14,side * 0.035,0), [SIMD3(-0.17,side * 0.11,0),SIMD3(-0.25,side * 0.095,0),SIMD3(-0.23,side * 0.035,0)], 2)
        }
        for i in 0..<48 { for j in 0..<24 {
            vertices += [body(i,j),body(i+1,j),body(i+1,j+1),body(i,j),body(i+1,j+1),body(i,j+1)]
        }}
        // Narrow dorsal ridge, deliberately subtle from the overhead camera.
        fin(SIMD3(0.16,0,0.065), [SIMD3(-0.19,-0.008,0.035),SIMD3(-0.12,0.012,0.071),SIMD3(0.08,0.013,0.078)], 3)
        for side: Float in [-1,1] {
            let center = SIMD3<Float>(0.33,side * 0.063,0.037)
            for j in 0..<16 {
                let a = Float(j) / 16 * 2 * Float.pi, b = Float(j+1) / 16 * 2 * Float.pi
                vertices += [v(center,SIMD3(0,0,1),4),v(center+SIMD3(cos(a)*0.012,sin(a)*0.009,0),SIMD3(0,0,1),4),v(center+SIMD3(cos(b)*0.012,sin(b)*0.009,0),SIMD3(0,0,1),4)]
            }
        }
    }
}
