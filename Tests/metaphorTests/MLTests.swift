import Testing
import CoreML
import Metal
import simd
@testable import metaphor

// MARK: - MLTypes Tests

@Suite("MLClassification")
struct MLClassificationTests {

    @Test("construction and properties")
    func basicConstruction() {
        let cls = MLClassification(label: "cat", confidence: 0.95)
        #expect(cls.label == "cat")
        #expect(cls.confidence == 0.95)
    }

    @Test("sendable conformance")
    func sendable() {
        let cls = MLClassification(label: "dog", confidence: 0.8)
        let _: any Sendable = cls
        #expect(cls.label == "dog")
    }
}

@Suite("MLDetection")
struct MLDetectionTests {

    @Test("construction and properties")
    func basicConstruction() {
        let det = MLDetection(label: "person", confidence: 0.9, x: 10, y: 20, w: 100, h: 200)
        #expect(det.label == "person")
        #expect(det.confidence == 0.9)
        #expect(det.x == 10)
        #expect(det.y == 20)
        #expect(det.w == 100)
        #expect(det.h == 200)
    }
}

@Suite("MLLandmark")
struct MLLandmarkTests {

    @Test("construction and properties")
    func basicConstruction() {
        let lm = MLLandmark(name: "leftEye", x: 50, y: 60, confidence: 0.85)
        #expect(lm.name == "leftEye")
        #expect(lm.x == 50)
        #expect(lm.y == 60)
        #expect(lm.confidence == 0.85)
    }
}

@Suite("MLPose")
struct MLPoseTests {

    @Test("construction and landmark lookup")
    func basicConstruction() {
        let landmarks = [
            MLLandmark(name: "nose", x: 100, y: 100, confidence: 0.9),
            MLLandmark(name: "leftEye", x: 90, y: 95, confidence: 0.85),
            MLLandmark(name: "rightEye", x: 110, y: 95, confidence: 0.87),
        ]
        let pose = MLPose(landmarks: landmarks, confidence: 0.88)
        #expect(pose.landmarks.count == 3)
        #expect(pose.confidence == 0.88)
    }

    @Test("landmark search by name")
    func landmarkSearch() {
        let landmarks = [
            MLLandmark(name: "nose", x: 100, y: 100, confidence: 0.9),
            MLLandmark(name: "leftEye", x: 90, y: 95, confidence: 0.85),
        ]
        let pose = MLPose(landmarks: landmarks, confidence: 0.88)

        let nose = pose.landmark("nose")
        #expect(nose != nil)
        #expect(nose?.x == 100)

        let missing = pose.landmark("rightKnee")
        #expect(missing == nil)
    }
}

@Suite("MLSegmentMask")
struct MLSegmentMaskTests {

    @Test("construction and properties")
    func basicConstruction() {
        let data: [Float] = [0.0, 0.5, 1.0, 0.8]
        let mask = MLSegmentMask(width: 2, height: 2, data: data)
        #expect(mask.width == 2)
        #expect(mask.height == 2)
        #expect(mask.data.count == 4)
        #expect(mask.data[2] == 1.0)
    }
}

@Suite("MLFace")
struct MLFaceTests {

    @Test("construction and properties")
    func basicConstruction() {
        let face = MLFace(x: 10, y: 20, w: 50, h: 60, landmarks: [])
        #expect(face.x == 10)
        #expect(face.w == 50)
        #expect(face.landmarks.isEmpty)
    }

    @Test("with landmarks")
    func withLandmarks() {
        let landmarks = [
            MLLandmark(name: "leftEye", x: 30, y: 40, confidence: 0.9)
        ]
        let face = MLFace(x: 10, y: 20, w: 50, h: 60, landmarks: landmarks)
        #expect(face.landmarks.count == 1)
        #expect(face.landmarks[0].name == "leftEye")
    }
}

@Suite("MLText")
struct MLTextTests {

    @Test("construction and properties")
    func basicConstruction() {
        let text = MLText(text: "Hello", confidence: 0.95, x: 10, y: 20, w: 100, h: 30)
        #expect(text.text == "Hello")
        #expect(text.confidence == 0.95)
        #expect(text.x == 10)
    }
}

