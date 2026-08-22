import Foundation

/// viewer frame IPC（CONTRACT.md 契約点 5）の共有メモリのレイアウト（純粋な値）。
///
/// 1 世代の共有メモリには `slots` 枚の slot が page 境界で並ぶ。親はこの値を `hello` で受け取り、
/// `MTLBuffer.makeTexture(descriptor:offset:bytesPerRow:)` に `offset(slot:)` と `bytesPerRow` を
/// そのまま渡して linear texture として読む。
///
/// - `bytesPerRow = alignUp(width × 4, linearAlignment)` — `device.minimumLinearTextureAlignment(for: .bgra8Unorm)`
/// - `slotBytes = alignUp(bytesPerRow × height, pageSize)` — slot の先頭を page 境界に置くことで
///   `makeTexture(offset:)` の alignment 要件を満たし、`makeBuffer(bytesNoCopy:)` の長さ要件
///   （page の倍数）も全長で満たす
struct ViewerFrameLayout: Equatable, Sendable {
    /// v1 の slot 枚数。1 枚は tearing、2 枚は親の GPU 読みが 1 frame 遅れると競合するので 3。
    static let slotCount = 3

    let width: Int
    let height: Int
    let bytesPerRow: Int
    let slotBytes: Int
    let slots: Int

    /// 共有メモリの全長（`ftruncate` / `fstat` で突き合わせる値）。
    var totalBytes: Int { slotBytes * slots }

    /// - Parameters:
    ///   - width: キャンバスの幅（px）。
    ///   - height: キャンバスの高さ（px）。
    ///   - linearAlignment: linear texture の行 alignment（`minimumLinearTextureAlignment(for:)`）。
    ///   - pageSize: `getpagesize()`。
    ///   - slots: slot 枚数（既定 ``slotCount``）。
    init(width: Int, height: Int, linearAlignment: Int, pageSize: Int, slots: Int = ViewerFrameLayout.slotCount) {
        precondition(width > 0 && height > 0, "viewer frame layout needs a non-empty canvas")
        precondition(linearAlignment > 0 && pageSize > 0 && slots > 0)
        self.width = width
        self.height = height
        self.bytesPerRow = Self.alignUp(width * 4, to: linearAlignment)
        self.slotBytes = Self.alignUp(bytesPerRow * height, to: pageSize)
        self.slots = slots
    }

    /// slot の先頭 offset（byte）。
    func offset(slot: Int) -> Int {
        precondition(slot >= 0 && slot < slots, "slot out of range")
        return slot * slotBytes
    }

    /// `value` を `alignment` の倍数へ切り上げる。
    static func alignUp(_ value: Int, to alignment: Int) -> Int {
        let remainder = value % alignment
        return remainder == 0 ? value : value + (alignment - remainder)
    }
}
