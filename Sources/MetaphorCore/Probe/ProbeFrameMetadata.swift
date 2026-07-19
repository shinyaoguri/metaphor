import Foundation

/// `frame.json` のスキーマ。`frame.png` と一緒に書き出され、
/// AI エージェントが「見た目」と並行して内部状態を観測するための
/// 構造化メタデータです。
struct ProbeFrameMetadata: Encodable {
    /// JSON スキーマのバージョン。後方互換性のため将来増やす想定。
    let schemaVersion: Int

    /// 対応するリクエストの id。
    let id: String

    /// オプションのリクエストラベル。
    let label: String?

    /// ソース世代の刻印（provenance）。`METAPHOR_SOURCE_STAMP` 環境変数または
    /// `MetaphorProbeConfig.sourceStamp` で注入される、編集ごとに変わる識別子。
    /// AI エージェント／測定ハーネスが「観測したフレームがどのソース版を反映するか」を
    /// 判定し、保存→反映（リビルド→再起動）の完了を機械検出するために使う。
    /// 未設定時は nil（schemaVersion 4 で additive 追加）。
    let sourceStamp: String?

    /// レンダリングされたフレーム番号。
    let frame: Int

    /// スケッチ開始からの経過時間（秒）。
    let time: Double

    /// オフスクリーン解像度。
    let size: Size

    /// `Sketch.probe(_:_:)` で記録されたユーザー定義値。
    let custom: [String: ProbeValue]

    /// `custom` の各キーの型タグ（例: `"double"` / `"vec2"`）。
    /// ベクトルが裸の配列としてシリアライズされるため、値だけでは
    /// `vec2` と「2 要素の配列」を区別できない問題を解消します。
    let customTypes: [String: String]

    /// プラグインが検出した警告（例: blank frame）。
    let warnings: [String]

    /// 軽量な画像統計。AI エージェントが PNG をデコードせずに
    /// 「何が・どこに・どれくらい・何色で描かれているか」を数値で判断し、
    /// スナップショット間の差分を引き算で得るためのシグナル。
    /// 解析できない場合（テクスチャ読み出し失敗など）は nil。
    let stats: Stats?

    /// 実測パフォーマンス統計（schemaVersion 4 のまま additive 追加、Issue #271）。
    /// スケッチの「重さ」を AI が画像からの推測でなく数値で判断するためのシグナル。
    /// 単一フレーム経路（`current/frame.json`）のみで搭載し、連続キャプチャ
    /// （`sequence/frame.NNNN.json`）と失敗応答では省略する（nil）。
    let performance: Performance?

    struct Size: Encodable {
        let width: Int
        let height: Int
    }

    /// リクエスト処理時に採取する実測パフォーマンス統計。
    struct Performance: Encodable {
        /// 直近約 1 秒の実測フレームレート。ウィンドウ内のフレームが
        /// 2 個未満（noLoop 停止中・起動直後）で算出できない場合は nil。
        let fps: Double?

        /// 実効ターゲット FPS（`frameRate()` / `METAPHOR_FPS` 解決後の設定値）。
        let targetFPS: Int

        /// 直近約 1 秒のフレーム時間（ミリ秒）。`fps` と同じ条件で nil。
        let frameTimeMs: FrameTime?

        /// 自プロセスの phys_footprint（MB）。Activity Monitor の「メモリ」に
        /// 相当する実効フットプリント。取得失敗時は nil。
        let memoryMB: Double?

        /// 前回 Probe リクエストから今回まで（初回はスケッチ起動から）の
        /// 平均 CPU 使用率（%）。1 コア = 100%（`top` 互換。マルチコア使用で
        /// 100 超あり）。取得失敗時は nil。
        let cpuPercent: Double?

        /// thermal state（`nominal` / `fair` / `serious` / `critical` / `unknown`）。
        let thermalState: String

        /// フレーム時間の統計（ミリ秒）。`max` はスパイク検出用。
        struct FrameTime: Encodable {
            let mean: Double
            let max: Double
        }
    }

    /// 32x32 グリッドサンプルから 1 パスで計算する画像統計。
    struct Stats: Encodable {
        /// サンプルの平均色 `[r, g, b]`（各 0..1、ガンマ符号化値）。
        let meanColor: [Float]

        /// サンプルの平均輝度（Rec. 709 重み、0..1）。
        let meanLuminance: Float

        /// 背景色（四隅サンプルの平均）と十分に異なる「コンテンツ」サンプルの割合（0..1）。
        /// 「何かが描かれているか」「画面のどれだけを占めるか」の目安。
        let contentFraction: Float

        /// コンテンツの正規化バウンディングボックス（原点=左上、各 0..1）。
        /// コンテンツが無い（ほぼ単色）場合は nil。グリッド粒度の近似値。
        let contentBounds: Bounds?

        /// 1 辺あたりのサンプル数（= 32）。バウンディングボックスの粒度を AI に伝える。
        let sampleGrid: Int
    }

    /// 正規化バウンディングボックス（原点=左上、各成分 0..1）。
    struct Bounds: Encodable {
        let x: Float
        let y: Float
        let width: Float
        let height: Float
    }
}
