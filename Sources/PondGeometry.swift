import simd

struct PondGeometry {
    static let imageSize = SIMD2<Float>(1600, 1000)

    // Source-image coordinates, clockwise from the upper-left bank. The line is
    // deliberately inside the visible water so effects never spill onto land.
    private static let shore: [SIMD2<Float>] = [
        SIMD2(215, 205), SIMD2(245, 145), SIMD2(330, 112), SIMD2(455, 126),
        SIMD2(570, 139), SIMD2(665, 119), SIMD2(800, 124), SIMD2(915, 147),
        SIMD2(1030, 185), SIMD2(1130, 222), SIMD2(1220, 202), SIMD2(1310, 215),
        SIMD2(1370, 277), SIMD2(1400, 390), SIMD2(1460, 495), SIMD2(1470, 610),
        SIMD2(1415, 690), SIMD2(1335, 740), SIMD2(1245, 775), SIMD2(1170, 812),
        SIMD2(1080, 823), SIMD2(974, 802), SIMD2(865, 768), SIMD2(763, 739),
        SIMD2(665, 738), SIMD2(595, 779), SIMD2(495, 778), SIMD2(408, 729),
        SIMD2(325, 672), SIMD2(251, 625), SIMD2(185, 562), SIMD2(143, 474),
        SIMD2(145, 365), SIMD2(172, 278)
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
        return (inside ? closest : -closest) * scale
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
