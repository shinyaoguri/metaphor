import Testing
import Metal
import CoreImage
@testable import MetaphorCoreImage

// MARK: - CIFilterPreset Tests

@Suite("CIFilterPreset")
struct CIFilterPresetTests {

    @Test("twirl filter name and parameters")
    func twirlFilter() {
        let preset = CIFilterPreset.twirl(radius: 200, angle: .pi)
        #expect(preset.filterName == "CITwirlDistortion")
        #expect(!preset.isGenerator)
        let params = preset.parameters(textureSize: CGSize(width: 512, height: 512))
        #expect(params["inputAngle"] as? Float == .pi)
        #expect(params["inputRadius"] as? Float == 200)
    }

    @Test("vortex filter")
    func vortexFilter() {
        let preset = CIFilterPreset.vortex(radius: 150, angle: 2.0)
        #expect(preset.filterName == "CIVortexDistortion")
    }

    @Test("bump filter")
    func bumpFilter() {
        let preset = CIFilterPreset.bump(radius: 100, scale: 0.5)
        #expect(preset.filterName == "CIBumpDistortion")
    }

    @Test("pinch filter")
    func pinchFilter() {
        let preset = CIFilterPreset.pinch(radius: 200, scale: 0.5)
        #expect(preset.filterName == "CIPinchDistortion")
    }

    @Test("pixellate filter")
    func pixellateFilter() {
        let preset = CIFilterPreset.ciPixellate(scale: 10)
        #expect(preset.filterName == "CIPixellate")
    }

    @Test("crystallize filter")
    func crystallizeFilter() {
        let preset = CIFilterPreset.crystallize(radius: 20)
        #expect(preset.filterName == "CICrystallize")
    }

    @Test("pointillize filter")
    func pointillizeFilter() {
        let preset = CIFilterPreset.pointillize(radius: 15)
        #expect(preset.filterName == "CIPointillize")
    }

    @Test("edges filter")
    func edgesFilter() {
        let preset = CIFilterPreset.ciEdges(intensity: 5.0)
        #expect(preset.filterName == "CIEdges")
    }

    @Test("comic filter")
    func comicFilter() {
        let preset = CIFilterPreset.comic
        #expect(preset.filterName == "CIComicEffect")
    }

    @Test("hexPixellate filter")
    func hexPixellateFilter() {
        let preset = CIFilterPreset.hexPixellate(scale: 8)
        #expect(preset.filterName == "CIHexagonalPixellate")
    }

    @Test("kaleidoscope filter")
    func kaleidoscopeFilter() {
        let preset = CIFilterPreset.kaleidoscope(count: 6, angle: 0)
        #expect(preset.filterName == "CIKaleidoscope")
    }

    @Test("triangleKaleidoscope filter")
    func triangleKaleidoscopeFilter() {
        let preset = CIFilterPreset.triangleKaleidoscope(size: 100, decay: 0.85)
        #expect(preset.filterName == "CITriangleKaleidoscope")
    }

    // MARK: - Generator Tests

    @Test("checkerboard is generator")
    func checkerboardIsGenerator() {
        let preset = CIFilterPreset.checkerboard(width: 40)
        #expect(preset.isGenerator)
        #expect(preset.filterName == "CICheckerboardGenerator")
    }

    @Test("stripes is generator")
    func stripesIsGenerator() {
        let preset = CIFilterPreset.stripes(width: 20)
        #expect(preset.isGenerator)
        #expect(preset.filterName == "CIStripesGenerator")
    }

    @Test("starShine is generator")
    func starShineIsGenerator() {
        let preset = CIFilterPreset.starShine(radius: 50, crossScale: 15, crossAngle: 0.6, crossOpacity: -2)
        #expect(preset.isGenerator)
    }

    @Test("sunbeams is generator")
    func sunbeamsIsGenerator() {
        let preset = CIFilterPreset.sunbeams(sunRadius: 40, maxStriationRadius: 2.58)
        #expect(preset.isGenerator)
    }

    // MARK: - Color Effect Tests

    @Test("falseColor filter")
    func falseColorFilter() {
        let preset = CIFilterPreset.falseColor(
            color0: CIColor(red: 0, green: 0, blue: 0),
            color1: CIColor(red: 1, green: 1, blue: 1)
        )
        #expect(preset.filterName == "CIFalseColor")
    }

