import Foundation

// MARK: - PluginRequirements

/// プラグインがレンダーループに求める条件。
///
/// ``PluginFactory`` と ``MetaphorOutputProvider`` が**宣言的に**持ち、`SketchRunner` /
/// `SketchWindow` はレンダーループの駆動方法を決める**前**にこれを集計します
/// （プラグインを先に生成して尋ねる方式は、`onAttach(renderer:)` がレンダラー確定後に
/// 呼ばれる前提を崩すため採りません）。
///
/// ```swift
/// SketchConfig(plugins: [
///     PluginFactory(requirements: [.externalRenderLoop]) { NDIOutput() }
/// ])
/// ```
public struct PluginRequirements: OptionSet, Sendable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    /// ウィンドウのディスプレイリンクから独立したレンダーループ（``RenderLoopMode/timer(fps:)``）を
    /// 必要とする。ウィンドウが隠れても出力を止めたくない Syphon / NDI のような出力先が宣言します。
    /// ``RenderLoopMode/displayLink`` が指定されていれば自動的にタイマー駆動へ切り替わり、
    /// 明示的な ``RenderLoopMode/timer(fps:)`` はそのまま使われます。
    public static let externalRenderLoop = PluginRequirements(rawValue: 1 << 0)
}

// MARK: - MetaphorOutputContext

/// 出力 provider が「この起動で出力を提供するか」を判断するための材料。
///
/// プライマリスケッチ（``SketchConfig``）とセカンダリウィンドウ（``SketchWindowConfig``）の
/// どちらの起動かを ``scope`` が表し、環境変数とヘッドレス（`METAPHOR_VIEWER=1`）かどうかを添えます。
public struct MetaphorOutputContext: Sendable {
    /// 出力を要求している側。
    public enum Scope: Sendable {
        /// プライマリスケッチ（`Sketch.main()` / `SketchRunner`）。
        case primary(SketchConfig)
        /// ``SketchWindow``（セカンダリウィンドウ）。
        case window(SketchWindowConfig)
    }

    /// 出力を要求している側。
    public let scope: Scope

    /// 参照する環境変数（テストから注入できるよう `ProcessInfo` を直接読みません）。
    public let environment: [String: String]

    /// ヘッドレス起動（ウィンドウを開かない）かどうか。
    public let isHeadless: Bool

    public init(scope: Scope, environment: [String: String], isHeadless: Bool) {
        self.scope = scope
        self.environment = environment
        self.isHeadless = isHeadless
    }

    /// ``scope`` がプライマリならその ``SketchConfig``。
    public var sketchConfig: SketchConfig? {
        if case .primary(let config) = scope { return config }
        return nil
    }

    /// ``scope`` がセカンダリウィンドウならその ``SketchWindowConfig``。
    public var windowConfig: SketchWindowConfig? {
        if case .window(let config) = scope { return config }
        return nil
    }
}

// MARK: - MetaphorOutputProvider

/// 出力プラグイン（Syphon / NDI / 開発ツール向け転送など）を起動時に自動配線するための provider。
///
/// `MetaphorCore` は具体的な出力実装を参照しません。出力を持つモジュール（例: `MetaphorSyphon`）が
/// ロード時に ``MetaphorOutputProviders/register(_:)`` で provider を登録し、`SketchRunner` /
/// `SketchWindow` は起動のたびに登録済み provider を**すべて**走査して、``makeOutput(context:)`` が
/// 返した ``MetaphorOutputPlugin`` を出力フェーズに接続します。複数の provider が同時に有効でも
/// 互いを上書きしません。
///
/// ```swift
/// struct NDIOutputProvider: MetaphorOutputProvider {
///     let id = "com.example.ndi"
///     let requirements: PluginRequirements = [.externalRenderLoop]
///
///     func makeOutput(context: MetaphorOutputContext) -> MetaphorOutputPlugin? {
///         guard let name = context.environment["NDI_NAME"] else { return nil }
///         return NDIOutputPlugin(name: name)
///     }
/// }
/// MetaphorOutputProviders.register(NDIOutputProvider())
/// ```
public protocol MetaphorOutputProvider: Sendable {
    /// 安定した識別子。同じ `id` の再登録は置換になります（二重登録に寛容）。
    var id: String { get }

