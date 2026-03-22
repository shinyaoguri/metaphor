/// MPS レイトレーシングシェーダー関数名定数。
///
/// MSLソースコードはバンドルされた .txt リソースファイルからランタイムに読み込まれます。
/// プライマリレイ生成、アンビエントオクルージョンシェーディングとアキュムレーション、
/// および半球ライティングによるシンプルなディフューズシェーディングを含みます。
enum MPSRayTracerShaders {

    /// MPS レイトレーサーシェーダー関数名定数。
    enum FunctionName {
        /// プライマリレイ生成のMSL関数名。
        static let generatePrimaryRays = "generatePrimaryRays"
        /// アンビエントオクルージョンシェーディングのMSL関数名。
        static let shadeAmbientOcclusion = "shadeAmbientOcclusion"
        /// AOアキュムレーションのMSL関数名。
        static let accumulateAO = "accumulateAO"
        /// シンプルディフューズシェーディングのMSL関数名。
        static let shadeDiffuse = "shadeDiffuse"
    }
}
