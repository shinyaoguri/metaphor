import CMetaphorIPC
import Foundation
import Metal
import Testing
@testable import MetaphorCore
import MetaphorTestSupport

// MARK: - Fake parent (in-process viewer)

/// metaphor-cli のライブビューア（親）の役をテスト内で演じる: 一時ディレクトリの Unix socket を
/// listen し、`hello`（+ `SCM_RIGHTS` の fd）/ `frame` を読み、`release` を返す。
/// CONTRACT.md 契約点 5 の consumer 側を最小限に写したもの（cli の実装とは独立）。
final class FakeViewerParent: @unchecked Sendable {
    let path: String
    private let listenFD: Int32
    private var connectionFD: Int32 = -1
    private var pending = Data()
    /// 直近に受け取った共有メモリの fd（`hello` に添えられる）。
    private(set) var receivedFD: Int32 = -1

    init() throws {
        // sun_path の上限（103 byte）に収まる短いパス。
        let name = "mp-\(getpid())-\(UInt32.random(in: 0...0xFFFF_FFFF)).sock"
        path = FileManager.default.temporaryDirectory.appendingPathComponent(name).path
        unlink(path)
        listenFD = socket(AF_UNIX, SOCK_STREAM, 0)
        try #require(listenFD >= 0)
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(listenFD, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        try #require(bound == 0, "bind failed: \(String(cString: strerror(errno)))")
        try #require(listen(listenFD, 1) == 0)
    }

    /// 子の connect を受ける（connect は子の `onAttach` で同期に済んでいるので backlog から即返る）。
    func accept(timeout: TimeInterval = 2) throws {
        try #require(Self.wait(fd: listenFD, timeout: timeout), "no connection within \(timeout)s")
        connectionFD = Darwin.accept(listenFD, nil, nil)
        try #require(connectionFD >= 0)
    }

    /// 次の 1 行（JSON）を読む。`timeout` 以内に来なければ `nil`。
    func nextLine(timeout: TimeInterval = 2) throws -> [String: Any]? {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            if let newline = pending.firstIndex(of: 0x0A) {
                let lineData = pending[pending.startIndex..<newline]
                pending.removeSubrange(pending.startIndex...newline)
                let object = try JSONSerialization.jsonObject(with: Data(lineData))
                return try #require(object as? [String: Any])
            }
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0, Self.wait(fd: connectionFD, timeout: remaining) else { return nil }
            var buffer = [UInt8](repeating: 0, count: 4096)
            var fd: Int32 = -1
            let count = buffer.withUnsafeMutableBytes { raw in
                metaphor_recv_fd(connectionFD, raw.baseAddress, raw.count, &fd)
            }
            if fd >= 0 { receivedFD = fd }
            guard count > 0 else { return nil }
            pending.append(contentsOf: buffer[0..<count])
        }
    }

    func send(_ object: [String: Any]) throws {
        var data = try JSONSerialization.data(withJSONObject: object)
        data.append(0x0A)
        let written = data.withUnsafeBytes { raw in Darwin.write(connectionFD, raw.baseAddress, raw.count) }
        try #require(written == data.count)
    }

    func release(slot: Int) throws {
        try send(["t": "release", "slot": slot])
    }

    func close() {
        if connectionFD >= 0 { Darwin.close(connectionFD); connectionFD = -1 }
        Darwin.close(listenFD)
        unlink(path)
    }

    /// `fd` が読めるようになるまで待つ（poll）。
    private static func wait(fd: Int32, timeout: TimeInterval) -> Bool {
        var descriptor = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
        let result = poll(&descriptor, 1, Int32(max(0, timeout * 1000)))
        return result > 0
    }
}

/// 共有メモリの fd を読み取り専用で mmap し、slot の先頭ピクセル（BGRA）を返す。
private func readFirstPixel(fd: Int32, layout: (slotBytes: Int, totalBytes: Int), slot: Int) throws -> [UInt8] {
    var info = stat()
    try #require(fstat(fd, &info) == 0)
    #expect(Int(info.st_size) == layout.totalBytes, "fstat のサイズが hello の slotBytes*slots と一致する")
    let base = try #require(mmap(nil, layout.totalBytes, PROT_READ, MAP_SHARED, fd, 0))
    try #require(base != MAP_FAILED)
    defer { munmap(base, layout.totalBytes) }
    let pixel = base.advanced(by: slot * layout.slotBytes).assumingMemoryBound(to: UInt8.self)
    return [pixel[0], pixel[1], pixel[2], pixel[3]]
}

// MARK: - Tests

@Suite("ViewerOutputPlugin（fake 親との end-to-end）", .serialized, .enabled(if: MetalTestHelper.isGPUAvailable))
@MainActor
struct ViewerOutputPluginTests {

    private func makeRenderer() throws -> MetaphorRenderer {
        let renderer = try MetaphorRenderer(width: 64, height: 48)
        // BGRA premultiplied で 33 66 cc ff（spike と同じ色）。
        renderer.setClearColor(0.8, 0.4, 0.2, 1.0)
        return renderer
    }

