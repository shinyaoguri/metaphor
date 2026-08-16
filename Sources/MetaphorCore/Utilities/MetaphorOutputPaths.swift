import Foundation

/// スケッチが書き出すファイル（スクリーンショット・連番・動画・GIF）の
/// **保存先**を解決します（Issue #757）。
///
/// 従来は渡された名前に無条件で `~/Desktop/` を前置していました。保存先を選べないうえ、
/// 絶対パスを渡すと `~/Desktop/tmp/shots/a.png` のような別の場所へ落ち、
/// 親ディレクトリが作られてしまうので**失敗にも気付けません**でした。
///
/// 規則は次の 3 つです。
///
/// - **既定**（引数を省略したとき）はプロジェクトの中の `output/`
/// - **相対パス**はプロジェクト直下からの相対（Processing のスケッチフォルダ相当）
/// - **絶対パス**と `~` 始まりはそのまま
///
/// ここでいうプロジェクト（基準ディレクトリ）は ``MetaphorPaths/baseDirectory`` で、
/// `METAPHOR_STATE_DIR` があればそこ、無ければプロセスの cwd です（`swift build && swift run`
/// ならパッケージ直下、`metaphor run` / `watch` の子プロセスなら渡されたプロジェクト）。
enum MetaphorOutputPaths {
    /// 既定の出力ディレクトリ名。
    static let directoryName = "output"

    /// 既定の出力ディレクトリ（`<base>/output`）。
    static func defaultDirectory(base: String = MetaphorPaths.baseDirectory) -> String {
        MetaphorPaths.resolve(directoryName, base: base)
    }

    /// ``SketchContext/saveFrame(_:)`` の保存先。
    ///
    /// - Parameters:
    ///   - filename: 呼び出し側が指定したパス（`nil` なら `output/screen-<frameCount>.png`）。
    ///   - frameCount: 既定名に使うフレーム番号（4 桁ゼロ詰め）。
    static func screenshot(
        filename: String?, frameCount: Int, base: String = MetaphorPaths.baseDirectory
    ) -> String {
        guard let filename else {
            let name = "screen-\(String(format: "%04d", frameCount)).png"
            return MetaphorPaths.resolve(name, base: defaultDirectory(base: base))
        }
        return MetaphorPaths.resolve(filename, base: base)
    }

    /// ``SketchContext/save()`` の保存先（`output/metaphor_<timestamp>.png`）。
    static func timestampedScreenshot(
        timestamp: String, base: String = MetaphorPaths.baseDirectory
    ) -> String {
        MetaphorPaths.resolve("metaphor_\(timestamp).png", base: defaultDirectory(base: base))
    }

    /// ``SketchContext/beginFrameRecord(directory:pattern:)`` の出力ディレクトリ。
    static func frameSequenceDirectory(
        _ directory: String?, timestamp: String, base: String = MetaphorPaths.baseDirectory
    ) -> String {
        guard let directory else {
            return MetaphorPaths.resolve(
                "metaphor_frames_\(timestamp)", base: defaultDirectory(base: base))
        }
        return MetaphorPaths.resolve(directory, base: base)
    }

    /// 動画 / GIF の書き出し先（`output/metaphor_<timestamp>.<fileExtension>`）。
    static func recording(
        _ path: String?, fileExtension: String, timestamp: String,
        base: String = MetaphorPaths.baseDirectory
    ) -> String {
        guard let path else {
            return MetaphorPaths.resolve(
                "metaphor_\(timestamp).\(fileExtension)", base: defaultDirectory(base: base))
        }
        return MetaphorPaths.resolve(path, base: base)
    }

    /// 既定のファイル名に使うタイムスタンプ（`yyyyMMdd_HHmmss`）。
    static func timestamp(_ date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter.string(from: date)
    }
}
