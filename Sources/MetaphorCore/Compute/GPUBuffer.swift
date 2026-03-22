@preconcurrency import Metal

/// CPU と GPU の両方からアクセス可能な型付き GPU バッファを提供します。
///
/// `storageModeShared` を使用し、Apple Silicon ユニファイドメモリにより
/// CPU と GPU の両側からゼロコピーアクセスを実現します。
///
/// ```swift
/// var positions = createBuffer(count: 1000, type: SIMD2<Float>.self)
/// positions![0] = SIMD2<Float>(100, 200)
/// ```
@MainActor
public final class GPUBuffer<T> {
    /// 基盤となる Metal バッファ
    public let buffer: MTLBuffer

    /// バッファ内の要素数
    public let count: Int

    /// バッファ内容への型付きポインタ
    private let pointer: UnsafeMutablePointer<T>

    // MARK: - 初期化

    /// 指定された要素数でゼロ初期化された空のバッファを作成します。
    /// - Parameters:
    ///   - device: バッファ確保に使用する Metal デバイス
    ///   - count: 確保する要素数
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

    /// 要素の配列で初期化されたバッファを作成します。
    /// - Parameters:
    ///   - device: バッファ確保に使用する Metal デバイス
    ///   - data: バッファにコピーする初期データの配列
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

    // MARK: - 要素アクセス

    /// 指定されたインデックスの要素にアクセスします。
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

    /// バッファの内容を Swift 配列にコピーします。
    /// - Returns: バッファの全要素を含む新しい配列
    public func toArray() -> [T] {
        Array(UnsafeBufferPointer(start: pointer, count: count))
    }

    /// Swift 配列の要素をバッファにコピーします。
    /// - Parameter data: ソース配列。`min(data.count, count)` 要素のみがコピーされます
    public func copyFrom(_ data: [T]) {
        let copyCount = min(data.count, count)
        data.withUnsafeBufferPointer { src in
            _ = memcpy(pointer, src.baseAddress!, MemoryLayout<T>.stride * copyCount)
        }
    }

    /// バッファ内容への直接アクセスを unsafe mutable buffer pointer として提供します。
    /// - Returns: 高パフォーマンスな一括操作用の全要素にわたる `UnsafeMutableBufferPointer`
    public var contents: UnsafeMutableBufferPointer<T> {
        UnsafeMutableBufferPointer(start: pointer, count: count)
    }
}
