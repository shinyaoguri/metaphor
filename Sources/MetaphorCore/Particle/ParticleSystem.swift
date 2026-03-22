@preconcurrency import Metal
import simd

// MARK: - Particle (GPU 互換、64 バイト)

/// 単一の GPU 互換パーティクル（64 バイト、16 バイトアライメント）
///
/// この構造体は Swift と MSL で共有され、
/// Metal シェーダー側のカウンターパートと正確なレイアウト互換性を維持する必要があります。
public struct Particle {
    /// 位置 (xyz) と残り寿命 (w)
    public var position: SIMD4<Float>

    /// 速度 (xyz) と経過時間 (w)
    public var velocity: SIMD4<Float>

    /// パーティクルの RGBA カラー
    public var color: SIMD4<Float>

    /// パック済みフィールド: x = サイズ, y = 初期寿命, z = 未使用, w = 生存フラグ (1.0 または 0.0)
    public var sizeAndFlags: SIMD4<Float>

    /// ゼロ初期化されたパーティクルを作成します（デフォルトで死亡状態）。
    public init() {
        position = .zero
        velocity = .zero
        color = .zero
        sizeAndFlags = .zero
    }
}

// MARK: - パーティクルフォース

/// 各フレームでパーティクルに適用できるフォースの種類を定義します。
public enum ParticleForce {
    /// 指定方向への定数重力加速度
    case gravity(Float, Float, Float)

    /// 指定した強度でのポイントへの引力
    case attraction(x: Float, y: Float, z: Float, strength: Float)

    /// 指定した強度でのポイントからの斥力
    case repulsion(x: Float, y: Float, z: Float, strength: Float)

    /// 設定可能なスケールと強度によるノイズベースフォース
    case noise(scale: Float, strength: Float)

    /// 指定した強度での軸周りの渦フォース
    case vortex(x: Float, y: Float, z: Float, strength: Float)

    /// 指定した係数で毎フレーム速度を減衰させるダンピング
    case damping(Float)
}

// MARK: - エミッター形状

/// パーティクルが放出される空間形状を定義します。
public enum EmitterShape {
    /// 単一の点から放出
    case point(Float, Float, Float)

    /// 2つの端点間の線分に沿って放出
    case line(x1: Float, y1: Float, z1: Float, x2: Float, y2: Float, z2: Float)

    /// XY 平面上の円から放出
    case circle(x: Float, y: Float, z: Float, radius: Float)

    /// 球の表面から放出
    case sphere(x: Float, y: Float, z: Float, radius: Float)
}

// MARK: - GPU 構造体 (Swift <-> MSL 対応)

/// GPU コンピュートシェーダー用のフォース記述子 (32 バイト)
///
/// - `typeAndParams`: x = フォースタイプインデックス, yzw = 位置または方向パラメータ
/// - `strengthAndExtra`: x = 強度, yzw = 追加パラメータ（例: ノイズスケール）
struct ForceDescriptor {
    var typeAndParams: SIMD4<Float>       // x=タイプ, yzw=パラメータ
    var strengthAndExtra: SIMD4<Float>    // x=強度, yzw=追加
}

/// パーティクル更新コンピュートシェーダー用のフレーム毎ユニフォームデータ
struct ParticleUniforms {
    var deltaTime: Float
    var time: Float
    var particleCount: UInt32
    var forceCount: UInt32
    var emissionRate: Float
    var particleLife: Float
    var particleSize: Float
    var _pad: Float = 0
    var startColor: SIMD4<Float>
    var endColor: SIMD4<Float>
    var emitterType: UInt32
    var _pad2: UInt32 = 0
    var _pad3: UInt32 = 0
    var _pad4: UInt32 = 0
    var emitterParam1: SIMD4<Float>
    var emitterParam2: SIMD4<Float>
}

/// パーティクルレンダー頂点シェーダー用のフレーム毎ユニフォームデータ (96 バイト)
struct ParticleRenderUniforms {
    var viewProjection: float4x4
    var cameraRight: SIMD4<Float>    // xyz を使用
    var cameraUp: SIMD4<Float>       // xyz を使用
}

// MARK: - ParticleSystem

/// Metal コンピュートシェーダーを使用した GPU ベースパーティクルシステムを駆動します。
///
/// ``ParticleSystem`` はパーティクルデータをダブルバッファリングし、
/// 毎フレーム GPU 上で全パーティクルを並列に更新します。レンダリングは
/// 加算ブレンドのインスタンスビルボードクワッドを使用します。
///
/// ```swift
/// let ps = try createParticleSystem(count: 100_000)
/// ps.setEmitter(.sphere(x: 0, y: 0, z: 0, radius: 1.0))
/// ps.addForce(.gravity(0, -9.8, 0))
/// // compute() 内: updateParticles(ps)
/// // draw() 内: drawParticles(ps)
/// ```
@MainActor
public final class ParticleSystem {
    /// このシステムの最大パーティクル数
    public let count: Int

