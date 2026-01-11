import metaphor

struct Vertex {
    var position: SIMD3<Float>
    var normal: SIMD3<Float>
    var color: SIMD4<Float>
}

struct Uniforms {
    var modelMatrix: float4x4
    var viewMatrix: float4x4
    var projectionMatrix: float4x4
    var time: Float
}

final class CubeRenderer {
    private let device: MTLDevice
    private var pipelineState: MTLRenderPipelineState!
    private var depthState: MTLDepthStencilState!
    private var vertexBuffer: MTLBuffer!
    private var indexBuffer: MTLBuffer!
    private var uniformBuffer: MTLBuffer!
    private var indexCount: Int = 0

    init(device: MTLDevice) {
        self.device = device
        buildPipeline()
        buildDepthState()
        buildBuffers()
    }

    private func buildPipeline() {
        let shaderSource = """
        #include <metal_stdlib>
        using namespace metal;

        struct Vertex {
            float3 position [[attribute(0)]];
            float3 normal [[attribute(1)]];
            float4 color [[attribute(2)]];
        };

        struct Uniforms {
            float4x4 modelMatrix;
            float4x4 viewMatrix;
            float4x4 projectionMatrix;
            float time;
        };

        struct VertexOut {
            float4 position [[position]];
            float3 normal;
            float4 color;
            float3 worldPosition;
        };

        vertex VertexOut vertexShader(
            Vertex in [[stage_in]],
            constant Uniforms &uniforms [[buffer(1)]]
        ) {
            VertexOut out;

            float4 worldPosition = uniforms.modelMatrix * float4(in.position, 1.0);
            out.worldPosition = worldPosition.xyz;
            out.position = uniforms.projectionMatrix * uniforms.viewMatrix * worldPosition;
            out.normal = (uniforms.modelMatrix * float4(in.normal, 0.0)).xyz;
            out.color = in.color;

            return out;
        }

        fragment float4 fragmentShader(
            VertexOut in [[stage_in]],
            constant Uniforms &uniforms [[buffer(1)]]
        ) {
            float3 lightDir = normalize(float3(1, 1, 1));
            float3 normal = normalize(in.normal);

            float diffuse = max(dot(normal, lightDir), 0.0);
            float ambient = 0.3;
            float lighting = ambient + diffuse * 0.7;

            return float4(in.color.rgb * lighting, in.color.a);
        }
        """

        let library = try! device.makeLibrary(source: shaderSource, options: nil)
        let vertexFunction = library.makeFunction(name: "vertexShader")
        let fragmentFunction = library.makeFunction(name: "fragmentShader")

        let vertexDescriptor = MTLVertexDescriptor()
        // Position
        vertexDescriptor.attributes[0].format = .float3
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        // Normal
        vertexDescriptor.attributes[1].format = .float3
        vertexDescriptor.attributes[1].offset = MemoryLayout<SIMD3<Float>>.stride
        vertexDescriptor.attributes[1].bufferIndex = 0
        // Color
        vertexDescriptor.attributes[2].format = .float4
        vertexDescriptor.attributes[2].offset = MemoryLayout<SIMD3<Float>>.stride * 2
        vertexDescriptor.attributes[2].bufferIndex = 0
        // Layout
        vertexDescriptor.layouts[0].stride = MemoryLayout<Vertex>.stride

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.vertexDescriptor = vertexDescriptor
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipelineDescriptor.depthAttachmentPixelFormat = .depth32Float

        pipelineState = try! device.makeRenderPipelineState(descriptor: pipelineDescriptor)
    }

    private func buildDepthState() {
        let depthDescriptor = MTLDepthStencilDescriptor()
        depthDescriptor.depthCompareFunction = .less
        depthDescriptor.isDepthWriteEnabled = true
        depthState = device.makeDepthStencilState(descriptor: depthDescriptor)
    }

