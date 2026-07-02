import MetaphorCore
import MetaphorPhysics

// MARK: - 物理ブリッジ

extension Sketch {
    /// 2D物理シミュレーションワールドを作成します。
    ///
    /// - Parameter cellSize: ブロードフェーズ衝突検出用の空間ハッシュセルサイズ。
    /// - Returns: 新しい ``MetaphorPhysics/Physics2D`` インスタンス。
    public func createPhysics2D(cellSize: Float = 50) -> Physics2D {
        guard cellSize > 0 else {
            print("[metaphor] Warning: createPhysics2D: cellSize must be positive (got \(cellSize)); using 50")
            return Physics2D(cellSize: 50)
        }
        return Physics2D(cellSize: cellSize)
    }

    /// ``createPhysics2D(cellSize:)`` の検証付きバリアント。
    ///
    /// - Parameter cellSize: ブロードフェーズ衝突検出用の空間ハッシュセルサイズ（正の値）。
    /// - Returns: 新しい ``MetaphorPhysics/Physics2D`` インスタンス。
    @available(*, deprecated, message: "検証は createPhysics2D(cellSize:) に統合されました（ADR-0005。次の minor で削除予定）")
    public func makePhysics2D(cellSize: Float = 50) throws -> Physics2D {
        guard cellSize > 0 else {
            throw MetaphorError.invalidParameter("cellSize は正の値である必要があります (指定: \(cellSize))")
        }
        return Physics2D(cellSize: cellSize)
    }
}

// MARK: - Node ↔ Physics2D ブリッジ

extension Node {
    /// 2D物理ボディからこのノードの XY 位置を同期します。
    ///
    /// Z 位置は保持されます。`physics.step()` の後に毎フレーム呼び出してください。
    ///
    /// - Parameter body: 位置を読み取る物理ボディ。
    public func syncFromPhysics(_ body: PhysicsBody2D) {
        position = SIMD3(body.position.x, body.position.y, position.z)
    }

    /// このノードの XY 位置を2D物理ボディに書き戻します。
    ///
    /// ボディをノードの位置にテレポートする場合に使用します。
    ///
    /// - Parameter body: 位置を書き込む物理ボディ。
    public func syncToPhysics(_ body: PhysicsBody2D) {
        body.position = SIMD2(position.x, position.y)
        body.previousPosition = body.position
    }
}
