import Metal
import simd

/// Provide an immediate-mode 2D drawing context powered by Metal.
///
/// Offers a p5.js-style API for 2D rendering with Metal.
/// Accumulates shapes into pre-allocated vertex buffers and draws them in a single batch on ``end()``.
///
/// ```swift
/// let canvas = Canvas2D(renderer: renderer)
///
/// renderer.onDraw = { encoder, time in
///     canvas.begin(encoder: encoder)
///     canvas.background(.black)
///     canvas.fill(Color(hue: 0.6, saturation: 0.8, brightness: 1.0))
///     canvas.ellipse(960, 540, 300, 300)
///     canvas.end()
/// }
/// ```
@MainActor
public final class Canvas2D {
    // MARK: - Metal Resources

    let device: MTLDevice
    let shaderLibrary: ShaderLibrary
    let pipelineStates: [BlendMode: MTLRenderPipelineState]
    let texturedPipelineStates: [BlendMode: MTLRenderPipelineState]
    let depthStencilState: MTLDepthStencilState?

    // MARK: - 2D Instancing Resources

    let instancedPipelineStates: [BlendMode: MTLRenderPipelineState]
    let instanceBatcher2D: InstanceBatcher2D
    let unitCircleBuffer: MTLBuffer
    let unitCircleVertexCount: Int
    let unitRectBuffer: MTLBuffer
    let unitRectVertexCount: Int

    // Triple buffers to avoid CPU/GPU synchronization conflicts
    private static let bufferCount = 3
    private let vertexBuffers: [MTLBuffer]
    private let verticesArray: [UnsafeMutablePointer<Vertex2D>]
    private var currentBufferIndex: Int = 0

    // Textured triple buffers
    private let texturedVertexBuffers: [MTLBuffer]
    private let texturedVerticesArray: [UnsafeMutablePointer<TexturedVertex2D>]
    var texturedVertexCount: Int = 0
    var texturedBufferOffset: Int = 0
    var currentBoundTexture: MTLTexture?
    let maxTexturedVertices: Int = 65536

    // Vertex pointer for the current buffer
    var vertices: UnsafeMutablePointer<Vertex2D> {
        verticesArray[currentBufferIndex]
    }

    // Current vertex buffer
    var vertexBuffer: MTLBuffer {
        vertexBuffers[currentBufferIndex]
    }

    // Vertex pointer for the current textured buffer
    var texturedVertices: UnsafeMutablePointer<TexturedVertex2D> {
        texturedVerticesArray[currentBufferIndex]
    }

    // Current textured vertex buffer
    private var texturedVertexBuffer: MTLBuffer {
        texturedVertexBuffers[currentBufferIndex]
    }

    // MARK: - Dimensions

    /// The width of the canvas in pixels.
    public let width: Float

    /// The height of the canvas in pixels.
    public let height: Float

    // MARK: - Constants

    let maxVertices: Int = 786432
    let ellipseSegments: Int = 32

    // MARK: - Per-frame State

    var encoder: MTLRenderCommandEncoder?

    /// Access the current render command encoder, valid only during a frame.
    public var currentEncoder: MTLRenderCommandEncoder? { encoder }
    var vertexCount: Int = 0
    var bufferOffset: Int = 0
    let projectionMatrix: float4x4

    // MARK: - Style State

    var fillColor: SIMD4<Float> = SIMD4<Float>(1, 1, 1, 1)
    var strokeColor: SIMD4<Float> = SIMD4<Float>(1, 1, 1, 1)
    var currentStrokeWeight: Float = 1.0
    var hasFill: Bool = true
    var hasStroke: Bool = true
    var currentBlendMode: BlendMode = .alpha
    var currentRectMode: RectMode = .corner
    var currentEllipseMode: EllipseMode = .center
    var currentImageMode: ImageMode = .corner
    var colorModeConfig: ColorModeConfig = ColorModeConfig()
    var tintColor: SIMD4<Float> = SIMD4<Float>(1, 1, 1, 1)
    var hasTint: Bool = false
    var currentStrokeCap: StrokeCap = .round
    var currentStrokeJoin: StrokeJoin = .miter

    // MARK: - Text State

    var currentTextSize: Float = 32
    var currentFontFamily: String = "Helvetica"
    var currentTextAlignH: TextAlignH = .left
    var currentTextAlignV: TextAlignV = .baseline
    var currentTextLeading: Float = 1.2
    let textRenderer: TextRenderer
    var frameCounter: Int = 0

    // MARK: - Curve State

    var curveDetailCount: Int = 20
    var curveTightnessValue: Float = 0.0

    // MARK: - Shape Building State

    enum ShapeVertexType {
        case normal(Float, Float)
        case colored(Float, Float, SIMD4<Float>)
        case textured(Float, Float, Float, Float)
        case bezier(cx1: Float, cy1: Float, cx2: Float, cy2: Float, x: Float, y: Float)
        case curve(Float, Float)
    }

