import Metal

/// A typed GPU buffer that both the CPU and the GPU can read and write.
///
/// It is allocated with `storageModeShared`, so on Apple silicon's unified memory the CPU and
/// the GPU address the same bytes with no copy.
///
/// ```swift
/// var positions = createBuffer(count: 1000, type: SIMD2<Float>.self)
/// positions![0] = SIMD2<Float>(100, 200)
/// ```
///
/// ## Reading back what a kernel wrote
///
/// A read placed right after a dispatch returns the contents from *before* the kernel ran —
/// no warning, no crash, just the old numbers:
///
/// ```swift
/// func compute() {
///     dispatch(kernel, threads: buffer.count) { enc in
///         enc.setBuffer(buffer.buffer, offset: 0, index: 0)
///     }
///     print(buffer[0])   // still the old value: the kernel has not run yet
/// }
/// ```
///
/// - Important: **Reading this buffer never waits for the GPU.** ``subscript(_:)``,
///   ``toArray()`` and ``contents`` hand back the shared memory exactly as it stands at that
///   instant. ``Sketch/dispatch(_:threads:configure:)`` only *encodes* the kernel into the
///   frame's command buffer, and the GPU does not begin until that buffer is committed, so a
///   value read later in the same `compute()` is the value from before the dispatch.
///
/// - Important: "Read it on the next frame" is not a guarantee either, because a command
///   buffer completes asynchronously. The one public API that does wait is
///   ``Sketch/loadPixels()``: on the normal path (shadows off, called from `draw()`) it
///   commits **the frame's command buffer, the same one that carried `compute()`**, and blocks
///   until the GPU finishes, so this frame's kernel writes are readable once it returns. Being
///   a pixel API it also brings its own render pass split (cleared depth, changed 2D/3D
///   stacking order), and with `enableShadows()` on it cannot split the pass at all and so
///   does **not** wait for this frame's compute.
///
/// - Note: Until a read back of its own exists (Issue #1136), the portable way to know that a
///   result has landed is to have the kernel write a sentinel of its own — a frame counter, a
///   "done" flag — and to read the payload only once the sentinel has changed. Comparing
///   values that are "probably one frame behind" instead counts the lag itself as a
///   disagreement.
@MainActor
public final class GPUBuffer<T> {
    /// The underlying Metal buffer.
    public let buffer: MTLBuffer

    /// The number of elements in the buffer.
    public let count: Int

    /// A typed pointer to the buffer contents.
    private let pointer: UnsafeMutablePointer<T>

    // MARK: - 初期化

    /// Creates an empty buffer of the given element count, zero filled.
    /// - Parameters:
    ///   - device: The Metal device to allocate the buffer on.
    ///   - count: The number of elements to allocate.
    public init?(device: MTLDevice, count: Int) {
        // 掛け算はガードの内側で行う。先に書くと、大きな count が `nil` ではなく
        // 算術オーバーフローの trap になり、Optional を返す契約が効かなくなる (#1091)。
        let (byteLength, overflow) = MemoryLayout<T>.stride.multipliedReportingOverflow(by: count)
        guard !overflow, byteLength > 0,
            let buffer = device.makeBuffer(length: byteLength, options: .storageModeShared)
        else {
            return nil
        }
        self.buffer = buffer
        self.count = count
        self.pointer = buffer.contents().bindMemory(to: T.self, capacity: count)
        memset(buffer.contents(), 0, byteLength)
    }

    /// Creates a buffer initialized with an array of elements.
    /// - Parameters:
    ///   - device: The Metal device to allocate the buffer on.
    ///   - data: The array of initial data to copy into the buffer.
    public init?(device: MTLDevice, data: [T]) {
        let count = data.count
        // `data.count` 由来なので溢れようがないが、掛け算をガードの内側に置く形は
        // `init?(device:count:)` と揃えておく (#1091)。
        let (byteLength, overflow) = MemoryLayout<T>.stride.multipliedReportingOverflow(by: count)
        guard !overflow, byteLength > 0,
            let buffer = device.makeBuffer(length: byteLength, options: .storageModeShared)
        else {
            return nil
        }
        self.buffer = buffer
        self.count = count
        self.pointer = buffer.contents().bindMemory(to: T.self, capacity: count)
        data.withUnsafeBufferPointer { src in
            _ = memcpy(buffer.contents(), src.baseAddress!, byteLength)
        }
    }

    // MARK: - 要素アクセス

    /// Accesses the element at the given index.
    ///
    /// An out of range index is a programming error and stops immediately through a
    /// `precondition` (the same semantics as `Swift.Array`, applying the "programming error =
    /// trap" rule of the ADR-0005 error reporting convention). Validate against ``count`` in
    /// advance when the range is dynamic.
    ///
    /// - Important: The read does **not** wait for the GPU. See the discussion on ``GPUBuffer``
    ///   for what is and is not guaranteed after a dispatch.
    public subscript(index: Int) -> T {
        get {
            precondition(
                index >= 0 && index < count, "GPUBuffer index \(index) out of range [0..<\(count)]")
            return pointer[index]
        }
        set {
            precondition(
                index >= 0 && index < count, "GPUBuffer index \(index) out of range [0..<\(count)]")
            pointer[index] = newValue
        }
    }

    /// Copies the buffer contents into a Swift array.
    /// - Returns: A new array holding every element of the buffer.
    /// - Important: The copy does **not** wait for the GPU. It snapshots the shared memory as
    ///   it stands, so a call made in the same `compute()` as the dispatch that fills the
    ///   buffer returns the contents from before the kernel ran. See the discussion on
    ///   ``GPUBuffer``.
    public func toArray() -> [T] {
        Array(UnsafeBufferPointer(start: pointer, count: count))
    }

    /// Copies the elements of a Swift array into the buffer.
    /// - Parameter data: The source array. Only `min(data.count, count)` elements are copied.
    public func copyFrom(_ data: [T]) {
        let copyCount = min(data.count, count)
        guard copyCount > 0 else { return }
        data.withUnsafeBufferPointer { src in
            _ = memcpy(pointer, src.baseAddress!, MemoryLayout<T>.stride * copyCount)
        }
    }

    /// Direct access to the buffer contents as an unsafe mutable buffer pointer.
    /// - Returns: An `UnsafeMutableBufferPointer` over every element, for high performance bulk
    ///   operations.
    /// - Important: Access through the pointer does **not** wait for the GPU, and the GPU may
    ///   be writing the same bytes concurrently. See the discussion on ``GPUBuffer``.
    public var contents: UnsafeMutableBufferPointer<T> {
        UnsafeMutableBufferPointer(start: pointer, count: count)
    }
}
