import Testing
import Metal
@testable import MetaphorCore
import MetaphorTestSupport

// MARK: - Mock Plugin

@MainActor
final class MockPlugin: MetaphorPlugin {
    let pluginID: String
    var attachedSketch: (any Sketch)?
    var attachedRenderer: MetaphorRenderer?
    var detached = false
    var preCallCount = 0
    var postCallCount = 0
    var lastPreTime: Double = 0
    var lastPostTexture: MTLTexture?
    var mouseEvents: [(x: Float, y: Float, button: Int, type: MouseEventType)] = []
    var keyEvents: [(key: Character?, keyCode: UInt16, type: KeyEventType)] = []
    var resizeEvents: [(width: Int, height: Int)] = []
    // Legacy hooks
    var legacyBeforeRenderCount = 0
    var legacyAfterRenderCount = 0

    init(id: String = "mock") {
        self.pluginID = id
    }

    func onAttach(sketch: any Sketch) {
        attachedSketch = sketch
    }

    func onAttach(renderer: MetaphorRenderer) {
        attachedRenderer = renderer
    }

    func onDetach() {
        detached = true
    }

    func pre(commandBuffer: MTLCommandBuffer, time: Double) {
        preCallCount += 1
        lastPreTime = time
    }

    func post(texture: MTLTexture, commandBuffer: MTLCommandBuffer) {
        postCallCount += 1
        lastPostTexture = texture
    }

    func mouseEvent(x: Float, y: Float, button: Int, type: MouseEventType) {
        mouseEvents.append((x: x, y: y, button: button, type: type))
    }

    func keyEvent(key: Character?, keyCode: UInt16, type: KeyEventType) {
        keyEvents.append((key: key, keyCode: keyCode, type: type))
    }

    func onResize(width: Int, height: Int) {
        resizeEvents.append((width: width, height: height))
    }

    func onBeforeRender(commandBuffer: MTLCommandBuffer, time: Double) {
        legacyBeforeRenderCount += 1
    }

    func onAfterRender(texture: MTLTexture, commandBuffer: MTLCommandBuffer) {
        legacyAfterRenderCount += 1
    }
}

// MARK: - Tests

@Suite("MetaphorPlugin Enhanced", .enabled(if: MetalTestHelper.isGPUAvailable))
@MainActor
struct PluginTests {

    // MARK: - Registration

    @Test("addPlugin with sketch calls onAttach(sketch:) and onAttach(renderer:)")
    func addPluginWithSketch() throws {
        let renderer = try MetaphorRenderer(width: 64, height: 64)
        let plugin = MockPlugin(id: "test-attach")

        // Use a minimal mock sketch
        let sketch = TestSketch()
        let canvas = try Canvas2D(renderer: renderer)
        let canvas3D = try Canvas3D(renderer: renderer)
        sketch._context = SketchContext(
            renderer: renderer, canvas: canvas, canvas3D: canvas3D, input: renderer.input
        )

        renderer.addPlugin(plugin, sketch: sketch)

        #expect(plugin.attachedSketch != nil)
        #expect(plugin.attachedRenderer != nil)
        #expect(plugin.attachedRenderer === renderer)
    }

    @Test("legacy addPlugin only calls onAttach(renderer:)")
    func legacyAddPlugin() throws {
        let renderer = try MetaphorRenderer(width: 64, height: 64)
        let plugin = MockPlugin(id: "test-legacy")

        renderer.addPlugin(plugin)

        #expect(plugin.attachedSketch == nil)
        #expect(plugin.attachedRenderer != nil)
    }

    @Test("removePlugin calls onDetach")
    func removePlugin() throws {
        let renderer = try MetaphorRenderer(width: 64, height: 64)
        let plugin = MockPlugin(id: "test-remove")

        renderer.addPlugin(plugin)
        #expect(plugin.detached == false)

        renderer.removePlugin(id: "test-remove")
        #expect(plugin.detached == true)
    }

    @Test("plugin lookup by ID")
    func pluginLookup() throws {
        let renderer = try MetaphorRenderer(width: 64, height: 64)
        let plugin = MockPlugin(id: "test-lookup")

        renderer.addPlugin(plugin)
        let found = renderer.plugin(id: "test-lookup")
        #expect(found != nil)
        #expect(found?.pluginID == "test-lookup")
        #expect(renderer.plugin(id: "nonexistent") == nil)
    }

    // MARK: - Input Forwarding

    @Test("notifyPluginsMouseEvent forwards to all plugins")
    func mouseEventForwarding() throws {
        let renderer = try MetaphorRenderer(width: 64, height: 64)
        let plugin1 = MockPlugin(id: "mouse-1")
        let plugin2 = MockPlugin(id: "mouse-2")

        renderer.addPlugin(plugin1)
        renderer.addPlugin(plugin2)

        renderer.notifyPluginsMouseEvent(x: 100, y: 200, button: 0, type: .pressed)

        #expect(plugin1.mouseEvents.count == 1)
        #expect(plugin1.mouseEvents[0].x == 100)
        #expect(plugin1.mouseEvents[0].y == 200)
        #expect(plugin1.mouseEvents[0].type == .pressed)

        #expect(plugin2.mouseEvents.count == 1)
    }