    @Test("接続 → hello（fd 付き・サイズ一致）→ frame が届き、slot のピクセルが clear color と一致する")
    func helloThenFrame() throws {
        let parent = try FakeViewerParent()
        defer { parent.close() }
        let renderer = try makeRenderer()
        let plugin = ViewerOutputPlugin(socketPath: parent.path)
        renderer.addPlugin(plugin)
        #expect(plugin.isConnected)
        try parent.accept()

        renderer.renderFrame()

        let hello = try #require(try parent.nextLine())
        #expect(hello["t"] as? String == "hello")
        #expect(hello["protocolVersion"] as? Int == 1)
        #expect(hello["width"] as? Int == 64)
        #expect(hello["height"] as? Int == 48)
        #expect(hello["pixelFormat"] as? String == "bgra8Unorm")
        #expect(hello["orientation"] as? String == "topLeft")
        #expect(hello["metaphor"] as? String == Metaphor.version)
        #expect(parent.receivedFD >= 0, "hello に共有メモリの fd が SCM_RIGHTS で添えられる")
        let slotBytes = try #require(hello["slotBytes"] as? Int)
        let slots = try #require(hello["slots"] as? Int)
        #expect(slots == 3)

        let frame = try #require(try parent.nextLine())
        #expect(frame["t"] as? String == "frame")
        #expect(frame["slot"] as? Int == 0)
        #expect(frame["seq"] as? Int == 0)
        #expect((frame["frameCount"] as? Int ?? 0) >= 1)
        #expect((frame["time"] as? Double ?? -1) >= 0)

        let pixel = try readFirstPixel(
            fd: parent.receivedFD, layout: (slotBytes, slotBytes * slots), slot: 0
        )
        #expect(pixel == [0x33, 0x66, 0xCC, 0xFF], "BGRA premultiplied の clear color がそのまま slot にある")
    }

    @Test("3 枚とも親が握ると publish を飛ばし、release で再開する")
    func backpressure() throws {
        let parent = try FakeViewerParent()
        defer { parent.close() }
        let renderer = try makeRenderer()
        renderer.addPlugin(ViewerOutputPlugin(socketPath: parent.path))
        try parent.accept()

        renderer.renderFrame()
        _ = try #require(try parent.nextLine())          // hello
        var slotsSeen: [Int] = []
        slotsSeen.append(try #require(try parent.nextLine())["slot"] as? Int ?? -1)
        renderer.renderFrame()
        slotsSeen.append(try #require(try parent.nextLine())["slot"] as? Int ?? -1)
        renderer.renderFrame()
        slotsSeen.append(try #require(try parent.nextLine())["slot"] as? Int ?? -1)
        #expect(slotsSeen == [0, 1, 2])

        // 4 枚目: 親が 3 枚とも握っているので frame は来ない（描画は止まらない）。
        renderer.renderFrame()
        #expect(try parent.nextLine(timeout: 0.3) == nil)

        // release で空いた slot へ再開。seq は飛ばしたぶん進まない。
        try parent.release(slot: 1)
        // release は受信スレッド経由なので、反映されるまで 1 フレーム待つ余地を与える。
        for _ in 0..<20 {
            renderer.renderFrame()
            if let frame = try parent.nextLine(timeout: 0.1) {
                #expect(frame["slot"] as? Int == 1)
                #expect(frame["seq"] as? Int == 3)
                return
            }
        }
        Issue.record("release 後に frame が再開しなかった")
    }

    @Test("キャンバスの resize で新しい fd 付きの hello を再送する")
    func resizeResendsHello() throws {
        let parent = try FakeViewerParent()
        defer { parent.close() }
        let renderer = try makeRenderer()
        renderer.addPlugin(ViewerOutputPlugin(socketPath: parent.path))
        try parent.accept()

        renderer.renderFrame()
        _ = try #require(try parent.nextLine())          // hello
        _ = try #require(try parent.nextLine())          // frame
        let firstFD = parent.receivedFD

        renderer.resizeCanvas(width: 32, height: 32)
        renderer.renderFrame()
        let hello = try #require(try parent.nextLine())
        #expect(hello["t"] as? String == "hello")
        #expect(hello["width"] as? Int == 32)
        #expect(hello["height"] as? Int == 32)
        #expect(parent.receivedFD != firstFD, "新しい共有メモリの fd が添えられる")
        let frame = try #require(try parent.nextLine())
        #expect(frame["t"] as? String == "frame")
        #expect(frame["slot"] as? Int == 0, "新しい world では slot 0 から")
    }

    @Test("detach で bye を送り、socket を閉じる")
    func detachSendsBye() throws {
        let parent = try FakeViewerParent()
        defer { parent.close() }
        let renderer = try makeRenderer()
        renderer.addPlugin(ViewerOutputPlugin(socketPath: parent.path))
        try parent.accept()
        renderer.removePlugin(id: ViewerOutputPlugin.id)
        let bye = try #require(try parent.nextLine())
        #expect(bye["t"] as? String == "bye")
        #expect(try parent.nextLine(timeout: 0.5) == nil, "閉じた後は何も来ない（EOF）")
    }

    @Test("socket が無ければ警告 1 行で接続せず、post() は何もしない")
    func missingSocketIsInert() throws {
        let renderer = try makeRenderer()
        let plugin = ViewerOutputPlugin(socketPath: "/nonexistent/metaphor-viewer-test.sock")
        renderer.addPlugin(plugin)
        #expect(!plugin.isConnected)
        renderer.renderFrame()   // クラッシュしない・ハングしない
    }

    @Test("socket のパスが 103 byte を超えると接続しない")
    func pathTooLong() throws {
        let renderer = try makeRenderer()
        let long = "/tmp/" + String(repeating: "x", count: 120) + ".sock"
        let plugin = ViewerOutputPlugin(socketPath: long)
        renderer.addPlugin(plugin)
        #expect(!plugin.isConnected)
    }
}
