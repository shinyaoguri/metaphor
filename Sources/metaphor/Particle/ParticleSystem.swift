@preconcurrency import Metal
import simd

// MARK: - Particle (GPU Compatible, 64 bytes)

/// GPU互換パーティクル構造体（64 bytes, 16-byte aligned）
public struct Particle {
    /// xyz=位置, w=残り寿命
    public var position: SIMD4<Float>
    /// xyz=速度, w=経過時間
    public var velocity: SIMD4<Float>
    /// RGBA カラー
    public var color: SIMD4<Float>
    /// x=サイズ, y=初期寿命, z=未使用, w=生存フラグ(1.0/0.0)
    public var sizeAndFlags: SIMD4<Float>

    public init() {
        position = .zero
        velocity = .zero
        color = .zero
        sizeAndFlags = .zero
    }
}

// MARK: - Particle Force

/// パーティクルに適用するフォース
public enum ParticleForce {
    /// 重力（方向ベクトル = 加速度）
    case gravity(Float, Float, Float)
    /// 引力（指定点に向かう力）
    case attraction(x: Float, y: Float, z: Float, strength: Float)
    /// 反発力（指定点から離れる力）
    case repulsion(x: Float, y: Float, z: Float, strength: Float)
    /// ノイズフォース（scale: ノイズスケール, strength: 強度）
    case noise(scale: Float, strength: Float)
    /// 渦フォース（軸周りの回転力）
    case vortex(x: Float, y: Float, z: Float, strength: Float)
    /// 減衰（速度を毎フレーム減衰させる）
    case damping(Float)
}

// MARK: - Emitter Shape

/// パーティクルの発生形状
public enum EmitterShape {
    /// 点
    case point(Float, Float, Float)
    /// 線分
    case line(x1: Float, y1: Float, z1: Float, x2: Float, y2: Float, z2: Float)
    /// 円（XY平面）
    case circle(x: Float, y: Float, z: Float, radius: Float)
    /// 球
    case sphere(x: Float, y: Float, z: Float, radius: Float)
}

// MARK: - GPU Structs (Swift ↔ MSL 一致)

/// フォース記述子（32 bytes）
struct ForceDescriptor {
    var typeAndParams: SIMD4<Float>       // x=type, yzw=params
    var strengthAndExtra: SIMD4<Float>    // x=strength, yzw=extra
}

/// パーティクルユニフォーム
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

/// レンダリングユニフォーム（96 bytes）
struct ParticleRenderUniforms {
    var viewProjection: float4x4
    var cameraRight: SIMD4<Float>    // xyz 使用
    var cameraUp: SIMD4<Float>       // xyz 使用
}

// MARK: - ParticleSystem

/// Metal Compute で駆動する GPU パーティクルシステム
///
/// ダブルバッファリングでパーティクルデータを毎フレーム更新し、
/// インスタンスドレンダリングでビルボードクワッドを描画する。
///
/// ```swift
/// let ps = try createParticleSystem(count: 100_000)
/// ps.setEmitter(.sphere(x: 0, y: 0, z: 0, radius: 1.0))
/// ps.addForce(.gravity(0, -9.8, 0))
/// // compute() で updateParticles(ps)
/// // draw() で drawParticles(ps)
/// ```
@MainActor
public final class ParticleSystem {
    /// パーティクル数
    public let count: Int

    // MARK: - Emitter Settings

    /// 発生形状
    public var emitter: EmitterShape = .point(0, 0, 0)

    /// 発生レート（particles/sec）
    public var emissionRate: Float = 10000

    /// パーティクル寿命（秒）
    public var particleLife: Float = 2.0

    /// パーティクルサイズ（ワールド単位）
    public var particleSize: Float = 0.05

    /// 開始カラー
    public var startColor: SIMD4<Float> = SIMD4(1, 1, 1, 1)

    /// 終了カラー（寿命末期に向かって補間）
    public var endColor: SIMD4<Float> = SIMD4(1, 1, 1, 0)

    // MARK: - Forces

    /// 適用中のフォース一覧
    public private(set) var forces: [ParticleForce] = []

    // MARK: - Metal Resources

    private let device: MTLDevice
    private var bufferA: MTLBuffer
    private var bufferB: MTLBuffer
    private var useBufferA = true
    private var forceBuffer: MTLBuffer?
    private let updatePipeline: MTLComputePipelineState
    private let renderPipeline: MTLRenderPipelineState
    private let depthState: MTLDepthStencilState?

    // MARK: - Initialization

