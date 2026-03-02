import Testing
import Metal
import simd
@testable import metaphor

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
        input.handleKeyDown(keyCode: 49, characters: " ")
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
        input.handleKeyDown(keyCode: 0, characters: "a")
        input.handleKeyDown(keyCode: 1, characters: "s")
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

// MARK: - Mesh Tests

@Suite("Mesh", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct MeshTests {

    @Test("box has 24 vertices and 36 indices")
    func boxCounts() {
        let device = MTLCreateSystemDefaultDevice()!
        let mesh = Mesh.box(device: device)
        #expect(mesh.vertexCount == 24)
        #expect(mesh.indexCount == 36)
        #expect(mesh.indexBuffer != nil)
    }

    @Test("sphere has expected vertex count")
    func sphereCounts() {
        let device = MTLCreateSystemDefaultDevice()!
        let mesh = Mesh.sphere(device: device, radius: 1, segments: 8, rings: 4)
        // (rings+1) * (segments+1) = 5 * 9 = 45
        #expect(mesh.vertexCount == 45)
        // rings * segments * 6 = 4 * 8 * 6 = 192
        #expect(mesh.indexCount == 192)
    }

    @Test("plane has 4 vertices and 6 indices")
    func planeCounts() {
        let device = MTLCreateSystemDefaultDevice()!
        let mesh = Mesh.plane(device: device)
        #expect(mesh.vertexCount == 4)
        #expect(mesh.indexCount == 6)
    }

    @Test("cylinder has expected index count")
    func cylinderCounts() {
        let device = MTLCreateSystemDefaultDevice()!
        let mesh = Mesh.cylinder(device: device, segments: 8)
        // Side: 8*6=48, Top cap: 8*3=24, Bot cap: 8*3=24 = 96
        #expect(mesh.indexCount == 96)
    }

    @Test("cone has expected index count")
    func coneCounts() {
        let device = MTLCreateSystemDefaultDevice()!
        let mesh = Mesh.cone(device: device, segments: 8)
        // Side: 8*3=24, Bot cap: 8*3=24 = 48
        #expect(mesh.indexCount == 48)
    }

    @Test("torus has expected vertex count")
    func torusCounts() {
        let device = MTLCreateSystemDefaultDevice()!
        let mesh = Mesh.torus(device: device, segments: 8, tubeSegments: 4)
        // (segments+1) * (tubeSegments+1) = 9 * 5 = 45
        #expect(mesh.vertexCount == 45)
        // segments * tubeSegments * 6 = 8 * 4 * 6 = 192
        #expect(mesh.indexCount == 192)
    }

    @Test("box with custom dimensions")
    func boxCustom() {
        let device = MTLCreateSystemDefaultDevice()!
        let mesh = Mesh.box(device: device, width: 2, height: 3, depth: 4)
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

    @Test("renderer has saveScreenshot method")
    func saveScreenshotAPI() throws {
        let renderer = try MetaphorRenderer()
        // pendingSavePath が設定されることを確認（直接アクセスはできないがクラッシュしないことを検証）
        renderer.saveScreenshot(to: "/tmp/test_screenshot.png")
    }
}