    var isRecordingShape: Bool = false
    var shapeMode: ShapeMode = .polygon
    var shapeVertexList: [ShapeVertexType] = {
        var arr: [ShapeVertexType] = []
        arr.reserveCapacity(64)
        return arr
    }()

    // MARK: - Contour State (for polygons with holes)

    var contourVertices: [[(Float, Float)]] = []
    var isRecordingContour: Bool = false
    var currentContour: [(Float, Float)] = []

    // MARK: - Background Optimization

    // Tracks whether anything has been drawn (for background() optimization)
    var hasDrawnAnything: Bool = false

    /// Whether background() was called during the current frame's draw().
    /// Used to determine loadAction for the next frame.
    var backgroundCalledThisFrame: Bool = false

    /// Whether the current frame will clear via Metal's loadAction.
    /// When true, background() can skip drawing a quad if nothing else has been drawn.
    var frameWillClear: Bool = true

    // Closure to set the clear color, injected by MetaphorRenderer
    var onSetClearColor: ((Double, Double, Double, Double) -> Void)?

    // MARK: - Style Snapshot (for push/pop)

    struct StyleState {
        var transform: float3x3
        var fillColor: SIMD4<Float>
        var strokeColor: SIMD4<Float>
        var strokeWeight: Float
        var hasFill: Bool
        var hasStroke: Bool
        var blendMode: BlendMode
        var rectMode: RectMode
        var ellipseMode: EllipseMode
        var imageMode: ImageMode
        var colorModeConfig: ColorModeConfig
        var tintColor: SIMD4<Float>
        var hasTint: Bool
        var textSize: Float
        var fontFamily: String
        var textAlignH: TextAlignH
        var textAlignV: TextAlignV
        var textLeading: Float
        var curveDetail: Int
        var curveTightness: Float
        var strokeCap: StrokeCap
        var strokeJoin: StrokeJoin
    }

    // MARK: - Transform & Style Stack

    var stateStack: [StyleState] = []
    var styleOnlyStack: [StyleState] = []
    var matrixStack: [float3x3] = []
    var currentTransform: float3x3 = float3x3(1)

    // MARK: - Vertex Layout (packed, 24 bytes)

    struct Vertex2D {
        var posX: Float
        var posY: Float
        var r: Float
        var g: Float
        var b: Float
        var a: Float
    }

    // MARK: - Textured Vertex Layout (packed, 32 bytes)

    struct TexturedVertex2D {
        var posX: Float
        var posY: Float
        var u: Float
        var v: Float
        var r: Float
        var g: Float
        var b: Float
        var a: Float
    }

    // MARK: - Initialization

    /// Create a canvas from a ``MetaphorRenderer`` instance.
    ///
    /// - Parameter renderer: The renderer that provides the Metal device, shader library, and texture dimensions.
    /// - Throws: ``Canvas2DError`` if buffer or pipeline creation fails.
    public convenience init(renderer: MetaphorRenderer) throws {
        try self.init(
            device: renderer.device,
            shaderLibrary: renderer.shaderLibrary,
            depthStencilCache: renderer.depthStencilCache,
            width: Float(renderer.textureManager.width),
            height: Float(renderer.textureManager.height),
            sampleCount: renderer.textureManager.sampleCount
        )
    }