    init(
        device: MTLDevice,
        shaderLibrary: ShaderLibrary,
        sampleCount: Int,
        count: Int
    ) throws {
        self.device = device
        self.count = count

        // パーティクルバッファ（ダブルバッファ）
        let bufferSize = MemoryLayout<Particle>.stride * count
        guard let a = device.makeBuffer(length: bufferSize, options: .storageModeShared),
              let b = device.makeBuffer(length: bufferSize, options: .storageModeShared) else {
            throw ParticleError.bufferCreationFailed
        }
        self.bufferA = a
        self.bufferB = b
        a.label = "metaphor.particle.bufferA"
        b.label = "metaphor.particle.bufferB"
        memset(a.contents(), 0, bufferSize)
        memset(b.contents(), 0, bufferSize)

        // コンピュートパイプライン
        guard let updateFn = shaderLibrary.function(
            named: ParticleShaders.FunctionName.update,
            from: ShaderLibrary.BuiltinKey.particle
        ) else {
            throw ParticleError.shaderNotFound(ParticleShaders.FunctionName.update)
        }
        self.updatePipeline = try device.makeComputePipelineState(function: updateFn)

        // レンダーパイプライン（頂点ディスクリプタなし: バッファから直接読み取り）
        guard let vertexFn = shaderLibrary.function(
            named: ParticleShaders.FunctionName.vertex,
            from: ShaderLibrary.BuiltinKey.particle
        ),
              let fragmentFn = shaderLibrary.function(
            named: ParticleShaders.FunctionName.fragment,
            from: ShaderLibrary.BuiltinKey.particle
        ) else {
            throw ParticleError.shaderNotFound("particle vertex/fragment")
        }

        self.renderPipeline = try PipelineFactory(device: device)
            .vertex(vertexFn)
            .fragment(fragmentFn)
            .blending(.additive)
            .sampleCount(sampleCount)
            .build()

        // 深度ステート（テスト有効・書き込み無効）
        let depthDesc = MTLDepthStencilDescriptor()
        depthDesc.depthCompareFunction = .less
        depthDesc.isDepthWriteEnabled = false
        self.depthState = device.makeDepthStencilState(descriptor: depthDesc)
    }

    // MARK: - Force Management

    /// フォースを追加
    public func addForce(_ force: ParticleForce) {
        forces.append(force)
        rebuildForceBuffer()
    }

    /// 全フォースをクリア
    public func clearForces() {
        forces.removeAll()
        forceBuffer = nil
    }

    /// エミッターの形状を設定
    public func setEmitter(_ shape: EmitterShape) {
        self.emitter = shape
    }

    // MARK: - Update (Compute Phase)

    /// コンピュートエンコーダでパーティクルを更新（compute() 内で呼ぶ）
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
    }

    // MARK: - Draw (Render Phase)

    /// レンダーエンコーダでパーティクルを描画（draw() 内で呼ぶ）
    func draw(
        encoder: MTLRenderCommandEncoder,
        viewProjection: float4x4,
        cameraRight: SIMD3<Float>,
        cameraUp: SIMD3<Float>
    ) {
        let currentBuffer = useBufferA ? bufferA : bufferB

        var renderUniforms = ParticleRenderUniforms(
            viewProjection: viewProjection,
            cameraRight: SIMD4(cameraRight.x, cameraRight.y, cameraRight.z, 0),
            cameraUp: SIMD4(cameraUp.x, cameraUp.y, cameraUp.z, 0)
        )

        if let ds = depthState {
            encoder.setDepthStencilState(ds)
        }
        encoder.setRenderPipelineState(renderPipeline)
        encoder.setVertexBuffer(currentBuffer, offset: 0, index: 0)
        encoder.setVertexBytes(&renderUniforms, length: MemoryLayout<ParticleRenderUniforms>.size, index: 1)

        // インスタンスドレンダリング: 4頂点 × N個のビルボードクワッド
        encoder.drawPrimitives(
            type: .triangleStrip,
            vertexStart: 0,
            vertexCount: 4,
            instanceCount: count
        )
    }

    // MARK: - Private Helpers

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

// MARK: - ParticleError

/// パーティクルシステムのエラー
public enum ParticleError: Error, CustomStringConvertible {
    case bufferCreationFailed
    case shaderNotFound(String)

    public var description: String {
        switch self {
        case .bufferCreationFailed:
            return "Failed to create particle buffers"
        case .shaderNotFound(let name):
            return "Particle shader '\(name)' not found"
        }
    }
}