@Suite("MLSaliency")
struct MLSaliencyTests {

    @Test("construction and properties")
    func basicConstruction() {
        let sal = MLSaliency(width: 4, height: 4, data: [Float](repeating: 0.5, count: 16))
        #expect(sal.width == 4)
        #expect(sal.height == 4)
        #expect(sal.data.count == 16)
    }
}

@Suite("MLBarcode")
struct MLBarcodeTests {

    @Test("construction and properties")
    func basicConstruction() {
        let bc = MLBarcode(payload: "https://example.com", symbology: "QR", x: 10, y: 20, w: 100, h: 100)
        #expect(bc.payload == "https://example.com")
        #expect(bc.symbology == "QR")
    }
}

@Suite("MLContour")
struct MLContourTests {

    @Test("construction and properties")
    func basicConstruction() {
        let points: [SIMD2<Float>] = [
            SIMD2(0, 0), SIMD2(100, 0), SIMD2(100, 100), SIMD2(0, 100)
        ]
        let contour = MLContour(points: points, childIndices: [1, 2])
        #expect(contour.points.count == 4)
        #expect(contour.childIndices == [1, 2])
    }
}

@Suite("MLComputeUnit")
struct MLComputeUnitTests {

    @Test("coreML unit mapping")
    func mapping() {
        #expect(MLComputeUnit.cpuOnly.coreMLUnit == .cpuOnly)
        #expect(MLComputeUnit.cpuAndGPU.coreMLUnit == .cpuAndGPU)
        #expect(MLComputeUnit.cpuAndNeuralEngine.coreMLUnit == .cpuAndNeuralEngine)
        #expect(MLComputeUnit.all.coreMLUnit == .all)
    }
}

// MARK: - MLError Tests

@Suite("MLError")
struct MLErrorTests {

    @Test("modelNotFound description")
    func modelNotFound() {
        let err = MLError.modelNotFound("/path/to/model.mlmodelc")
        #expect(err.errorDescription?.contains("not found") == true)
        #expect(err.errorDescription?.contains("/path/to/model.mlmodelc") == true)
    }

    @Test("modelLoadFailed description")
    func modelLoadFailed() {
        let underlying = NSError(domain: "test", code: 1)
        let err = MLError.modelLoadFailed("test_model", underlying: underlying)
        #expect(err.errorDescription?.contains("test_model") == true)
    }

    @Test("inferenceFailed description")
    func inferenceFailed() {
        let err = MLError.inferenceFailed("timeout")
        #expect(err.errorDescription?.contains("timeout") == true)
    }

    @Test("textureConversionFailed description")
    func textureConversionFailed() {
        let err = MLError.textureConversionFailed("invalid format")
        #expect(err.errorDescription?.contains("invalid format") == true)
    }

    @Test("all error cases have descriptions")
    func allCases() {
        let errors: [MLError] = [
            .modelNotFound("x"),
            .modelLoadFailed("x", underlying: NSError(domain: "", code: 0)),
            .inferenceFailed("x"),
            .visionRequestFailed("x", underlying: NSError(domain: "", code: 0)),
            .textureConversionFailed("x"),
            .invalidModelFormat("x"),
            .unsupportedFeatureType("x"),
        ]
        for err in errors {
            #expect(err.errorDescription != nil)
            #expect(err.errorDescription!.contains("[metaphor]"))
        }
    }
}

// MARK: - MLProcessor Tests