    /// Create a canvas from individual components.
    ///
    /// - Parameters:
    ///   - device: The Metal device used to allocate buffers and pipelines.
    ///   - shaderLibrary: The shader library containing built-in 2D shaders.
    ///   - depthStencilCache: A cache providing depth-stencil states.
    ///   - width: The canvas width in pixels.
    ///   - height: The canvas height in pixels.
    ///   - sampleCount: The MSAA sample count for pipeline creation.
    /// - Throws: ``Canvas2DError`` if buffer or pipeline creation fails.
    public init(
        device: MTLDevice,
        shaderLibrary: ShaderLibrary,
        depthStencilCache: DepthStencilCache,
        width: Float,
        height: Float,
        sampleCount: Int = 1
    ) throws {
        self.device = device
        self.shaderLibrary = shaderLibrary
        self.width = width
        self.height = height

        // Triple vertex buffers (pre-allocated)
        let bufferSize = maxVertices * MemoryLayout<Vertex2D>.stride
        var buffers: [MTLBuffer] = []
        var pointers: [UnsafeMutablePointer<Vertex2D>] = []
        for _ in 0..<Self.bufferCount {
            guard let buffer = device.makeBuffer(length: bufferSize, options: .storageModeShared) else {
                throw Canvas2DError.bufferCreationFailed
            }
            buffers.append(buffer)
            pointers.append(buffer.contents().bindMemory(to: Vertex2D.self, capacity: maxVertices))
        }
        self.vertexBuffers = buffers
        self.verticesArray = pointers

        // Textured triple vertex buffers
        let texBufSize = 65536 * MemoryLayout<TexturedVertex2D>.stride
        var texBuffers: [MTLBuffer] = []
        var texPointers: [UnsafeMutablePointer<TexturedVertex2D>] = []
        for _ in 0..<Self.bufferCount {
            guard let buffer = device.makeBuffer(length: texBufSize, options: .storageModeShared) else {
                throw Canvas2DError.bufferCreationFailed
            }
            texBuffers.append(buffer)
            texPointers.append(buffer.contents().bindMemory(to: TexturedVertex2D.self, capacity: 65536))
        }
        self.texturedVertexBuffers = texBuffers
        self.texturedVerticesArray = texPointers

        // Color pipelines (one per BlendMode)
        let vertexFn = shaderLibrary.function(
            named: BuiltinShaders.FunctionName.canvas2DVertex,
            from: ShaderLibrary.BuiltinKey.canvas2D
        )
        let fragmentFn = shaderLibrary.function(
            named: BuiltinShaders.FunctionName.canvas2DFragment,
            from: ShaderLibrary.BuiltinKey.canvas2D
        )
        let diffFragFn = shaderLibrary.function(
            named: BuiltinShaders.FunctionName.canvas2DDifferenceFragment,
            from: ShaderLibrary.BuiltinKey.canvas2D
        )
        let exclFragFn = shaderLibrary.function(
            named: BuiltinShaders.FunctionName.canvas2DExclusionFragment,
            from: ShaderLibrary.BuiltinKey.canvas2D
        )

        var colorPipelines: [BlendMode: MTLRenderPipelineState] = [:]
        for mode in BlendMode.allCases {
            let fragFn: MTLFunction?
            switch mode {
            case .difference: fragFn = diffFragFn
            case .exclusion: fragFn = exclFragFn
            default: fragFn = fragmentFn
            }
            colorPipelines[mode] = try PipelineFactory(device: device)
                .vertex(vertexFn)
                .fragment(fragFn)
                .vertexLayout(.position2DColor)
                .blending(mode)
                .sampleCount(sampleCount)
                .build()
        }
        self.pipelineStates = colorPipelines

        // Textured pipelines (one per BlendMode)
        let texVertexFn = shaderLibrary.function(
            named: BuiltinShaders.FunctionName.canvas2DTexturedVertex,
            from: ShaderLibrary.BuiltinKey.canvas2DTextured
        )
        let texFragmentFn = shaderLibrary.function(
            named: BuiltinShaders.FunctionName.canvas2DTexturedFragment,
            from: ShaderLibrary.BuiltinKey.canvas2DTextured
        )
        let texDiffFragFn = shaderLibrary.function(
            named: BuiltinShaders.FunctionName.canvas2DTexturedDifferenceFragment,
            from: ShaderLibrary.BuiltinKey.canvas2DTextured
        )
        let texExclFragFn = shaderLibrary.function(
            named: BuiltinShaders.FunctionName.canvas2DTexturedExclusionFragment,
            from: ShaderLibrary.BuiltinKey.canvas2DTextured
        )

        var texPipelines: [BlendMode: MTLRenderPipelineState] = [:]
        for mode in BlendMode.allCases {
            let fragFn: MTLFunction?
            switch mode {
            case .difference: fragFn = texDiffFragFn
            case .exclusion: fragFn = texExclFragFn
            default: fragFn = texFragmentFn
            }
            texPipelines[mode] = try PipelineFactory(device: device)
                .vertex(texVertexFn)
                .fragment(fragFn)
                .vertexLayout(.position2DTexCoordColor)
                .blending(mode)
                .sampleCount(sampleCount)
                .build()
        }
        self.texturedPipelineStates = texPipelines

        // Depth test disabled
        self.depthStencilState = depthStencilCache.state(for: .disabled)

        // Text renderer
        self.textRenderer = TextRenderer(device: device)

        // Projection matrix (top-left origin, pixel coordinates)
        self.projectionMatrix = float4x4(columns: (
            SIMD4<Float>(2.0 / width, 0, 0, 0),
            SIMD4<Float>(0, -2.0 / height, 0, 0),
            SIMD4<Float>(0, 0, 1, 0),
            SIMD4<Float>(-1, 1, 0, 1)
        ))

        precondition(MemoryLayout<Vertex2D>.stride == 24,
                     "Vertex2D stride must be 24 to match position2DColor layout")
        precondition(MemoryLayout<TexturedVertex2D>.stride == 32,
                     "TexturedVertex2D stride must be 32 to match position2DTexCoordColor layout")

        // 2D instancing resources
        guard let (circleBuf, circleCount) = UnitMesh2D.createCircle(device: device) else {
            throw MetaphorError.bufferCreationFailed(size: 32 * 3 * MemoryLayout<SIMD2<Float>>.stride)
        }
        self.unitCircleBuffer = circleBuf
        self.unitCircleVertexCount = circleCount
        guard let (rectBuf, rectCount) = UnitMesh2D.createRect(device: device) else {
            throw MetaphorError.bufferCreationFailed(size: 6 * MemoryLayout<SIMD2<Float>>.stride)
        }
        self.unitRectBuffer = rectBuf
        self.unitRectVertexCount = rectCount
        self.instanceBatcher2D = try InstanceBatcher2D(device: device)

        // Instanced pipelines (one per BlendMode)
        let instVertexFn = shaderLibrary.function(
            named: Canvas2DInstancedShaders.vertexFunctionName,
            from: ShaderLibrary.BuiltinKey.canvas2DInstanced
        )
        var instPipelines: [BlendMode: MTLRenderPipelineState] = [:]
        for mode in BlendMode.allCases {
            let fragName: String
            switch mode {
            case .difference: fragName = Canvas2DInstancedShaders.differenceFragmentFunctionName
            case .exclusion: fragName = Canvas2DInstancedShaders.exclusionFragmentFunctionName
            default: fragName = Canvas2DInstancedShaders.fragmentFunctionName
            }
            let fragFn = shaderLibrary.function(
                named: fragName,
                from: ShaderLibrary.BuiltinKey.canvas2DInstanced
            )
            instPipelines[mode] = try PipelineFactory(device: device)
                .vertex(instVertexFn)
                .fragment(fragFn)
                .vertexLayout(.position2DOnly)
                .blending(mode)
                .sampleCount(sampleCount)
                .build()
        }
        self.instancedPipelineStates = instPipelines
    }

