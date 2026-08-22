import CMetaphorIPC
import Foundation
import Metal
import os
import QuartzCore

// MARK: - ViewerWorld

/// viewer frame IPC の 1 世代ぶんの共有メモリ（匿名 POSIX shm）と、それを GPU から書くための
/// `MTLBuffer(bytesNoCopy:)`。
///
/// 親へは `hello` で fd を渡す。名前は作成時に捨ててあるので（`metaphor_shm_open_anon`）、
/// fd を持つ 2 プロセス以外から到達できず、両者が mapping を手放せば自動的に解放される。
/// resize で新しい world に差し替えたあとも、進行中の blit の完了ハンドラが旧 world を
/// 握っている間は mapping を生かす（`deinit` で `munmap` + `close`）。
final class ViewerWorld: @unchecked Sendable {
    enum Failure: Error, CustomStringConvertible {
        case shmOpen(errno: Int32)
        case ftruncate(errno: Int32)
        case mmap(errno: Int32)
        case makeBuffer

        var description: String {
            switch self {
            case .shmOpen(let errno): return "shm_open failed: \(String(cString: strerror(errno)))"
            case .ftruncate(let errno): return "ftruncate failed: \(String(cString: strerror(errno)))"
            case .mmap(let errno): return "mmap failed: \(String(cString: strerror(errno)))"
            case .makeBuffer: return "MTLDevice.makeBuffer(bytesNoCopy:) rejected the shared memory mapping"
            }
        }
    }

    let layout: ViewerFrameLayout
    let fd: Int32
    private let base: UnsafeMutableRawPointer
    private var bufferStorage: MTLBuffer?

    /// GPU の blit 先。
    var buffer: MTLBuffer { bufferStorage! }

    init(device: MTLDevice, layout: ViewerFrameLayout) throws {
        let fd = metaphor_shm_open_anon()
        guard fd >= 0 else { throw Failure.shmOpen(errno: errno) }
        // サイズは作成時の 1 回だけ決められる（macOS では 2 回目の ftruncate が EINVAL）。
        guard ftruncate(fd, off_t(layout.totalBytes)) == 0 else {
            let saved = errno
            Darwin.close(fd)
            throw Failure.ftruncate(errno: saved)
        }
        guard let base = mmap(nil, layout.totalBytes, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0),
              base != MAP_FAILED
        else {
            let saved = errno
            Darwin.close(fd)
            throw Failure.mmap(errno: saved)
        }
        // page 境界・page の倍数の長さ（layout が保証）なので bytesNoCopy が受け付ける。
        guard let buffer = device.makeBuffer(
            bytesNoCopy: base, length: layout.totalBytes, options: .storageModeShared, deallocator: nil
        ) else {
            munmap(base, layout.totalBytes)
            Darwin.close(fd)
            throw Failure.makeBuffer
        }
        buffer.label = "metaphor.viewer.frames"
        self.layout = layout
        self.fd = fd
        self.base = base
        self.bufferStorage = buffer
    }

    deinit {
        // MTLBuffer を先に手放してから mapping を外す（bytesNoCopy の裏メモリを先に消さない）。
        bufferStorage = nil
        munmap(base, layout.totalBytes)
        Darwin.close(fd)
    }
}

// MARK: - ViewerOutputPlugin