    // MARK: - エミッター設定

    /// 新しいパーティクルが放出される形状
    public var emitter: EmitterShape = .point(0, 0, 0)

    /// パーティクル毎秒の放出レート
    public var emissionRate: Float = 10000

    /// 各パーティクルの寿命（秒）
    public var particleLife: Float = 2.0

    /// 各パーティクルのワールド単位でのサイズ
    public var particleSize: Float = 0.05

    /// 新しく放出されるパーティクルのカラー
    public var startColor: SIMD4<Float> = SIMD4(1, 1, 1, 1)

    /// 寿命の終わりに向けてパーティクルが補間されるカラー
    public var endColor: SIMD4<Float> = SIMD4(1, 1, 1, 0)

    // MARK: - フォース

    /// 現在システムに適用されているフォースのリスト
    public private(set) var forces: [ParticleForce] = []

    // MARK: - Metal リソース

    /// バッファとパイプライン作成に使用される Metal デバイス
    private let device: MTLDevice

    /// 第1パーティクルバッファ（ダブルバッファリング: ソースまたはデスティネーション）
    private var bufferA: MTLBuffer

    /// 第2パーティクルバッファ（ダブルバッファリング: ソースまたはデスティネーション）
    private var bufferB: MTLBuffer

    /// どちらのバッファが現在のソースかを示すトグル
    private var useBufferA = true

    /// フォース記述子を含む GPU バッファ。フォースが未アクティブの場合は nil
    private var forceBuffer: MTLBuffer?

    /// パーティクル更新カーネル用コンピュートパイプラインステート
    private let updatePipeline: MTLComputePipelineState

    /// ビルボードクワッド描画用レンダーパイプラインステート
    private let renderPipeline: MTLRenderPipelineState

    /// デプスステンシルステート（デプステスト有効、書き込み無効）
    private let depthState: MTLDepthStencilState?

    // MARK: - Indirect Draw リソース

    /// 生存パーティクルのみをレンダリングする Indirect Draw を有効化（後方互換性のためデフォルト `false`）
    public var useIndirectDraw: Bool = false

    /// Indirect Draw 用のコンパクト済み生存パーティクルを保持するバッファ
    private var compactBuffer: MTLBuffer?

    /// コンパクション用のアトミックカウンターバッファ (4 バイト)
    private var counterBuffer: MTLBuffer?

    /// `drawPrimitives(indirectBuffer:)` 用の Indirect 引数バッファ (16 バイト)
    private var indirectArgsBuffer: MTLBuffer?

    /// アトミックカウンターリセット用コンピュートパイプライン
    private let resetCounterPipeline: MTLComputePipelineState?

    /// 生存パーティクルコンパクション用コンピュートパイプライン
    private let compactPipeline: MTLComputePipelineState?

    /// Indirect Draw 引数ビルド用コンピュートパイプライン
    private let buildArgsPipeline: MTLComputePipelineState?

    // MARK: - 初期化