@Suite("MLProcessor", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct MLProcessorTests {

    @Test("initial state")
    func initialState() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let queue = device.makeCommandQueue()!
        let processor = MLProcessor(device: device, commandQueue: queue)

        #expect(processor.isLoaded == false)
        #expect(processor.isProcessing == false)
        #expect(processor.inferenceTime == 0)
        #expect(processor.outputTexture == nil)
        #expect(processor.outputMultiArray == nil)
        #expect(processor.outputClassifications.isEmpty)
        #expect(processor.outputDictionary == nil)
        #expect(processor.rawModel == nil)
        #expect(processor.inputDescriptions.isEmpty)
        #expect(processor.outputDescriptions.isEmpty)
    }

    @Test("load nonexistent model throws")
    func loadNonexistent() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let queue = device.makeCommandQueue()!
        let processor = MLProcessor(device: device, commandQueue: queue)

        #expect(throws: MLError.self) {
            try processor.load("/nonexistent/model.mlmodelc")
        }
    }

    @Test("predict without loading does nothing")
    func predictWithoutLoad() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let queue = device.makeCommandQueue()!
        let processor = MLProcessor(device: device, commandQueue: queue)

        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: 64, height: 64, mipmapped: false)
        desc.usage = [.shaderRead]
        desc.storageMode = .shared
        let texture = device.makeTexture(descriptor: desc)!

        processor.predict(texture: texture)
        #expect(processor.isProcessing == false)
    }

    @Test("update without inference has no effect")
    func updateNoOp() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let queue = device.makeCommandQueue()!
        let processor = MLProcessor(device: device, commandQueue: queue)

        processor.update()
        #expect(processor.isProcessing == false)
        #expect(processor.inferenceTime == 0)
    }

    @Test("computeUnit default is all")
    func computeUnitDefault() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let queue = device.makeCommandQueue()!
        let processor = MLProcessor(device: device, commandQueue: queue)
        #expect(processor.computeUnit.coreMLUnit == .all)
    }
}

// MARK: - MLVision Tests

@Suite("MLVision", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct MLVisionTests {

    @Test("initial state")
    func initialState() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let queue = device.makeCommandQueue()!
        let vision = MLVision(device: device, commandQueue: queue)

        #expect(vision.classifications.isEmpty)
        #expect(vision.detections.isEmpty)
        #expect(vision.poses.isEmpty)
        #expect(vision.segmentMask == nil)
        #expect(vision.segmentMaskTexture == nil)
        #expect(vision.faces.isEmpty)
        #expect(vision.texts.isEmpty)
        #expect(vision.saliency == nil)
        #expect(vision.saliencyTexture == nil)
        #expect(vision.barcodes.isEmpty)
        #expect(vision.contours.isEmpty)
        #expect(vision.isProcessing == false)
        #expect(vision.inferenceTime == 0)
    }

    @Test("default configuration")
    func defaultConfig() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let queue = device.makeCommandQueue()!
        let vision = MLVision(device: device, commandQueue: queue)

        #expect(vision.maxClassifications == 5)
        #expect(vision.confidenceThreshold == 0.5)
        #expect(vision.detectFaceLandmarks == true)
        #expect(vision.textRecognitionLanguages == ["en", "ja"])
    }

    @Test("update without inference has no effect")
    func updateNoOp() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let queue = device.makeCommandQueue()!
        let vision = MLVision(device: device, commandQueue: queue)

        vision.update()
        #expect(vision.isProcessing == false)
        #expect(vision.classifications.isEmpty)
    }

    @Test("loadModel nonexistent throws")
    func loadModelNonexistent() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let queue = device.makeCommandQueue()!
        let vision = MLVision(device: device, commandQueue: queue)

        #expect(throws: (any Error).self) {
            try vision.loadModel("/nonexistent/model.mlmodelc")
        }
    }

    @Test("detect without model does nothing")
    func detectWithoutModel() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let queue = device.makeCommandQueue()!
        let vision = MLVision(device: device, commandQueue: queue)

        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: 64, height: 64, mipmapped: false)
        desc.usage = [.shaderRead]
        desc.storageMode = .shared
        let texture = device.makeTexture(descriptor: desc)!

        // detect requires custom model, should silently return
        vision.detect(texture)
        #expect(vision.isProcessing == false)
    }
}

// MARK: - MLStyleTransfer Tests

