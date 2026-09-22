import Foundation
import simd

// Model coordinates: nose toward +x, belly toward -y, visible flank toward +z.
struct FishVertex {
    var position: SIMD4<Float>
    var normal: SIMD4<Float>
    var detail: SIMD4<Float> // material, fin motion, u, v
}

struct FishMesh {
    var vertices: [FishVertex] = []

    init(species: FishSpecies) {
        if species == .manta {
            makeManta()
        } else {
            makeFish(species)
        }
    }

    private mutating func triangle(_ a: FishVertex, _ b: FishVertex, _ c: FishVertex) {
        vertices.append(contentsOf: [a, b, c])
    }

    private func vertex(_ p: SIMD3<Float>, _ n: SIMD3<Float>, _ material: Float = 0,
                        _ motion: Float = 0, _ uv: SIMD2<Float> = .zero) -> FishVertex {
        FishVertex(position: SIMD4(p, 1), normal: SIMD4(n, 0), detail: SIMD4(material, motion, uv.x, uv.y))
    }

    private mutating func ellipsoid(center: SIMD3<Float>, radius: SIMD3<Float>, material: Float,
                                    rings: Int = 12, sides: Int = 24) {
        func point(_ i: Int, _ j: Int) -> FishVertex {
            let theta = Float(i) / Float(rings) * .pi
            let phi = Float(j) / Float(sides) * .pi * 2
            let unit = SIMD3<Float>(cos(theta), sin(theta) * sin(phi), sin(theta) * cos(phi))
            return vertex(center + unit * radius, simd_normalize(unit / radius), material)
        }
        for i in 0..<rings {
            for j in 0..<sides {
                triangle(point(i, j), point(i + 1, j), point(i + 1, j + 1))
                triangle(point(i, j), point(i + 1, j + 1), point(i, j + 1))
            }
        }
    }

    private mutating func fin(root: SIMD3<Float>, edge: [SIMD3<Float>], material: Float = 1,
                              motion: Float = 0) {
        var outline: [SIMD3<Float>] = []
        for i in 0..<(edge.count - 1) {
            let a = edge[max(0, i - 1)], b = edge[i], c = edge[i + 1], d = edge[min(edge.count - 1, i + 2)]
            let linear: SIMD3<Float> = (c - a) * 0.5
            var quadratic = a
            quadratic -= b * 2.5
            quadratic += c * 2
            quadratic -= d * 0.5
            var cubic: SIMD3<Float> = (d - a) * 0.5
            cubic += (b - c) * 1.5
            for step in 0..<5 {
                let t = Float(step) / 5
                var point = b + linear * t
                point += quadratic * (t * t)
                point += cubic * (t * t * t)
                outline.append(point)
            }
        }
        outline.append(edge.last!)
        for i in 0..<(outline.count - 1) {
            let n = simd_normalize(simd_cross(outline[i] - root, outline[i + 1] - root))
            let frontNormal = n.z < 0 ? -n : n
            let facing = root.z < 0 ? -frontNormal : frontNormal
            // Subdivision lets the shader bend membranes without rigid triangle motion.
            for row in 0..<8 {
                let a = Float(row) / 8, b = Float(row + 1) / 8
                let p0 = root + (outline[i] - root) * a
                let p1 = root + (outline[i] - root) * b
                let p2 = root + (outline[i + 1] - root) * b
                let p3 = root + (outline[i + 1] - root) * a
                let u0 = Float(i) / Float(outline.count - 1)
                let u1 = Float(i + 1) / Float(outline.count - 1)
                triangle(vertex(p0, facing, material, motion, SIMD2(u0, a)),
                         vertex(p1, facing, material, motion, SIMD2(u0, b)),
                         vertex(p2, facing, material, motion, SIMD2(u1, b)))
                triangle(vertex(p0, facing, material, motion, SIMD2(u0, a)),
                         vertex(p2, facing, material, motion, SIMD2(u1, b)),
                         vertex(p3, facing, material, motion, SIMD2(u1, a)))
            }
        }
    }

