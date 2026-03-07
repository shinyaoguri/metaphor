import Testing
import CoreML
import CoreVideo
import Metal
import simd
@testable import metaphor
@testable import MetaphorCore
import MetaphorML

// MARK: - SketchContext MLTextureConverter Factory Test

@Suite("SketchContext MLTextureConverter", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct SketchContextMLTextureConverterTests {

    @Test("createMLTextureConverter returns valid instance")
    func createMLTextureConverter() throws {
        let renderer = try MetaphorRenderer()

        let converter = MLTextureConverter(device: renderer.device, commandQueue: renderer.commandQueue)
        // Converter should be functional
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: 2, height: 2, mipmapped: false)
        desc.storageMode = .shared
        let tex = renderer.device.makeTexture(descriptor: desc)!
        let pb = converter.pixelBuffer(from: tex)
        #expect(pb != nil)
    }
}
