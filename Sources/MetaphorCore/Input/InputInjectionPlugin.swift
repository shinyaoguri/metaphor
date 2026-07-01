import Foundation
import Metal
import os

/// 標準入力（stdin）から JSON Lines 形式の入力イベントを読み取り、
/// ``InputManager`` に注入するプラグイン。
///
/// ヘッドレスモード（環境変数 `METAPHOR_VIEWER=1`）でスケッチを子プロセスとして
/// 実行する metaphor-cli のライブビューアが、親プロセスでキャプチャしたマウス/
/// キーイベントを子プロセスへ転送するために使用します。座標は**キャンバス座標系**で
/// 受け取ります（ビュー→キャンバスの逆変換は親プロセスの責務）。
///
/// ## プロトコル
///
/// stdin に 1 行 1 イベントの JSON を書き込みます（`\n` 区切り）。`t` がイベント種別:
///
/// ```text
/// {"t":"mouseDown","x":120.0,"y":80.0,"button":0}
/// {"t":"mouseUp","x":120.0,"y":80.0,"button":0}
/// {"t":"mouseMove","x":120.0,"y":80.0}
/// {"t":"mouseDrag","x":120.0,"y":80.0}
/// {"t":"scroll","dx":0.0,"dy":-2.0}
/// {"t":"keyDown","code":53,"chars":"a","repeat":false}
/// {"t":"keyUp","code":53}
/// ```
///
/// 読み取りは専用スレッドで行い、パース済みイベントをロック付きキューに溜め、
/// 各フレーム冒頭の ``pre(commandBuffer:time:)`` でメインアクター上から
/// ``InputManager`` に流し込みます。``InputManager/updateFrame()`` が同フレームの
/// `pre()` より前に呼ばれるため、`pmouseX`/`pmouseY` の更新も正しく機能します。
///
/// ## 性能契約（ランタイム非侵害・Issue #118）
///
/// stdin の読み取りは**専用スレッド**で行うため描画スレッドを塞ぎません。`pre()` は
/// キューが空なら（＝イベント未着なら）ロック取得後すぐ `return` し、`InputManager` にも
/// 触れません。dispatch は溜まったイベントがある時だけ発生します。未登録（通常実行）時は
/// フレームループから一切呼ばれずゼロコスト。回帰ガードは
/// `Tests/metaphorTests/ObservabilityOverheadTests.swift`。
@MainActor
public final class InputInjectionPlugin: MetaphorPlugin {
    /// 安定したプラグイン識別子。
    public static let id = "org.metaphor.input-injection"

    public let pluginID: String

    /// 接続中のレンダラーへの弱参照。``InputManager`` への到達に利用します。
    weak var renderer: MetaphorRenderer?

    /// stdin リーダースレッドが溜めた未処理イベント（複数スレッドから触るためロックで保護）。
    private let pending = OSAllocatedUnfairLock<[RawInputEvent]>(initialState: [])

    /// リーダースレッドを多重起動しないためのフラグ。
    private var readerStarted = false

    /// 描画ループが大きく停滞した場合に未処理キューが無限に伸びるのを防ぐ上限。
    /// 超過分は最古から捨てる。
    private static let maxPendingEvents = 4096

    /// テスト用にカスタムのイベント供給元を差し込むためのフック。
    /// 実行時は `nil`（stdin から読む）。
    private let lineSource: (@Sendable () -> String?)?

    /// - Parameter lineSource: 1 行ずつイベント JSON を返すクロージャ。`nil` の場合は
    ///   標準入力から読み取ります。テストでのみ指定します。
    public init(lineSource: (@Sendable () -> String?)? = nil) {
        self.pluginID = Self.id
        self.lineSource = lineSource
    }

    // MARK: - Lifecycle

    public func onAttach(renderer: MetaphorRenderer) {
        self.renderer = renderer
        startReaderIfNeeded()
    }

    public func onDetach() {
        renderer = nil
    }

    // MARK: - Frame hook

    public func pre(commandBuffer: MTLCommandBuffer, time: Double) {
        let events = pending.withLock { queue -> [RawInputEvent] in
            guard !queue.isEmpty else { return [] }
            let drained = queue
            queue.removeAll(keepingCapacity: true)
            return drained
        }
        guard !events.isEmpty, let input = renderer?.input else { return }
        for event in events {
            dispatch(event, to: input)
        }
    }

    // MARK: - stdin reader

    private func startReaderIfNeeded() {
        guard !readerStarted else { return }
        readerStarted = true

        let pending = self.pending
        let source = self.lineSource
        let cap = Self.maxPendingEvents

        let thread = Thread {
            let nextLine: () -> String? = source ?? { readLine(strippingNewline: true) }
            while let line = nextLine() {
                if line.isEmpty { continue }
                guard let data = line.data(using: .utf8),
                      let event = try? JSONDecoder().decode(RawInputEvent.self, from: data)
                else {
                    // 不正な入力イベントは無視するが、なぜ反映されないのかを切り分け
                    // できるよう METAPHOR_DEBUG=1 のときだけ診断を残す。
                    metaphorDiagnostic("input: 不正な JSON Lines イベントを無視: \(line)")
                    continue
                }
                pending.withLock { queue in
                    queue.append(event)
                    if queue.count > cap {
                        queue.removeFirst(queue.count - cap)
                    }
                }
            }
        }
        thread.name = "metaphor.input-injection.reader"
        thread.stackSize = 1 << 16
        thread.start()
    }

    // MARK: - Dispatch

    private func dispatch(_ event: RawInputEvent, to input: InputManager) {
        switch event.t {
        case "mouseDown":
            input.handleMouseDown(x: event.x ?? 0, y: event.y ?? 0, button: event.button ?? 0)
        case "mouseUp":
            input.handleMouseUp(x: event.x ?? 0, y: event.y ?? 0, button: event.button ?? 0)
        case "mouseMove":
            input.handleMouseMoved(x: event.x ?? 0, y: event.y ?? 0)
        case "mouseDrag":
            input.handleMouseDragged(x: event.x ?? 0, y: event.y ?? 0)
        case "scroll":
            input.handleMouseScrolled(dx: event.dx ?? 0, dy: event.dy ?? 0)
        case "keyDown":
            input.handleKeyDown(
                keyCode: event.code ?? 0,
                characters: event.chars,
                isRepeat: event.repeat ?? false
            )
        case "keyUp":
            input.handleKeyUp(keyCode: event.code ?? 0)
        default:
            break  // 未知のイベント種別は無視
        }
    }
}

/// stdin から 1 行ずつデコードする入力イベント。全フィールドはイベント種別ごとに
/// 任意で、欠落時は ``InputInjectionPlugin`` がゼロ既定値で補います。
struct RawInputEvent: Decodable, Sendable {
    let t: String
    let x: Float?
    let y: Float?
    let button: Int?
    let dx: Float?
    let dy: Float?
    let code: UInt16?
    let chars: String?
    let `repeat`: Bool?
}