/// `metaphor watch --viewer` のライブビューア（親プロセス）へ最終フレームを送る出力プラグイン
/// （CONTRACT.md 契約点 5 / ADR-0014）。
///
/// 環境変数 `METAPHOR_VIEWER_SOCKET` に親が listen している Unix domain socket のパスがあれば、
/// `SketchRunner` が `ViewerOutputProvider` 経由で自動登録します（`InputInjectionPlugin` /
/// `MetaphorProbePlugin` と同列の開発ツール用プラグイン。通常の `swift run` では登録されず、
/// フレームループのコストはゼロ）。
///
/// ## 動き
///
/// - `onAttach(renderer:)` で socket に接続する。接続できなければ警告 1 行を出し、以後 ``post(texture:commandBuffer:)``
///   は何もしない（Probe など他の観測手段はそのまま動く）
/// - 最初の `post()` で出力テクスチャの幅高から共有メモリ（3 slot）を作り、fd を添えた `hello` を送る。
///   以後テクスチャの幅高が変わるたびに新しい共有メモリ + `hello` を送る（resize）
/// - 毎フレーム、親が握っていない slot へ最終テクスチャを GPU blit し、command buffer の完了ハンドラから
///   `frame {slot, seq, frameCount, time}` を送る。3 枚とも親が握っていれば（親の読みが遅い）そのフレームは
///   送らない = latest-wins。描画そのものは止めない
/// - 親からの `release {slot}` は受信スレッドで受けて slot を空きに戻す。親が切断したら送信をやめる
///
/// slot の中身は `bgra8Unorm` / premultiplied alpha / row 0 = top（無変換で blit する。ADR-0012）。
@MainActor
public final class ViewerOutputPlugin: MetaphorOutputPlugin {
    /// 安定したプラグイン識別子（provider の id と同じ。nonisolated なので provider からも読める）。
    public nonisolated static let id = "org.metaphor.viewer-output"

    public let pluginID: String

    /// 親が listen している socket のパス（`METAPHOR_VIEWER_SOCKET`）。
    public let socketPath: String

    private weak var renderer: MetaphorRenderer?
    private var device: MTLDevice?
    private var transport: ViewerTransport?
    private var world: ViewerWorld?
    private let slots = ViewerSlotState()
    /// 受信スレッドが EOF / エラーを見たら立てる（メインアクターは次の `post()` で片付ける）。
    private let parentDisconnected = OSAllocatedUnfairLock(initialState: false)
    private var warnedUnsupportedFormat = false

    /// 接続できていて、`post()` がフレームを送る状態か（テスト用）。
    var isConnected: Bool { transport != nil }

    /// - Parameter socketPath: 親が listen している Unix domain socket のパス。
    public init(socketPath: String) {
        self.pluginID = Self.id
        self.socketPath = socketPath
    }

    // MARK: Lifecycle

    public func onAttach(renderer: MetaphorRenderer) {
        self.renderer = renderer
        self.device = renderer.device
        do {
            let transport = try ViewerTransport(connectingTo: socketPath)
            self.transport = transport
            let slots = self.slots
            let disconnected = self.parentDisconnected
            transport.startReader(
                onRelease: { slot in slots.release(slot: slot) },
                onDisconnect: { disconnected.withLock { $0 = true } }
            )
        } catch {
            // 出力先が無いまま黙って回り続けないよう 1 行だけ残す。スケッチは止めない。
            metaphorWarning(
                "viewer: could not connect to METAPHOR_VIEWER_SOCKET (\(socketPath)): \(error). "
                + "Frames will not be sent to the live viewer."
            )
        }
    }

    public func onDetach() {
        if let transport {
            if let bye = try? ViewerFrameIPC.encodeLine(ViewerFrameIPC.Bye()) {
                transport.send(bye)
            }
            transport.close()
        }
        tearDown()
    }

    // MARK: Output phase