    /// 指定された容量で新しいパーティクルシステムを作成します。
    ///
    /// - Parameters:
    ///   - device: リソース作成用の Metal デバイス
    ///   - shaderLibrary: パーティクルシェーダー関数を含むシェーダーライブラリ
    ///   - sampleCount: レンダーパイプラインの MSAA サンプル数
    ///   - count: 最大パーティクル数
    /// - Throws: GPU バッファの確保に失敗した場合、または必要なシェーダー関数が
    ///   見つからない場合 ``MetaphorError/particle(_:)``
    init(
        device: MTLDevice,
        shaderLibrary: ShaderLibrary,
        sampleCount: Int,
        count: Int
    ) throws {
        self.device = device
        self.count = count

        // ダブルバッファリングパーティクルデータ
        let bufferSize = MemoryLayout<Particle>.stride * count
        guard let a = device.makeBuffer(length: bufferSize, options: .storageModeShared),
              let b = device.makeBuffer(length: bufferSize, options: .storageModeShared) else {
            throw MetaphorError.particle(.bufferCreationFailed)
        }
        self.bufferA = a
        self.bufferB = b
        a.label = "metaphor.particle.bufferA"
        b.label = "metaphor.particle.bufferB"
        memset(a.contents(), 0, bufferSize)
        memset(b.contents(), 0, bufferSize)

        // パーティクル更新用コンピュートパイプライン
        guard let updateFn = shaderLibrary.function(
            named: ParticleShaders.FunctionName.update,
            from: ShaderLibrary.BuiltinKey.particle
        ) else {
            throw MetaphorError.particle(.shaderNotFound(ParticleShaders.FunctionName.update))
        }
        self.updatePipeline = try device.makeComputePipelineState(function: updateFn)

        // レンダーパイプライン（頂点デスクリプタなし: バッファから直接読み取り）
        guard let vertexFn = shaderLibrary.function(
            named: ParticleShaders.FunctionName.vertex,
            from: ShaderLibrary.BuiltinKey.particle
        ),
              let fragmentFn = shaderLibrary.function(
            named: ParticleShaders.FunctionName.fragment,
            from: ShaderLibrary.BuiltinKey.particle
        ) else {
            throw MetaphorError.particle(.shaderNotFound("particle vertex/fragment"))
        }

        self.renderPipeline = try PipelineFactory(device: device)
            .vertex(vertexFn)
            .fragment(fragmentFn)
            .blending(.additive)
            .sampleCount(sampleCount)
            .build()

        // デプスステンシルステート（加算ブレンド用にテスト有効、書き込み無効）
        let depthDesc = MTLDepthStencilDescriptor()
        depthDesc.depthCompareFunction = .less
        depthDesc.isDepthWriteEnabled = false
        self.depthState = device.makeDepthStencilState(descriptor: depthDesc)

        // Indirect Draw パイプライン（オプション: 失敗時は通常モードにフォールバック）
        if let resetFn = shaderLibrary.function(
            named: ParticleShaders.FunctionName.resetCounter,
            from: ShaderLibrary.BuiltinKey.particle
        ),
           let compactFn = shaderLibrary.function(
            named: ParticleShaders.FunctionName.compact,
            from: ShaderLibrary.BuiltinKey.particle
        ),
           let buildArgsFn = shaderLibrary.function(
            named: ParticleShaders.FunctionName.buildIndirectArgs,
            from: ShaderLibrary.BuiltinKey.particle
        ) {
            self.resetCounterPipeline = {
                do { return try device.makeComputePipelineState(function: resetFn) }
                catch { metaphorWarning("Indirect draw pipeline unavailable (resetCounter): \(error)"); return nil }
            }()
            self.compactPipeline = {
                do { return try device.makeComputePipelineState(function: compactFn) }
                catch { metaphorWarning("Indirect draw pipeline unavailable (compact): \(error)"); return nil }
            }()
            self.buildArgsPipeline = {
                do { return try device.makeComputePipelineState(function: buildArgsFn) }
                catch { metaphorWarning("Indirect draw pipeline unavailable (buildArgs): \(error)"); return nil }
            }()

            // 生存パーティクル用コンパクトバッファ
            self.compactBuffer = device.makeBuffer(length: bufferSize, options: .storageModeShared)
            self.compactBuffer?.label = "metaphor.particle.compact"
            // アトミックカウンターバッファ (4 バイト)
            self.counterBuffer = device.makeBuffer(length: MemoryLayout<UInt32>.size, options: .storageModeShared)
            self.counterBuffer?.label = "metaphor.particle.counter"
            // Indirect 引数バッファ (16 バイト)
            self.indirectArgsBuffer = device.makeBuffer(
                length: MemoryLayout<MTLDrawPrimitivesIndirectArguments>.size,
                options: .storageModeShared
            )
            self.indirectArgsBuffer?.label = "metaphor.particle.indirectArgs"
        } else {
            self.resetCounterPipeline = nil
            self.compactPipeline = nil
            self.buildArgsPipeline = nil
        }
    }

    // MARK: - フォース管理

    /// パーティクルシステムにフォースを追加します。
    ///
    /// - Parameter force: 追加するフォース
    public func addForce(_ force: ParticleForce) {
        forces.append(force)
        rebuildForceBuffer()
    }

    /// パーティクルシステムから全フォースを削除します。
    public func clearForces() {
        forces.removeAll()
        forceBuffer = nil
    }

    /// パーティクル生成用のエミッター形状を設定します。
    ///
    /// - Parameter shape: 新しいエミッター形状
    public func setEmitter(_ shape: EmitterShape) {
        self.emitter = shape
    }

    // MARK: - 更新（コンピュートフェーズ）

