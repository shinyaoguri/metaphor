@preconcurrency import Metal

/// GPU上の型付きバッファ
///
/// `storageModeShared`でCPUとGPU両方からアクセス可能。
/// Apple Silicon統合メモリでゼロコピーアクセスを提供する。
///
/// ```swift
/// var positions = createBuffer(count: 1000, type: SIMD2<Float>.self)
/// positions![0] = SIMD2<Float>(100, 200)
/// ```
@MainActor
public final class GPUBuffer<T> {
    /// 内部のMTLBuffer
    public let buffer: MTLBuffer

    /// 要素数
    public let count: Int

    /// 型付きポインタ
    private let pointer: UnsafeMutablePointer<T>

    // MARK: - Initialization

    /// 空のバッファを作成（ゼロ初期化）
    /// - Parameters:
    ///   - device: MTLDevice
    ///   - count: 要素数
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

    /// 配列からバッファを作成
    /// - Parameters:
    ///   - device: MTLDevice
    ///   - data: 初期データ配列
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
            memcpy(buffer.contents(), src.baseAddress!, byteLength)
        }
    }

    // MARK: - Element Access

    /// 要素にアクセス
    public subscript(index: Int) -> T {
        get {
            assert(index >= 0 && index < count, "GPUBuffer index \(index) out of range [0..<\(count)]")
            return pointer[index]
        }
        set {
            assert(index >= 0 && index < count, "GPUBuffer index \(index) out of range [0..<\(count)]")
            pointer[index] = newValue
        }
    }

    /// バッファ内容をSwift配列としてコピー
    public func toArray() -> [T] {
        Array(UnsafeBufferPointer(start: pointer, count: count))
    }

    /// Swift配列からバッファへコピー
    public func copyFrom(_ data: [T]) {
        let copyCount = min(data.count, count)
        data.withUnsafeBufferPointer { src in
            memcpy(pointer, src.baseAddress!, MemoryLayout<T>.stride * copyCount)
        }
    }

    /// UnsafeMutableBufferPointerとしてアクセス（高速一括操作用）
    public var contents: UnsafeMutableBufferPointer<T> {
        UnsafeMutableBufferPointer(start: pointer, count: count)
    }
}
