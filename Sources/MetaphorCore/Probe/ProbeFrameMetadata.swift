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

    struct Size: Encodable {
        let width: Int
        let height: Int
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
