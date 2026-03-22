import Metal

/// 動的に拡張可能なトリプルバッファリング GPU バッファ。
///
/// 小さな初期容量から開始し、必要に応じて倍増することで、
/// Canvas2D の起動時メモリを約57MBから約300KBに削減します。
///
/// - Parameter T: 要素ごとのデータ型（例: `Vertex2D`、`TexturedVertex2D`）。
@MainActor
final class GrowableGPUBuffer<T> {

    static var bufferCount: Int { 3 }

    private let device: MTLDevice
    private let label: String
    private let maxCapacity: Int

    /// トリプルバッファリングストレージ。
    private(set) var buffers: [MTLBuffer]
    private(set) var pointers: [UnsafeMutablePointer<T>]

    /// バッファあたりの現在の要素容量。
    private(set) var capacity: Int

    /// トリプルバッファリングされたストレージで新しい拡張可能バッファを作成します。
    ///
    /// - Parameters:
    ///   - device: Metal デバイス。
    ///   - initialCapacity: 開始要素数（デフォルト 4096）。
    ///   - maxCapacity: 拡張の上限（デフォルト 1,000,000）。
    ///   - label: GPU バッファのラベルプレフィックス。
    init(
        device: MTLDevice,
        initialCapacity: Int = 4096,
        maxCapacity: Int = 1_000_000,
        label: String = "metaphor.growable"
    ) throws {
        self.device = device
        self.label = label
        self.maxCapacity = maxCapacity
        self.capacity = initialCapacity

        let stride = MemoryLayout<T>.stride
        let bufferSize = initialCapacity * stride
        var bufs: [MTLBuffer] = []
        var ptrs: [UnsafeMutablePointer<T>] = []
        for i in 0..<Self.bufferCount {
            guard let buf = device.makeBuffer(length: bufferSize, options: .storageModeShared) else {
                throw MetaphorError.bufferCreationFailed(size: bufferSize)
            }
            buf.label = "\(label).\(i)"
            bufs.append(buf)
            ptrs.append(buf.contents().bindMemory(to: T.self, capacity: initialCapacity))
        }
        self.buffers = bufs
        self.pointers = ptrs
    }

    /// 指定されたトリプルバッファインデックスのバッファ。
    func buffer(for index: Int) -> MTLBuffer {
        buffers[index % Self.bufferCount]
    }

    /// 指定されたトリプルバッファインデックスのポインタ。
    func pointer(for index: Int) -> UnsafeMutablePointer<T> {
        pointers[index % Self.bufferCount]
    }

    /// バッファが少なくとも `needed` 個の要素を保持できることを保証します。
    ///
    /// 現在の容量が不足している場合、3つのバッファすべてを現在の容量の2倍で
    /// 再割り当てします（`maxCapacity` で上限）。
    /// 指定されたバッファインデックスの既存データは新しいバッファにコピーされます。
    ///
    /// - Parameters:
    ///   - needed: 必要な最小要素数。
    ///   - activeIndex: 現在アクティブなバッファインデックス（データコピー用）。
    ///   - usedCount: 保存する既存データの要素数。
    /// - Returns: 拡張が成功または不要な場合は `true`、最大容量に達した場合は `false`。
    @discardableResult
    func ensureCapacity(_ needed: Int, activeIndex: Int, usedCount: Int) -> Bool {
        guard needed > capacity else { return true }
        guard needed <= maxCapacity else { return false }

        var newCapacity = capacity
        while newCapacity < needed {
            newCapacity = min(newCapacity * 2, maxCapacity)
        }

        let stride = MemoryLayout<T>.stride
        let newSize = newCapacity * stride

        var newBuffers: [MTLBuffer] = []
        var newPointers: [UnsafeMutablePointer<T>] = []

        for i in 0..<Self.bufferCount {
            guard let buf = device.makeBuffer(length: newSize, options: .storageModeShared) else {
                return false
            }
            buf.label = "\(label).\(i)"
            let ptr = buf.contents().bindMemory(to: T.self, capacity: newCapacity)

            // アクティブなバッファの既存データをコピー
            if i == (activeIndex % Self.bufferCount) && usedCount > 0 {
                ptr.update(from: pointers[i], count: usedCount)
            }

            newBuffers.append(buf)
            newPointers.append(ptr)
        }

        buffers = newBuffers
        pointers = newPointers
        capacity = newCapacity
        return true
    }
}
