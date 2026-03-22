@preconcurrency import Metal

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
    /// - Throws: 関数名が見つからない場合 `MetaphorError.compute(.functionNotFound)`、
    ///   または Metal コンパイルエラー
    public init(device: MTLDevice, source: String, functionName: String) throws {
        let library = try device.makeLibrary(source: source, options: nil)
        guard let function = library.makeFunction(name: functionName) else {
            throw MetaphorError.compute(.functionNotFound(functionName))
        }
        self.pipelineState = try device.makeComputePipelineState(function: function)
    }

    /// プリコンパイル済み Metal 関数からコンピュートカーネルを作成します。
    /// - Parameters:
    ///   - device: パイプラインステート作成に使用する Metal デバイス
    ///   - function: プリコンパイル済み `MTLFunction`
    /// - Throws: Metal パイプライン作成エラー
    public init(device: MTLDevice, function: MTLFunction) throws {
        self.pipelineState = try device.makeComputePipelineState(function: function)
    }
}
