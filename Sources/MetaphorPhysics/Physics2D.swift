import simd

/// Verlet 積分を使用した2D物理ワールドを管理します。
///
/// ``Physics2D`` は円と軸整列矩形をサポートするシンプルな剛体シミュレーションを提供します。
/// ボディは Verlet 積分で統合され、衝突は空間ハッシュで検出され、
/// 拘束は各ステップで反復的に解決されます。
///
/// ```swift
/// let world = Physics2D(cellSize: 50)
/// world.addGravity(0, 980)
/// let ball = world.addCircle(x: 100, y: 100, radius: 20)
/// world.step(1.0 / 60.0)
/// ```
@MainActor
public final class Physics2D {
    /// 現在ワールド内にある物理ボディのリスト。
    public private(set) var bodies: [PhysicsBody2D] = []

    /// 現在ワールド内にある拘束のリスト。
    public private(set) var constraints: [PhysicsConstraint2D] = []

    /// 各ステップですべての非静的ボディに適用されるグローバル重力加速度。
    private var gravity: SIMD2<Float> = SIMD2(0, 0)

    /// ブロードフェーズ衝突検出に使用される空間ハッシュ。
    private let spatialHash: SpatialHash2D

    /// すべてのボディを制限範囲内に閉じ込めるオプションのバウンディングボックス。
    ///
    /// 設定すると、各反復でボディが `min` と `max` の範囲内にクランプされます。
    public var bounds: (min: SIMD2<Float>, max: SIMD2<Float>)?

    /// 新しい2D物理ワールドを作成します。
    ///
    /// - Parameter cellSize: ブロードフェーズ衝突検出に使用する空間ハッシュのセルサイズ。
    ///   値が大きいほどハッシュのオーバーヘッドは減りますが、チェックする候補ペア数が増えます。
    public init(cellSize: Float = 50) {
        self.spatialHash = SpatialHash2D(cellSize: cellSize)
    }

    // MARK: - ボディ作成

    /// 円形の物理ボディをワールドに追加します。
    ///
    /// - Parameters:
    ///   - x: ボディの初期 X 座標。
    ///   - y: ボディの初期 Y 座標。
    ///   - radius: 円の半径。
    ///   - mass: ボディの質量（デフォルトは1.0）。
    /// - Returns: 新しく作成された ``PhysicsBody2D`` インスタンス。
    @discardableResult
    public func addCircle(x: Float, y: Float, radius: Float, mass: Float = 1.0) -> PhysicsBody2D {
        let body = PhysicsBody2D(x: x, y: y, shape: .circle(radius: radius), mass: mass)
        bodies.append(body)
        return body
    }

    /// 矩形の物理ボディをワールドに追加します。
    ///
    /// - Parameters:
    ///   - x: ボディ中心の初期 X 座標。
    ///   - y: ボディ中心の初期 Y 座標。
    ///   - width: 矩形の幅。
    ///   - height: 矩形の高さ。
    ///   - mass: ボディの質量（デフォルトは1.0）。
    /// - Returns: 新しく作成された ``PhysicsBody2D`` インスタンス。
    @discardableResult
    public func addRect(x: Float, y: Float, width: Float, height: Float, mass: Float = 1.0) -> PhysicsBody2D {
        let body = PhysicsBody2D(x: x, y: y, shape: .rect(width: width, height: height), mass: mass)
        bodies.append(body)
        return body
    }

    // MARK: - 力

    /// 各ステップですべてのボディに適用されるグローバル重力加速度を設定します。
    ///
    /// - Parameters:
    ///   - x: 重力ベクトルの水平成分。
    ///   - y: 重力ベクトルの垂直成分。
    public func addGravity(_ x: Float, _ y: Float) {
        gravity = SIMD2(x, y)
    }

    // MARK: - 拘束

    /// 2つのボディ間に距離拘束を追加します。
    ///
    /// - Parameters:
    ///   - a: 1つ目のボディ。
    ///   - b: 2つ目のボディ。
    ///   - distance: 2つのボディ間の目標距離。`nil` の場合、
    ///     作成時の現在の距離が使用されます。
    /// - Returns: 新しく作成された ``PhysicsConstraint2D`` インスタンス。
    @discardableResult
    public func addConstraint(_ a: PhysicsBody2D, _ b: PhysicsBody2D, distance: Float? = nil) -> PhysicsConstraint2D {
        let c = PhysicsConstraint2D(a, b, distance: distance)
        constraints.append(c)
        return c
    }

