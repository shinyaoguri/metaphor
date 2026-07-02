import Testing
import Metal
import simd
@testable import metaphor
@testable import MetaphorCore

// MARK: - InputManager Tests

@Suite("InputManager")
@MainActor
struct InputManagerTests {

    @Test("initial state is zero")
    func initialState() {
        let input = InputManager()
        #expect(input.mouseX == 0)
        #expect(input.mouseY == 0)
        #expect(input.isMouseDown == false)
        #expect(input.isKeyPressed == false)
    }

    @Test("mouse down updates state")
    func mouseDown() {
        let input = InputManager()
        input.handleMouseDown(x: 100, y: 200, button: 0)
        #expect(input.mouseX == 100)
        #expect(input.mouseY == 200)
        #expect(input.isMouseDown == true)
        #expect(input.mouseButton == 0)
    }

    @Test("mouse up clears isMouseDown")
    func mouseUp() {
        let input = InputManager()
        input.handleMouseDown(x: 100, y: 200, button: 0)
        input.handleMouseUp(x: 100, y: 200, button: 0)
        #expect(input.isMouseDown == false)
    }

    @Test("mouse moved updates position")
    func mouseMoved() {
        let input = InputManager()
        input.handleMouseMoved(x: 50, y: 75)
        #expect(input.mouseX == 50)
        #expect(input.mouseY == 75)
    }

    @Test("frame update saves previous position")
    func frameUpdate() {
        let input = InputManager()
        input.handleMouseMoved(x: 10, y: 20)
        input.updateFrame()
        input.handleMouseMoved(x: 30, y: 40)
        #expect(input.pmouseX == 10)
        #expect(input.pmouseY == 20)
        #expect(input.mouseX == 30)
        #expect(input.mouseY == 40)
    }

    @Test("key down/up tracking")
    func keyTracking() {
        let input = InputManager()
        input.handleKeyDown(keyCode: 49, characters: " ", isRepeat: false)
        #expect(input.isKeyPressed == true)
        #expect(input.isKeyDown(49) == true)
        #expect(input.lastKeyCode == 49)
        #expect(input.lastKey == " ")

        input.handleKeyUp(keyCode: 49)
        #expect(input.isKeyPressed == false)
        #expect(input.isKeyDown(49) == false)
    }

    @Test("multiple keys tracked independently")
    func multipleKeys() {
        let input = InputManager()
        input.handleKeyDown(keyCode: 0, characters: "a", isRepeat: false)
        input.handleKeyDown(keyCode: 1, characters: "s", isRepeat: false)
        #expect(input.isKeyDown(0) == true)
        #expect(input.isKeyDown(1) == true)

        input.handleKeyUp(keyCode: 0)
        #expect(input.isKeyDown(0) == false)
        #expect(input.isKeyDown(1) == true)
        #expect(input.isKeyPressed == true)
    }

    @Test("callbacks are invoked")
    func callbacks() {
        let input = InputManager()
        var called = false
        input.onMousePressed = { _, _, _ in called = true }
        input.handleMouseDown(x: 0, y: 0, button: 0)
        #expect(called == true)
    }

    @Test("middle mouse button updates state")
    func middleMouseButton() {
        let input = InputManager()
        input.handleMouseDown(x: 50, y: 60, button: 2)
        #expect(input.isMouseDown == true)
        #expect(input.mouseButton == 2)
        #expect(input.mouseX == 50)
        #expect(input.mouseY == 60)

        input.handleMouseUp(x: 50, y: 60, button: 2)
        #expect(input.isMouseDown == false)
    }

    @Test("scroll deltas accumulate within a frame")
    func scrollAccumulation() {
        let input = InputManager()
        input.updateFrame()
        input.handleMouseScrolled(dx: 1.5, dy: 2.0)
        input.handleMouseScrolled(dx: 0.5, dy: -1.0)
        #expect(input.scrollX == 2.0)
        #expect(input.scrollY == 1.0)

        // Reset on next frame
        input.updateFrame()
        #expect(input.scrollX == 0)
        #expect(input.scrollY == 0)
    }

    @Test("isKeyRepeat tracks auto-repeat state")
    func keyRepeat() {
        let input = InputManager()
        input.handleKeyDown(keyCode: 0, characters: "a", isRepeat: false)
        #expect(input.isKeyRepeat == false)

        input.handleKeyDown(keyCode: 0, characters: "a", isRepeat: true)
        #expect(input.isKeyRepeat == true)

        // Different key resets
        input.handleKeyDown(keyCode: 1, characters: "s", isRepeat: false)
        #expect(input.isKeyRepeat == false)
    }