    @Test("colorPosterize filter")
    func colorPosterizeFilter() {
        let preset = CIFilterPreset.colorPosterize(levels: 4)
        #expect(preset.filterName == "CIColorPosterize")
    }

    @Test("photoEffectMono filter")
    func photoEffectMonoFilter() {
        let preset = CIFilterPreset.photoEffectMono
        #expect(preset.filterName == "CIPhotoEffectMono")
    }

    @Test("photoEffectChrome filter")
    func photoEffectChromeFilter() {
        let preset = CIFilterPreset.photoEffectChrome
        #expect(preset.filterName == "CIPhotoEffectChrome")
    }

    @Test("photoEffectNoir filter")
    func photoEffectNoirFilter() {
        let preset = CIFilterPreset.photoEffectNoir
        #expect(preset.filterName == "CIPhotoEffectNoir")
    }

    @Test("photoEffectFade filter")
    func photoEffectFadeFilter() {
        let preset = CIFilterPreset.photoEffectFade
        #expect(preset.filterName == "CIPhotoEffectFade")
    }

    // MARK: - Blur Tests

    @Test("gaussianBlur filter")
    func gaussianBlurFilter() {
        let preset = CIFilterPreset.ciGaussianBlur(radius: 10)
        #expect(preset.filterName == "CIGaussianBlur")
    }

    @Test("motionBlur filter")
    func motionBlurFilter() {
        let preset = CIFilterPreset.motionBlur(radius: 20, angle: .pi / 4)
        #expect(preset.filterName == "CIMotionBlur")
    }

    @Test("zoomBlur filter")
    func zoomBlurFilter() {
        let preset = CIFilterPreset.zoomBlur(amount: 30)
        #expect(preset.filterName == "CIZoomBlur")
    }

    @Test("discBlur filter")
    func discBlurFilter() {
        let preset = CIFilterPreset.discBlur(radius: 8)
        #expect(preset.filterName == "CIDiscBlur")
    }

    @Test("boxBlur filter")
    func boxBlurFilter() {
        let preset = CIFilterPreset.boxBlur(radius: 10)
        #expect(preset.filterName == "CIBoxBlur")
    }

    // MARK: - Center Parameter Tests

    @Test("default center uses texture center")
    func defaultCenter() {
        let preset = CIFilterPreset.twirl(radius: 200, angle: .pi)
        let params = preset.parameters(textureSize: CGSize(width: 800, height: 600))
        if let center = params["inputCenter"] as? CIVector {
            #expect(center.x == 400)
            #expect(center.y == 300)
        } else {
            Issue.record("Expected CIVector for inputCenter")
        }
    }

    @Test("custom center overrides default")
    func customCenter() {
        let preset = CIFilterPreset.twirl(center: SIMD2(100, 200), radius: 200, angle: .pi)
        let params = preset.parameters(textureSize: CGSize(width: 800, height: 600))
        if let center = params["inputCenter"] as? CIVector {
            #expect(center.x == 100)
            #expect(center.y == 200)
        } else {
            Issue.record("Expected CIVector for inputCenter")
        }
    }
}

// MARK: - CI PostEffect Classes Tests

@Suite("CI PostEffect Classes")
@MainActor
struct PostEffectCITests {

    @Test("CIFilter post effect")
    func ciFilterPostEffect() {
        let effect = CIFilterEffect(.comic)
        #expect(effect.name == "ciFilter")
        #expect(effect.preset.filterName == "CIComicEffect")
    }

    @Test("CIFilterRaw post effect")
    func ciFilterRawPostEffect() {
        let effect = CIFilterRawEffect(name: "CISepiaTone", parameters: ["inputIntensity": .double(0.8)])
        #expect(effect.filterName == "CISepiaTone")
        if case .double(let v) = effect.parameters["inputIntensity"] {
            #expect(v == 0.8)
        } else {
            Issue.record("Expected .double for inputIntensity")
        }
    }
}

// MARK: - CIFilterWrapper Tests (GPU-dependent)

