import Foundation
import Testing
import Metal
import AppKit
@testable import metaphor
@testable import MetaphorCore

// MARK: - Asset Cache (#284)

@Suite("AssetCache", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct AssetCacheTests {

    /// テスト用の小さな PNG をテンポラリに書き出してパスを返す
    private func writeTempPNG(name: String) throws -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("metaphor-assetcache-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let image = NSImage(size: NSSize(width: 4, height: 4), flipped: false) { rect in
            NSColor.red.setFill()
            rect.fill()
            return true
        }
        let tiff = image.tiffRepresentation!
        let png = NSBitmapImageRep(data: tiff)!.representation(using: .png, properties: [:])!
        let path = dir.appendingPathComponent("\(name).png").path
        try png.write(to: URL(fileURLWithPath: path))
        return path
    }

    private func makeContext() throws -> SketchContext {
        let renderer = try MetaphorRenderer(width: 32, height: 32)
        return SketchContext(
            renderer: renderer,
            canvas: try Canvas2D(renderer: renderer),
            canvas3D: try Canvas3D(renderer: renderer),
            input: renderer.input
        )
    }

    @Test("same path returns the identical MImage instance")
    func imageIdentity() throws {
        let context = try makeContext()
        let path = try writeTempPNG(name: "a")
        let first = try context.loadImage(path)
        let second = try context.loadImage(path)
        #expect(first === second)
        #expect(context.assetCache.imageCount == 1)
    }

    @Test("cache false bypasses and returns an independent copy")
    func cacheBypass() throws {
        let context = try makeContext()
        let path = try writeTempPNG(name: "b")
        let cached = try context.loadImage(path)
        let independent = try context.loadImage(path, cache: false)
        #expect(cached !== independent)
        // バイパス読込はキャッシュを上書きしない
        #expect(try context.loadImage(path) === cached)
    }

    @Test("relative and absolute spellings of the same path share one entry")
    func pathNormalization() throws {
        let context = try makeContext()
        let path = try writeTempPNG(name: "c")
        // "/dir/./c.png" と "/dir/c.png" は同一キーに正規化される
        let dotted = (path as NSString).deletingLastPathComponent + "/./" + (path as NSString).lastPathComponent
        let first = try context.loadImage(path)
        let second = try context.loadImage(dotted)
        #expect(first === second)
        #expect(context.assetCache.imageCount == 1)
    }

    @Test("clearCaches evicts cached assets")
    func clearCaches() throws {
        let context = try makeContext()
        let path = try writeTempPNG(name: "d")
        let first = try context.loadImage(path)
        context.clearCaches()
        #expect(context.assetCache.imageCount == 0)
        let second = try context.loadImage(path)
        #expect(first !== second)
    }

    @Test("async load returns the cached instance for the same path")
    func asyncSharesCache() async throws {
        let context = try makeContext()
        let path = try writeTempPNG(name: "e")
        let sync = try context.loadImage(path)
        let async = try await context.loadImageAsync(path)
        #expect(sync === async)
    }

    @Test("LRU evicts the least recently used entry beyond capacity")
    func lruEviction() throws {
        let cache = AssetCache(capacity: 2)
        let device = MTLCreateSystemDefaultDevice()!
        let img1 = MImage.createImage(2, 2, device: device)!
        let img2 = MImage.createImage(2, 2, device: device)!
        let img3 = MImage.createImage(2, 2, device: device)!

        cache.store(img1, forPath: "/a.png")
        cache.store(img2, forPath: "/b.png")
        _ = cache.image(forPath: "/a.png")  // a をタッチ → b が最古に
        cache.store(img3, forPath: "/c.png")

        #expect(cache.imageCount == 2)
        #expect(cache.image(forPath: "/a.png") === img1)
        #expect(cache.image(forPath: "/b.png") == nil)
        #expect(cache.image(forPath: "/c.png") === img3)
    }

    @Test("mesh cache keys include the normalize flag")
    func meshNormalizeKey() throws {
        let cache = AssetCache(capacity: 4)
        let device = MTLCreateSystemDefaultDevice()!
        let mesh = try Mesh.box(device: device)
        cache.store(mesh, forPath: "/m.obj", normalize: true)
        #expect(cache.mesh(forPath: "/m.obj", normalize: true) === mesh)
        #expect(cache.mesh(forPath: "/m.obj", normalize: false) == nil)
    }
}
