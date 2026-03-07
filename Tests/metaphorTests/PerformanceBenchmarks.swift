import Testing
import Metal
@testable import metaphor
@testable import MetaphorCore
import MetaphorTestSupport

// MARK: - Performance Benchmarks

@Suite("Performance Benchmarks", .enabled(if: MetalTestHelper.isGPUAvailable))
@MainActor
struct PerformanceBenchmarks {

    /// Measure execution time with ContinuousClock.
    private func measure(_ body: () throws -> Void) throws -> Duration {
        let clock = ContinuousClock()
        let elapsed = try clock.measure {
            try body()
        }
        return elapsed
    }

    @Test("ShaderLibrary init < 2 seconds")
    func shaderLibraryInit() throws {
        let device = MetalTestHelper.device!
        let elapsed = try measure {
            _ = try ShaderLibrary(device: device)
        }
        #expect(elapsed < .seconds(2), "ShaderLibrary init took \(elapsed)")
    }

    @Test("ComputeKernel compile < 1 second")
    func computeKernelCompile() throws {
        let device = MetalTestHelper.device!
        let source = """
        #include <metal_stdlib>
        using namespace metal;
        kernel void testKernel(device float *buf [[buffer(0)]], uint id [[thread_position_in_grid]]) {
            buf[id] = buf[id] * 2.0;
        }
        """
        let elapsed = try measure {
            _ = try ComputeKernel(device: device, source: source, functionName: "testKernel")
        }
        #expect(elapsed < .seconds(1), "ComputeKernel compile took \(elapsed)")
    }

    @Test("Mesh.box generation < 100ms")
    func meshBoxGeneration() throws {
        let device = MetalTestHelper.device!
        let elapsed = try measure {
            _ = try Mesh.box(device: device)
        }
        #expect(elapsed < .milliseconds(100), "Mesh.box took \(elapsed)")
    }

    @Test("Mesh.sphere generation < 100ms")
    func meshSphereGeneration() throws {
        let device = MetalTestHelper.device!
        let elapsed = try measure {
            _ = try Mesh.sphere(device: device)
        }
        #expect(elapsed < .milliseconds(100), "Mesh.sphere took \(elapsed)")
    }

    @Test("GrowableGPUBuffer 4K to 64K growth < 100ms")
    func growableBufferGrowth() throws {
        let device = MetalTestHelper.device!
        let elapsed = try measure {
            let buffer = try GrowableGPUBuffer<Float>(
                device: device,
                initialCapacity: 4096,
                maxCapacity: 1_000_000,
                label: "perf.test"
            )
            _ = buffer.ensureCapacity(65536, activeIndex: 0, usedCount: 0)
        }
        #expect(elapsed < .milliseconds(100), "Buffer growth took \(elapsed)")
    }

    @Test("TextureManager creation at 4K resolution < 500ms")
    func textureManager4K() throws {
        let device = MetalTestHelper.device!
        let elapsed = try measure {
            _ = try TextureManager(
                device: device,
                width: 3840,
                height: 2160,
                sampleCount: 1
            )
        }
        #expect(elapsed < .milliseconds(500), "TextureManager 4K creation took \(elapsed)")
    }

    @Test("PostProcessPipeline 5 effects setup < 500ms")
    func postProcessSetup() throws {
        let device = MetalTestHelper.device!
        let commandQueue = device.makeCommandQueue()!
        let shaderLib = try ShaderLibrary(device: device)

        let elapsed = try measure {
            let pipeline = try PostProcessPipeline(
                device: device,
                commandQueue: commandQueue,
                shaderLibrary: shaderLib
            )
            pipeline.add(BloomEffect(intensity: 1.0, threshold: 0.8))
            pipeline.add(BlurEffect(radius: 5.0))
            pipeline.add(InvertEffect())
            pipeline.add(GrayscaleEffect())
            pipeline.add(VignetteEffect(intensity: 0.5))
        }
        #expect(elapsed < .milliseconds(500), "PostProcess setup took \(elapsed)")
    }

    @Test("Canvas2D creation < 200ms")
    func canvas2DCreation() throws {
        let elapsed = try measure {
            _ = try MetalTestHelper.canvas2D(width: 1920, height: 1080)
        }
        #expect(elapsed < .milliseconds(200), "Canvas2D creation took \(elapsed)")
    }
}