@Suite("MLStyleTransfer", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct MLStyleTransferTests {

    @Test("initial state")
    func initialState() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let queue = device.makeCommandQueue()!
        let st = MLStyleTransfer(device: device, commandQueue: queue)

        #expect(st.isLoaded == false)
        #expect(st.isProcessing == false)
        #expect(st.inferenceTime == 0)
        #expect(st.outputTexture == nil)
    }

    @Test("update without inference has no effect")
    func updateNoOp() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let queue = device.makeCommandQueue()!
        let st = MLStyleTransfer(device: device, commandQueue: queue)

        st.update()
        #expect(st.isProcessing == false)
    }

    @Test("apply without loading does nothing")
    func applyWithoutLoad() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let queue = device.makeCommandQueue()!
        let st = MLStyleTransfer(device: device, commandQueue: queue)

        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: 64, height: 64, mipmapped: false)
        desc.usage = [.shaderRead]
        desc.storageMode = .shared
        let texture = device.makeTexture(descriptor: desc)!

        st.apply(texture)
        // Not loaded, so isProcessing should not change meaningfully
        #expect(st.outputTexture == nil)
    }
}

// MARK: - MLTextureConverter Tests

@Suite("MLTextureConverter", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct MLTextureConverterTests {

    @Test("pixelBuffer from shared texture")
    func pixelBufferFromShared() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let queue = device.makeCommandQueue()!
        let converter = MLTextureConverter(device: device, commandQueue: queue)

        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: 4, height: 4, mipmapped: false)
        desc.usage = [.shaderRead]
        desc.storageMode = .shared
        let texture = device.makeTexture(descriptor: desc)!

        // Fill with solid red (BGRA: 0, 0, 255, 255)
        var pixels = [UInt8](repeating: 0, count: 4 * 4 * 4)
        for i in stride(from: 0, to: pixels.count, by: 4) {
            pixels[i] = 0       // B
            pixels[i + 1] = 0   // G
            pixels[i + 2] = 255 // R
            pixels[i + 3] = 255 // A
        }
        texture.replace(
            region: MTLRegionMake2D(0, 0, 4, 4),
            mipmapLevel: 0,
            withBytes: pixels,
            bytesPerRow: 4 * 4
        )

        let pb = converter.pixelBuffer(from: texture)
        #expect(pb != nil)
        if let pb = pb {
            #expect(CVPixelBufferGetWidth(pb) == 4)
            #expect(CVPixelBufferGetHeight(pb) == 4)
        }
    }

    @Test("texture from CVPixelBuffer round-trip")
    func textureFromPixelBuffer() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let queue = device.makeCommandQueue()!
        let converter = MLTextureConverter(device: device, commandQueue: queue)

        // Create a CVPixelBuffer
        var pixelBuffer: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        CVPixelBufferCreate(nil, 8, 8, kCVPixelFormatType_32BGRA, attrs as CFDictionary, &pixelBuffer)
        #expect(pixelBuffer != nil)

        if let pb = pixelBuffer {
            let tex = converter.texture(from: pb)
            #expect(tex != nil)
            #expect(tex?.width == 8)
            #expect(tex?.height == 8)
        }
    }

    @Test("cgImage round-trip")
    func cgImageRoundTrip() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let queue = device.makeCommandQueue()!
        let converter = MLTextureConverter(device: device, commandQueue: queue)

        // Create a simple CGImage
        let width = 4
        let height = 4
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            Issue.record("Failed to create CGContext")
            return
        }
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let cgImage = context.makeImage() else {
            Issue.record("Failed to create CGImage")
            return
        }

        let tex = converter.texture(from: cgImage)
        #expect(tex != nil)
        #expect(tex?.width == 4)
        #expect(tex?.height == 4)

        if let tex = tex {
            let roundTrip = converter.cgImage(from: tex)
            #expect(roundTrip != nil)
            #expect(roundTrip?.width == 4)
            #expect(roundTrip?.height == 4)
        }
    }
}

// MARK: - SketchContext ML Factory Tests

