import CMetaphorIPC
import Foundation

/// viewer frame IPC の socket（`AF_UNIX` / `SOCK_STREAM`）を子側から扱う薄い層。
///
/// 接続・送信・受信スレッドだけを持ち、プロトコルの意味（slot の同期）は ``ViewerOutputPlugin`` /
/// ``ViewerSlotState`` が持つ。送信は **メインアクター（`hello`）・command buffer の完了ハンドラ
/// （`frame`）・受信スレッド**の 3 箇所から呼ばれるのでロックで直列化する。
///
/// 親が読まなくなったときにレンダーループを巻き込まないよう、送信には短いタイムアウトを
/// 付け（`SO_SNDTIMEO`）、失敗は `false` で返して呼び出し側に「切断」と判断させる。
/// `SIGPIPE` は `SO_NOSIGPIPE` で抑止する（親の死でスケッチが落ちない）。
final class ViewerTransport: @unchecked Sendable {
    enum Failure: Error, CustomStringConvertible {
        case pathTooLong(Int)
        case socket(errno: Int32)
        case connect(errno: Int32)

        var description: String {
            switch self {
            case .pathTooLong(let count):
                return "socket path is \(count) bytes; sun_path allows at most \(ViewerTransport.maxPathBytes)"
            case .socket(let errno):
                return "socket() failed: \(String(cString: strerror(errno)))"
            case .connect(let errno):
                return "connect() failed: \(String(cString: strerror(errno)))"
            }
        }
    }

    /// `sockaddr_un.sun_path` は 104 byte で、終端の NUL を除いた上限。
    static let maxPathBytes = 103

    private let fd: Int32
    private let lock = NSLock()
    private var closed = false
    private var readerStarted = false

    /// `path` の Unix domain socket へ接続する（親が先に `bind` + `listen` している前提）。
    init(connectingTo path: String) throws {
        let bytes = Array(path.utf8)
        guard bytes.count <= Self.maxPathBytes else { throw Failure.pathTooLong(bytes.count) }

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw Failure.socket(errno: errno) }

        var one: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        var timeout = timeval(tv_sec: 1, tv_usec: 0)
        _ = setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                Darwin.connect(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else {
            let saved = errno
            Darwin.close(fd)
            throw Failure.connect(errno: saved)
        }
        self.fd = fd
    }

    deinit {
        close()
    }

    // MARK: - 送信

    /// 1 行（末尾 `\n` 込み）を送る。`attachingFD` があれば最初の `sendmsg` に `SCM_RIGHTS` で添える。
    /// 部分送信は続きを送り、失敗（切断・タイムアウト）は `false`。
    @discardableResult
    func send(_ line: Data, attachingFD attached: Int32? = nil) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !closed else { return false }

        return line.withUnsafeBytes { raw -> Bool in
            guard var cursor = raw.baseAddress else { return true }
            var remaining = raw.count
            var pendingFD = attached
            while remaining > 0 {
                let sent: Int
                if let fd = pendingFD {
                    sent = metaphor_send_fd(self.fd, fd, cursor, remaining)
                } else {
                    sent = Darwin.write(self.fd, cursor, remaining)
                }
                if sent < 0 {
                    if errno == EINTR { continue }
                    return false
                }
                pendingFD = nil
                cursor += sent
                remaining -= sent
            }
            return true
        }
    }

    // MARK: - 受信

    /// 受信スレッドを起動する（1 回だけ）。`release {slot}` ごとに `onRelease`、EOF / エラーで `onDisconnect`。
    /// 未知の `t` と不正な行は読み飛ばす（`METAPHOR_DEBUG=1` のときだけ診断を出す）。
    func startReader(
        onRelease: @escaping @Sendable (Int) -> Void,
        onDisconnect: @escaping @Sendable () -> Void
    ) {
        lock.lock()
        let alreadyStarted = readerStarted
        readerStarted = true
        lock.unlock()
        guard !alreadyStarted else { return }

        let fd = self.fd
        let thread = Thread {
            var buffer = [UInt8](repeating: 0, count: 4096)
            var pending = Data()
            reading: while true {
                let count = buffer.withUnsafeMutableBytes { raw in
                    Darwin.read(fd, raw.baseAddress, raw.count)
                }
                if count < 0 && errno == EINTR { continue }
                if count <= 0 { break reading }
                pending.append(contentsOf: buffer[0..<count])
                while let newline = pending.firstIndex(of: 0x0A) {
                    let lineData = pending[pending.startIndex..<newline]
                    pending.removeSubrange(pending.startIndex...newline)
                    guard let line = String(data: lineData, encoding: .utf8), !line.isEmpty else { continue }
                    switch ViewerFrameIPC.decodeIncoming(line) {
                    case .release(let slot):
                        onRelease(slot)
                    case .unknown(let t):
                        metaphorDiagnostic("viewer: unknown message '\(t)' ignored")
                    case nil:
                        metaphorDiagnostic("viewer: malformed line ignored: \(line)")
                    }
                }
            }
            onDisconnect()
        }
        thread.name = "metaphor.viewer-output.reader"
        thread.stackSize = 1 << 16
        thread.start()
    }

    // MARK: - 終了

    /// 両方向を閉じる（受信スレッドは EOF で抜ける）。複数回呼んでも安全。
    func close() {
        lock.lock()
        defer { lock.unlock() }
        guard !closed else { return }
        closed = true
        _ = Darwin.shutdown(fd, SHUT_RDWR)
        _ = Darwin.close(fd)
    }
}