    @Test("notifyPluginsKeyEvent forwards to all plugins")
    func keyEventForwarding() throws {
        let renderer = try MetaphorRenderer(width: 64, height: 64)
        let plugin = MockPlugin(id: "key-test")

        renderer.addPlugin(plugin)

        renderer.notifyPluginsKeyEvent(key: "a", keyCode: 0, type: .pressed)
        renderer.notifyPluginsKeyEvent(key: nil, keyCode: 53, type: .released)

        #expect(plugin.keyEvents.count == 2)
        #expect(plugin.keyEvents[0].key == "a")
        #expect(plugin.keyEvents[0].type == .pressed)
        #expect(plugin.keyEvents[1].key == nil)
        #expect(plugin.keyEvents[1].type == .released)
    }

    @Test("mouse event types cover all cases")
    func mouseEventTypes() throws {
        let renderer = try MetaphorRenderer(width: 64, height: 64)
        let plugin = MockPlugin(id: "event-types")
        renderer.addPlugin(plugin)

        let types: [MouseEventType] = [.pressed, .released, .moved, .dragged, .scrolled, .clicked]
        for eventType in types {
            renderer.notifyPluginsMouseEvent(x: 0, y: 0, button: 0, type: eventType)
        }

        #expect(plugin.mouseEvents.count == 6)
        #expect(plugin.mouseEvents[0].type == .pressed)
        #expect(plugin.mouseEvents[1].type == .released)
        #expect(plugin.mouseEvents[2].type == .moved)
        #expect(plugin.mouseEvents[3].type == .dragged)
        #expect(plugin.mouseEvents[4].type == .scrolled)
        #expect(plugin.mouseEvents[5].type == .clicked)
    }

    // MARK: - Resize

    @Test("onResize called when canvas resizes")
    func resizeNotification() throws {
        let renderer = try MetaphorRenderer(width: 64, height: 64)
        let plugin = MockPlugin(id: "resize-test")
        renderer.addPlugin(plugin)

        try renderer.resizeCanvas(width: 128, height: 96)

        #expect(plugin.resizeEvents.count == 1)
        #expect(plugin.resizeEvents[0].width == 128)
        #expect(plugin.resizeEvents[0].height == 96)
    }

    // MARK: - PluginFactory

    @Test("PluginFactory creates plugin instances")
    func pluginFactory() {
        let factory = PluginFactory { MockPlugin(id: "factory-test") }
        let plugin = factory.create()

        #expect(plugin.pluginID == "factory-test")
    }

    @Test("PluginFactory captures configuration")
    func pluginFactoryCapture() {
        let name = "captured-id"
        let factory = PluginFactory { MockPlugin(id: name) }
        let plugin = factory.create()

        #expect(plugin.pluginID == "captured-id")
    }

    // MARK: - SketchConfig

    @Test("SketchConfig accepts plugins")
    func sketchConfigPlugins() {
        let config = SketchConfig(
            width: 800, height: 600,
            plugins: [
                PluginFactory { MockPlugin(id: "config-1") },
                PluginFactory { MockPlugin(id: "config-2") },
            ]
        )

        #expect(config.plugins.count == 2)
    }

    @Test("SketchConfig defaults to empty plugins")
    func sketchConfigDefaultPlugins() {
        let config = SketchConfig()
        #expect(config.plugins.isEmpty)
    }

    // MARK: - Sketch Convenience

    @Test("registerPlugin via Sketch protocol extension")
    func sketchRegisterPlugin() throws {
        let renderer = try MetaphorRenderer(width: 64, height: 64)
        let sketch = TestSketch()
        let canvas = try Canvas2D(renderer: renderer)
        let canvas3D = try Canvas3D(renderer: renderer)
        sketch._context = SketchContext(
            renderer: renderer, canvas: canvas, canvas3D: canvas3D, input: renderer.input
        )

        let plugin = MockPlugin(id: "sketch-register")
        sketch.registerPlugin(plugin)

        #expect(plugin.attachedSketch != nil)
        #expect(renderer.plugin(id: "sketch-register") != nil)
    }

    @Test("removePlugin via Sketch protocol extension")
    func sketchRemovePlugin() throws {
        let renderer = try MetaphorRenderer(width: 64, height: 64)
        let sketch = TestSketch()
        let canvas = try Canvas2D(renderer: renderer)
        let canvas3D = try Canvas3D(renderer: renderer)
        sketch._context = SketchContext(
            renderer: renderer, canvas: canvas, canvas3D: canvas3D, input: renderer.input
        )

        let plugin = MockPlugin(id: "sketch-remove")
        sketch.registerPlugin(plugin)
        #expect(sketch.plugin(id: "sketch-remove") != nil)

        sketch.removePlugin(id: "sketch-remove")
        #expect(sketch.plugin(id: "sketch-remove") == nil)
        #expect(plugin.detached == true)
    }
}

// MARK: - Test Sketch

@MainActor
private final class TestSketch: Sketch {
    init() {}
    var config: SketchConfig { SketchConfig(width: 64, height: 64) }
}