    @Test("isKeyRepeat resets on keyUp")
    func keyRepeatResetsOnKeyUp() {
        let input = InputManager()
        input.handleKeyDown(keyCode: 0, characters: "a", isRepeat: true)
        #expect(input.isKeyRepeat == true)

        input.handleKeyUp(keyCode: 0)
        #expect(input.isKeyRepeat == false)
    }

    @Test("flagsChanged syncs modifier keys into pressedKeys")
    func modifierKeys() {
        let input = InputManager()
        #expect(input.isKeyDown(SHIFT) == false)

        input.handleFlagsChanged(shift: true, control: false, option: false, command: false)
        #expect(input.isKeyDown(SHIFT) == true)
        #expect(input.isKeyDown(CONTROL) == false)
        #expect(input.isKeyPressed == true)

        input.handleFlagsChanged(shift: true, control: false, option: true, command: true)
        #expect(input.isKeyDown(SHIFT) == true)
        #expect(input.isKeyDown(OPTION) == true)
        #expect(input.isKeyDown(COMMAND) == true)

        input.handleFlagsChanged(shift: false, control: false, option: false, command: false)
        #expect(input.isKeyDown(SHIFT) == false)
        #expect(input.isKeyDown(OPTION) == false)
        #expect(input.isKeyDown(COMMAND) == false)
        #expect(input.isKeyPressed == false)
    }

    @Test("mouseClicked fires on press-release without drag")
    func mouseClicked() {
        let input = InputManager()
        var clickCount = 0
        var lastButton = -1
        input.onMouseClicked = { _, _, button in
            clickCount += 1
            lastButton = button
        }

        input.handleMouseDown(x: 10, y: 20, button: 0)
        input.handleMouseUp(x: 10, y: 20, button: 0)
        #expect(clickCount == 1)
        #expect(lastButton == 0)
    }

    @Test("mouseClicked suppressed when dragged")
    func mouseClickedSuppressedOnDrag() {
        let input = InputManager()
        var clickCount = 0
        input.onMouseClicked = { _, _, _ in clickCount += 1 }

        input.handleMouseDown(x: 10, y: 20, button: 0)
        input.handleMouseDragged(x: 50, y: 60)
        input.handleMouseUp(x: 50, y: 60, button: 0)
        #expect(clickCount == 0)
    }

    @Test("mouseClicked resets after drag-release cycle")
    func mouseClickedResetsAfterDrag() {
        let input = InputManager()
        var clickCount = 0
        input.onMouseClicked = { _, _, _ in clickCount += 1 }

        // First: drag (no click)
        input.handleMouseDown(x: 0, y: 0, button: 0)
        input.handleMouseDragged(x: 100, y: 100)
        input.handleMouseUp(x: 100, y: 100, button: 0)
        #expect(clickCount == 0)

        // Second: clean click
        input.handleMouseDown(x: 50, y: 50, button: 0)
        input.handleMouseUp(x: 50, y: 50, button: 0)
        #expect(clickCount == 1)
    }
}

// MARK: - MetaphorRenderer Input Integration Tests

