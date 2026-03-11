import Testing
import Metal
@testable import MetaphorCore
import MetaphorTestSupport

// MARK: - MetaphorError Description Tests

@Suite("MetaphorError descriptions")
struct MetaphorErrorDescriptionTests {

    @Test("deviceNotAvailable has description")
    func deviceNotAvailable() {
        let e = MetaphorError.deviceNotAvailable
        #expect(e.errorDescription?.isEmpty == false)
        #expect(e.errorDescription?.contains("[metaphor]") == true)
    }

    @Test("textureCreationFailed includes dimensions")
    func textureCreationFailed() {
        let e = MetaphorError.textureCreationFailed(width: 1024, height: 768, format: "bgra8Unorm")
        #expect(e.errorDescription?.contains("1024") == true)
    }

    @Test("commandQueueCreationFailed has description")
    func commandQueueCreationFailed() {
        let e = MetaphorError.commandQueueCreationFailed
        #expect(e.errorDescription?.isEmpty == false)
    }

    @Test("bufferCreationFailed includes size")
    func bufferCreationFailed() {
        let e = MetaphorError.bufferCreationFailed(size: 65536)
        #expect(e.errorDescription?.contains("65536") == true)
    }

    @Test("contextUnavailable includes method name")
    func contextUnavailable() {
        let e = MetaphorError.contextUnavailable(method: "circle")
        #expect(e.errorDescription?.contains("circle") == true)
    }

    @Test("shaderCompilationFailed includes shader name")
    func shaderCompilationFailed() {
        let e = MetaphorError.shaderCompilationFailed(
            name: "myShader",
            underlying: NSError(domain: "test", code: 0)
        )
        #expect(e.errorDescription?.contains("myShader") == true)
    }

    @Test("pipelineCreationFailed includes name")
    func pipelineCreationFailed() {
        let e = MetaphorError.pipelineCreationFailed(
            name: "myPipeline",
            underlying: NSError(domain: "test", code: 0)
        )
        #expect(e.errorDescription?.contains("myPipeline") == true)
    }

    @Test("shaderNotFound includes name")
    func shaderNotFound() {
        let e = MetaphorError.shaderNotFound("missingFunc")
        #expect(e.errorDescription?.contains("missingFunc") == true)
    }

    // MARK: - Nested Failure Types

    @Test("canvas failure has description")
    func canvasFailure() {
        let e = MetaphorError.canvas(.bufferCreationFailed)
        #expect(e.errorDescription?.isEmpty == false)
    }

    @Test("mesh failure includes detail")
    func meshFailure() {
        let e = MetaphorError.mesh(.parseError("bad vertex"))
        #expect(e.errorDescription?.contains("bad vertex") == true)
    }

    @Test("image failure has description")
    func imageFailure() {
        let e = MetaphorError.image(.invalidImage)
        #expect(e.errorDescription?.isEmpty == false)
    }

    @Test("material failure includes shader name")
    func materialFailure() {
        let e = MetaphorError.material(.shaderNotFound("customFrag"))
        #expect(e.errorDescription?.contains("customFrag") == true)
    }

    @Test("particle failure has description")
    func particleFailure() {
        let e = MetaphorError.particle(.bufferCreationFailed)
        #expect(e.errorDescription?.isEmpty == false)
    }

    @Test("export failure cases")
    func exportFailure() {
        let cases: [MetaphorError] = [
            .export(.noFrames),
            .export(.destinationCreationFailed),
            .export(.finalizationFailed),
            .export(.writerFailed("write error")),
            .export(.notRecording),
        ]
        for e in cases {
            #expect(e.errorDescription?.isEmpty == false)
        }
    }

    @Test("compute failure includes function name")
    func computeFailure() {
        let e = MetaphorError.compute(.functionNotFound("myKernel"))
        #expect(e.errorDescription?.contains("myKernel") == true)
    }

    @Test("renderGraph failure includes shader name")
    func renderGraphFailure() {
        let e = MetaphorError.renderGraph(.shaderNotFound("mergePass"))
        #expect(e.errorDescription?.contains("mergePass") == true)
    }
}

// MARK: - Error Throwing Tests

@Suite("Error Throwing", .enabled(if: MetalTestHelper.isGPUAvailable))
@MainActor
struct ErrorThrowingTests {

    @Test("ShaderLibrary with invalid MSL throws on register")
    func invalidMSL() throws {
        let shaderLib = try MetalTestHelper.shaderLibrary()
        // Invalid MSL should throw during register (Metal compile)
        #expect(throws: (any Error).self) {
            try shaderLib.register(source: "THIS IS NOT VALID MSL CODE !!!", as: "invalidShader")
        }
    }

    @Test("ShaderLibrary function not found returns nil")
    func functionNotFound() throws {
        let shaderLib = try MetalTestHelper.shaderLibrary()
        let fn = shaderLib.function(named: "nonExistentFunc", from: "nonExistentKey")
        #expect(fn == nil)
    }

    @Test("ComputeKernel with invalid function name throws")
    func invalidKernelFunction() throws {
        let device = MetalTestHelper.device!
        #expect(throws: MetaphorError.self) {
            _ = try ComputeKernel(
                device: device,
                source: "kernel void validKernel(device float* buf [[buffer(0)]], uint id [[thread_position_in_grid]]) { buf[id] = 0; }",
                functionName: "nonExistentFunction"
            )
        }
    }
}
