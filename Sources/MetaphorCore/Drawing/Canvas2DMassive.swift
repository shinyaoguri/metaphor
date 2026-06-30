import Metal
import simd

/// A compact per-circle record for explicit bulk 2D drawing.
///
/// `CircleInstance` is designed to match the Metal shader layout used by
/// ``Canvas2D/circles(_:)`` and ``Canvas2D/circles(_:count:)``. Values are in
/// the current 2D coordinate space; the active Canvas2D transform is applied to
/// the whole batch when it is drawn.
public struct CircleInstance: Sendable, Equatable {
    /// Circle center in local 2D coordinates.
    public var position: SIMD2<Float>
    /// Circle diameter in local units.
    public var diameter: Float
    var _padding: Float = 0
    /// Per-circle RGBA color, normalized to 0...1.
    public var color: SIMD4<Float>

    /// Creates a circle instance from a center vector, diameter, and SIMD color.
    public init(position: SIMD2<Float>, diameter: Float, color: SIMD4<Float> = SIMD4(1, 1, 1, 1)) {
        self.position = position
        self.diameter = diameter
        self.color = color
    }

    /// Creates a circle instance from a center vector, diameter, and ``Color``.
    public init(position: SIMD2<Float>, diameter: Float, color: Color) {
        self.init(position: position, diameter: diameter, color: color.simd)
    }

    /// Creates a circle instance from scalar coordinates, diameter, and ``Color``.
    public init(x: Float, y: Float, diameter: Float, color: Color = .white) {
        self.init(position: SIMD2(x, y), diameter: diameter, color: color.simd)
    }

    /// Creates a circle instance from scalar coordinates, diameter, and SIMD color.
    public init(x: Float, y: Float, diameter: Float, color: SIMD4<Float>) {
        self.init(position: SIMD2(x, y), diameter: diameter, color: color)
    }
}

extension Canvas2D {

    /// Draws many filled circles using a compact instanced path.
    ///
    /// This is the explicit high-throughput counterpart to repeated
    /// ``circle(_:_:_:)`` calls. Instance colors are used directly; `fill()` only
    /// controls whether filled shape drawing is currently enabled.
    ///
    /// - Parameter instances: Circle instances to draw in order.
    public func circles(_ instances: [CircleInstance]) {
        guard hasFill, !instances.isEmpty, encoder != nil || isDeferring else { return }
        let count = instances.count
        let needed = massiveCircleBufferOffset + count
        guard massiveCircleBuffer.ensureCapacity(
            needed,
            activeIndex: currentBufferIndex,
            usedCount: 0
        ) else {
            return
        }

        let writeOffset = massiveCircleBufferOffset
        instances.withUnsafeBufferPointer { src in
            guard let base = src.baseAddress else { return }
            massiveCircleBuffer
                .pointer(for: currentBufferIndex)
                .advanced(by: writeOffset)
                .update(from: base, count: count)
        }

        drawCircleInstances(
            buffer: massiveCircleBuffer.buffer(for: currentBufferIndex),
            byteOffset: writeOffset * MemoryLayout<CircleInstance>.stride,
            count: count
        )
        massiveCircleBufferOffset += count
    }

    /// Draws many filled circles from a typed GPU buffer without copying.
    ///
    /// Use this overload when a compute kernel updates the circle data on the
    /// GPU, or when the data already lives in a ``GPUBuffer``.
    ///
    /// - Parameters:
    ///   - instances: Source GPU buffer.
    ///   - count: Number of instances to draw. Defaults to the full buffer.
    public func circles(_ instances: GPUBuffer<CircleInstance>, count: Int? = nil) {
        let drawCount = min(max(count ?? instances.count, 0), instances.count)
        guard hasFill, drawCount > 0, encoder != nil || isDeferring else { return }
        drawCircleInstances(buffer: instances.buffer, byteOffset: 0, count: drawCount)
    }

    private func drawCircleInstances(buffer: MTLBuffer, byteOffset: Int, count: Int) {
        guard massiveCirclePipelineStates[currentBlendMode] != nil, count > 0 else { return }
        guard isDeferring || encoder != nil else { return }

        // 保留中の通常バッチを先に確定し、massive を呼び出し順どおりに続ける。
        flush()
        hasDrawnAnything = true

        // 遅延モードでは記録（影オン時の宿題②を根治）。即時モードでは即座にエンコード。
        // massive は変換を描画時に適用するため、記録時の変換を埋め込んで保持する。
        emit(.massiveCircles(
            blend: currentBlendMode, dataBuffer: buffer, byteOffset: byteOffset, count: count,
            transform: Canvas2D.embed2DTransform(currentTransform)))
    }
}
