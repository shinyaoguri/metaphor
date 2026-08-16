import simd

/// `normal()` を書かなかったカスタム 3D シェイプへ入れる法線を、三角形化済みの
/// インデックス列から求める（#738）。
///
/// 規則は 1 つだけ: **インデックス列を 1 三角形ずつ読み、面法線を 3 頂点へ加算し、
/// 最後に頂点ごとに正規化する。** モードごとの分岐を持たないので、
/// `.polygon` / `.triangles` / `.triangleStrip` / `.triangleFan` が同じ経路で片付く。
///
/// - `.polygon` / `.triangleFan` は同一平面のファンなら全三角形の面法線が一致するため、
///   結果は「先頭 3 頂点の面法線を全頂点へ」と同じになる（イミディエイト側の
///   `drawShape3DPolygon` と一致する）。非平面ならむしろ素直な結果になる。
/// - `.triangleStrip` の巻き方向の反転は**インデックスを組む側が既に補正済み**
///   （偶数番は `[i, i+1, i+2]`、奇数番は `[i+1, i, i+2]`）なので、出来上がった
///   インデックス順から計算すれば向きは自動的に揃う。ここに奇偶の分岐は要らない。
/// - `.lines` / `.points` は面のインデックス列を持たないので、呼び出し側がここを
///   通さない（法線は既定値のまま）。線・点に面法線は無い。
///
/// リテインド（`MShapeBuilder.buildFillMesh3D()`）とイミディエイト
/// （`Canvas3D+Shapes.swift` の `drawShape3DIndexed()`）の両方がここを呼ぶので、
/// 同じ形を書けば層をまたいでも同じ法線が付きます（#875 でイミディエイト側を
/// 「3 頂点ごと」の別規則からここへ寄せました）。
enum FaceNormals {

    /// 法線が定まらないとき（退化三角形・どの三角形にも属さない頂点）に入れる既定値。
    /// `vertex(x, y, z)` が法線未指定のときに入れる値と同じ。
    static let fallback = SIMD3<Float>(0, 1, 0)

    /// 三角形化済みのインデックス列から頂点法線を求めます。
    ///
    /// - Parameters:
    ///   - positions: 頂点位置（インデックスの参照先）。
    ///   - indices: 3 つ 1 組の三角形インデックス列。
    /// - Returns: `positions` と同じ並びの頂点法線。
    static func compute(
        positions: [SIMD3<Float>], indices: [UInt32]
    ) -> [SIMD3<Float>] {
        var accumulated = [SIMD3<Float>](repeating: .zero, count: positions.count)

        var i = 0
        while i + 2 < indices.count {
            let i0 = Int(indices[i])
            let i1 = Int(indices[i + 1])
            let i2 = Int(indices[i + 2])
            i += 3
            guard i0 < positions.count, i1 < positions.count, i2 < positions.count else { continue }

            // 正規化しない外積をそのまま足す。長さが三角形の面積の 2 倍になるので、
            // 大きい面ほど強く効く（面積重み付き法線）。退化三角形は零ベクトルに
            // なるので、加算しても他の面の寄与を壊さない。
            let p0 = positions[i0]
            let cross = simd_cross(positions[i1] - p0, positions[i2] - p0)
            accumulated[i0] += cross
            accumulated[i1] += cross
            accumulated[i2] += cross
        }

        return accumulated.map { sum in
            // 零ベクトル（退化三角形だけ／どの三角形にも属さない頂点）の正規化は
            // NaN になるので、既定値へ落とす。
            simd_length_squared(sum) > 0 ? simd_normalize(sum) : fallback
        }
    }
}