    /// ボディをワールド空間の固定位置にピン留めします。
    ///
    /// - Parameters:
    ///   - body: ピン留めするボディ。
    ///   - x: ピン位置の X 座標。
    ///   - y: ピン位置の Y 座標。
    /// - Returns: 新しく作成されたピン ``PhysicsConstraint2D`` インスタンス。
    @discardableResult
    public func pin(_ body: PhysicsBody2D, x: Float, y: Float) -> PhysicsConstraint2D {
        let c = PhysicsConstraint2D(pin: body, x: x, y: y)
        constraints.append(c)
        return c
    }

    // MARK: - シミュレーション

    /// シミュレーションを1タイムステップ進めます。
    ///
    /// 重力を適用し、Verlet 積分で位置を更新してから、
    /// 拘束の解決と衝突の解消を反復的に行います。
    ///
    /// - Parameters:
    ///   - dt: タイムステップ（秒）。
    ///   - iterations: 拘束・衝突解決の反復回数
    ///     （デフォルトは4）。反復回数が多いほど安定した結果が得られます。
    public func step(_ dt: Float, iterations: Int = 4) {
        // 重力を適用
        for body in bodies {
            body.applyForce(gravity * body.mass)
        }

        // 積分
        for body in bodies {
            body.integrate(dt: dt)
        }

        // 拘束と衝突を解決
        for _ in 0..<iterations {
            // 拘束
            for c in constraints {
                c.solve()
            }

            // 衝突検出 + 解消
            resolveCollisions()

            // 境界
            if let bounds = bounds {
                applyBounds(bounds)
            }
        }
    }

    // MARK: - 削除

    /// ボディとそれを参照するすべての拘束をワールドから削除します。
    ///
    /// - Parameter body: 削除するボディ。
    public func removeBody(_ body: PhysicsBody2D) {
        bodies.removeAll { $0 === body }
        constraints.removeAll { $0.bodyA === body || $0.bodyB === body }
    }

    /// 特定の拘束をワールドから削除します。
    ///
    /// - Parameter constraint: 削除する拘束。
    public func removeConstraint(_ constraint: PhysicsConstraint2D) {
        constraints.removeAll { $0 === constraint }
    }

    /// すべてのボディと拘束をワールドから削除します。
    public func clear() {
        bodies.removeAll()
        constraints.removeAll()
    }

    // MARK: - プライベート

    /// ブロードフェーズに空間ハッシュを使用して衝突を検出・解消します。
    private func resolveCollisions() {
        spatialHash.clear()

        for (i, body) in bodies.enumerated() {
            let radius = boundingRadius(body)
            spatialHash.insert(index: i, position: body.position, radius: radius)
        }

        let pairs = spatialHash.queryPairs()
        for (i, j) in pairs {
            resolveCollision(bodies[i], bodies[j])
        }
    }

    /// ブロードフェーズ挿入用のバウンディング半径を計算します。
    private func boundingRadius(_ body: PhysicsBody2D) -> Float {
        switch body.shape {
        case .circle(let r): return r
        case .rect(let w, let h): return sqrt(w * w + h * h) * 0.5
        }
    }

    /// 形状ペアに基づいて衝突解消を振り分けます。
    private func resolveCollision(_ a: PhysicsBody2D, _ b: PhysicsBody2D) {
        if a.isStatic && b.isStatic { return }

        switch (a.shape, b.shape) {
        case (.circle(let ra), .circle(let rb)):
            resolveCircleCircle(a, ra, b, rb)
        case (.circle(let r), .rect(let w, let h)):
            resolveCircleRect(a, r, b, w, h)
        case (.rect(let w, let h), .circle(let r)):
            resolveCircleRect(b, r, a, w, h)
        case (.rect(let wa, let ha), .rect(let wb, let hb)):
            resolveRectRect(a, wa, ha, b, wb, hb)
        }
    }