    /// この provider が返す出力プラグインがレンダーループに求める条件（既定は空）。
    /// レンダーループの駆動方法を決める前に集計されます。
    var requirements: PluginRequirements { get }

    /// この起動で出力を提供するなら出力プラグインを返し、提供しないなら `nil` を返します。
    ///
    /// 返したプラグインは `SketchRunner` / `SketchWindow` がレンダラーへ `addPlugin` します
    /// （ここでは生成だけを行い、サーバー起動などは `onAttach(renderer:)` で行ってください）。
    @MainActor
    func makeOutput(context: MetaphorOutputContext) -> MetaphorOutputPlugin?
}

extension MetaphorOutputProvider {
    public var requirements: PluginRequirements { [] }
}

// MARK: - MetaphorOutputProviders

/// 出力 provider の登録ポイント。
///
/// ``MetaphorOutputRegistry`` の後継です。旧 API は単一のファクトリしか持てず、複数の出力モジュールが
/// 自動登録すると後勝ちで上書きされました。ここでは ``MetaphorOutputProvider/id`` で識別される provider を
/// 複数保持し、起動時にすべて走査します。
///
/// ## 登録の仕組み
/// 出力モジュールは C の `__attribute__((constructor))` → `@_cdecl` 関数からプロセス起動時に
/// ``register(_:)`` を呼びます（`MetaphorSyphon` の `CMetaphorSyphonBootstrap` と同じ型）。
/// 登録はロード時の単一スレッドが主ですが、明示的な `enable()` から実行時に呼ばれることもあるため
/// ロックで守ります。走査（`makeOutputs(context:)`）は `MainActor` 上で行われます。
public enum MetaphorOutputProviders {
    /// 登録順を保つ配列。`id` の重複は ``register(_:)`` が置換で解消する。
    private nonisolated(unsafe) static var storage: [any MetaphorOutputProvider] = []
    private static let lock = NSLock()

    /// provider を登録します。同じ ``MetaphorOutputProvider/id`` が既にあれば置き換えます
    /// （ロード時の自動登録と明示的な `enable()` が重なっても二重に出力しない）。
    public static func register(_ provider: any MetaphorOutputProvider) {
        lock.lock()
        defer { lock.unlock() }
        if let index = storage.firstIndex(where: { $0.id == provider.id }) {
            storage[index] = provider
        } else {
            storage.append(provider)
        }
    }

    /// 指定した `id` の provider を登録から外します。無ければ何もしません。
    public static func unregister(id: String) {
        lock.lock()
        defer { lock.unlock() }
        storage.removeAll { $0.id == id }
    }

    /// 登録済み provider（登録順）。
    public static var registered: [any MetaphorOutputProvider] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    /// 走査の結果 1 件。生成済みプラグインと、その provider が宣言した要件。
    struct ResolvedOutput {
        let providerID: String
        let plugin: MetaphorOutputPlugin
        let requirements: PluginRequirements
    }

    /// 登録済み provider をすべて走査し、この起動で提供される出力を集めます。
    ///
    /// 旧 API ``MetaphorOutputRegistry/factory``（deprecated）にファクトリが残っていれば、
    /// 従来の名前解決（`METAPHOR_SYPHON_NAME` > `syphonName` > `syphon` / ヘッドレスなら `title`）で
    /// 1 件生成して末尾に加えます（挙動互換。旧 API とともに削除予定）。
    @MainActor
    static func makeOutputs(context: MetaphorOutputContext) -> [ResolvedOutput] {
        var outputs: [ResolvedOutput] = []
        for provider in registered {
            if let plugin = provider.makeOutput(context: context) {
                outputs.append(ResolvedOutput(
                    providerID: provider.id, plugin: plugin, requirements: provider.requirements
                ))
            }
        }
        if let legacy = MetaphorOutputRegistry.makeLegacyOutput(context: context) {
            outputs.append(legacy)
        }
        return outputs
    }
}
