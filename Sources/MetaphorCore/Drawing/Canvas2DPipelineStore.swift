import Metal

// MARK: - 2D パイプラインの識別

/// 2D 描画パイプラインの系統。頂点レイアウトと組み込みシェーダー関数の組を表します。
///
/// `Canvas2D` の 4 つの flush 経路（カラー頂点・テクスチャ頂点・インスタンス・massive 円）に
/// 対応します。テクスチャ頂点だけは、テクスチャの α の持ち方で 2 系統に分かれます。
enum Canvas2DPipelineKind: Hashable, CaseIterable, Sendable {
    /// 色付き頂点バッチ（`flushColorVertices`）。
    case color
    /// テクスチャ付き頂点バッチ（`flushTexturedVertices`）。テクスチャは premultiplied。
    case textured
    /// テクスチャ付き頂点バッチのうち、**テクスチャが straight** のもの（`updatePixels()`）。
    ///
    /// 頂点レイアウトも頂点関数も ``textured`` と同じで、違うのはフラグメントが
    /// サンプル値を割り戻すかどうかだけです（ADR-0012 / #848）。
    case straightTextured
    /// インスタンス描画バッチ（`flushInstancedBatch`）。
    case instanced
    /// massive 円インスタンス（`circles()`）。
    case massiveCircle
}

/// 描画コマンドが保持するパイプラインの識別子（#646 / Epic #291 E1）。
///
/// **記録時にこの値を確定させ、再生時は ``Canvas2DPipelineStore`` を引くだけにします。**
/// 以前は再生時に `Canvas2D.currentBlendMode` を引いてパイプラインを選んでいたため、
/// 記録したコマンドの描画結果が「再生時点の Canvas2D の可変状態」に依存していました。
/// キーを記録側で焼き込むことで、コマンド列だけで描画結果が一意に決まります
/// （#71 の決定論コマンドストリームが要求する性質）。
///
/// E2（#647）でこのキーにカスタムシェーダの識別子が加わり、
/// ``Canvas2DPipelineStore`` 側がカスタムパイプラインをキャッシュします。
struct Canvas2DPipelineKey: Hashable, Sendable {
    /// パイプラインの系統。
    let kind: Canvas2DPipelineKind
    /// ブレンドモード。
    let blend: BlendMode
    /// 適用中のカスタムフラグメントシェーダ。組み込みシェーダなら nil（#647 / Epic #291 E2）。
    let shader: Canvas2DShaderID?

    init(_ kind: Canvas2DPipelineKind, _ blend: BlendMode, shader: Canvas2DShaderID? = nil) {
        self.kind = kind
        self.blend = blend
        self.shader = shader
    }
}

// MARK: - パイプラインストア

/// Canvas2D の描画パイプラインを一元的に生成・保持します（#646 / Epic #291 E1）。
///
/// 以前は `Canvas2D` が系統ごとに 4 本の `[BlendMode: MTLRenderPipelineState]` を持ち、
/// 生成コードが `init` に直書きされていました。ここへ集約したことで、
///
/// - 記録側は ``state(for:)`` 1 本でパイプラインを解決できる
/// - E2 のカスタムシェーダは、この 1 つの辞書にエントリを足すだけで載る
/// - パイプライン生成に必要な材料（device / shaderLibrary / sampleCount）が 1 か所に集まる
///
/// という 3 点が揃います。
@MainActor
final class Canvas2DPipelineStore {
    private let device: MTLDevice
    private let shaderLibrary: ShaderLibrary
    private let sampleCount: Int

    /// 解決済みパイプライン。組み込み分は `init` で全件先行生成し、
    /// カスタムシェーダ分は初回参照時に遅延生成してここへ足します。
    private var states: [Canvas2DPipelineKey: MTLRenderPipelineState] = [:]

    /// 適用中のカスタムシェーダのフラグメント関数（#647）。
    /// `Canvas2D.shader(_:)` が ``register(_:)`` 経由で登録します。
    private var customFunctions: [Canvas2DShaderID: MTLFunction] = [:]

    /// パイプライン生成に失敗したカスタムキー。毎フレーム再試行しないための負のキャッシュ。
    private var failedCustomKeys: Set<Canvas2DPipelineKey> = []