    /// 質量重み付き位置補正を使用して2つの円の重なりを解消します。
    private func resolveCircleCircle(_ a: PhysicsBody2D, _ ra: Float, _ b: PhysicsBody2D, _ rb: Float) {
        let delta = b.position - a.position
        let dist = simd_length(delta)
        let minDist = ra + rb

        guard dist < minDist, dist > 0.0001 else { return }

        let normal = delta / dist
        let overlap = minDist - dist

        let totalMass = (a.isStatic ? 0 : a.mass) + (b.isStatic ? 0 : b.mass)
        guard totalMass > 0 else { return }

        if !a.isStatic { a.position -= normal * overlap * (b.isStatic ? 1 : b.mass / totalMass) }
        if !b.isStatic { b.position += normal * overlap * (a.isStatic ? 1 : a.mass / totalMass) }
    }

    /// 最近点投影を使用して円と矩形の重なりを解消します。
    private func resolveCircleRect(_ circle: PhysicsBody2D, _ r: Float, _ rect: PhysicsBody2D, _ w: Float, _ h: Float) {
        let hw = w * 0.5
        let hh = h * 0.5
        let delta = circle.position - rect.position
        let closest = SIMD2(
            max(-hw, min(hw, delta.x)),
            max(-hh, min(hh, delta.y))
        )
        let diff = delta - closest
        let dist = simd_length(diff)

        guard dist < r, dist > 0.0001 else { return }

        let normal = diff / dist
        let overlap = r - dist

        let totalMass = (circle.isStatic ? 0 : circle.mass) + (rect.isStatic ? 0 : rect.mass)
        guard totalMass > 0 else { return }

        if !circle.isStatic { circle.position += normal * overlap * (rect.isStatic ? 1 : rect.mass / totalMass) }
        if !rect.isStatic { rect.position -= normal * overlap * (circle.isStatic ? 1 : circle.mass / totalMass) }
    }

    /// 最小貫通軸を使用して2つの軸整列矩形の重なりを解消します。
    private func resolveRectRect(_ a: PhysicsBody2D, _ wa: Float, _ ha: Float, _ b: PhysicsBody2D, _ wb: Float, _ hb: Float) {
        // AABB 衝突
        let hwa = wa * 0.5
        let hha = ha * 0.5
        let hwb = wb * 0.5
        let hhb = hb * 0.5

        let dx = b.position.x - a.position.x
        let dy = b.position.y - a.position.y
        let overlapX = hwa + hwb - abs(dx)
        let overlapY = hha + hhb - abs(dy)

        guard overlapX > 0, overlapY > 0 else { return }

        let totalMass = (a.isStatic ? 0 : a.mass) + (b.isStatic ? 0 : b.mass)
        guard totalMass > 0 else { return }

        if overlapX < overlapY {
            let sign: Float = dx > 0 ? 1 : -1
            if !a.isStatic { a.position.x -= sign * overlapX * (b.isStatic ? 1 : b.mass / totalMass) }
            if !b.isStatic { b.position.x += sign * overlapX * (a.isStatic ? 1 : a.mass / totalMass) }
        } else {
            let sign: Float = dy > 0 ? 1 : -1
            if !a.isStatic { a.position.y -= sign * overlapY * (b.isStatic ? 1 : b.mass / totalMass) }
            if !b.isStatic { b.position.y += sign * overlapY * (a.isStatic ? 1 : a.mass / totalMass) }
        }
    }

    /// すべての非静的ボディをワールド境界内にクランプし、形状サイズを考慮します。
    private func applyBounds(_ bounds: (min: SIMD2<Float>, max: SIMD2<Float>)) {
        for body in bodies where !body.isStatic {
            switch body.shape {
            case .circle(let r):
                body.position.x = max(bounds.min.x + r, min(bounds.max.x - r, body.position.x))
                body.position.y = max(bounds.min.y + r, min(bounds.max.y - r, body.position.y))
            case .rect(let w, let h):
                let hw = w * 0.5
                let hh = h * 0.5
                body.position.x = max(bounds.min.x + hw, min(bounds.max.x - hw, body.position.x))
                body.position.y = max(bounds.min.y + hh, min(bounds.max.y - hh, body.position.y))
            }
        }
    }
}
