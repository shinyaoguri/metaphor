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

    // MARK: - 型統一で追加されたケース（Issue #323）

    @Test("shaderSourceLoadFailed includes path and detail")
    func shaderSourceLoadFailed() {
        let e = MetaphorError.shaderSourceLoadFailed(path: "/no/such.metal", detail: "no such file")
        #expect(e.errorDescription?.contains("/no/such.metal") == true)
        #expect(e.errorDescription?.contains("no such file") == true)
    }

    @Test("image loadFailed includes source and detail")
    func imageLoadFailed() {
        let e = MetaphorError.image(.loadFailed(source: "cat.png", detail: "corrupt"))
        #expect(e.errorDescription?.contains("cat.png") == true)
        #expect(e.errorDescription?.contains("corrupt") == true)
    }

    @Test("mesh loadFailed includes path and detail")
    func meshLoadFailed() {
        let e = MetaphorError.mesh(.loadFailed(path: "/no/such.obj", detail: "missing"))
        #expect(e.errorDescription?.contains("/no/such.obj") == true)
        #expect(e.errorDescription?.contains("missing") == true)
    }

    @Test("export fileWriteFailed includes path and detail")
    func exportFileWriteFailed() {
        let e = MetaphorError.export(.fileWriteFailed(path: "/ro/out.gif", detail: "read-only"))
        #expect(e.errorDescription?.contains("/ro/out.gif") == true)
        #expect(e.errorDescription?.contains("read-only") == true)
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
        #expect(throws: MetaphorError.self) {
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

// MARK: - エラー契約（Issue #323）

/// 生成系 public API が下層フレームワーク（Metal / Foundation / MetalKit）の生
/// `NSError` を素通りさせず、必ず ``MetaphorError`` の**特定のケース**へ包んでいることを
/// 凍結する。ここが崩れると「`catch let e as MetaphorError` で全部拾える」という
/// ADR-0005 のエラー契約が破れる。
@Suite("Error contract: MetaphorError only", .enabled(if: MetalTestHelper.isGPUAvailable))
@MainActor
struct ErrorContractTests {

    /// 投げられたエラーが期待どおりの ``MetaphorError`` ケースかを検査する。
    private func expectMetaphorError(
        _ body: () throws -> Void,
        matches: (MetaphorError) -> Bool,
        _ what: Comment,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        do {
            try body()
            Issue.record("expected a throw but the call succeeded: \(what)",
                         sourceLocation: sourceLocation)
        } catch let error as MetaphorError {
            #expect(matches(error), what, sourceLocation: sourceLocation)
        } catch {
            // ここに来るのが「生 NSError の素通り」= 契約違反
            Issue.record(
                "expected MetaphorError but got \(type(of: error)): \(error)",
                sourceLocation: sourceLocation)
        }
    }

    @Test("register(source:) wraps Metal compile errors as shaderCompilationFailed")
    func registerWrapsMetalError() throws {
        let shaderLib = try MetalTestHelper.shaderLibrary()
        expectMetaphorError({
            try shaderLib.register(source: "NOT VALID MSL !!!", as: "badShader")
        }, matches: {
            if case .shaderCompilationFailed(let name, _) = $0 { return name == "badShader" }
            return false
        }, "MSL コンパイル失敗は shaderCompilationFailed へ包まれる")
    }

    @Test("registerFromFile wraps missing-file IO errors as shaderSourceLoadFailed")
    func registerFromFileWrapsIOError() throws {
        let shaderLib = try MetalTestHelper.shaderLibrary()
        let missing = "/nonexistent/metaphor-test/never.metal"
        expectMetaphorError({
            try shaderLib.registerFromFile(path: missing, as: "fromMissingFile")
        }, matches: {
            if case .shaderSourceLoadFailed(let path, _) = $0 { return path == missing }
            return false
        }, "シェーダーソースの読み込み失敗は shaderSourceLoadFailed へ包まれる")
    }

    @Test("reloadFromFile wraps missing-file IO errors as shaderSourceLoadFailed")
    func reloadFromFileWrapsIOError() throws {
        let shaderLib = try MetalTestHelper.shaderLibrary()
        let missing = "/nonexistent/metaphor-test/never.metal"
        expectMetaphorError({
            try shaderLib.reloadFromFile(key: "anyKey", path: missing)
        }, matches: {
            if case .shaderSourceLoadFailed(let path, _) = $0 { return path == missing }
            return false
        }, "ホットリロードの読み込み失敗も shaderSourceLoadFailed へ包まれる")
    }

    @Test("ComputeKernel wraps Metal compile errors as shaderCompilationFailed")
    func computeKernelWrapsCompileError() throws {
        let device = MetalTestHelper.device!
        expectMetaphorError({
            _ = try ComputeKernel(
                device: device, source: "NOT VALID MSL !!!", functionName: "k")
        }, matches: {
            if case .shaderCompilationFailed = $0 { return true }
            return false
        }, "ComputeKernel の MSL コンパイル失敗は shaderCompilationFailed へ包まれる")
    }

    @Test("MImage wraps MetalKit loader errors as image(.loadFailed)")
    func imageWrapsLoaderError() throws {
        let device = MetalTestHelper.device!
        let missing = "/nonexistent/metaphor-test/never.png"
        expectMetaphorError({
            _ = try MImage(path: missing, device: device)
        }, matches: {
            if case .image(.loadFailed(let source, _)) = $0 { return source == missing }
            return false
        }, "画像の読み込み失敗は image(.loadFailed) へ包まれる")
    }

    @Test("Mesh.loadOBJ wraps Foundation IO errors as mesh(.loadFailed)")
    func meshWrapsIOError() throws {
        let device = MetalTestHelper.device!
        let missing = URL(fileURLWithPath: "/nonexistent/metaphor-test/never.obj")
        expectMetaphorError({
            _ = try Mesh.loadOBJ(device: device, url: missing)
        }, matches: {
            if case .mesh(.loadFailed(let path, _)) = $0 { return path == missing.path }
            return false
        }, "OBJ の読み込み失敗は mesh(.loadFailed) へ包まれる")
    }

    @Test("ResourceLoader wraps MetalKit loader errors as image(.loadFailed)")
    func resourceLoaderWrapsLoaderError() async throws {
        let device = MetalTestHelper.device!
        let loader = ResourceLoader(device: device)
        let missing = "/nonexistent/metaphor-test/never.png"
        do {
            _ = try await loader.loadImageAsync(path: missing)
            Issue.record("expected a throw but the call succeeded")
        } catch let error as MetaphorError {
            guard case .image(.loadFailed(let source, _)) = error else {
                Issue.record("expected image(.loadFailed) but got \(error)")
                return
            }
            #expect(source == missing)
        } catch {
            Issue.record("expected MetaphorError but got \(type(of: error)): \(error)")
        }
    }
}
