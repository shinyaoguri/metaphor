import Foundation

/// `Sketch.probe(_:_:)` で蓄積されたユーザー定義値を 1 フレーム分保持します。
///
/// `MetaphorProbePlugin` の `pre()` でリセットされ、`draw()` の中で値が積まれ、
/// `post()` でスナップショットされて `frame.json` の `custom` に書き出されます。
@MainActor
final class ProbeStateBuffer {
    private(set) var values: [String: ProbeValue] = [:]

    func set(_ name: String, _ value: ProbeValue) {
        values[name] = value
    }

    /// 現在の値の不変スナップショットを返します。
    func snapshot() -> [String: ProbeValue] {
        values
    }

    /// 値をすべて空にします。フレーム頭で呼ばれます。
    func reset() {
        values.removeAll(keepingCapacity: true)
    }
}
