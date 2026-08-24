import Metal
import simd

/// A compact per-circle record for explicit bulk 2D drawing.
///
/// `CircleInstance` is designed to match the Metal shader layout used by
/// ``Canvas2D/circles(_:)`` and ``Canvas2D/circles(_:count:)``. Values are in
/// the current 2D coordinate space; the active Canvas2D transform is applied to
/// the whole batch when it is drawn.
///
/// ## Filling a buffer from a compute kernel
///
/// ``Canvas2D/circles(_:count:)`` draws the bytes of a `GPUBuffer<CircleInstance>` exactly as
/// they stand, so a kernel that writes one has to declare the very same struct. This is the
/// definition the library itself compiles (`MetaphorCanvas2DMassive.metal`); paste it as is:
///
/// ```metal
/// struct CircleInstance {
///     float2 position;   // offset  0
///     float  diameter;   // offset  8
///     float  _pad;       // offset 12  (unused)
///     float4 color;      // offset 16
/// };                     // stride 32, 16-byte aligned
/// ```
///
/// The padding slot is missing from the property list above because the Swift declaration
/// keeps it internal, and it may be left out of the MSL struct too: `float4 color` is 16-byte
/// aligned, so it lands at offset 16 with or without a named `_pad`. The field *order* is the
/// part that cannot be left out.
///
/// - Important: The memory order is the declaration order, not the alphabetical order this
///   documentation lists the properties in. The matching MSL declaration is
///   `struct CircleInstance { float2 position; float diameter; float _pad; float4 color; };` —
///   `position` at 0, `diameter` at 8, four unused bytes at 12, `color` at 16, stride 32.
///
/// - Note: An MSL struct written in that alphabetical order (`color`, `diameter`, `position`)
///   compiles without a warning and still measures 32 bytes, so nothing flags it. It simply
///   draws no circle at all: every center is reinterpreted from color bits and lands off
///   screen, and every diameter is garbage. When a `GPUBuffer` batch renders nothing while the
///   same values drawn from a `[CircleInstance]` array render fine, check this order first.
public struct CircleInstance: Sendable, Equatable {
    /// Circle center in local 2D coordinates.
    ///
    /// - Note: First in memory, at offset 0. See the type's own documentation for the full
    ///   layout: the properties are listed alphabetically here, not in memory order.
    public var position: SIMD2<Float>
    /// Circle diameter in local units.
    ///
    /// - Note: Second in memory, at offset 8, followed by four bytes of padding.
    public var diameter: Float
    // Keeps `color` on its natural 16-byte boundary, matching `float _pad` in
    // `MetaphorCanvas2DMassive.metal`. Internal, so it never reaches the public documentation —
    // which is why the type's doc comment spells the layout out (#1090).
    var _padding: Float = 0
    /// Per-circle RGBA color, normalized to 0...1.
    ///
    /// - Note: Last in memory, at offset 16, despite being listed first alphabetically.
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
        svgRecorder?.recordUnsupported("circles() (massive instancing)")
        guard hasFill, !instances.isEmpty, encoder != nil || isDeferring else { return }
        let count = instances.count
        let needed = massiveCircleBufferOffset + count
        guard
            massiveCircleBuffer.ensureCapacity(
                needed,
                activeIndex: currentBufferIndex,
                usedCount: 0
            )
        else {
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
    /// - Important: The buffer is drawn byte for byte, so the struct a kernel writes has to
    ///   match ``CircleInstance`` in memory order — `position` at 0, `diameter` at 8, padding
    ///   at 12, `color` at 16. Getting it wrong compiles cleanly and draws nothing; the MSL
    ///   definition to paste is in the documentation for ``CircleInstance``.
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
        let key = pipelineKey(.massiveCircle, blend: currentBlendMode)
        guard pipelineStore.state(for: key) != nil, count > 0 else { return }
        guard isDeferring || encoder != nil else { return }

        // 保留中の通常バッチを先に確定し、massive を呼び出し順どおりに続ける。
        flush()
        hasDrawnAnything = true
        // massive は 1 呼び出し = 1 バッチなので、常にここが先頭（#647）。
        captureShaderParams(ifBatchEmpty: true)

        // 遅延モードでは記録（影オン時の宿題②を根治）。即時モードでは即座にエンコード。
        // massive は変換を描画時に適用するため、記録時の変換を埋め込んで保持する。
        emit(
            .massiveCircles(
                pipeline: key, dataBuffer: buffer, byteOffset: byteOffset, count: count,
                transform: Canvas2D.embed2DTransform(currentTransform),
                shaderParams: currentShaderParams))
    }
}
