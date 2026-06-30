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

    /// ソース世代の刻印（provenance）。`frame.json` の `sourceStamp` に書き出される。
    /// `nil` の場合はプラグインが環境変数 `METAPHOR_SOURCE_STAMP` をフォールバックに使う。
    /// 編集ごとに変わる識別子（cli が子プロセス起動時に注入する想定）。
    public var sourceStamp: String?

    public init(
        outputDirectory: String = ".metaphor/probe/current",
        requestFilePath: String = ".metaphor/probe/request.json",
        defaultScale: Float = 1.0,
        sourceStamp: String? = nil
    ) {
        self.outputDirectory = outputDirectory
        self.requestFilePath = requestFilePath
        self.defaultScale = defaultScale
        self.sourceStamp = sourceStamp
    }
}