    /// カスタムパイプラインへフォールバックした旨の警告を出したかどうか（初回のみ出す）。
    private var didWarnFallback = false

    /// 組み込みパイプラインを全系統 × 全ブレンドモード分だけ生成します。
    ///
    /// - Parameters:
    ///   - device: パイプライン生成に使う Metal デバイス。
    ///   - shaderLibrary: 組み込み 2D シェーダーを含むシェーダーライブラリ。
    ///   - sampleCount: MSAA サンプル数。
    /// - Throws: パイプラインを作成できない場合（組み込み関数が見つからない場合を含む）に
    ///   ``MetaphorError/pipelineCreationFailed(name:underlying:)``。
    init(device: MTLDevice, shaderLibrary: ShaderLibrary, sampleCount: Int) throws {
        self.device = device
        self.shaderLibrary = shaderLibrary
        self.sampleCount = sampleCount

        states.reserveCapacity(Canvas2DPipelineKind.allCases.count * BlendMode.allCases.count)
        for kind in Canvas2DPipelineKind.allCases {
            for blend in BlendMode.allCases {
                states[Canvas2DPipelineKey(kind, blend)] = try makeBuiltin(kind: kind, blend: blend)
            }
        }
    }

    /// キーに対応するパイプラインを返します。未登録なら `nil`。
    ///
    /// 再生時（`Canvas2D.encode(_:into:)`）はこの引きだけを行い、
    /// Canvas2D の可変状態は一切参照しません。
    ///
    /// カスタムシェーダのキー（`key.shader != nil`）は初回だけここで生成します。
    /// 生成に失敗した場合は**同じ系統・ブレンドの組み込みパイプラインへフォールバック**します
    /// （nil を返すと呼び出し側の flush が描画ごと捨ててしまい、絵が消えるため）。
    func state(for key: Canvas2DPipelineKey) -> MTLRenderPipelineState? {
        if let cached = states[key] { return cached }
        // 組み込みキーは init で全件生成済み。ここに来るのはカスタムキーだけ。
        guard let shaderID = key.shader else { return nil }
        guard !failedCustomKeys.contains(key), let fragment = customFunctions[shaderID] else {
            return builtinFallback(for: key)
        }
        do {
            let state = try makeCustom(kind: key.kind, blend: key.blend, fragment: fragment)
            states[key] = state
            return state
        } catch {
            failedCustomKeys.insert(key)
            warnFallback(kind: key.kind, error: error)
            return builtinFallback(for: key)
        }
    }

    /// カスタムシェーダのフラグメント関数を登録します（`Canvas2D.shader(_:)` から呼ばれます）。
    func register(_ shader: Shader2D) {
        customFunctions[shader.id] = shader.fragmentFunction
    }

    /// カスタムパイプラインのキャッシュを捨てます（シェーダのホットリロード後・#648 / E3 用）。
    ///
    /// 組み込み分は影響を受けません。
    func invalidateCustomPipelines() {
        states = states.filter { $0.key.shader == nil }
        failedCustomKeys.removeAll()
    }

    /// カスタムパイプラインを生成できなかったときの逃げ先（同じ系統・ブレンドの組み込み）。
    private func builtinFallback(for key: Canvas2DPipelineKey) -> MTLRenderPipelineState? {
        states[Canvas2DPipelineKey(key.kind, key.blend)]
    }

    private func warnFallback(kind: Canvas2DPipelineKind, error: Error) {
        guard !didWarnFallback else { return }
        didWarnFallback = true
        metaphorAlert("""
        カスタム 2D シェーダを \(kind) 経路のパイプラインに載せられませんでした。\
        組み込みシェーダで描画します（フラグメント関数の stage_in が \
        この経路の頂点出力と合っていない可能性があります）: \(error)
        """)
    }

    // MARK: - パイプラインの生成

    /// 組み込み頂点関数 + カスタムフラグメント関数でパイプラインを作ります。
    ///
    /// 頂点側は差し替えません。2D の頂点は投影変換と色の受け渡しだけを行い、
    /// カスタマイズの余地はフラグメント側にあるためです。
    private func makeCustom(
        kind: Canvas2DPipelineKind, blend: BlendMode, fragment: MTLFunction
    ) throws -> MTLRenderPipelineState {
        let functions = Self.builtinFunctions(kind: kind, blend: blend)
        return try PipelineFactory(device: device)
            .vertex(shaderLibrary.function(named: functions.vertex, from: functions.libraryKey))
            .fragment(fragment)
            .vertexLayout(Self.vertexLayout(for: kind))
            .blending(blend)
            .sampleCount(sampleCount)
            .build()
    }