@Suite("SketchContext ML", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct SketchContextMLTests {

    @Test("createMLProcessor returns valid instance")
    func createMLProcessor() throws {
        let renderer = try MetaphorRenderer()
        let canvas = try Canvas2D(renderer: renderer)
        let canvas3D = try Canvas3D(renderer: renderer)
        let ctx = SketchContext(renderer: renderer, canvas: canvas, canvas3D: canvas3D, input: renderer.input)

        let processor = ctx.createMLProcessor()
        #expect(processor.isLoaded == false)
    }

    @Test("createVision returns valid instance")
    func createVision() throws {
        let renderer = try MetaphorRenderer()
        let canvas = try Canvas2D(renderer: renderer)
        let canvas3D = try Canvas3D(renderer: renderer)
        let ctx = SketchContext(renderer: renderer, canvas: canvas, canvas3D: canvas3D, input: renderer.input)

        let vision = ctx.createVision()
        #expect(vision.classifications.isEmpty)
    }

    @Test("createStyleTransfer returns valid instance")
    func createStyleTransfer() throws {
        let renderer = try MetaphorRenderer()
        let canvas = try Canvas2D(renderer: renderer)
        let canvas3D = try Canvas3D(renderer: renderer)
        let ctx = SketchContext(renderer: renderer, canvas: canvas, canvas3D: canvas3D, input: renderer.input)

        let st = ctx.createStyleTransfer()
        #expect(st.isLoaded == false)
    }

    @Test("createMLTextureConverter returns valid instance")
    func createMLTextureConverter() throws {
        let renderer = try MetaphorRenderer()
        let canvas = try Canvas2D(renderer: renderer)
        let canvas3D = try Canvas3D(renderer: renderer)
        let ctx = SketchContext(renderer: renderer, canvas: canvas, canvas3D: canvas3D, input: renderer.input)

        let converter = ctx.createMLTextureConverter()
        // Converter should be functional
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: 2, height: 2, mipmapped: false)
        desc.storageMode = .shared
        let tex = renderer.device.makeTexture(descriptor: desc)!
        let pb = converter.pixelBuffer(from: tex)
        #expect(pb != nil)
    }

    @Test("loadMLModel with invalid path throws")
    func loadMLModelInvalid() throws {
        let renderer = try MetaphorRenderer()
        let canvas = try Canvas2D(renderer: renderer)
        let canvas3D = try Canvas3D(renderer: renderer)
        let ctx = SketchContext(renderer: renderer, canvas: canvas, canvas3D: canvas3D, input: renderer.input)

        #expect(throws: MLError.self) {
            try ctx.loadMLModel("/invalid/model.mlmodelc")
        }
    }
}

// MARK: - New Types Tests (Phase 2)

@Suite("MLLandmark3D")
struct MLLandmark3DTests {

    @Test("construction and properties")
    func basicConstruction() {
        let lm = MLLandmark3D(name: "root_joint", x: 0.1, y: 0.2, z: 0.3, confidence: 0.9)
        #expect(lm.name == "root_joint")
        #expect(lm.x == 0.1)
        #expect(lm.y == 0.2)
        #expect(lm.z == 0.3)
        #expect(lm.confidence == 0.9)
        #expect(lm.localPosition == nil)
    }

    @Test("position computed property")
    func position() {
        let lm = MLLandmark3D(name: "test", x: 1.0, y: 2.0, z: 3.0, confidence: 1.0)
        let pos = lm.position
        #expect(pos.x == 1.0)
        #expect(pos.y == 2.0)
        #expect(pos.z == 3.0)
    }

    @Test("with localPosition")
    func withLocalPosition() {
        let mat = matrix_identity_float4x4
        let lm = MLLandmark3D(name: "test", x: 0, y: 0, z: 0, confidence: 1.0, localPosition: mat)
        #expect(lm.localPosition != nil)
    }

    @Test("sendable conformance")
    func sendable() {
        let lm = MLLandmark3D(name: "test", x: 0, y: 0, z: 0, confidence: 1.0)
        let _: any Sendable = lm
        #expect(lm.name == "test")
    }
}

@Suite("MLPose3D")
struct MLPose3DTests {