    /// パーティクル更新コンピュートカーネルをディスパッチします。
    ///
    /// フレームのコンピュートフェーズ中に呼び出してください。カーネルは現在のソースバッファから読み取り、
    /// 更新されたパーティクルをデスティネーションバッファに書き込み、
    /// 次のフレームに向けてバッファを交換します。
    ///
    /// - Parameters:
    ///   - encoder: コンピュートコマンドエンコーダー
    ///   - deltaTime: 前フレームからの経過時間（秒）
    ///   - time: 合計経過時間（秒）
    func update(encoder: MTLComputeCommandEncoder, deltaTime: Float, time: Float) {
        let src = useBufferA ? bufferA : bufferB
        let dst = useBufferA ? bufferB : bufferA

        var uniforms = makeUniforms(deltaTime: deltaTime, time: time)

        encoder.setComputePipelineState(updatePipeline)
        encoder.setBuffer(src, offset: 0, index: 0)
        encoder.setBuffer(dst, offset: 0, index: 1)
        encoder.setBytes(&uniforms, length: MemoryLayout<ParticleUniforms>.size, index: 2)

        if let fb = forceBuffer {
            encoder.setBuffer(fb, offset: 0, index: 3)
        }

        let w = updatePipeline.threadExecutionWidth
        let threadsPerGroup = MTLSize(width: w, height: 1, depth: 1)
        let gridSize = MTLSize(width: count, height: 1, depth: 1)
        encoder.dispatchThreads(gridSize, threadsPerThreadgroup: threadsPerGroup)

        useBufferA.toggle()

        // Indirect Draw: 生存パーティクルをコンパクト
        if useIndirectDraw {
            compactAliveParticles(encoder: encoder)
        }
    }

    /// 生存パーティクルを連続バッファにコンパクトし、Indirect Draw 引数をビルドします。
    private func compactAliveParticles(encoder: MTLComputeCommandEncoder) {
        guard let resetPipeline = resetCounterPipeline,
              let compactPipe = compactPipeline,
              let buildPipe = buildArgsPipeline,
              let compactBuf = compactBuffer,
              let counterBuf = counterBuffer,
              let argsBuf = indirectArgsBuffer else { return }

        let currentBuffer = useBufferA ? bufferA : bufferB

        // 1) アトミックカウンターをリセット
        encoder.setComputePipelineState(resetPipeline)
        encoder.setBuffer(counterBuf, offset: 0, index: 0)
        encoder.dispatchThreads(MTLSize(width: 1, height: 1, depth: 1),
                                threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1))

        encoder.memoryBarrier(scope: .buffers)

        // 2) 生存パーティクルをコンパクトバッファにコンパクト
        encoder.setComputePipelineState(compactPipe)
        encoder.setBuffer(currentBuffer, offset: 0, index: 0)
        encoder.setBuffer(compactBuf, offset: 0, index: 1)
        encoder.setBuffer(counterBuf, offset: 0, index: 2)
        let w = compactPipe.threadExecutionWidth
        encoder.dispatchThreads(MTLSize(width: count, height: 1, depth: 1),
                                threadsPerThreadgroup: MTLSize(width: w, height: 1, depth: 1))

        encoder.memoryBarrier(scope: .buffers)

