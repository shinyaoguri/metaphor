import Testing
import Metal
import simd
@testable import metaphor
@testable import MetaphorCore

// MARK: - ComputeKernel Tests

@Suite("ComputeKernel", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct ComputeKernelTests {

    @Test("can create kernel from MSL source")
    func createFromSource() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let source = """
        #include <metal_stdlib>
        using namespace metal;
        kernel void testKernel(device float *buf [[buffer(0)]], uint id [[thread_position_in_grid]]) {
            buf[id] = float(id);
        }
        """
        let kernel = try ComputeKernel(device: device, source: source, functionName: "testKernel")
        #expect(kernel.maxTotalThreadsPerThreadgroup > 0)
        #expect(kernel.threadExecutionWidth > 0)
    }

    @Test("throws on invalid function name")
    func invalidFunction() {
        let device = MTLCreateSystemDefaultDevice()!
        let source = """
        #include <metal_stdlib>
        using namespace metal;
        kernel void realFunction(device float *buf [[buffer(0)]], uint id [[thread_position_in_grid]]) {
            buf[id] = 0;
        }
        """
        #expect(throws: ComputeKernelError.self) {
            try ComputeKernel(device: device, source: source, functionName: "nonExistent")
        }
    }

    @Test("can create kernel from MTLFunction")
    func createFromFunction() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let source = """
        #include <metal_stdlib>
        using namespace metal;
        kernel void testFn(device float *buf [[buffer(0)]], uint id [[thread_position_in_grid]]) {
            buf[id] = 1.0;
        }
        """
        let library = try device.makeLibrary(source: source, options: nil)
        let function = library.makeFunction(name: "testFn")!
        let kernel = try ComputeKernel(device: device, function: function)
        #expect(kernel.maxTotalThreadsPerThreadgroup > 0)
    }
}

// MARK: - GPUBuffer Tests

@Suite("GPUBuffer", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct GPUBufferTests {

    @Test("can create empty buffer")
    func createEmpty() {
        let device = MTLCreateSystemDefaultDevice()!
        let buf = GPUBuffer<Float>(device: device, count: 100)
        #expect(buf != nil)
        #expect(buf!.count == 100)
        #expect(buf![0] == 0)
    }

    @Test("can create buffer from array")
    func createFromArray() {
        let device = MTLCreateSystemDefaultDevice()!
        let data: [Float] = [1.0, 2.0, 3.0, 4.0]
        let buf = GPUBuffer<Float>(device: device, data: data)
        #expect(buf != nil)
        #expect(buf!.count == 4)
        #expect(buf![0] == 1.0)
        #expect(buf![3] == 4.0)
    }

    @Test("subscript get/set")
    func subscriptAccess() {
        let device = MTLCreateSystemDefaultDevice()!
        let buf = GPUBuffer<Float>(device: device, count: 10)!
        buf[5] = 42.0
        #expect(buf[5] == 42.0)
    }

    @Test("toArray returns copy")
    func toArray() {
        let device = MTLCreateSystemDefaultDevice()!
        let data: [SIMD2<Float>] = [SIMD2(1, 2), SIMD2(3, 4)]
        let buf = GPUBuffer<SIMD2<Float>>(device: device, data: data)!
        let arr = buf.toArray()
        #expect(arr.count == 2)
        #expect(arr[0] == SIMD2(1, 2))
    }

    @Test("copyFrom copies data")
    func copyFrom() {
        let device = MTLCreateSystemDefaultDevice()!
        let buf = GPUBuffer<Int32>(device: device, count: 4)!
        buf.copyFrom([10, 20, 30, 40])
        #expect(buf[0] == 10)
        #expect(buf[3] == 40)
    }

    @Test("works with custom struct")
    func customStruct() {
        struct Particle {
            var x: Float
            var y: Float
            var vx: Float
            var vy: Float
        }
        let device = MTLCreateSystemDefaultDevice()!
        let buf = GPUBuffer<Particle>(device: device, count: 100)!
        buf[0] = Particle(x: 1, y: 2, vx: 3, vy: 4)
        #expect(buf[0].x == 1)
        #expect(buf[0].vy == 4)
    }

    @Test("buffer has correct byte length")
    func byteLength() {
        let device = MTLCreateSystemDefaultDevice()!
        let buf = GPUBuffer<Float>(device: device, count: 256)!
        #expect(buf.buffer.length == MemoryLayout<Float>.stride * 256)
    }
}

// MARK: - Compute Integration Tests

@Suite("Compute Integration", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct ComputeIntegrationTests {

    @Test("can dispatch compute kernel and read results")
    func dispatchAndRead() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let source = """
        #include <metal_stdlib>
        using namespace metal;
        kernel void fillBuffer(device float *output [[buffer(0)]], uint id [[thread_position_in_grid]]) {
            output[id] = float(id) * 2.0;
        }
        """
        let kernel = try ComputeKernel(device: device, source: source, functionName: "fillBuffer")
        let buffer = GPUBuffer<Float>(device: device, count: 64)!

        let commandQueue = device.makeCommandQueue()!
        let commandBuffer = commandQueue.makeCommandBuffer()!
        let encoder = commandBuffer.makeComputeCommandEncoder()!

        encoder.setComputePipelineState(kernel.pipelineState)
        encoder.setBuffer(buffer.buffer, offset: 0, index: 0)

        let w = kernel.threadExecutionWidth
        encoder.dispatchThreads(
            MTLSize(width: 64, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: w, height: 1, depth: 1)
        )
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        #expect(buffer[0] == 0.0)
        #expect(buffer[1] == 2.0)
        #expect(buffer[63] == 126.0)
    }

    @Test("double dispatch with barrier reads correct data")
    func doubleDispatchWithBarrier() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let source = """
        #include <metal_stdlib>
        using namespace metal;
        kernel void step1(device float *buf [[buffer(0)]], uint id [[thread_position_in_grid]]) {
            buf[id] = float(id);
        }
        kernel void step2(device float *buf [[buffer(0)]], uint id [[thread_position_in_grid]]) {
            buf[id] = buf[id] * 3.0;
        }
        """
        let kernel1 = try ComputeKernel(device: device, source: source, functionName: "step1")
        let kernel2 = try ComputeKernel(device: device, source: source, functionName: "step2")
        let buffer = GPUBuffer<Float>(device: device, count: 32)!

        let commandQueue = device.makeCommandQueue()!
        let commandBuffer = commandQueue.makeCommandBuffer()!
        let encoder = commandBuffer.makeComputeCommandEncoder()!

        encoder.setComputePipelineState(kernel1.pipelineState)
        encoder.setBuffer(buffer.buffer, offset: 0, index: 0)
        let w = kernel1.threadExecutionWidth
        encoder.dispatchThreads(
            MTLSize(width: 32, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: w, height: 1, depth: 1)
        )

        encoder.memoryBarrier(scope: .buffers)

        encoder.setComputePipelineState(kernel2.pipelineState)
        encoder.setBuffer(buffer.buffer, offset: 0, index: 0)
        encoder.dispatchThreads(
            MTLSize(width: 32, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: w, height: 1, depth: 1)
        )

        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        #expect(buffer[0] == 0.0)
        #expect(buffer[1] == 3.0)
        #expect(buffer[10] == 30.0)
    }
}