    // MARK: - Frame Control

    /// Begin a new drawing frame with the given render command encoder.
    ///
    /// Resets all per-frame state including vertex counts, style, and transform.
    /// Call this at the start of each frame before issuing draw commands.
    ///
    /// - Parameters:
    ///   - encoder: The render command encoder for the current frame.
    ///   - bufferIndex: The triple-buffer index for this frame.
    public func begin(encoder: MTLRenderCommandEncoder, bufferIndex: Int = 0) {
        self.encoder = encoder
        self.currentBufferIndex = bufferIndex % Self.bufferCount
        // Reset per-frame rendering state
        self.vertexCount = 0
        self.bufferOffset = 0
        self.texturedVertexCount = 0
        self.texturedBufferOffset = 0
        self.currentBoundTexture = nil
        self.currentTransform = float3x3(1)
        self.stateStack.removeAll(keepingCapacity: true)
        // Style state (fill, stroke, colorMode, etc.) is preserved across frames
        // to match Processing behavior where setup() styles carry into draw().
        self.frameCounter += 1
        self.hasDrawnAnything = false
        self.backgroundCalledThisFrame = false
        self.instanceBatcher2D.beginFrame(bufferIndex: currentBufferIndex)
    }

    /// End the current frame by flushing all accumulated vertices and releasing the encoder.
    public func end() {
        flush()
        encoder = nil
    }

    /// Flush all pending draw batches including color, textured, and instanced vertices.
    public func flush() {
        flushInstancedBatch()
        flushColorVertices()
        flushTexturedVertices()
    }

    // Flush only the color vertex batch
    func flushColorVertices() {
        guard let encoder = encoder, vertexCount > 0 else { return }

        guard let pipeline = pipelineStates[currentBlendMode] else { return }
        encoder.setRenderPipelineState(pipeline)
        if let depthState = depthStencilState {
            encoder.setDepthStencilState(depthState)
        }
        encoder.setCullMode(.none)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)

        var proj = projectionMatrix
        encoder.setVertexBytes(&proj, length: MemoryLayout<float4x4>.size, index: 1)