    private func buildBuffers() {
        let s: Float = 0.5
        let vertices: [Vertex] = [
            // Front face (red)
            Vertex(position: [-s, -s,  s], normal: [0, 0, 1], color: [1, 0.3, 0.3, 1]),
            Vertex(position: [ s, -s,  s], normal: [0, 0, 1], color: [1, 0.3, 0.3, 1]),
            Vertex(position: [ s,  s,  s], normal: [0, 0, 1], color: [1, 0.3, 0.3, 1]),
            Vertex(position: [-s,  s,  s], normal: [0, 0, 1], color: [1, 0.3, 0.3, 1]),
            // Back face (green)
            Vertex(position: [ s, -s, -s], normal: [0, 0, -1], color: [0.3, 1, 0.3, 1]),
            Vertex(position: [-s, -s, -s], normal: [0, 0, -1], color: [0.3, 1, 0.3, 1]),
            Vertex(position: [-s,  s, -s], normal: [0, 0, -1], color: [0.3, 1, 0.3, 1]),
            Vertex(position: [ s,  s, -s], normal: [0, 0, -1], color: [0.3, 1, 0.3, 1]),
            // Top face (blue)
            Vertex(position: [-s,  s,  s], normal: [0, 1, 0], color: [0.3, 0.3, 1, 1]),
            Vertex(position: [ s,  s,  s], normal: [0, 1, 0], color: [0.3, 0.3, 1, 1]),
            Vertex(position: [ s,  s, -s], normal: [0, 1, 0], color: [0.3, 0.3, 1, 1]),
            Vertex(position: [-s,  s, -s], normal: [0, 1, 0], color: [0.3, 0.3, 1, 1]),
            // Bottom face (yellow)
            Vertex(position: [-s, -s, -s], normal: [0, -1, 0], color: [1, 1, 0.3, 1]),
            Vertex(position: [ s, -s, -s], normal: [0, -1, 0], color: [1, 1, 0.3, 1]),
            Vertex(position: [ s, -s,  s], normal: [0, -1, 0], color: [1, 1, 0.3, 1]),
            Vertex(position: [-s, -s,  s], normal: [0, -1, 0], color: [1, 1, 0.3, 1]),
            // Right face (magenta)
            Vertex(position: [ s, -s,  s], normal: [1, 0, 0], color: [1, 0.3, 1, 1]),
            Vertex(position: [ s, -s, -s], normal: [1, 0, 0], color: [1, 0.3, 1, 1]),
            Vertex(position: [ s,  s, -s], normal: [1, 0, 0], color: [1, 0.3, 1, 1]),
            Vertex(position: [ s,  s,  s], normal: [1, 0, 0], color: [1, 0.3, 1, 1]),
            // Left face (cyan)
            Vertex(position: [-s, -s, -s], normal: [-1, 0, 0], color: [0.3, 1, 1, 1]),
            Vertex(position: [-s, -s,  s], normal: [-1, 0, 0], color: [0.3, 1, 1, 1]),
            Vertex(position: [-s,  s,  s], normal: [-1, 0, 0], color: [0.3, 1, 1, 1]),
            Vertex(position: [-s,  s, -s], normal: [-1, 0, 0], color: [0.3, 1, 1, 1]),
        ]

        let indices: [UInt16] = [
            0, 1, 2, 0, 2, 3,       // front
            4, 5, 6, 4, 6, 7,       // back
            8, 9, 10, 8, 10, 11,    // top
            12, 13, 14, 12, 14, 15, // bottom
            16, 17, 18, 16, 18, 19, // right
            20, 21, 22, 20, 22, 23  // left
        ]

        indexCount = indices.count

        vertexBuffer = device.makeBuffer(
            bytes: vertices,
            length: MemoryLayout<Vertex>.stride * vertices.count,
            options: .storageModeShared
        )

        indexBuffer = device.makeBuffer(
            bytes: indices,
            length: MemoryLayout<UInt16>.stride * indices.count,
            options: .storageModeShared
        )

        uniformBuffer = device.makeBuffer(
            length: MemoryLayout<Uniforms>.stride,
            options: .storageModeShared
        )
    }

    func draw(encoder: MTLRenderCommandEncoder, time: Double, aspect: Float) {
        let t = Float(time)

        // Create matrices
        let rotation = t * 0.5
        let modelMatrix = float4x4(rotationY: rotation) * float4x4(rotationX: rotation * 0.7)

        let eye = SIMD3<Float>(0, 0, 3)
        let center = SIMD3<Float>(0, 0, 0)
        let up = SIMD3<Float>(0, 1, 0)
        let viewMatrix = float4x4(lookAt: eye, center: center, up: up)

        let projectionMatrix = float4x4(perspectiveFov: .pi / 4, aspect: aspect, near: 0.1, far: 100)

        var uniforms = Uniforms(
            modelMatrix: modelMatrix,
            viewMatrix: viewMatrix,
            projectionMatrix: projectionMatrix,
            time: t
        )

        uniformBuffer.contents().copyMemory(
            from: &uniforms,
            byteCount: MemoryLayout<Uniforms>.stride
        )

        encoder.setRenderPipelineState(pipelineState)
        encoder.setDepthStencilState(depthState)
        encoder.setFrontFacing(.counterClockwise)
        encoder.setCullMode(.back)

        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setVertexBuffer(uniformBuffer, offset: 0, index: 1)
        encoder.setFragmentBuffer(uniformBuffer, offset: 0, index: 1)

        encoder.drawIndexedPrimitives(
            type: .triangle,
            indexCount: indexCount,
            indexType: .uint16,
            indexBuffer: indexBuffer,
            indexBufferOffset: 0
        )
    }
}
