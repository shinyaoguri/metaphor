import Metal

/// Generic GPU instance buffer manager for triple-buffered instanced rendering.
///
/// Handles GPU buffer allocation, triple-buffering lifecycle, bounds checking,
/// and per-instance data writing. Used by both `Canvas2D` and `Canvas3D`
/// instancing systems.
///
/// - Parameters:
///   - T: The per-instance data type (e.g., `InstanceData2D`, `InstanceData3D`).
@MainActor
final class InstanceBatcher<T> {

    /// Number of triple-buffered GPU buffers.
    static var bufferCount: Int { 3 }

    /// Maximum number of instances per frame (across all batches).
    let maxInstances: Int

    private let device: MTLDevice
    private let instanceBuffers: [MTLBuffer]
    private let instancePointers: [UnsafeMutablePointer<T>]
    private var currentBufferIndex: Int = 0

    /// Running offset into the instance buffer across batches within a single frame.
    private(set) var frameOffset: Int = 0

    /// The number of instances accumulated in the current batch.
    private(set) var instanceCount: Int = 0

    /// Creates a new instance batcher with triple-buffered GPU storage.
    ///
    /// - Parameters:
    ///   - device: The Metal device used to create buffers.
    ///   - maxInstances: The maximum number of instances per frame.
    ///   - label: A label prefix for the GPU buffers.
    init(device: MTLDevice, maxInstances: Int = 65536, label: String = "metaphor.instance") throws {
        self.device = device
        self.maxInstances = maxInstances
        let stride = MemoryLayout<T>.stride
        let bufferSize = maxInstances * stride
        var buffers: [MTLBuffer] = []
        var pointers: [UnsafeMutablePointer<T>] = []
        for i in 0..<Self.bufferCount {
            guard let buf = device.makeBuffer(length: bufferSize, options: .storageModeShared) else {
                throw MetaphorError.bufferCreationFailed(size: bufferSize)
            }
            buf.label = "\(label).\(i)"
            buffers.append(buf)
            pointers.append(buf.contents().bindMemory(to: T.self, capacity: maxInstances))
        }
        self.instanceBuffers = buffers
        self.instancePointers = pointers
    }

    /// Prepares the batcher for a new frame by selecting the buffer and resetting state.
    func beginFrame(bufferIndex: Int) {
        currentBufferIndex = bufferIndex % Self.bufferCount
        frameOffset = 0
        instanceCount = 0
    }

    /// Whether there is room for another instance in the current frame.
    var canAdd: Bool {
        (frameOffset + instanceCount) < maxInstances
    }

    /// Writes per-instance data at the current position and advances the instance count.
    ///
    /// - Parameter data: The per-instance data to write.
    /// - Precondition: ``canAdd`` must be `true`.
    func addInstance(_ data: T) {
        instancePointers[currentBufferIndex][frameOffset + instanceCount] = data
        instanceCount += 1
    }

    /// The currently active instance data buffer.
    var currentBuffer: MTLBuffer {
        instanceBuffers[currentBufferIndex]
    }

    /// The byte offset into the current buffer where the active batch starts.
    var currentBufferOffset: Int {
        frameOffset * MemoryLayout<T>.stride
    }

    /// Advances the frame offset by the current instance count and resets the batch.
    func advanceBatch() {
        frameOffset += instanceCount
        instanceCount = 0
    }
}
