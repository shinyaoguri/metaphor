import simd

// MARK: - float4x4 Extensions

extension float4x4 {
    /// 単位行列
    public static let identity = float4x4(diagonal: SIMD4<Float>(1, 1, 1, 1))

    /// X軸回転行列
    public init(rotationX angle: Float) {
        let c = cos(angle)
        let s = sin(angle)
        self.init(columns: (
            SIMD4<Float>(1, 0, 0, 0),
            SIMD4<Float>(0, c, s, 0),
            SIMD4<Float>(0, -s, c, 0),
            SIMD4<Float>(0, 0, 0, 1)
        ))
    }

    /// Y軸回転行列
    public init(rotationY angle: Float) {
        let c = cos(angle)
        let s = sin(angle)
        self.init(columns: (
            SIMD4<Float>(c, 0, -s, 0),
            SIMD4<Float>(0, 1, 0, 0),
            SIMD4<Float>(s, 0, c, 0),
            SIMD4<Float>(0, 0, 0, 1)
        ))
    }

    /// Z軸回転行列
    public init(rotationZ angle: Float) {
        let c = cos(angle)
        let s = sin(angle)
        self.init(columns: (
            SIMD4<Float>(c, s, 0, 0),
            SIMD4<Float>(-s, c, 0, 0),
            SIMD4<Float>(0, 0, 1, 0),
            SIMD4<Float>(0, 0, 0, 1)
        ))
    }

    /// 平行移動行列
    public init(translation: SIMD3<Float>) {
        self.init(columns: (
            SIMD4<Float>(1, 0, 0, 0),
            SIMD4<Float>(0, 1, 0, 0),
            SIMD4<Float>(0, 0, 1, 0),
            SIMD4<Float>(translation.x, translation.y, translation.z, 1)
        ))
    }

    /// スケール行列
    public init(scale: SIMD3<Float>) {
        self.init(diagonal: SIMD4<Float>(scale.x, scale.y, scale.z, 1))
    }

    /// 均一スケール行列
    public init(scale: Float) {
        self.init(diagonal: SIMD4<Float>(scale, scale, scale, 1))
    }

    /// ビュー行列（lookAt）
    public init(lookAt eye: SIMD3<Float>, center: SIMD3<Float>, up: SIMD3<Float>) {
        let z = normalize(eye - center)
        let x = normalize(cross(up, z))
        let y = cross(z, x)

        self.init(columns: (
            SIMD4<Float>(x.x, y.x, z.x, 0),
            SIMD4<Float>(x.y, y.y, z.y, 0),
            SIMD4<Float>(x.z, y.z, z.z, 0),
            SIMD4<Float>(-dot(x, eye), -dot(y, eye), -dot(z, eye), 1)
        ))
    }

    /// 透視投影行列
    public init(perspectiveFov fov: Float, aspect: Float, near: Float, far: Float) {
        let y = 1 / tan(fov * 0.5)
        let x = y / aspect
        let z = far / (near - far)

        self.init(columns: (
            SIMD4<Float>(x, 0, 0, 0),
            SIMD4<Float>(0, y, 0, 0),
            SIMD4<Float>(0, 0, z, -1),
            SIMD4<Float>(0, 0, z * near, 0)
        ))
    }

    /// 正射影行列
    public init(orthographic left: Float, right: Float, bottom: Float, top: Float, near: Float, far: Float) {
        let sx = 2 / (right - left)
        let sy = 2 / (top - bottom)
        let sz = 1 / (near - far)
        let tx = (left + right) / (left - right)
        let ty = (top + bottom) / (bottom - top)
        let tz = near / (near - far)

        self.init(columns: (
            SIMD4<Float>(sx, 0, 0, 0),
            SIMD4<Float>(0, sy, 0, 0),
            SIMD4<Float>(0, 0, sz, 0),
            SIMD4<Float>(tx, ty, tz, 1)
        ))
    }
}

// MARK: - Angle Conversions

/// 度をラジアンに変換
public func radians(_ degrees: Float) -> Float {
    degrees * .pi / 180
}

/// ラジアンを度に変換
public func degrees(_ radians: Float) -> Float {
    radians * 180 / .pi
}

// MARK: - Interpolation

/// 線形補間
public func lerp<T: FloatingPoint>(_ a: T, _ b: T, _ t: T) -> T {
    a + (b - a) * t
}

/// SIMD2の線形補間
public func lerp(_ a: SIMD2<Float>, _ b: SIMD2<Float>, _ t: Float) -> SIMD2<Float> {
    a + (b - a) * t
}

/// SIMD3の線形補間
public func lerp(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ t: Float) -> SIMD3<Float> {
    a + (b - a) * t
}

/// SIMD4の線形補間
public func lerp(_ a: SIMD4<Float>, _ b: SIMD4<Float>, _ t: Float) -> SIMD4<Float> {
    a + (b - a) * t
}

/// 0-1の範囲にクランプ
public func saturate(_ x: Float) -> Float {
    min(max(x, 0), 1)
}

/// smoothstep関数
public func smoothstep(_ edge0: Float, _ edge1: Float, _ x: Float) -> Float {
    let t = saturate((x - edge0) / (edge1 - edge0))
    return t * t * (3 - 2 * t)
}