    @Test("construction and properties")
    func basicConstruction() {
        let lm1 = MLLandmark3D(name: "root", x: 0, y: 0, z: 0, confidence: 1.0)
        let lm2 = MLLandmark3D(name: "head", x: 0, y: 1.7, z: 0, confidence: 0.9)
        let pose = MLPose3D(landmarks: [lm1, lm2], confidence: 0.95, bodyHeight: 1.75)
        #expect(pose.landmarks.count == 2)
        #expect(pose.confidence == 0.95)
        #expect(pose.bodyHeight == 1.75)
    }

    @Test("landmark search by name")
    func landmarkSearch() {
        let lm1 = MLLandmark3D(name: "root", x: 0, y: 0, z: 0, confidence: 1.0)
        let lm2 = MLLandmark3D(name: "head", x: 0, y: 1.7, z: 0, confidence: 0.9)
        let pose = MLPose3D(landmarks: [lm1, lm2], confidence: 0.95)
        #expect(pose.landmark("head")?.y == 1.7)
        #expect(pose.landmark("nonexistent") == nil)
    }

    @Test("default body height is zero")
    func defaultBodyHeight() {
        let pose = MLPose3D(landmarks: [], confidence: 1.0)
        #expect(pose.bodyHeight == 0)
    }
}

@Suite("MLRectangle")
struct MLRectangleTests {

    @Test("construction and properties")
    func basicConstruction() {
        let rect = MLRectangle(
            topLeft: SIMD2<Float>(0, 0),
            topRight: SIMD2<Float>(100, 0),
            bottomRight: SIMD2<Float>(100, 100),
            bottomLeft: SIMD2<Float>(0, 100),
            confidence: 0.8
        )
        #expect(rect.topLeft.x == 0)
        #expect(rect.topRight.x == 100)
        #expect(rect.bottomRight.y == 100)
        #expect(rect.confidence == 0.8)
    }

    @Test("center computed property")
    func center() {
        let rect = MLRectangle(
            topLeft: SIMD2<Float>(0, 0),
            topRight: SIMD2<Float>(100, 0),
            bottomRight: SIMD2<Float>(100, 100),
            bottomLeft: SIMD2<Float>(0, 100),
            confidence: 1.0
        )
        let c = rect.center
        #expect(c.x == 50)
        #expect(c.y == 50)
    }

    @Test("sendable conformance")
    func sendable() {
        let rect = MLRectangle(
            topLeft: .zero, topRight: .zero, bottomRight: .zero, bottomLeft: .zero, confidence: 0
        )
        let _: any Sendable = rect
        #expect(rect.confidence == 0)
    }
}

@Suite("MLFeaturePrint")
struct MLFeaturePrintTests {

    @Test("construction and properties")
    func basicConstruction() {
        let fp = MLFeaturePrint(data: [1.0, 2.0, 3.0], elementType: "float")
        #expect(fp.data.count == 3)
        #expect(fp.elementType == "float")
        #expect(fp.count == 3)
    }

    @Test("default element type is float")
    func defaultElementType() {
        let fp = MLFeaturePrint(data: [1.0])
        #expect(fp.elementType == "float")
    }

    @Test("distance to identical vector is zero")
    func distanceIdentical() {
        let fp1 = MLFeaturePrint(data: [1.0, 0.0, 0.0])
        let fp2 = MLFeaturePrint(data: [1.0, 0.0, 0.0])
        let dist = fp1.distance(to: fp2)
        #expect(abs(dist) < 0.001)
    }

    @Test("distance to orthogonal vector is one")
    func distanceOrthogonal() {
        let fp1 = MLFeaturePrint(data: [1.0, 0.0, 0.0])
        let fp2 = MLFeaturePrint(data: [0.0, 1.0, 0.0])
        let dist = fp1.distance(to: fp2)
        #expect(abs(dist - 1.0) < 0.001)
    }

    @Test("distance to opposite vector is two")
    func distanceOpposite() {
        let fp1 = MLFeaturePrint(data: [1.0, 0.0])
        let fp2 = MLFeaturePrint(data: [-1.0, 0.0])
        let dist = fp1.distance(to: fp2)
        #expect(abs(dist - 2.0) < 0.001)
    }

