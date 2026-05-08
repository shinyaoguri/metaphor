import Foundation

/// ``MetaphorProbePlugin`` の設定。
///
/// 出力先ディレクトリやリクエストファイルのパスをカスタマイズできます。
/// デフォルトはプロジェクトのカレントディレクトリ配下の `.metaphor/probe/`。
public struct MetaphorProbeConfig: Sendable {
    /// PNG と JSON を書き出すディレクトリ。
    public var outputDirectory: String

    /// AI エージェントが書き込むリクエストファイルのパス。
    public var requestFilePath: String

    /// 出力画像のスケール（1.0 = フルサイズ）。
    public var defaultScale: Float

    public init(
        outputDirectory: String = ".metaphor/probe/current",
        requestFilePath: String = ".metaphor/probe/request.json",
        defaultScale: Float = 1.0
    ) {
        self.outputDirectory = outputDirectory
        self.requestFilePath = requestFilePath
        self.defaultScale = defaultScale
    }
}