@Suite("CIFilterWrapper", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct CIFilterWrapperTests {

    /// CPU から読み書きできるテスト用テクスチャを作成します。
    private static func makeTexture(device: MTLDevice, width: Int = 64, height: Int = 64) -> MTLTexture? {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false
        )
        desc.usage = [.shaderRead, .shaderWrite, .renderTarget]
        desc.storageMode = .shared
        return device.makeTexture(descriptor: desc)
    }

    private static func fill(_ texture: MTLTexture, byte: UInt8) {
        let count = texture.width * texture.height * 4
        let bytes = [UInt8](repeating: byte, count: count)
        texture.replace(
            region: MTLRegionMake2D(0, 0, texture.width, texture.height),
            mipmapLevel: 0, withBytes: bytes, bytesPerRow: texture.width * 4
        )
    }

    private static func readBytes(_ texture: MTLTexture) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: texture.width * texture.height * 4)
        bytes.withUnsafeMutableBytes { buf in
            texture.getBytes(
                buf.baseAddress!, bytesPerRow: texture.width * 4,
                from: MTLRegionMake2D(0, 0, texture.width, texture.height), mipmapLevel: 0
            )
        }
        return bytes
    }

    @Test("initialization")
    func initialization() {
        let device = MTLCreateSystemDefaultDevice()!
              let queue = device.makeCommandQueue()!
        let wrapper = CIFilterWrapper(device: device, commandQueue: queue)
        _ = wrapper
    }

    @Test("generator presets applied via image path do not crash",
          arguments: [
            CIFilterPreset.checkerboard(),
            .stripes(),
            .starShine(),
            .sunbeams()
          ])
    func generatorPresetsDoNotCrash(preset: CIFilterPreset) {
        let device = MTLCreateSystemDefaultDevice()!
        let queue = device.makeCommandQueue()!
        let source = Self.makeTexture(device: device)!
        let destination = Self.makeTexture(device: device)!
        let cmdBuf = queue.makeCommandBuffer()!
        let wrapper = CIFilterWrapper(device: device, commandQueue: queue)
        // 修正前はジェネレーターへ kCIInputImageKey を setValue して
        // NSException でプロセスごとクラッシュしていた経路。
        let params = preset.parameters(textureSize: CGSize(width: source.width, height: source.height))
        wrapper.apply(
            filterName: preset.filterName, parameters: params,
            source: source, destination: destination, commandBuffer: cmdBuf
        )
        cmdBuf.commit()
        cmdBuf.waitUntilCompleted()
        #expect(cmdBuf.error == nil)
    }

    @Test("unknown filter name falls back to passthrough copy")
    func unknownFilterPassesThrough() {
        let device = MTLCreateSystemDefaultDevice()!
        let queue = device.makeCommandQueue()!
        let source = Self.makeTexture(device: device)!
        let destination = Self.makeTexture(device: device)!
        let cmdBuf = queue.makeCommandBuffer()!
        Self.fill(source, byte: 0x7F)
        Self.fill(destination, byte: 0x00)

        let wrapper = CIFilterWrapper(device: device, commandQueue: queue)
        wrapper.apply(
            filterName: "CINotARealFilter", parameters: [:],
            source: source, destination: destination, commandBuffer: cmdBuf
        )
        cmdBuf.commit()
        cmdBuf.waitUntilCompleted()

        #expect(Self.readBytes(destination) == Self.readBytes(source))
    }

    @Test("unknown parameter key is ignored without crashing")
    func unknownParameterKeyIgnored() {
        let device = MTLCreateSystemDefaultDevice()!
        let queue = device.makeCommandQueue()!
        let source = Self.makeTexture(device: device)!
        let destination = Self.makeTexture(device: device)!
        let cmdBuf = queue.makeCommandBuffer()!
        let wrapper = CIFilterWrapper(device: device, commandQueue: queue)
        // 修正前は KVC の NSException でクラッシュしていた（キー名 typo 想定）。
        wrapper.apply(
            filterName: "CISepiaTone",
            parameters: ["inputIntenstiy": Float(0.8)],
            source: source, destination: destination, commandBuffer: cmdBuf
        )
        cmdBuf.commit()
        cmdBuf.waitUntilCompleted()
        #expect(cmdBuf.error == nil)
    }

    @Test("generate with unknown filter name does not crash")
    func generateUnknownFilter() {
        let device = MTLCreateSystemDefaultDevice()!
              let queue = device.makeCommandQueue()!
        let wrapper = CIFilterWrapper(device: device, commandQueue: queue)
        _ = wrapper.generate(filterName: "CINotARealFilter", parameters: [:], width: 32, height: 32)
    }
}