    private mutating func line(_ points: [SIMD3<Float>], width: Float, material: Float, side: Float = 1) {
        for i in 0..<(points.count - 1) {
            let a = points[i], b = points[i + 1]
            let d = simd_normalize(SIMD3<Float>(-(b.y - a.y), b.x - a.x, 0)) * width
            triangle(vertex(a - d, SIMD3(0, 0, side), material), vertex(b - d, SIMD3(0, 0, side), material), vertex(b + d, SIMD3(0, 0, side), material))
            triangle(vertex(a - d, SIMD3(0, 0, side), material), vertex(b + d, SIMD3(0, 0, side), material), vertex(a + d, SIMD3(0, 0, side), material))
        }
    }

    private mutating func makeFish(_ species: FishSpecies) {
        let height: Float = species == .silver ? 0.115 : species == .clown ? 0.205 : species == .tang ? 0.245 : 0.285
        let girth: Float = species == .silver ? 0.068 : species == .clown ? 0.12 : 0.073
        let rings = 36, sides = 32
        func body(_ i: Int, _ j: Int) -> FishVertex {
            let t = Float(i) / Float(rings)
            let x = -0.34 + t * 0.77
            let angle = Float(j) / Float(sides) * 2 * .pi
            // A narrow caudal peduncle flows into a deep shoulder and a rounded snout.
            let profile = pow(max(0, sin(.pi * t)), 0.62) * (0.49 + 0.65 * t)
            let y = sin(angle) * height * profile
            let z = cos(angle) * girth * profile
            func profileAt(_ value: Float) -> Float {
                pow(max(0, sin(.pi * min(max(value, 0), 1))), 0.62) * (0.49 + 0.65 * value)
            }
            let slope = (profileAt(t + 0.001) - profileAt(t - 0.001)) / 0.00154
            let n = simd_normalize(SIMD3<Float>(-slope, sin(angle) / height, cos(angle) / girth))
            return vertex(SIMD3(x, y, z), n, 0, 0, SIMD2(t, Float(j) / Float(sides)))
        }
        // Far membranes first, then opaque trunk, then near-side detail.
        let tailH: Float = species == .silver ? 0.18 : species == .clown ? 0.17 : 0.225
        let fork: Float = species == .clown ? -0.55 : -0.45
        fin(root: SIMD3(-0.28, 0, 0), edge: [SIMD3(-0.60, tailH, 0), SIMD3(-0.57, tailH * 0.50, 0), SIMD3(fork, 0, 0), SIMD3(-0.57, -tailH * 0.50, 0), SIMD3(-0.60, -tailH, 0)], material: 2)
        fin(root: SIMD3(-0.1, height * 0.50, 0), edge: [SIMD3(-0.28, height * 0.45, 0), SIMD3(-0.22, height * 1.08, 0), SIMD3(-0.04, height * 1.37, 0), SIMD3(0.13, height * 1.18, 0), SIMD3(0.22, height * 0.74, 0)])
        fin(root: SIMD3(-0.07, -height * 0.48, 0), edge: [SIMD3(-0.28, -height * 0.42, 0), SIMD3(-0.2, -height * 1.05, 0), SIMD3(0.01, -height * 1.16, 0), SIMD3(0.15, -height * 0.64, 0)])
        for i in 0..<rings {
            for j in 0..<sides {
                triangle(body(i, j), body(i + 1, j), body(i + 1, j + 1))
                triangle(body(i, j), body(i + 1, j + 1), body(i, j + 1))
            }
        }
        let eyeX: Float = 0.295, eyeY = height * 0.27
        let eyeZ = girth * 0.69
        let eyeSize: Float = species == .silver ? 0.028 : 0.034
        for side: Float in [-1, 1] {
            ellipsoid(center: SIMD3(eyeX, eyeY, eyeZ * side), radius: SIMD3(eyeSize, eyeSize, 0.012), material: 3)
            ellipsoid(center: SIMD3(eyeX + 0.003, eyeY, (eyeZ + 0.010) * side), radius: SIMD3(eyeSize * 0.65, eyeSize * 0.73, 0.008), material: 4)
            ellipsoid(center: SIMD3(eyeX + 0.010, eyeY + eyeSize * 0.30, (eyeZ + 0.018) * side), radius: SIMD3(eyeSize * 0.18, eyeSize * 0.18, 0.003), material: 5, rings: 6, sides: 10)
        }
        var gill: [SIMD3<Float>] = []
        for i in 0...16 {
            let t = Float(i) / 16
            gill.append(SIMD3(0.16 - 0.05 * sin(t * .pi), height * (0.62 - t * 1.18), girth * (0.80 + 0.17 * sin(t * .pi))))
        }
        for side: Float in [-1, 1] {
            line(gill.map { SIMD3($0.x, $0.y, $0.z * side) }, width: 0.0022, material: 6, side: side)
            line([SIMD3(0.401, -height * 0.05, girth * 0.28 * side), SIMD3(0.355, -height * 0.10, girth * 0.49 * side)], width: 0.0025, material: 6, side: side)
            fin(root: SIMD3(0.14, -height * 0.18, girth * 0.92 * side), edge: [SIMD3(0.005, -height * 0.16, girth * 1.50 * side), SIMD3(-0.09, -height * 0.56, girth * 1.90 * side), SIMD3(-0.035, -height * 0.86, girth * 1.70 * side), SIMD3(0.045, -height * 0.74, girth * 1.25 * side)], motion: 1)
        }
    }

