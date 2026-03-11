import Metal

/// A dynamically-growing triple-buffered GPU buffer.
///
/// Starts with a small initial capacity and doubles on demand,
/// reducing startup memory from ~57MB to ~300KB for Canvas2D.
///
/// - Parameter T: The per-element data type (e.g., `Vertex2D`, `TexturedVertex2D`).
@MainActor
final class GrowableGPUBuffer<T> {

    static var bufferCount: Int { 3 }

    private let device: MTLDevice
    private let label: String
    private let maxCapacity: Int

    /// Triple-buffered storage.
    private(set) var buffers: [MTLBuffer]
    private(set) var pointers: [UnsafeMutablePointer<T>]

    /// Current element capacity per buffer.
    private(set) var capacity: Int

    /// Creates a new growable buffer with triple-buffered storage.
    ///
    /// - Parameters:
    ///   - device: The Metal device.
    ///   - initialCapacity: Starting element count (default 4096).
    ///   - maxCapacity: Upper bound for growth (default 1,000,000).
    ///   - label: Label prefix for GPU buffers.
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

    /// The buffer for the given triple-buffer index.
    func buffer(for index: Int) -> MTLBuffer {
        buffers[index % Self.bufferCount]
    }

    /// The pointer for the given triple-buffer index.
    func pointer(for index: Int) -> UnsafeMutablePointer<T> {
        pointers[index % Self.bufferCount]
    }

    /// Ensures the buffer can hold at least `needed` elements.
    ///
    /// If current capacity is insufficient, reallocates all three buffers
    /// at double the current capacity (capped at `maxCapacity`).
    /// Existing data in the specified buffer index is copied to the new buffer.
    ///
    /// - Parameters:
    ///   - needed: The minimum number of elements required.
    ///   - activeIndex: The currently active buffer index (for data copy).
    ///   - usedCount: How many elements of existing data to preserve.
    /// - Returns: `true` if growth succeeded or was unnecessary, `false` if at max capacity.
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

            // Copy existing data for the active buffer
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
