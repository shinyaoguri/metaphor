import Metal

/// トリプルバッファリングされたインスタンスレンダリング用の汎用 GPU インスタンスバッファマネージャー。
///
/// GPU バッファの割り当て、トリプルバッファリングのライフサイクル、境界チェック、
/// インスタンスごとのデータ書き込みを処理します。`Canvas2D` と `Canvas3D`
/// の両方のインスタンシングシステムで使用されます。
///
/// - Parameters:
///   - T: インスタンスごとのデータ型（例: `InstanceData2D`、`InstanceData3D`）。
@MainActor
final class InstanceBatcher<T> {

    /// トリプルバッファリングされた GPU バッファの数。
    static var bufferCount: Int { 3 }

    /// フレームあたりの最大インスタンス数（全バッチ合計）。
    let maxInstances: Int

    private let device: MTLDevice
    private let instanceBuffers: [MTLBuffer]
    private let instancePointers: [UnsafeMutablePointer<T>]
    private var currentBufferIndex: Int = 0

    /// 単一フレーム内のバッチ間で蓄積されるインスタンスバッファへのオフセット。
    private(set) var frameOffset: Int = 0

    /// 現在のバッチに蓄積されたインスタンス数。
    private(set) var instanceCount: Int = 0

    /// トリプルバッファリングされた GPU ストレージで新しいインスタンスバッチャーを作成します。
    ///
    /// - Parameters:
    ///   - device: バッファ作成に使用する Metal デバイス。
    ///   - maxInstances: フレームあたりの最大インスタンス数。
    ///   - label: GPU バッファのラベルプレフィックス。
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

    /// バッファを選択し状態をリセットして、新しいフレームの準備をします。
    func beginFrame(bufferIndex: Int) {
        currentBufferIndex = bufferIndex % Self.bufferCount
        frameOffset = 0
        instanceCount = 0
    }

    /// 現在のフレームにもう1つインスタンスを追加する余地があるかどうか。
    var canAdd: Bool {
        (frameOffset + instanceCount) < maxInstances
    }

    /// 現在位置にインスタンスごとのデータを書き込み、インスタンスカウントを進めます。
    ///
    /// - Parameter data: 書き込むインスタンスごとのデータ。
    /// - Precondition: ``canAdd`` が `true` である必要があります。
    func addInstance(_ data: T) {
        instancePointers[currentBufferIndex][frameOffset + instanceCount] = data
        instanceCount += 1
    }

    /// 現在アクティブなインスタンスデータバッファ。
    var currentBuffer: MTLBuffer {
        instanceBuffers[currentBufferIndex]
    }

    /// アクティブなバッチが開始する現在のバッファへのバイトオフセット。
    var currentBufferOffset: Int {
        frameOffset * MemoryLayout<T>.stride
    }

    /// 現在のインスタンスカウント分だけフレームオフセットを進め、バッチをリセットします。
    func advanceBatch() {
        frameOffset += instanceCount
        instanceCount = 0
    }
}
