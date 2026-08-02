import Metal

/// GPU コンピュートカーネルをパイプラインステートとメタデータでラップします。
///
/// MSL ソース文字列からコンピュートパイプラインステートをコンパイルし、
/// ディスパッチ設定用のスレッドグループサイズメタデータを公開します。
///
/// ```swift
/// let kernel = try createComputeKernel(
///     source: "kernel void update(...) { ... }",
///     function: "update"
/// )
/// ```
@MainActor
public final class ComputeKernel {
    /// コンパイル済みコンピュートパイプラインステート
    public let pipelineState: MTLComputePipelineState

    /// スレッドグループあたりの最大スレッド数を返します。
    public var maxTotalThreadsPerThreadgroup: Int {
        pipelineState.maxTotalThreadsPerThreadgroup
    }

    /// 推奨される 1D スレッドグループサイズ（SIMD 幅）を返します。
    public var threadExecutionWidth: Int {
        pipelineState.threadExecutionWidth
    }

    /// MSL ソースコードをランタイムでコンパイルしてコンピュートカーネルを作成します。
    /// - Parameters:
    ///   - device: コンパイルに使用する Metal デバイス
    ///   - source: MSL ソースコード文字列
    ///   - functionName: ルックアップするカーネル関数名
    /// - Throws: ``MetaphorError``。MSL のコンパイルに失敗した場合は
    ///   ``MetaphorError/shaderCompilationFailed(name:underlying:)``、関数名が
    ///   見つからない場合は ``MetaphorError/compute(_:)`` の
    ///   ``MetaphorError/ComputeFailure/functionNotFound(_:)``、パイプライン作成に
    ///   失敗した場合は ``MetaphorError/pipelineCreationFailed(name:underlying:)``
    public init(device: MTLDevice, source: String, functionName: String) throws {
        let library: MTLLibrary
        do {
            library = try device.makeLibrary(source: source, options: nil)
        } catch {
            throw MetaphorError.shaderCompilationFailed(name: functionName, underlying: error)
        }
        guard let function = library.makeFunction(name: functionName) else {
            throw MetaphorError.compute(.functionNotFound(functionName))
        }
        self.pipelineState = try PipelineFactory.buildCompute(device: device, function: function)
    }

    /// プリコンパイル済み Metal 関数からコンピュートカーネルを作成します。
    /// - Parameters:
    ///   - device: パイプラインステート作成に使用する Metal デバイス
    ///   - function: プリコンパイル済み `MTLFunction`
    /// - Throws: ``MetaphorError/pipelineCreationFailed(name:underlying:)``
    ///   パイプライン作成に失敗した場合
    public init(device: MTLDevice, function: MTLFunction) throws {
        self.pipelineState = try PipelineFactory.buildCompute(device: device, function: function)
    }
}