    @Test("distance with mismatched sizes returns infinity")
    func distanceMismatch() {
        let fp1 = MLFeaturePrint(data: [1.0, 2.0])
        let fp2 = MLFeaturePrint(data: [1.0])
        let dist = fp1.distance(to: fp2)
        #expect(dist == Float.infinity)
    }

    @Test("distance with empty vector returns infinity")
    func distanceEmpty() {
        let fp1 = MLFeaturePrint(data: [])
        let fp2 = MLFeaturePrint(data: [])
        let dist = fp1.distance(to: fp2)
        #expect(dist == Float.infinity)
    }
}

@Suite("MLInstanceMask")
struct MLInstanceMaskTests {

    @Test("construction and properties")
    func basicConstruction() {
        let mask = MLInstanceMask(
            width: 10, height: 10, instanceCount: 2,
            instanceMasks: [[Float](repeating: 1.0, count: 100), [Float](repeating: 0.5, count: 100)],
            combinedMask: [Float](repeating: 0.75, count: 100)
        )
        #expect(mask.width == 10)
        #expect(mask.height == 10)
        #expect(mask.instanceCount == 2)
        #expect(mask.instanceMasks.count == 2)
        #expect(mask.combinedMask.count == 100)
    }

    @Test("mask for instance valid index")
    func maskForInstanceValid() {
        let mask = MLInstanceMask(
            width: 2, height: 2, instanceCount: 1,
            instanceMasks: [[1.0, 0.5, 0.3, 0.0]],
            combinedMask: [1.0, 0.5, 0.3, 0.0]
        )
        let data = mask.mask(forInstance: 0)
        #expect(data != nil)
        #expect(data?.count == 4)
        #expect(data?[0] == 1.0)
    }

    @Test("mask for instance invalid index returns nil")
    func maskForInstanceInvalid() {
        let mask = MLInstanceMask(
            width: 2, height: 2, instanceCount: 1,
            instanceMasks: [[1.0, 0.5, 0.3, 0.0]],
            combinedMask: [1.0, 0.5, 0.3, 0.0]
        )
        #expect(mask.mask(forInstance: -1) == nil)
        #expect(mask.mask(forInstance: 1) == nil)
    }
}

@Suite("MLTrackedObject")
struct MLTrackedObjectTests {

    @Test("construction and properties")
    func basicConstruction() {
        let obj = MLTrackedObject(x: 10, y: 20, w: 100, h: 200, confidence: 0.9, isTracking: true)
        #expect(obj.x == 10)
        #expect(obj.y == 20)
        #expect(obj.w == 100)
        #expect(obj.h == 200)
        #expect(obj.confidence == 0.9)
        #expect(obj.isTracking == true)
    }

    @Test("tracking false state")
    func notTracking() {
        let obj = MLTrackedObject(x: 0, y: 0, w: 0, h: 0, confidence: 0.1, isTracking: false)
        #expect(obj.isTracking == false)
    }

    @Test("sendable conformance")
    func sendable() {
        let obj = MLTrackedObject(x: 0, y: 0, w: 0, h: 0, confidence: 0, isTracking: false)
        let _: any Sendable = obj
        #expect(obj.confidence == 0)
    }
}

@Suite("MLOpticalFlow")
struct MLOpticalFlowTests {

    @Test("construction and properties")
    func basicConstruction() {
        let flow = MLOpticalFlow(width: 2, height: 2, data: [1, 2, 3, 4, 5, 6, 7, 8])
        #expect(flow.width == 2)
        #expect(flow.height == 2)
        #expect(flow.data.count == 8)
    }

    @Test("flow at valid position")
    func flowAtValid() {
        // 2x2 flow: (1,2), (3,4), (5,6), (7,8)
        let flow = MLOpticalFlow(width: 2, height: 2, data: [1, 2, 3, 4, 5, 6, 7, 8])
        let v00 = flow.flow(at: 0, y: 0)
        #expect(v00 != nil)
        #expect(v00?.x == 1)
        #expect(v00?.y == 2)
        let v10 = flow.flow(at: 1, y: 0)
        #expect(v10?.x == 3)
        #expect(v10?.y == 4)
        let v01 = flow.flow(at: 0, y: 1)
        #expect(v01?.x == 5)
        #expect(v01?.y == 6)
    }

