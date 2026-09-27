import simd

struct PondGeometry {
    static let imageSize = SIMD2<Float>(1600, 1000)

    // Top-left source coordinates: only opaque corner foliage is excluded.
    // Dark canopy reflections remain water; broad stretches of every edge are open.
    private static let shore: [SIMD2<Float>] = [
        SIMD2(550, 0), SIMD2(1300, 0), SIMD2(1300, 65),
        SIMD2(1410, 105), SIMD2(1470, 150), SIMD2(1530, 180), SIMD2(1600, 190),
        SIMD2(1600, 655), SIMD2(1550, 675), SIMD2(1520, 780), SIMD2(1430, 785),
        SIMD2(1360, 845), SIMD2(1340, 905), SIMD2(1240, 920), SIMD2(1240, 1000),
        SIMD2(220, 1000), SIMD2(220, 955), SIMD2(320, 905), SIMD2(310, 860),
        SIMD2(225, 850), SIMD2(215, 800), SIMD2(175, 760), SIMD2(200, 670),
        SIMD2(120, 650), SIMD2(60, 695), SIMD2(0, 685),
        SIMD2(0, 335), SIMD2(70, 325), SIMD2(85, 225), SIMD2(120, 190),
        SIMD2(250, 200), SIMD2(320, 175), SIMD2(300, 110), SIMD2(270, 70),
        SIMD2(350, 40), SIMD2(385, 95), SIMD2(440, 75), SIMD2(500, 110), SIMD2(550, 65)
    ]

    private static func transform(_ size: SIMD2<Float>) -> (scale: Float, offset: SIMD2<Float>) {
        let scale = max(size.x / imageSize.x, size.y / imageSize.y)
        return (scale, (size - imageSize * scale) * 0.5)
    }

    static func uv(for point: SIMD2<Float>, size: SIMD2<Float>) -> SIMD2<Float> {
        let (scale, offset) = transform(size)
        let imagePoint = (point - offset) / scale
        return SIMD2(imagePoint.x / imageSize.x, 1 - imagePoint.y / imageSize.y)
    }

    static func point(for uv: SIMD2<Float>, size: SIMD2<Float>) -> SIMD2<Float> {
        let (scale, offset) = transform(size)
        return SIMD2(uv.x * imageSize.x, (1 - uv.y) * imageSize.y) * scale + offset
    }

    static func signedDistance(at point: SIMD2<Float>, size: SIMD2<Float>) -> Float {
        guard point.x.isFinite, point.y.isFinite else { return -.infinity }
        let (scale, offset) = transform(size)
        let screenImagePoint = (point - offset) / scale
        let p = SIMD2(screenImagePoint.x, imageSize.y - screenImagePoint.y)
        var closest = Float.infinity
        var inside = false
        for index in shore.indices {
            let a = shore[index]
            let b = shore[(index + 1) % shore.count]
            let edge = b - a
            let t = min(1, max(0, simd_dot(p - a, edge) / simd_length_squared(edge)))
            closest = min(closest, simd_distance(p, a + edge * t))
            if (a.y > p.y) != (b.y > p.y) && p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x {
                inside.toggle()
            }
        }
        let viewportRoom = min(point.x, point.y, size.x - point.x, size.y - point.y)
        return min((inside ? closest : -closest) * scale, viewportRoom)
    }

    static func inwardNormal(at point: SIMD2<Float>, size: SIMD2<Float>) -> SIMD2<Float> {
        let h: Float = 2
        let gradient = SIMD2(
            signedDistance(at: point + SIMD2(h, 0), size: size) - signedDistance(at: point - SIMD2(h, 0), size: size),
            signedDistance(at: point + SIMD2(0, h), size: size) - signedDistance(at: point - SIMD2(0, h), size: size)
        )
        let length = simd_length(gradient)
        return length > 0.0001 && length.isFinite ? gradient / length : SIMD2(0, 1)
    }

    static func contains(_ point: SIMD2<Float>, size: SIMD2<Float>, margin: Float = 0) -> Bool {
        signedDistance(at: point, size: size) >= margin
    }
}
