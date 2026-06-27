import Foundation

/// 毎フレーム更新と開始/停止のライフサイクルを持つサブシステム（オーディオ、物理、
/// ビデオなど）を統一的に扱うためのプロトコル。
///
/// オーディオ/物理/ビデオなどの補助モジュールは、それぞれ `update()` や `step(dt)` を
/// `draw()` 内で手動呼び出しする設計です。``SketchSubsystem`` に準拠させ
/// ``AutoSubsystemManager`` に登録すると、`draw()` での手動呼び出しなしに毎フレーム
/// 自動で `update(deltaTime:)` が駆動されます。
///
/// これは**追加的なオプトイン**です。従来どおり手動で `update()` を呼ぶコードはそのまま
/// 動作します（自動管理を使う場合だけ登録してください）。
@MainActor
public protocol SketchSubsystem: AnyObject {
    /// レンダーループ開始時に一度呼ばれます。
    func onStart()
    /// レンダーループ停止時に一度呼ばれます。
    func onStop()
    /// 毎フレーム、レンダリング前に呼ばれます。
    /// - Parameter deltaTime: 前フレームからの経過秒（初回は 0）。
    func update(deltaTime: Float)
}

public extension SketchSubsystem {
    func onStart() {}
    func onStop() {}
    func update(deltaTime: Float) {}
}