        encoder.drawPrimitives(type: .triangle, vertexStart: bufferOffset, vertexCount: vertexCount)
        bufferOffset += vertexCount
        vertexCount = 0
    }

    // Flush only the textured vertex batch
    func flushTexturedVertices() {
        guard let encoder = encoder, texturedVertexCount > 0 else { return }
        guard let texPipeline = texturedPipelineStates[currentBlendMode] else { return }
        guard let texture = currentBoundTexture else { return }

        encoder.setRenderPipelineState(texPipeline)
        if let depthState = depthStencilState {
            encoder.setDepthStencilState(depthState)
        }
        encoder.setCullMode(.none)
        encoder.setVertexBuffer(texturedVertexBuffer, offset: 0, index: 0)

        var proj = projectionMatrix
        encoder.setVertexBytes(&proj, length: MemoryLayout<float4x4>.size, index: 1)
        encoder.setFragmentTexture(texture, index: 0)

        encoder.drawPrimitives(type: .triangle, vertexStart: texturedBufferOffset, vertexCount: texturedVertexCount)
        texturedBufferOffset += texturedVertexCount
        texturedVertexCount = 0
    }

    // MARK: - Blend Mode

    /// Set the blend mode, flushing the current batch before switching.
    ///
    /// - Parameter mode: The blend mode to apply to subsequent draw calls.
    public func blendMode(_ mode: BlendMode) {
        if mode != currentBlendMode {
            flushInstancedBatch()
            flushColorVertices()
            flushTexturedVertices()
            currentBlendMode = mode
        }
    }

    // MARK: - Shape Mode Settings

    /// Set the coordinate interpretation mode for rectangles.
    ///
    /// - Parameter mode: The rectangle mode (e.g., `.corner`, `.center`).
    public func rectMode(_ mode: RectMode) {
        currentRectMode = mode
    }

    /// Set the coordinate interpretation mode for ellipses.
    ///
    /// - Parameter mode: The ellipse mode (e.g., `.center`, `.corner`).
    public func ellipseMode(_ mode: EllipseMode) {
        currentEllipseMode = mode
    }

    /// Set the coordinate interpretation mode for images.
    ///
    /// - Parameter mode: The image mode (e.g., `.corner`, `.center`).
    public func imageMode(_ mode: ImageMode) {
        currentImageMode = mode
    }

    // MARK: - Color Mode

    /// Set the color space and per-channel maximum values.
    ///
    /// - Parameters:
    ///   - space: The color space to use (e.g., `.rgb`, `.hsb`).
    ///   - max1: The maximum value for the first channel.
    ///   - max2: The maximum value for the second channel.
    ///   - max3: The maximum value for the third channel.
    ///   - maxA: The maximum value for the alpha channel.
    public func colorMode(_ space: ColorSpace, _ max1: Float = 1.0, _ max2: Float = 1.0, _ max3: Float = 1.0, _ maxA: Float = 1.0) {
        colorModeConfig = ColorModeConfig(space: space, max1: max1, max2: max2, max3: max3, maxAlpha: maxA)
    }

    /// Set the color space with a uniform maximum value for all channels.
    ///
    /// - Parameters:
    ///   - space: The color space to use.
    ///   - maxAll: The maximum value applied to all channels including alpha.
    public func colorMode(_ space: ColorSpace, _ maxAll: Float) {
        colorModeConfig = ColorModeConfig(space: space, max1: maxAll, max2: maxAll, max3: maxAll, maxAlpha: maxAll)
    }

    // MARK: - Tint

    /// Set the tint color for images.
    ///
    /// - Parameter color: The tint color to apply.
    public func tint(_ color: Color) {
        tintColor = color.simd
        hasTint = true
    }

    /// Set the tint color for images using color mode values.
    ///
    /// - Parameters:
    ///   - v1: The first color channel value, interpreted according to the current color mode.
    ///   - v2: The second color channel value.
    ///   - v3: The third color channel value.
    ///   - a: The optional alpha value.
    public func tint(_ v1: Float, _ v2: Float, _ v3: Float, _ a: Float? = nil) {
        tintColor = colorModeConfig.toColor(v1, v2, v3, a).simd
        hasTint = true
    }

    /// Set the tint color using a grayscale value.
    ///
    /// - Parameter gray: The grayscale brightness value.
    public func tint(_ gray: Float) {
        tintColor = colorModeConfig.toGray(gray).simd
        hasTint = true
    }

    /// Set the tint color using grayscale and alpha values.
    ///
    /// - Parameters:
    ///   - gray: The grayscale brightness value.
    ///   - alpha: The alpha transparency value.
    public func tint(_ gray: Float, _ alpha: Float) {
        tintColor = colorModeConfig.toGray(gray, alpha).simd
        hasTint = true
    }

    /// Disable image tinting.
    public func noTint() {
        tintColor = SIMD4<Float>(1, 1, 1, 1)
        hasTint = false
    }

    // MARK: - Style Sync

    /// Synchronize shared style properties from a ``DrawingStyle`` instance.
    ///
    /// - Parameter style: The drawing style to synchronize from.
    public func syncStyle(_ style: DrawingStyle) {
        fillColor = style.fillColor
        strokeColor = style.strokeColor
        hasFill = style.hasFill
        hasStroke = style.hasStroke
        colorModeConfig = style.colorModeConfig
    }

    // MARK: - Style

    /// Set the fill color for subsequent shapes.
    ///
    /// - Parameter color: The fill color.
    public func fill(_ color: Color) {
        fillColor = color.simd
        hasFill = true
    }

    /// Set the fill color using color mode values.
    ///
    /// - Parameters:
    ///   - v1: The first color channel value, interpreted according to the current color mode.
    ///   - v2: The second color channel value.
    ///   - v3: The third color channel value.
    ///   - a: The optional alpha value.
    public func fill(_ v1: Float, _ v2: Float, _ v3: Float, _ a: Float? = nil) {
        fillColor = colorModeConfig.toColor(v1, v2, v3, a).simd
        hasFill = true
    }

    /// Set the fill color using a grayscale value.
    ///
    /// - Parameter gray: The grayscale brightness value.
    public func fill(_ gray: Float) {
        fillColor = colorModeConfig.toGray(gray).simd
        hasFill = true
    }

    /// Set the fill color using grayscale and alpha values.
    ///
    /// - Parameters:
    ///   - gray: The grayscale brightness value.
    ///   - alpha: The alpha transparency value.
    public func fill(_ gray: Float, _ alpha: Float) {
        fillColor = colorModeConfig.toGray(gray, alpha).simd
        hasFill = true
    }

    /// Disable filling for subsequent shapes.
    public func noFill() {
        hasFill = false
    }

    /// Set the stroke color for subsequent shapes.
    ///
    /// - Parameter color: The stroke color.
    public func stroke(_ color: Color) {
        strokeColor = color.simd
        hasStroke = true
    }

    /// Set the stroke color using color mode values.
    ///
    /// - Parameters:
    ///   - v1: The first color channel value, interpreted according to the current color mode.
    ///   - v2: The second color channel value.
    ///   - v3: The third color channel value.
    ///   - a: The optional alpha value.
    public func stroke(_ v1: Float, _ v2: Float, _ v3: Float, _ a: Float? = nil) {
        strokeColor = colorModeConfig.toColor(v1, v2, v3, a).simd
        hasStroke = true
    }

    /// Set the stroke color using a grayscale value.
    ///
    /// - Parameter gray: The grayscale brightness value.
    public func stroke(_ gray: Float) {
        strokeColor = colorModeConfig.toGray(gray).simd
        hasStroke = true
    }

    /// Set the stroke color using grayscale and alpha values.
    ///
    /// - Parameters:
    ///   - gray: The grayscale brightness value.
    ///   - alpha: The alpha transparency value.
    public func stroke(_ gray: Float, _ alpha: Float) {
        strokeColor = colorModeConfig.toGray(gray, alpha).simd
        hasStroke = true
    }

    /// Disable stroke for subsequent shapes.
    public func noStroke() {
        hasStroke = false
    }

    /// Set the stroke weight (line thickness) in pixels.
    ///
    /// - Parameter weight: The stroke thickness.
    public func strokeWeight(_ weight: Float) {
        currentStrokeWeight = weight
    }

    /// Set the stroke cap style for line endpoints.
    ///
    /// - Parameter cap: The cap style (e.g., `.round`, `.square`, `.project`).
    public func strokeCap(_ cap: StrokeCap) {
        currentStrokeCap = cap
    }

    /// Set the stroke join style for line corners.
    ///
    /// - Parameter join: The join style (e.g., `.miter`, `.bevel`, `.round`).
    public func strokeJoin(_ join: StrokeJoin) {
        currentStrokeJoin = join
    }

    // MARK: - Background

    /// Fill the entire canvas with a solid color, ignoring the current transform.
    ///
    /// When nothing has been drawn yet this frame, only updates the clear color
    /// for optimal performance.
    ///
    /// - Parameter color: The background color.
    public func background(_ color: Color) {
        let c = color.simd
        backgroundCalledThisFrame = true
        onSetClearColor?(Double(c.x), Double(c.y), Double(c.z), Double(c.w))
        if !hasDrawnAnything && frameWillClear {
            // Metal's loadAction = .clear will handle clearing
            return
        }
        // Draw a full-screen quad (either because something was already drawn,
        // or because loadAction = .load and we need to explicitly clear)
        addVertexRaw(0, 0, c)
        addVertexRaw(width, 0, c)
        addVertexRaw(width, height, c)
        addVertexRaw(0, 0, c)
        addVertexRaw(width, height, c)
        addVertexRaw(0, height, c)
        flush()
    }

    /// Fill the background with a grayscale value.
    ///
    /// - Parameter gray: The grayscale brightness value.
    public func background(_ gray: Float) {
        background(colorModeConfig.toGray(gray))
    }

    /// Fill the background using color mode values.
    ///
    /// - Parameters:
    ///   - v1: The first color channel value, interpreted according to the current color mode.
    ///   - v2: The second color channel value.
    ///   - v3: The third color channel value.
    ///   - a: The optional alpha value.
    public func background(_ v1: Float, _ v2: Float, _ v3: Float, _ a: Float? = nil) {
        background(colorModeConfig.toColor(v1, v2, v3, a))
    }

    // MARK: - 2D Instanced Shape Drawing

    // Submit the current instanced batch to the GPU
    func flushInstancedBatch() {
        guard let encoder = encoder,
              instanceBatcher2D.instanceCount > 0,
              let batchKey = instanceBatcher2D.currentBatchKey else { return }

        guard let pipeline = instancedPipelineStates[batchKey.blendMode] else { return }
        encoder.setRenderPipelineState(pipeline)
        if let depthState = depthStencilState {
            encoder.setDepthStencilState(depthState)
        }
        encoder.setCullMode(.none)

        let (meshBuffer, meshVertexCount) = unitMeshFor(batchKey.shapeType)
        encoder.setVertexBuffer(meshBuffer, offset: 0, index: 0)
        encoder.setVertexBuffer(instanceBatcher2D.currentBuffer, offset: instanceBatcher2D.currentBufferOffset, index: 6)

        var proj = projectionMatrix
        encoder.setVertexBytes(&proj, length: MemoryLayout<float4x4>.size, index: 1)

        encoder.drawPrimitives(
            type: .triangle,
            vertexStart: 0,
            vertexCount: meshVertexCount,
            instanceCount: instanceBatcher2D.instanceCount
        )

        instanceBatcher2D.reset()
    }

    // Add a shape to the instanced batch.
    // cx, cy: center position in local space
    // sx, sy: scale factors applied to the unit mesh
    func addShapeInstance(_ shapeType: Shape2DType, cx: Float, cy: Float, sx: Float, sy: Float) {
        hasDrawnAnything = true

        // Preserve draw order: flush non-instanced vertices first if pending
        if texturedVertexCount > 0 {
            flushTexturedVertices()
            currentBoundTexture = nil
        }
        if vertexCount > 0 {
            flushColorVertices()
        }

        let key = InstanceBatcher2D.BatchKey2D(
            shapeType: shapeType,
            blendMode: currentBlendMode
        )

        // Convert currentTransform * translate(cx,cy) * scale(sx,sy) to float4x4
        let shapeLocal = float3x3(columns: (
            SIMD3<Float>(sx, 0, 0),
            SIMD3<Float>(0, sy, 0),
            SIMD3<Float>(cx, cy, 1)
        ))
        let combined = currentTransform * shapeLocal
        let transform = Canvas2D.embed2DTransform(combined)

        if !instanceBatcher2D.tryAddInstance(key: key, transform: transform, color: fillColor) {
            flushInstancedBatch()
            if !instanceBatcher2D.tryAddInstance(key: key, transform: transform, color: fillColor) {
                // Instance buffer exhausted for this frame — fall back to color vertices
                addShapeFallback(shapeType, cx: cx, cy: cy, sx: sx, sy: sy)
            }
        }
    }

    /// Fallback: draw a shape as non-instanced color vertices when instance buffer is full.
    private func addShapeFallback(_ shapeType: Shape2DType, cx: Float, cy: Float, sx: Float, sy: Float) {
        let color = fillColor
        switch shapeType {
        case .ellipse:
            let segments = 16
            let step = Float.pi * 2.0 / Float(segments)
            let rx = sx * 0.5
            let ry = sy * 0.5
            for i in 0..<segments {
                let a0 = step * Float(i)
                let a1 = step * Float(i + 1)
                addVertex(cx, cy, color)
                addVertex(cx + rx * cos(a0), cy + ry * sin(a0), color)
                addVertex(cx + rx * cos(a1), cy + ry * sin(a1), color)
            }
        case .rect:
            let hx = sx * 0.5
            let hy = sy * 0.5
            addVertex(cx - hx, cy - hy, color)
            addVertex(cx + hx, cy - hy, color)
            addVertex(cx + hx, cy + hy, color)
            addVertex(cx - hx, cy - hy, color)
            addVertex(cx + hx, cy + hy, color)
            addVertex(cx - hx, cy + hy, color)
        }
    }

    private func unitMeshFor(_ shapeType: Shape2DType) -> (MTLBuffer, Int) {
        switch shapeType {
        case .ellipse: return (unitCircleBuffer, unitCircleVertexCount)
        case .rect: return (unitRectBuffer, unitRectVertexCount)
        }
    }

    // MARK: - Transform Stack

    /// Save the current transform and style state onto the stack.
    ///
    /// Use ``pop()`` to restore the saved state. Compatible with the Processing API.
    public func push() {
        stateStack.append(StyleState(
            transform: currentTransform,
            fillColor: fillColor,
            strokeColor: strokeColor,
            strokeWeight: currentStrokeWeight,
            hasFill: hasFill,
            hasStroke: hasStroke,
            blendMode: currentBlendMode,
            rectMode: currentRectMode,
            ellipseMode: currentEllipseMode,
            imageMode: currentImageMode,
            colorModeConfig: colorModeConfig,
            tintColor: tintColor,
            hasTint: hasTint,
            textSize: currentTextSize,
            fontFamily: currentFontFamily,
            textAlignH: currentTextAlignH,
            textAlignV: currentTextAlignV,
            textLeading: currentTextLeading,
            curveDetail: curveDetailCount,
            curveTightness: curveTightnessValue,
            strokeCap: currentStrokeCap,
            strokeJoin: currentStrokeJoin
        ))
    }

    /// Restore the most recently saved transform and style state from the stack.
    ///
    /// Flushes the current batch if the blend mode changed. Compatible with the Processing API.
    public func pop() {
        guard let saved = stateStack.popLast() else { return }
        let prevBlendMode = currentBlendMode
        currentTransform = saved.transform
        fillColor = saved.fillColor
        strokeColor = saved.strokeColor
        currentStrokeWeight = saved.strokeWeight
        hasFill = saved.hasFill
        hasStroke = saved.hasStroke
        currentBlendMode = saved.blendMode
        currentRectMode = saved.rectMode
        currentEllipseMode = saved.ellipseMode
        currentImageMode = saved.imageMode
        colorModeConfig = saved.colorModeConfig
        tintColor = saved.tintColor
        hasTint = saved.hasTint
        currentTextSize = saved.textSize
        currentFontFamily = saved.fontFamily
        currentTextAlignH = saved.textAlignH
        currentTextAlignV = saved.textAlignV
        currentTextLeading = saved.textLeading
        curveDetailCount = saved.curveDetail
        curveTightnessValue = saved.curveTightness
        currentStrokeCap = saved.strokeCap
        currentStrokeJoin = saved.strokeJoin
        if prevBlendMode != currentBlendMode {
            flush()
        }
    }

    /// Save only the style state onto the style-only stack, excluding the transform.
    public func pushStyle() {
        styleOnlyStack.append(StyleState(
            transform: currentTransform,
            fillColor: fillColor,
            strokeColor: strokeColor,
            strokeWeight: currentStrokeWeight,
            hasFill: hasFill,
            hasStroke: hasStroke,
            blendMode: currentBlendMode,
            rectMode: currentRectMode,
            ellipseMode: currentEllipseMode,
            imageMode: currentImageMode,
            colorModeConfig: colorModeConfig,
            tintColor: tintColor,
            hasTint: hasTint,
            textSize: currentTextSize,
            fontFamily: currentFontFamily,
            textAlignH: currentTextAlignH,
            textAlignV: currentTextAlignV,
            textLeading: currentTextLeading,
            curveDetail: curveDetailCount,
            curveTightness: curveTightnessValue,
            strokeCap: currentStrokeCap,
            strokeJoin: currentStrokeJoin
        ))
    }

    /// Restore only the style state from the style-only stack, leaving the transform unchanged.
    public func popStyle() {
        guard let saved = styleOnlyStack.popLast() else { return }
        let prevBlendMode = currentBlendMode
        fillColor = saved.fillColor
        strokeColor = saved.strokeColor
        currentStrokeWeight = saved.strokeWeight
        hasFill = saved.hasFill
        hasStroke = saved.hasStroke
        currentBlendMode = saved.blendMode
        currentRectMode = saved.rectMode
        currentEllipseMode = saved.ellipseMode
        currentImageMode = saved.imageMode
        colorModeConfig = saved.colorModeConfig
        tintColor = saved.tintColor
        hasTint = saved.hasTint
        currentTextSize = saved.textSize
        currentFontFamily = saved.fontFamily
        currentTextAlignH = saved.textAlignH
        currentTextAlignV = saved.textAlignV
        currentTextLeading = saved.textLeading
        curveDetailCount = saved.curveDetail
        curveTightnessValue = saved.curveTightness
        currentStrokeCap = saved.strokeCap
        currentStrokeJoin = saved.strokeJoin
        if prevBlendMode != currentBlendMode {
            flush()
        }
    }

    /// Save only the current transform matrix onto the matrix stack.
    public func pushMatrix() {
        matrixStack.append(currentTransform)
    }

    /// Restore only the transform matrix from the matrix stack.
    public func popMatrix() {
        guard let saved = matrixStack.popLast() else { return }
        currentTransform = saved
    }

    /// Apply a translation to the current transform.
    ///
    /// - Parameters:
    ///   - x: The horizontal translation in pixels.
    ///   - y: The vertical translation in pixels.
    public func translate(_ x: Float, _ y: Float) {
        let t = float3x3(columns: (
            SIMD3<Float>(1, 0, 0),
            SIMD3<Float>(0, 1, 0),
            SIMD3<Float>(x, y, 1)
        ))
        currentTransform = currentTransform * t
    }

    /// Apply a rotation to the current transform.
    ///
    /// - Parameter angle: The rotation angle in radians.
    public func rotate(_ angle: Float) {
        let c = cos(angle)
        let s = sin(angle)
        let r = float3x3(columns: (
            SIMD3<Float>(c, s, 0),
            SIMD3<Float>(-s, c, 0),
            SIMD3<Float>(0, 0, 1)
        ))
        currentTransform = currentTransform * r
    }

    /// Apply a non-uniform scale to the current transform.
    ///
    /// - Parameters:
    ///   - sx: The horizontal scale factor.
    ///   - sy: The vertical scale factor.
    public func scale(_ sx: Float, _ sy: Float) {
        let s = float3x3(columns: (
            SIMD3<Float>(sx, 0, 0),
            SIMD3<Float>(0, sy, 0),
            SIMD3<Float>(0, 0, 1)
        ))
        currentTransform = currentTransform * s
    }

    /// Apply a uniform scale to the current transform.
    ///
    /// - Parameter s: The scale factor applied to both axes.
    public func scale(_ s: Float) {
        scale(s, s)
    }
}
