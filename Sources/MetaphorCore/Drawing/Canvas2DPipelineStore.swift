import Metal

// MARK: - 2D パイプラインの識別

/// 2D 描画パイプラインの系統。頂点レイアウトと組み込みシェーダー関数の組を表します。
///
/// `Canvas2D` の 4 つの flush 経路（カラー頂点・テクスチャ頂点・インスタンス・massive 円）に
/// 1 対 1 で対応します。
enum Canvas2DPipelineKind: Hashable, CaseIterable, Sendable {
    /// 色付き頂点バッチ（`flushColorVertices`）。
    case color
    /// テクスチャ付き頂点バッチ（`flushTexturedVertices`）。
    case textured
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
/// E2（2D カスタムシェーダ）ではこのキーにシェーダ識別子が加わり、
/// ``Canvas2DPipelineStore`` 側がカスタムパイプラインをキャッシュします。
struct Canvas2DPipelineKey: Hashable, Sendable {
    /// パイプラインの系統。
    let kind: Canvas2DPipelineKind
    /// ブレンドモード。
    let blend: BlendMode

    init(_ kind: Canvas2DPipelineKind, _ blend: BlendMode) {
        self.kind = kind
        self.blend = blend
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

    /// 解決済みパイプライン。組み込み分は `init` で全件先行生成します。
    private var states: [Canvas2DPipelineKey: MTLRenderPipelineState] = [:]

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
    func state(for key: Canvas2DPipelineKey) -> MTLRenderPipelineState? {
        states[key]
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
    /// `.difference` / `.exclusion` はフレームバッファフェッチ（`float4 dest [[color(0)]]`）を
    /// 読む専用のフラグメント関数で実装されているため、ここだけ関数名が分岐します。
    private static func builtinFunctions(
        kind: Canvas2DPipelineKind, blend: BlendMode
    ) -> (libraryKey: String, vertex: String, fragment: String) {
        switch kind {
        case .color:
            let fragment: String
            switch blend {
            case .difference: fragment = BuiltinShaders.FunctionName.canvas2DDifferenceFragment
            case .exclusion: fragment = BuiltinShaders.FunctionName.canvas2DExclusionFragment
            default: fragment = BuiltinShaders.FunctionName.canvas2DFragment
            }
            return (ShaderLibrary.BuiltinKey.canvas2D,
                    BuiltinShaders.FunctionName.canvas2DVertex,
                    fragment)

        case .textured:
            let fragment: String
            switch blend {
            case .difference:
                fragment = BuiltinShaders.FunctionName.canvas2DTexturedDifferenceFragment
            case .exclusion:
                fragment = BuiltinShaders.FunctionName.canvas2DTexturedExclusionFragment
            default:
                fragment = BuiltinShaders.FunctionName.canvas2DTexturedFragment
            }
            return (ShaderLibrary.BuiltinKey.canvas2DTextured,
                    BuiltinShaders.FunctionName.canvas2DTexturedVertex,
                    fragment)

        case .instanced:
            let fragment: String
            switch blend {
            case .difference: fragment = Canvas2DInstancedShaders.differenceFragmentFunctionName
            case .exclusion: fragment = Canvas2DInstancedShaders.exclusionFragmentFunctionName
            default: fragment = Canvas2DInstancedShaders.fragmentFunctionName
            }
            return (ShaderLibrary.BuiltinKey.canvas2DInstanced,
                    Canvas2DInstancedShaders.vertexFunctionName,
                    fragment)

        case .massiveCircle:
            let fragment: String
            switch blend {
            case .difference: fragment = Canvas2DMassiveShaders.differenceFragmentFunctionName
            case .exclusion: fragment = Canvas2DMassiveShaders.exclusionFragmentFunctionName
            default: fragment = Canvas2DMassiveShaders.fragmentFunctionName
            }
            return (ShaderLibrary.BuiltinKey.canvas2DMassive,
                    Canvas2DMassiveShaders.circleVertexFunctionName,
                    fragment)
        }
    }

    /// 系統ごとの頂点レイアウト。`Vertex2D` / `TexturedVertex2D` のストライドと対応します。
    private static func vertexLayout(for kind: Canvas2DPipelineKind) -> VertexLayout {
        switch kind {
        case .color: return .position2DColor
        case .textured: return .position2DTexCoordColor
        // インスタンス系は単位メッシュ（位置のみ）を頂点バッファに取り、
        // 変換と色はインスタンスバッファ（index 6）から読む。
        case .instanced, .massiveCircle: return .position2DOnly
        }
    }
}
