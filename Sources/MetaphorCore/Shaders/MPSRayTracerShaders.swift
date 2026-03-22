/// Metal レイトレーシングシェーダー関数名定数。
///
/// MSLソースコードはバンドルされた .txt リソースファイルからランタイムに読み込まれます。
/// Metal ネイティブ Ray Tracing API を使用したインライン交差によるアンビエントオクルージョン、
/// ソフトシャドウ、およびディフューズシェーディングを含みます。
enum MPSRayTracerShaders {

    /// レイトレーサーシェーダー関数名定数。
    enum FunctionName {
        /// アンビエントオクルージョントレーシングのMSL関数名。
        static let traceAmbientOcclusion = "traceAmbientOcclusion"
        /// ソフトシャドウトレーシングのMSL関数名。
        static let traceSoftShadow = "traceSoftShadow"
        /// シンプルディフューズシェーディングのMSL関数名。
        static let traceDiffuse = "traceDiffuse"
    }
}
