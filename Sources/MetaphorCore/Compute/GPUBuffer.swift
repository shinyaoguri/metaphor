@preconcurrency import Metal

/// Provide a typed GPU buffer accessible from both CPU and GPU.
///
/// Use `storageModeShared` so that Apple Silicon unified memory enables
/// zero-copy access from both the CPU and GPU sides.
///
/// ```swift
/// var positions = createBuffer(count: 1000, type: SIMD2<Float>.self)
/// positions![0] = SIMD2<Float>(100, 200)
/// ```
@MainActor
public final class GPUBuffer<T> {
    /// The underlying Metal buffer.
    public let buffer: MTLBuffer

    /// The number of elements in the buffer.
    public let count: Int

    /// Typed pointer to the buffer contents.
    private let pointer: UnsafeMutablePointer<T>

    // MARK: - Initialization

    /// Create an empty zero-initialized buffer with the given element count.
    /// - Parameters:
    ///   - device: The Metal device used to allocate the buffer.
    ///   - count: The number of elements to allocate.
    public init?(device: MTLDevice, count: Int) {
        let byteLength = MemoryLayout<T>.stride * count
        guard byteLength > 0,
              let buffer = device.makeBuffer(length: byteLength, options: .storageModeShared) else {
            return nil
        }
        self.buffer = buffer
        self.count = count
        self.pointer = buffer.contents().bindMemory(to: T.self, capacity: count)
        memset(buffer.contents(), 0, byteLength)
    }

    /// Create a buffer initialized from an array of elements.
    /// - Parameters:
    ///   - device: The Metal device used to allocate the buffer.
    ///   - data: The array of initial data to copy into the buffer.
    public init?(device: MTLDevice, data: [T]) {
        let count = data.count
        let byteLength = MemoryLayout<T>.stride * count
        guard byteLength > 0,
              let buffer = device.makeBuffer(length: byteLength, options: .storageModeShared) else {
            return nil
        }
        self.buffer = buffer
        self.count = count
        self.pointer = buffer.contents().bindMemory(to: T.self, capacity: count)
        data.withUnsafeBufferPointer { src in
            _ = memcpy(buffer.contents(), src.baseAddress!, byteLength)
        }
    }

    // MARK: - Element Access

    /// Access the element at the given index.
    public subscript(index: Int) -> T {
        get {
            precondition(index >= 0 && index < count, "GPUBuffer index \(index) out of range [0..<\(count)]")
            return pointer[index]
        }
        set {
            precondition(index >= 0 && index < count, "GPUBuffer index \(index) out of range [0..<\(count)]")
            pointer[index] = newValue
        }
    }

    /// Copy the buffer contents into a Swift array.
    /// - Returns: A new array containing all elements from the buffer.
    public func toArray() -> [T] {
        Array(UnsafeBufferPointer(start: pointer, count: count))
    }

    /// Copy elements from a Swift array into the buffer.
    /// - Parameter data: The source array. Only `min(data.count, count)` elements are copied.
    public func copyFrom(_ data: [T]) {
        let copyCount = min(data.count, count)
        data.withUnsafeBufferPointer { src in
            _ = memcpy(pointer, src.baseAddress!, MemoryLayout<T>.stride * copyCount)
        }
    }

    /// Provide direct access to the buffer contents as an unsafe mutable buffer pointer.
    /// - Returns: An `UnsafeMutableBufferPointer` over all elements for high-performance bulk operations.
    public var contents: UnsafeMutableBufferPointer<T> {
        UnsafeMutableBufferPointer(start: pointer, count: count)
    }
}
