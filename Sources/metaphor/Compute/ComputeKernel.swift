@preconcurrency import Metal

/// GPUコンピュートカーネルをラップするクラス
///
/// MSLソース文字列からコンパイルしたコンピュートパイプラインステートを保持し、
/// スレッドグループサイズなどのメタデータを提供する。
///
/// ```swift
/// let kernel = try createComputeKernel(
///     source: "kernel void update(...) { ... }",
///     function: "update"
/// )
/// ```
@MainActor
public final class ComputeKernel {
    /// コンピュートパイプラインステート
    public let pipelineState: MTLComputePipelineState

    /// スレッドグループあたりの最大スレッド数
    public var maxTotalThreadsPerThreadgroup: Int {
        pipelineState.maxTotalThreadsPerThreadgroup
    }

    /// 推奨1Dスレッドグループサイズ（SIMD幅）
    public var threadExecutionWidth: Int {
        pipelineState.threadExecutionWidth
    }

    /// MSLソースからコンピュートカーネルを作成
    /// - Parameters:
    ///   - device: MTLDevice
    ///   - source: MSLソースコード
    ///   - functionName: カーネル関数名
    public init(device: MTLDevice, source: String, functionName: String) throws {
        let library = try device.makeLibrary(source: source, options: nil)
        guard let function = library.makeFunction(name: functionName) else {
            throw ComputeKernelError.functionNotFound(functionName)
        }
        self.pipelineState = try device.makeComputePipelineState(function: function)
    }

    /// 事前コンパイル済みMTLFunctionからコンピュートカーネルを作成
    /// - Parameters:
    ///   - device: MTLDevice
    ///   - function: MTLFunction
    public init(device: MTLDevice, function: MTLFunction) throws {
        self.pipelineState = try device.makeComputePipelineState(function: function)
    }
}

/// コンピュートカーネルのエラー
public enum ComputeKernelError: Error, CustomStringConvertible {
    case functionNotFound(String)

    public var description: String {
        switch self {
        case .functionNotFound(let name):
            return "Compute function '\(name)' not found in shader source"
        }
    }
}