    // MARK: - 組み込みパイプラインの生成

    private func makeBuiltin(
        kind: Canvas2DPipelineKind, blend: BlendMode
    ) throws -> MTLRenderPipelineState {
        let functions = Self.builtinFunctions(kind: kind, blend: blend)
        return try PipelineFactory(device: device)
            .vertex(shaderLibrary.function(named: functions.vertex, from: functions.libraryKey))
            .fragment(shaderLibrary.function(named: functions.fragment, from: functions.libraryKey))
            .vertexLayout(Self.vertexLayout(for: kind))
            .blending(blend)
            .sampleCount(sampleCount)
            .build()
    }

    /// 系統とブレンドモードから、使用する組み込みシェーダー関数を決めます。
    ///
    /// 分離可能ブレンドモード（`BlendMode.requiresFramebufferFetch` が true）は
    /// フレームバッファフェッチ（`float4 dest [[color(0)]]`）を読む専用のフラグメント関数で
    /// 実装されているため、ここでフラグメント名が分岐します。名前は
    /// `metaphor_canvas2D<系統><接尾辞>Fragment` の規則で組み立てます（ADR-0012 / #801）。
    private static func builtinFunctions(
        kind: Canvas2DPipelineKind, blend: BlendMode
    ) -> (libraryKey: String, vertex: String, fragment: String) {
        let info = builtinKindInfo(kind)
        guard let suffix = blend.fragmentFunctionSuffix else {
            return (info.libraryKey, info.vertex, info.fragment)
        }
        return (info.libraryKey, info.vertex, "metaphor_canvas2D\(info.infix)\(suffix)Fragment")
    }

    /// 系統ごとの固定情報（ライブラリキー・頂点関数・既定フラグメント・関数名の中置き）。
    private static func builtinKindInfo(
        _ kind: Canvas2DPipelineKind
    ) -> (libraryKey: String, vertex: String, fragment: String, infix: String) {
        switch kind {
        case .color:
            return (ShaderLibrary.BuiltinKey.canvas2D,
                    BuiltinShaders.FunctionName.canvas2DVertex,
                    BuiltinShaders.FunctionName.canvas2DFragment,
                    "")
        case .textured:
            return (ShaderLibrary.BuiltinKey.canvas2DTextured,
                    BuiltinShaders.FunctionName.canvas2DTexturedVertex,
                    BuiltinShaders.FunctionName.canvas2DTexturedFragment,
                    "Textured")
        case .straightTextured:
            return (ShaderLibrary.BuiltinKey.canvas2DTextured,
                    BuiltinShaders.FunctionName.canvas2DTexturedVertex,
                    BuiltinShaders.FunctionName.canvas2DStraightTexturedFragment,
                    "StraightTextured")
        case .instanced:
            return (ShaderLibrary.BuiltinKey.canvas2DInstanced,
                    Canvas2DInstancedShaders.vertexFunctionName,
                    Canvas2DInstancedShaders.fragmentFunctionName,
                    "Instanced")
        case .massiveCircle:
            return (ShaderLibrary.BuiltinKey.canvas2DMassive,
                    Canvas2DMassiveShaders.circleVertexFunctionName,
                    Canvas2DMassiveShaders.fragmentFunctionName,
                    "Massive")
        }
    }

    /// 系統ごとの頂点レイアウト。`Vertex2D` / `TexturedVertex2D` のストライドと対応します。
    private static func vertexLayout(for kind: Canvas2DPipelineKind) -> VertexLayout {
        switch kind {
        case .color: return .position2DColor
        case .textured, .straightTextured: return .position2DTexCoordColor
        // インスタンス系は単位メッシュ（位置のみ）を頂点バッファに取り、
        // 変換と色はインスタンスバッファ（index 6）から読む。
        case .instanced, .massiveCircle: return .position2DOnly
        }
    }
}