    private mutating func makeManta() {
        // Smooth planform: rounded head, broad swept wings, recessed trailing edge.
        let rows = 32, columns = 32
        func wing(_ i: Int, _ j: Int, _ side: Float) -> FishVertex {
            let u = Float(i) / Float(rows), v = Float(j) / Float(columns)
            let span = v * 0.58
            let front = 0.34 - 0.31 * pow(v, 1.6)
            let back = -0.23 + 0.23 * pow(v, 0.6)
            let x = mix(back, front, u)
            let z = 0.085 * sin(.pi * u) * pow(1 - v, 0.6)
            let n = simd_normalize(SIMD3<Float>(0.10 * (u - 0.5), side * 0.30 * v, 1))
            return vertex(SIMD3(x, side * span, z), n, 0, 2, SIMD2(u, v))
        }
        for side: Float in [-1, 1] {
            for i in 0..<rows {
                for j in 0..<columns {
                    triangle(wing(i, j, side), wing(i + 1, j, side), wing(i + 1, j + 1, side))
                    triangle(wing(i, j, side), wing(i + 1, j + 1, side), wing(i, j + 1, side))
                }
            }
        }
        ellipsoid(center: SIMD3(0.08, 0, 0.035), radius: SIMD3(0.27, 0.12, 0.070), material: 0)
        // A long, tapered whip tail with enough segments for a travelling wave.
        for i in 0..<48 {
            let t = Float(i) / 48, next = Float(i + 1) / 48
            let a = SIMD3<Float>(-0.16 - t * 0.72, 0, 0.015)
            let b = SIMD3<Float>(-0.16 - next * 0.72, 0, 0.015)
            let wa: Float = 0.014 * (1 - t) + 0.001
            let wb: Float = 0.014 * (1 - next) + 0.001
            triangle(vertex(a + SIMD3(0, wa, 0), SIMD3(0, 0, 1)), vertex(b + SIMD3(0, wb, 0), SIMD3(0, 0, 1)), vertex(b - SIMD3(0, wb, 0), SIMD3(0, 0, 1)))
            triangle(vertex(a + SIMD3(0, wa, 0), SIMD3(0, 0, 1)), vertex(b - SIMD3(0, wb, 0), SIMD3(0, 0, 1)), vertex(a - SIMD3(0, wa, 0), SIMD3(0, 0, 1)))
        }
        for side: Float in [-1, 1] {
            ellipsoid(center: SIMD3(0.23, side * 0.105, 0.055), radius: SIMD3(0.033, 0.024, 0.025), material: 3)
            ellipsoid(center: SIMD3(0.24, side * 0.109, 0.075), radius: SIMD3(0.018, 0.013, 0.012), material: 4)
            fin(root: SIMD3(0.24, side * 0.070, 0.035), edge: [SIMD3(0.37, side * 0.09, 0.025), SIMD3(0.40, side * 0.058, 0.035), SIMD3(0.30, side * 0.035, 0.06)], material: 0)
        }
    }
}

private func mix(_ a: Float, _ b: Float, _ t: Float) -> Float { a + (b - a) * t }