@Suite("MetaphorRenderer Input", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct RendererInputTests {

    @Test("renderer has input manager")
    func rendererHasInput() throws {
        let renderer = try MetaphorRenderer()
        #expect(renderer.input.mouseX == 0)
        #expect(renderer.input.isMouseDown == false)
    }
}

// MARK: - ParameterGUI Interaction Tests

@Suite("ParameterGUI Interaction", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct ParameterGUIInteractionTests {

    private func makeCanvas() throws -> (Canvas2D, InputManager) {
        let renderer = try MetaphorRenderer(width: 256, height: 256)
        let canvas = try Canvas2D(renderer: renderer)
        return (canvas, renderer.input)
    }

    @Test("toggle flips exactly once while mouse is held down")
    func toggleSingleFlip() throws {
        let (canvas, input) = try makeCanvas()
        let gui = ParameterGUI()
        var flag = false

        // デフォルトレイアウト: toggleX=14, toggleY=16..32 → (20, 20) はヒット
        input.handleMouseDown(x: 20, y: 20, button: 0)
        for _ in 0..<5 {
            gui.begin()
            gui.toggle("flag", &flag, canvas: canvas, input: input)
            gui.end()
            gui.updateInput(input: input)
        }
        // 押下中に何フレーム回っても 1 回だけ反転する
        #expect(flag == true)

        input.handleMouseUp(x: 20, y: 20, button: 0)
        gui.begin()
        gui.toggle("flag", &flag, canvas: canvas, input: input)
        gui.end()
        gui.updateInput(input: input)
        #expect(flag == true)
    }

    @Test("two sliders with the same label drag independently")
    func sliderIDUniqueness() throws {
        let (canvas, input) = try makeCanvas()
        let gui = ParameterGUI()
        var v1: Float = 0.5
        var v2: Float = 0.5

        func frame() {
            gui.begin()
            gui.slider("same", &v1, min: 0, max: 1, canvas: canvas, input: input)
            gui.slider("same", &v2, min: 0, max: 1, canvas: canvas, input: input)
            gui.end()
            gui.updateInput(input: input)
        }

        // レイアウト: slider1 トラック y=28..44、slider2 トラック y=62..78
        // 2 本目のトラック上で押下 → 2 本目だけが動く
        input.handleMouseDown(x: 100, y: 70, button: 0)
        frame()
        input.handleMouseDragged(x: 150, y: 70)
        frame()

        #expect(v1 == 0.5, "1 本目のスライダーは動かない（旧: ラベル由来 ID の衝突で同時ドラッグ）")
        #expect(abs(v2 - (150.0 - 14.0) / 200.0) < 0.01)
    }

    @Test("slider is not grabbed when dragging across it with button already down")
    func sliderNoMidDragGrab() throws {
        let (canvas, input) = try makeCanvas()
        let gui = ParameterGUI()
        var v: Float = 0.5

        func frame() {
            gui.begin()
            gui.slider("v", &v, min: 0, max: 1, canvas: canvas, input: input)
            gui.end()
            gui.updateInput(input: input)
        }

        // トラック外（下方）で押下してから、押したままトラック上を通過
        input.handleMouseDown(x: 100, y: 200, button: 0)
        frame()
        input.handleMouseDragged(x: 100, y: 36)  // トラック内 (y=28..44)
        frame()

        #expect(v == 0.5, "押下済みのままトラックへ入ってもスライダーを掴まない")
    }
}

// MARK: - Mesh Tests

@Suite("Mesh", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct MeshTests {

    @Test("box has 24 vertices and 36 indices")
    func boxCounts() {
        let device = MTLCreateSystemDefaultDevice()!
        let mesh = try! Mesh.box(device: device)
        #expect(mesh.vertexCount == 24)
        #expect(mesh.indexCount == 36)
        #expect(mesh.indexBuffer != nil)
    }

    @Test("sphere has expected vertex count")
    func sphereCounts() {
        let device = MTLCreateSystemDefaultDevice()!
        let mesh = try! Mesh.sphere(device: device, radius: 1, segments: 8, rings: 4)
        // (rings+1) * (segments+1) = 5 * 9 = 45
        #expect(mesh.vertexCount == 45)
        // rings * segments * 6 = 4 * 8 * 6 = 192
        #expect(mesh.indexCount == 192)
    }

    @Test("plane has 4 vertices and 6 indices")
    func planeCounts() {
        let device = MTLCreateSystemDefaultDevice()!
        let mesh = try! Mesh.plane(device: device)
        #expect(mesh.vertexCount == 4)
        #expect(mesh.indexCount == 6)
    }

    @Test("cylinder has expected index count")
    func cylinderCounts() {
        let device = MTLCreateSystemDefaultDevice()!
        let mesh = try! Mesh.cylinder(device: device, segments: 8)
        // Side: 8*6=48, Top cap: 8*3=24, Bot cap: 8*3=24 = 96
        #expect(mesh.indexCount == 96)
    }

    @Test("cone has expected index count")
    func coneCounts() {
        let device = MTLCreateSystemDefaultDevice()!
        let mesh = try! Mesh.cone(device: device, segments: 8)
        // Side: 8*3=24, Bot cap: 8*3=24 = 48
        #expect(mesh.indexCount == 48)
    }

    @Test("torus has expected vertex count")
    func torusCounts() {
        let device = MTLCreateSystemDefaultDevice()!
        let mesh = try! Mesh.torus(device: device, segments: 8, tubeSegments: 4)
        // (segments+1) * (tubeSegments+1) = 9 * 5 = 45
        #expect(mesh.vertexCount == 45)
        // segments * tubeSegments * 6 = 8 * 4 * 6 = 192
        #expect(mesh.indexCount == 192)
    }

    @Test("box with custom dimensions")
    func boxCustom() {
        let device = MTLCreateSystemDefaultDevice()!
        let mesh = try! Mesh.box(device: device, width: 2, height: 3, depth: 4)
        #expect(mesh.vertexCount == 24)
        #expect(mesh.indexCount == 36)
    }
}

// MARK: - MImage Tests

@Suite("MImage", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct MImageTests {

    @Test("MImage from texture")
    func fromTexture() {
        let device = MTLCreateSystemDefaultDevice()!
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: 64, height: 32, mipmapped: false
        )
        desc.usage = .shaderRead
        let texture = device.makeTexture(descriptor: desc)!
        let img = MImage(texture: texture)
        #expect(img.width == 64)
        #expect(img.height == 32)
    }

    @Test("loadPixels preserves RGBA texture channel order")
    func loadPixelsRGBAOrder() {
        let device = MTLCreateSystemDefaultDevice()!
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false
        )
        desc.usage = .shaderRead
        desc.storageMode = .shared
        let texture = device.makeTexture(descriptor: desc)!
        let rgba: [UInt8] = [255, 0, 0, 255]
        rgba.withUnsafeBytes { bytes in
            texture.replace(
                region: MTLRegionMake2D(0, 0, 1, 1),
                mipmapLevel: 0,
                withBytes: bytes.baseAddress!,
                bytesPerRow: 4
            )
        }

        let img = MImage(texture: texture)
        img.loadPixels()

        #expect(img.pixels == [255, 0, 0, 255])
    }

    @Test("updatePixels preserves RGBA texture channel order")
    func updatePixelsRGBAOrder() {
        let device = MTLCreateSystemDefaultDevice()!
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false
        )
        desc.usage = .shaderRead
        desc.storageMode = .shared
        let texture = device.makeTexture(descriptor: desc)!
        let img = MImage(texture: texture)
        img.pixels = [0, 255, 0, 255]
        img.updatePixels()

        var readback = [UInt8](repeating: 0, count: 4)
        texture.getBytes(
            &readback,
            bytesPerRow: 4,
            from: MTLRegionMake2D(0, 0, 1, 1),
            mipmapLevel: 0
        )

        #expect(readback == [0, 255, 0, 255])
    }
}

// MARK: - TextRenderer Tests

@Suite("TextRenderer", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct TextRendererTests {

    @Test("can render text to texture")
    func renderText() {
        let device = MTLCreateSystemDefaultDevice()!
        let renderer = TextRenderer(device: device)
        let cached = renderer.textTexture(
            string: "Hello",
            fontSize: 32,
            fontFamily: "Helvetica",
            frameCount: 1
        )
        #expect(cached != nil)
        #expect(cached!.width > 0)
        #expect(cached!.height > 0)
    }

    @Test("cache hit returns same texture")
    func cacheHit() {
        let device = MTLCreateSystemDefaultDevice()!
        let renderer = TextRenderer(device: device)
        let first = renderer.textTexture(
            string: "Test", fontSize: 24, fontFamily: "Helvetica", frameCount: 1
        )
        let second = renderer.textTexture(
            string: "Test", fontSize: 24, fontFamily: "Helvetica", frameCount: 2
        )
        #expect(first != nil)
        #expect(second != nil)
        #expect(first!.texture === second!.texture)
    }

    @Test("different params produce different textures")
    func cacheMiss() {
        let device = MTLCreateSystemDefaultDevice()!
        let renderer = TextRenderer(device: device)
        let a = renderer.textTexture(
            string: "AAA", fontSize: 24, fontFamily: "Helvetica", frameCount: 1
        )
        let b = renderer.textTexture(
            string: "BBB", fontSize: 24, fontFamily: "Helvetica", frameCount: 1
        )
        #expect(a != nil)
        #expect(b != nil)
        #expect(a!.texture !== b!.texture)
    }
}

// MARK: - Screenshot Tests

@Suite("Screenshot", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct ScreenshotTests {

    @Test("saveScreenshot does not affect renderer state")
    func saveScreenshotAPI() throws {
        let renderer = try MetaphorRenderer()
        let widthBefore = renderer.textureManager.width
        renderer.saveScreenshot(to: "/tmp/test_screenshot.png")
        // saveScreenshot はパスを保持するだけで、レンダラーの状態を壊さない
        #expect(renderer.textureManager.width == widthBefore)
        #expect(renderer.feedbackEnabled == false)
    }
}