        // 3) カウンターから Indirect Draw 引数をビルド
        encoder.setComputePipelineState(buildPipe)
        encoder.setBuffer(counterBuf, offset: 0, index: 0)
        encoder.setBuffer(argsBuf, offset: 0, index: 1)
        encoder.dispatchThreads(MTLSize(width: 1, height: 1, depth: 1),
                                threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1))
    }

    // MARK: - 描画（レンダーフェーズ）

    /// パーティクルをインスタンスビルボードクワッドとしてレンダリングします。
    ///
    /// フレームのレンダーフェーズ中に呼び出してください。各生存パーティクルは
    /// 加算ブレンドのカメラ向きクワッドとして描画されます。
    ///
    /// - Parameters:
    ///   - encoder: レンダーコマンドエンコーダー
    ///   - viewProjection: 結合されたビュー・プロジェクション行列
    ///   - cameraRight: カメラの右方向ベクトル（ビルボード向き用）
    ///   - cameraUp: カメラの上方向ベクトル（ビルボード向き用）
    func draw(
        encoder: MTLRenderCommandEncoder,
        viewProjection: float4x4,
        cameraRight: SIMD3<Float>,
        cameraUp: SIMD3<Float>
    ) {
        var renderUniforms = ParticleRenderUniforms(
            viewProjection: viewProjection,
            cameraRight: SIMD4(cameraRight.x, cameraRight.y, cameraRight.z, 0),
            cameraUp: SIMD4(cameraUp.x, cameraUp.y, cameraUp.z, 0)
        )

        if let ds = depthState {
            encoder.setDepthStencilState(ds)
        }
        encoder.setRenderPipelineState(renderPipeline)
        encoder.setVertexBytes(&renderUniforms, length: MemoryLayout<ParticleRenderUniforms>.size, index: 1)

        if useIndirectDraw,
           let compactBuf = compactBuffer,
           let argsBuf = indirectArgsBuffer {
            // Indirect Draw: コンパクト済み生存パーティクルのみレンダリング
            encoder.setVertexBuffer(compactBuf, offset: 0, index: 0)
            encoder.drawPrimitives(
                type: .triangleStrip,
                indirectBuffer: argsBuf,
                indirectBufferOffset: 0
            )
        } else {
            // 標準描画: 全パーティクルスロットのインスタンスレンダリング
            let currentBuffer = useBufferA ? bufferA : bufferB
            encoder.setVertexBuffer(currentBuffer, offset: 0, index: 0)
            encoder.drawPrimitives(
                type: .triangleStrip,
                vertexStart: 0,
                vertexCount: 4,
                instanceCount: count
            )
        }
    }

    // MARK: - プライベートヘルパー

    /// パーティクル更新コンピュートカーネル用のユニフォーム構造体をビルドします。
    private func makeUniforms(deltaTime: Float, time: Float) -> ParticleUniforms {
        let (emitterType, param1, param2) = emitterParams()

        return ParticleUniforms(
            deltaTime: deltaTime,
            time: time,
            particleCount: UInt32(count),
            forceCount: UInt32(forces.count),
            emissionRate: emissionRate,
            particleLife: particleLife,
            particleSize: particleSize,
            startColor: startColor,
            endColor: endColor,
            emitterType: emitterType,
            emitterParam1: param1,
            emitterParam2: param2
        )
    }

    /// 現在のエミッター形状を GPU 互換パラメータに変換します。
    private func emitterParams() -> (UInt32, SIMD4<Float>, SIMD4<Float>) {
        switch emitter {
        case .point(let x, let y, let z):
            return (0, SIMD4(x, y, z, 0), .zero)
        case .line(let x1, let y1, let z1, let x2, let y2, let z2):
            return (1, SIMD4(x1, y1, z1, 0), SIMD4(x2, y2, z2, 0))
        case .circle(let x, let y, let z, let r):
            return (2, SIMD4(x, y, z, 0), SIMD4(r, 0, 0, 0))
        case .sphere(let x, let y, let z, let r):
            return (3, SIMD4(x, y, z, 0), SIMD4(r, 0, 0, 0))
        }
    }

    /// 現在のフォース配列から GPU フォースバッファを再ビルドします。
    private func rebuildForceBuffer() {
        var descriptors: [ForceDescriptor] = []
        for force in forces {
            switch force {
            case .gravity(let x, let y, let z):
                descriptors.append(ForceDescriptor(
                    typeAndParams: SIMD4(0, x, y, z),
                    strengthAndExtra: SIMD4(1, 0, 0, 0)
                ))
            case .attraction(let x, let y, let z, let s):
                descriptors.append(ForceDescriptor(
                    typeAndParams: SIMD4(1, x, y, z),
                    strengthAndExtra: SIMD4(s, 0, 0, 0)
                ))
            case .repulsion(let x, let y, let z, let s):
                descriptors.append(ForceDescriptor(
                    typeAndParams: SIMD4(2, x, y, z),
                    strengthAndExtra: SIMD4(s, 0, 0, 0)
                ))
            case .noise(let scale, let strength):
                descriptors.append(ForceDescriptor(
                    typeAndParams: SIMD4(3, 0, 0, 0),
                    strengthAndExtra: SIMD4(strength, scale, 0, 0)
                ))
            case .vortex(let x, let y, let z, let s):
                descriptors.append(ForceDescriptor(
                    typeAndParams: SIMD4(4, x, y, z),
                    strengthAndExtra: SIMD4(s, 0, 0, 0)
                ))
            case .damping(let factor):
                descriptors.append(ForceDescriptor(
                    typeAndParams: SIMD4(5, 0, 0, 0),
                    strengthAndExtra: SIMD4(factor, 0, 0, 0)
                ))
            }
        }

        if descriptors.isEmpty {
            forceBuffer = nil
        } else {
            forceBuffer = device.makeBuffer(
                bytes: descriptors,
                length: MemoryLayout<ForceDescriptor>.stride * descriptors.count,
                options: .storageModeShared
            )
        }
    }
}
