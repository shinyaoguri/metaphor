import Foundation
import simd

/// AI エージェント向けに「いま見えている値」を申告するための API。
///
/// `MetaphorProbePlugin` が登録されているとき、`probe(_:_:)` で送られた値は
/// 現フレームのバッファに蓄積され、スナップショット要求が来たフレームの
/// `frame.json` の `custom` セクションに書き出されます。
///
/// プラグインが登録されていない場合（通常実行や本番ビルド）はこの呼び出しは
/// 完全に no-op で、ホットパスに残しても安全です。
///
/// ```swift
/// override func draw() {
///     probe("particles.count", particles.count)
///     probe("camera.position", cameraPosition)
///     probe("phase", phaseName)
/// }
/// ```
@MainActor
public extension Sketch {
    /// 数値（Double）として記録します。
    func probe(_ name: String, _ value: Double) {
        probePlugin?.recordValue(name: name, value: .double(value))
    }

    /// 数値（Int）として記録します。
    func probe(_ name: String, _ value: Int) {
        probePlugin?.recordValue(name: name, value: .int(value))
    }

    /// 数値（Float）として記録します。Double に昇格して保存されます。
    func probe(_ name: String, _ value: Float) {
        probePlugin?.recordValue(name: name, value: .double(Double(value)))
    }

    /// 文字列として記録します。フェーズ名や状態の説明に。
    func probe(_ name: String, _ value: String) {
        probePlugin?.recordValue(name: name, value: .string(value))
    }

    /// 真偽値として記録します。
    func probe(_ name: String, _ value: Bool) {
        probePlugin?.recordValue(name: name, value: .bool(value))
    }

    /// 2 成分ベクトルとして記録します。`[x, y]` の JSON 配列になります。
    func probe(_ name: String, _ value: SIMD2<Float>) {
        probePlugin?.recordValue(name: name, value: .vec2(value.x, value.y))
    }

    /// 3 成分ベクトルとして記録します。
    func probe(_ name: String, _ value: SIMD3<Float>) {
        probePlugin?.recordValue(name: name, value: .vec3(value.x, value.y, value.z))
    }

    /// 4 成分ベクトルとして記録します。
    func probe(_ name: String, _ value: SIMD4<Float>) {
        probePlugin?.recordValue(name: name, value: .vec4(value.x, value.y, value.z, value.w))
    }

    /// 登録済みの probe プラグインを返します。未登録なら `nil`（呼び出しは no-op）。
    private var probePlugin: MetaphorProbePlugin? {
        _context?.renderer.plugin(id: MetaphorProbePlugin.id) as? MetaphorProbePlugin
    }
}
