import Foundation

/// GPU パーティクルシステムシェーダー関数名定数。
///
/// MSLソースコードはバンドルされた .txt リソースファイルからランタイムに読み込まれます。
/// パーティクル更新用コンピュートカーネル、間接描画サポート
/// （カウンターリセット、コンパクション、引数ビルド）、およびソフトサークル表現の
/// ビルボードクワッドレンダリング用頂点/フラグメントシェーダーを含みます。
enum ParticleShaders {

    /// パーティクルシェーダー関数名定数。
    enum FunctionName {
        /// パーティクル更新コンピュートカーネルのMSL関数名。
        static let update = "metaphor_particleUpdate"
        /// パーティクルビルボード頂点シェーダーのMSL関数名。
        static let vertex = "metaphor_particleVertex"
        /// パーティクルソフトサークルフラグメントシェーダーのMSL関数名。
        static let fragment = "metaphor_particleFragment"
        /// アトミックカウンターリセットコンピュートカーネルのMSL関数名。
        static let resetCounter = "metaphor_particleResetCounter"
        /// 生存パーティクルコンパクションコンピュートカーネルのMSL関数名。
        static let compact = "metaphor_particleCompact"
        /// 間接描画引数ビルダーコンピュートカーネルのMSL関数名。
        static let buildIndirectArgs = "metaphor_particleBuildIndirectArgs"
    }
}
