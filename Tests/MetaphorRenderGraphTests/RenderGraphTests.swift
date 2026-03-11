import Testing
import Metal
import simd
@testable import MetaphorCore
@testable import MetaphorRenderGraph

@Suite("RenderGraph", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct RenderGraphTests {
    let device: MTLDevice

    init() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw MetaphorError.deviceNotAvailable
        }
        self.device = device
    }

    // MARK: - SourcePass Tests

    @Test("SourcePass creates valid offscreen texture")
    func sourcePassCreatesTexture() throws {
        let pass = try SourcePass(label: "test", device: device, width: 256, height: 256)
        #expect(pass.label == "test")
        #expect(pass.output != nil)
        #expect(pass.output?.width == 256)
        #expect(pass.output?.height == 256)
    }

    @Test("SourcePass onDraw callback is invoked")
    func sourcePassCallbackInvoked() throws {
        let pass = try SourcePass(label: "cb", device: device, width: 64, height: 64)
        var called = false
        pass.onDraw = { _, _ in called = true }

        guard let queue = device.makeCommandQueue(),
              let cmdBuf = queue.makeCommandBuffer() else {
            return
        }

        let renderer = try MetaphorRenderer(
            device: device,
            width: 64,
            height: 64
        )
        pass.execute(commandBuffer: cmdBuf, time: 0, renderer: renderer)
        cmdBuf.commit()
        cmdBuf.waitUntilCompleted()
        #expect(called)
    }

    @Test("SourcePass with different sizes")
    func sourcePassDifferentSizes() throws {
        let small = try SourcePass(label: "s", device: device, width: 32, height: 32)
        let large = try SourcePass(label: "l", device: device, width: 1024, height: 512)
        #expect(small.output?.width == 32)
        #expect(large.output?.width == 1024)
        #expect(large.output?.height == 512)
    }

    // MARK: - EffectPass Tests

    @Test("EffectPass wraps upstream pass")
    func effectPassWrapsUpstream() throws {
        let source = try SourcePass(label: "src", device: device, width: 128, height: 128)
        let shaderLib = try ShaderLibrary(device: device)
        let queue = device.makeCommandQueue()!
        let effect = try EffectPass(
            source,
            effects: [],
            device: device,
            commandQueue: queue,
            shaderLibrary: shaderLib
        )
        #expect(effect.label == "effect(src)")
    }

    // MARK: - RenderGraph Tests

    @Test("RenderGraph with single SourcePass produces output")
    func graphSingleSourcePass() throws {
        let pass = try SourcePass(label: "root", device: device, width: 64, height: 64)
        pass.onDraw = { encoder, _ in
            // Just end encoding, no actual drawing needed
        }

        let graph = RenderGraph(root: pass)
        guard let queue = device.makeCommandQueue(),
              let cmdBuf = queue.makeCommandBuffer() else {
            return
        }

        let renderer = try MetaphorRenderer(
            device: device,
            width: 64,
            height: 64
        )
        let output = graph.execute(commandBuffer: cmdBuf, time: 0, renderer: renderer)
        cmdBuf.commit()
        cmdBuf.waitUntilCompleted()
        #expect(output != nil)
        #expect(output?.width == 64)
    }

    // MARK: - MergePass.BlendType Tests

    @Test("BlendType cases have correct raw indices")
    func blendTypeIndices() {
        #expect(MergePass.BlendType.add.rawIndex == 0)
        #expect(MergePass.BlendType.alpha.rawIndex == 1)
        #expect(MergePass.BlendType.multiply.rawIndex == 2)
        #expect(MergePass.BlendType.screen.rawIndex == 3)
    }

    @Test("BlendType has all 4 cases")
    func blendTypeAllCases() {
        #expect(MergePass.BlendType.allCases.count == 4)
    }

    // MARK: - RenderPassNode Protocol

    @Test("RenderPassNode protocol conformance for SourcePass")
    func sourcePassConformsToProtocol() throws {
        let pass = try SourcePass(label: "proto", device: device, width: 64, height: 64)
        let node: RenderPassNode = pass
        #expect(node.label == "proto")
        #expect(node.output != nil)
    }
}