    @Test("flow at invalid position returns nil")
    func flowAtInvalid() {
        let flow = MLOpticalFlow(width: 2, height: 2, data: [1, 2, 3, 4, 5, 6, 7, 8])
        #expect(flow.flow(at: -1, y: 0) == nil)
        #expect(flow.flow(at: 2, y: 0) == nil)
        #expect(flow.flow(at: 0, y: 2) == nil)
    }

    @Test("average magnitude")
    func averageMagnitude() {
        // 2 pixels: (3,4)=5, (0,0)=0 → average = 2.5
        let flow = MLOpticalFlow(width: 2, height: 1, data: [3, 4, 0, 0])
        let avg = flow.averageMagnitude
        #expect(abs(avg - 2.5) < 0.001)
    }

    @Test("average magnitude empty flow")
    func averageMagnitudeEmpty() {
        let flow = MLOpticalFlow(width: 0, height: 0, data: [])
        #expect(flow.averageMagnitude == 0)
    }
}

// MARK: - MLVision New Properties Tests

@Suite("MLVision New Properties")
struct MLVisionNewPropertiesTests {

    @Test("initial state of new properties") @MainActor
    func initialState() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        let queue = device.makeCommandQueue()!
        let vision = MLVision(device: device, commandQueue: queue)

        #expect(vision.poses3D.isEmpty)
        #expect(vision.animalDetections.isEmpty)
        #expect(vision.animalPoses.isEmpty)
        #expect(vision.humanRectangles.isEmpty)
        #expect(vision.rectangles.isEmpty)
        #expect(vision.featurePrint == nil)
        #expect(vision.foregroundInstanceMask == nil)
        #expect(vision.foregroundMaskTexture == nil)
        #expect(vision.personInstanceMask == nil)
        #expect(vision.personMaskTexture == nil)
        #expect(vision.trackedObject == nil)
        #expect(vision.isTracking == false)
        #expect(vision.opticalFlow == nil)
        #expect(vision.opticalFlowTexture == nil)
    }

    @Test("new configuration defaults") @MainActor
    func configDefaults() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        let queue = device.makeCommandQueue()!
        let vision = MLVision(device: device, commandQueue: queue)

        #expect(vision.rectangleMinAspectRatio == 0.0)
        #expect(vision.rectangleMaxAspectRatio == 1.0)
        #expect(vision.rectangleMinSize == 0.1)
        #expect(vision.maxRectangles == 10)
        #expect(vision.trackingConfidenceThreshold == 0.3)
    }
}

// MARK: - Object Tracking State Tests

@Suite("MLVision Tracking State")
struct MLVisionTrackingTests {

    @Test("startTracking and stopTracking") @MainActor
    func trackingLifecycle() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        let queue = device.makeCommandQueue()!
        let vision = MLVision(device: device, commandQueue: queue)

        #expect(vision.isTracking == false)

        vision.startTracking(x: 10, y: 20, w: 100, h: 200, imageWidth: 640, imageHeight: 480)
        #expect(vision.isTracking == true)

        vision.stopTracking()
        #expect(vision.isTracking == false)
        #expect(vision.trackedObject == nil)
    }
}

// MARK: - Optical Flow State Tests

@Suite("MLVision Optical Flow State")
struct MLVisionOpticalFlowTests {

    @Test("resetOpticalFlow clears state") @MainActor
    func resetState() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        let queue = device.makeCommandQueue()!
        let vision = MLVision(device: device, commandQueue: queue)

        #expect(vision.opticalFlow == nil)
        #expect(vision.opticalFlowTexture == nil)

        vision.resetOpticalFlow()
        #expect(vision.opticalFlow == nil)
        #expect(vision.opticalFlowTexture == nil)
    }
}
