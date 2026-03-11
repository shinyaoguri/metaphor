import Testing
import Metal
import simd
@testable import metaphor
@testable import MetaphorCore

// MARK: - InstanceData2D Layout Tests

@Suite("InstanceData2D Layout", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct InstanceData2DLayoutTests {

    @Test("InstanceData2D is 80 bytes with 16-byte alignment")
    func layout() {
        #expect(MemoryLayout<InstanceData2D>.stride == 80)
        #expect(MemoryLayout<InstanceData2D>.alignment == 16)
    }

    @Test("InstanceData2D fields are correct")
    func fields() {
        let data = InstanceData2D(
            transform: float4x4(1),
            color: SIMD4<Float>(1, 0, 0, 1)
        )
        #expect(data.transform == float4x4(1))
        #expect(data.color == SIMD4<Float>(1, 0, 0, 1))
    }
}

// MARK: - BatchKey2D Tests

@Suite("BatchKey2D", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct BatchKey2DTests {

    @Test("Equal keys match")
    func equalKeys() {
        let k1 = BatchKey2D(shapeType: .ellipse, blendMode: .alpha)
        let k2 = BatchKey2D(shapeType: .ellipse, blendMode: .alpha)
        #expect(k1 == k2)
    }

    @Test("Different shape types don't match")
    func differentShapeType() {
        let k1 = BatchKey2D(shapeType: .ellipse, blendMode: .alpha)
        let k2 = BatchKey2D(shapeType: .rect, blendMode: .alpha)
        #expect(k1 != k2)
    }

    @Test("Different blend modes don't match")
    func differentBlendMode() {
        let k1 = BatchKey2D(shapeType: .ellipse, blendMode: .alpha)
        let k2 = BatchKey2D(shapeType: .ellipse, blendMode: .additive)
        #expect(k1 != k2)
    }
}

// MARK: - InstanceBatcher2D Tests

@Suite("InstanceBatcher2D", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct InstanceBatcher2DTests {

    @Test("Batcher accumulates instances")
    func accumulation() {
        let device = MTLCreateSystemDefaultDevice()!
        let batcher = try! InstanceBatcher2D(device: device)
        batcher.beginFrame(bufferIndex: 0)

        let key = BatchKey2D(shapeType: .ellipse, blendMode: .alpha)
        #expect(batcher.tryAddInstance(key: key, transform: float4x4(1), color: .one))
        #expect(batcher.instanceCount == 1)
        #expect(batcher.tryAddInstance(key: key, transform: float4x4(1), color: .one))
        #expect(batcher.instanceCount == 2)
    }

    @Test("Batcher rejects mismatched key")
    func keyMismatch() {
        let device = MTLCreateSystemDefaultDevice()!
        let batcher = try! InstanceBatcher2D(device: device)
        batcher.beginFrame(bufferIndex: 0)

        let k1 = BatchKey2D(shapeType: .ellipse, blendMode: .alpha)
        let k2 = BatchKey2D(shapeType: .rect, blendMode: .alpha)

        #expect(batcher.tryAddInstance(key: k1, transform: float4x4(1), color: .one))
        #expect(!batcher.tryAddInstance(key: k2, transform: float4x4(1), color: .one))
    }

    @Test("Reset clears batch")
    func reset() {
        let device = MTLCreateSystemDefaultDevice()!
        let batcher = try! InstanceBatcher2D(device: device)
        batcher.beginFrame(bufferIndex: 0)

        let key = BatchKey2D(shapeType: .ellipse, blendMode: .alpha)
        let _ = batcher.tryAddInstance(key: key, transform: float4x4(1), color: .one)
        #expect(batcher.instanceCount == 1)

        batcher.reset()
        #expect(batcher.instanceCount == 0)
        #expect(batcher.currentBatchKey == nil)
    }

    @Test("Triple buffer rotation")
    func tripleBuffering() {
        let device = MTLCreateSystemDefaultDevice()!
        let batcher = try! InstanceBatcher2D(device: device)

        // 3回のフレームで異なるバッファが使われること
        var buffers: [MTLBuffer] = []
        for i in 0..<3 {
            batcher.beginFrame(bufferIndex: i)
            buffers.append(batcher.currentBuffer)
        }
        // 3つのバッファは全て異なるオブジェクト
        #expect(buffers[0] !== buffers[1])
        #expect(buffers[1] !== buffers[2])
        #expect(buffers[0] !== buffers[2])

        // 4フレーム目は最初のバッファに戻る
        batcher.beginFrame(bufferIndex: 3)
        #expect(batcher.currentBuffer === buffers[0])
    }

    @Test("Multiple instances with different colors")
    func differentColors() {
        let device = MTLCreateSystemDefaultDevice()!
        let batcher = try! InstanceBatcher2D(device: device)
        batcher.beginFrame(bufferIndex: 0)

        let key = BatchKey2D(shapeType: .ellipse, blendMode: .alpha)
        let red = SIMD4<Float>(1, 0, 0, 1)
        let blue = SIMD4<Float>(0, 0, 1, 1)

        // 色が違ってもキーが同じならバッチされる
        #expect(batcher.tryAddInstance(key: key, transform: float4x4(1), color: red))
        #expect(batcher.tryAddInstance(key: key, transform: float4x4(1), color: blue))
        #expect(batcher.instanceCount == 2)
    }
}

// MARK: - UnitMesh2D Tests

@Suite("UnitMesh2D", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct UnitMesh2DTests {

    @Test("Unit circle has 96 vertices (32 segments × 3)")
    func circleVertexCount() {
        let device = MTLCreateSystemDefaultDevice()!
        let (buffer, count) = UnitMesh2D.createCircle(device: device)!
        #expect(count == 96)
        #expect(buffer.length == 96 * MemoryLayout<SIMD2<Float>>.stride)
    }

    @Test("Unit rect has 6 vertices (2 triangles)")
    func rectVertexCount() {
        let device = MTLCreateSystemDefaultDevice()!
        let (buffer, count) = UnitMesh2D.createRect(device: device)!
        #expect(count == 6)
        #expect(buffer.length == 6 * MemoryLayout<SIMD2<Float>>.stride)
    }

    @Test("Unit circle vertices are within [-0.5, 0.5]")
    func circleVertexRange() {
        let device = MTLCreateSystemDefaultDevice()!
        let (buffer, count) = UnitMesh2D.createCircle(device: device)!
        let ptr = buffer.contents().bindMemory(to: SIMD2<Float>.self, capacity: count)
        for i in 0..<count {
            let v = ptr[i]
            #expect(v.x >= -0.501 && v.x <= 0.501)
            #expect(v.y >= -0.501 && v.y <= 0.501)
        }
    }

    @Test("Unit rect vertices are within [-0.5, 0.5]")
    func rectVertexRange() {
        let device = MTLCreateSystemDefaultDevice()!
        let (buffer, count) = UnitMesh2D.createRect(device: device)!
        let ptr = buffer.contents().bindMemory(to: SIMD2<Float>.self, capacity: count)
        for i in 0..<count {
            let v = ptr[i]
            #expect(v.x >= -0.5 && v.x <= 0.5)
            #expect(v.y >= -0.5 && v.y <= 0.5)
        }
    }
}

// MARK: - Transform Embedding Tests

@Suite("2D Transform Embedding", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct TransformEmbeddingTests {

    @Test("Identity float3x3 embeds as identity float4x4")
    func identityEmbedding() {
        let t = float3x3(1)
        let m = Canvas2D.embed2DTransform(t)
        #expect(m == float4x4(1))
    }

    @Test("Translation embeds correctly")
    func translationEmbedding() {
        let t = float3x3(columns: (
            SIMD3<Float>(1, 0, 0),
            SIMD3<Float>(0, 1, 0),
            SIMD3<Float>(100, 200, 1)
        ))
        let m = Canvas2D.embed2DTransform(t)
        #expect(m.columns.3.x == 100)
        #expect(m.columns.3.y == 200)
        #expect(m.columns.3.z == 0)
        #expect(m.columns.3.w == 1)
    }

    @Test("Scale embeds correctly")
    func scaleEmbedding() {
        let t = float3x3(columns: (
            SIMD3<Float>(2, 0, 0),
            SIMD3<Float>(0, 3, 0),
            SIMD3<Float>(0, 0, 1)
        ))
        let m = Canvas2D.embed2DTransform(t)
        #expect(m.columns.0.x == 2)
        #expect(m.columns.1.y == 3)
        #expect(m.columns.2.z == 1)
    }

    @Test("Rotation embeds correctly")
    func rotationEmbedding() {
        let angle = Float.pi / 4 // 45 degrees
        let c = cos(angle)
        let s = sin(angle)
        let t = float3x3(columns: (
            SIMD3<Float>(c, s, 0),
            SIMD3<Float>(-s, c, 0),
            SIMD3<Float>(0, 0, 1)
        ))
        let m = Canvas2D.embed2DTransform(t)
        #expect(abs(m.columns.0.x - c) < 1e-6)
        #expect(abs(m.columns.0.y - s) < 1e-6)
        #expect(abs(m.columns.1.x - (-s)) < 1e-6)
        #expect(abs(m.columns.1.y - c) < 1e-6)
    }
}

// MARK: - Canvas2D Instancing Integration Tests

@Suite("Canvas2D Instancing Integration", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct Canvas2DInstancingIntegrationTests {

    @Test("Canvas2D initializes with instancing resources")
    func initResources() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let shaderLib = try ShaderLibrary(device: device)
        let depthCache = DepthStencilCache(device: device)

        let canvas = try Canvas2D(
            device: device,
            shaderLibrary: shaderLib,
            depthStencilCache: depthCache,
            width: 1920,
            height: 1080
        )

        #expect(canvas.unitCircleVertexCount == 96)
        #expect(canvas.unitRectVertexCount == 6)
        #expect(!canvas.instancedPipelineStates.isEmpty)
    }

    @Test("Shader library registers canvas2DInstanced")
    func shaderRegistration() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let shaderLib = try ShaderLibrary(device: device)

        #expect(shaderLib.hasLibrary(for: ShaderLibrary.BuiltinKey.canvas2DInstanced))

        let vertexFn = shaderLib.function(
            named: Canvas2DInstancedShaders.vertexFunctionName,
            from: ShaderLibrary.BuiltinKey.canvas2DInstanced
        )
        #expect(vertexFn != nil)

        let fragmentFn = shaderLib.function(
            named: Canvas2DInstancedShaders.fragmentFunctionName,
            from: ShaderLibrary.BuiltinKey.canvas2DInstanced
        )
        #expect(fragmentFn != nil)
    }
}