    public func post(texture: MTLTexture, commandBuffer: MTLCommandBuffer) {
        guard let transport, let device else { return }

        if parentDisconnected.withLock({ $0 }) {
            metaphorDiagnostic("viewer: parent closed the socket; stopping frame output")
            tearDown()
            return
        }

        guard texture.pixelFormat == .bgra8Unorm else {
            if !warnedUnsupportedFormat {
                warnedUnsupportedFormat = true
                metaphorWarning(
                    "viewer: output texture format \(texture.pixelFormat) is not supported by the "
                    + "live viewer transport (bgra8Unorm only); frames will not be sent"
                )
            }
            return
        }

        // world（共有メモリ）は最初の post で遅延生成し、幅高が変わったら作り直す（= resize）。
        if world == nil || world?.layout.width != texture.width || world?.layout.height != texture.height {
            guard let fresh = makeWorld(device: device, width: texture.width, height: texture.height) else {
                tearDown()
                return
            }
            slots.reset()
            world = fresh
            let hello = ViewerFrameIPC.Hello(
                pid: Int(getpid()), metaphor: Metaphor.version, layout: fresh.layout
            )
            guard let line = try? ViewerFrameIPC.encodeLine(hello), transport.send(line, attachingFD: fresh.fd) else {
                metaphorDiagnostic("viewer: could not send hello; stopping frame output")
                tearDown()
                return
            }
        }
        guard let world, let ticket = slots.acquire() else {
            // 3 枚とも親が握っている（か GPU が書いている）: このフレームは送らない。
            return
        }

        guard let blit = commandBuffer.makeBlitCommandEncoder() else {
            slots.abandon(ticket)
            return
        }
        blit.label = "metaphor.viewer.blit"
        blit.copy(
            from: texture,
            sourceSlice: 0,
            sourceLevel: 0,
            sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
            sourceSize: MTLSize(width: texture.width, height: texture.height, depth: 1),
            to: world.buffer,
            destinationOffset: world.layout.offset(slot: ticket.slot),
            destinationBytesPerRow: world.layout.bytesPerRow,
            destinationBytesPerImage: world.layout.slotBytes
        )
        blit.endEncoding()

        let frameCount = Int(truncatingIfNeeded: renderer?.frameToken ?? 0)
        let slots = self.slots
        let keepAlive = world
        commandBuffer.addCompletedHandler { _ in
            // 旧世代（resize 後）や切断後の完了は seq が付かず捨てられる。
            guard let seq = slots.complete(ticket) else { return }
            let frame = ViewerFrameIPC.Frame(
                slot: ticket.slot, seq: seq, frameCount: frameCount, time: CACurrentMediaTime()
            )
            if let line = try? ViewerFrameIPC.encodeLine(frame) {
                transport.send(line)
            }
            withExtendedLifetime(keepAlive) {}
        }
    }

    // MARK: Helpers

    private func makeWorld(device: MTLDevice, width: Int, height: Int) -> ViewerWorld? {
        let layout = ViewerFrameLayout(
            width: width,
            height: height,
            linearAlignment: device.minimumLinearTextureAlignment(for: .bgra8Unorm),
            pageSize: Int(getpagesize())
        )
        do {
            return try ViewerWorld(device: device, layout: layout)
        } catch {
            metaphorWarning("viewer: could not create shared frame memory (\(layout.totalBytes) bytes): \(error)")
            return nil
        }
    }

    /// 送信をやめる（切断・失敗・detach）。共有メモリは進行中の blit が終われば解放される。
    private func tearDown() {
        transport?.close()
        transport = nil
        world = nil
        slots.reset()
    }
}

// MARK: - ViewerOutputProvider

/// `METAPHOR_VIEWER_SOCKET` があれば ``ViewerOutputPlugin`` を返す Core 内蔵の出力 provider。
///
/// `SketchRunner` が起動時に登録する（同じ id の再登録は置換なので何度呼んでも 1 つ）。
/// セカンダリウィンドウ（`SketchWindow`）はビューアに出さない（現状どおり・非目標）。
struct ViewerOutputProvider: MetaphorOutputProvider {
    static let providerID = ViewerOutputPlugin.id

    var id: String { Self.providerID }
    /// 親が受ける側なので、ウィンドウが隠れても送り続ける（ヘッドレスでは元々タイマー）。
    let requirements: PluginRequirements = [.externalRenderLoop]

    @MainActor
    func makeOutput(context: MetaphorOutputContext) -> MetaphorOutputPlugin? {
        guard case .primary = context.scope,
              let path = context.environment["METAPHOR_VIEWER_SOCKET"], !path.isEmpty
        else { return nil }
        return ViewerOutputPlugin(socketPath: path)
    }

    /// `MetaphorOutputProviders` へ登録する（冪等）。
    static func register() {
        MetaphorOutputProviders.register(ViewerOutputProvider())
    }
}
