import Metal
import simd

extension Canvas3D {
    // MARK: - マテリアル

    /// 現在のマテリアルのスペキュラハイライト色を設定します。
    ///
    /// - Parameter color: スペキュラ色。
    public func specular(_ color: Color) {
        currentMaterial.specularAndShininess = SIMD4(
            color.r, color.g, color.b,
            currentMaterial.specularAndShininess.w
        )
    }

    /// グレースケール値でスペキュラハイライト色を設定します。
    ///
    /// - Parameter gray: 全チャンネルに適用されるグレースケール強度。
    public func specular(_ gray: Float) {
        currentMaterial.specularAndShininess = SIMD4(
            gray, gray, gray,
            currentMaterial.specularAndShininess.w
        )
    }

    /// 現在のマテリアルの光沢度指数を設定します。
    ///
    /// - Parameter value: 光沢度指数（値が大きいほどハイライトが鋭くなります）。
    public func shininess(_ value: Float) {
        currentMaterial.specularAndShininess.w = value
    }

    /// 現在のマテリアルのエミッシブ色を設定します。
    ///
    /// - Parameter color: エミッシブ色。
    public func emissive(_ color: Color) {
        currentMaterial.emissiveAndMetallic = SIMD4(
            color.r, color.g, color.b,
            currentMaterial.emissiveAndMetallic.w
        )
    }

    /// グレースケール値でエミッシブ色を設定します。
    ///
    /// - Parameter gray: 全チャンネルに適用されるグレースケール強度。
    public func emissive(_ gray: Float) {
        currentMaterial.emissiveAndMetallic = SIMD4(
            gray, gray, gray,
            currentMaterial.emissiveAndMetallic.w
        )
    }

    /// 現在のマテリアルのメタリック係数を設定します。
    ///
    /// - Parameter value: メタリック係数。0.0（誘電体）から 1.0（完全金属）まで。
    public func metallic(_ value: Float) {
        currentMaterial.emissiveAndMetallic.w = value
    }

    /// PBR ラフネスを設定し、自動的に PBR シェーディングモードを有効にします。
    ///
    /// - Parameter value: ラフネス。0.0（鏡面）から 1.0（完全拡散）まで。
    public func roughness(_ value: Float) {
        currentMaterial.pbrParams.x = value
        currentMaterial.pbrParams.y = 1  // 自動的に PBR モードを有効化
    }

    /// PBR アンビエントオクルージョン係数を設定します。
    ///
    /// - Parameter value: オクルージョン。0.0（完全遮蔽）から 1.0（遮蔽なし）まで。
    public func ambientOcclusion(_ value: Float) {
        currentMaterial.pbrParams.z = value
    }

    /// PBR シェーディングモードを明示的に切り替えます。
    ///
    /// - Parameter enabled: `true` で Cook-Torrance GGX シェーディング、`false` で Blinn-Phong。
    public func pbr(_ enabled: Bool) {
        currentMaterial.pbrParams.y = enabled ? 1 : 0
    }

    // MARK: - カスタムマテリアル

    /// 以降の描画コマンドにカスタムフラグメントシェーダーマテリアルを適用します。
    ///
    /// - Parameter custom: 適用するカスタムマテリアル。
    public func material(_ custom: CustomMaterial) {
        currentCustomMaterial = custom
    }

    /// カスタムマテリアルを除去し、組み込みシェーダーに戻します。
    public func noMaterial() {
        currentCustomMaterial = nil
    }

    // MARK: - テクスチャ

    /// 以降のテクスチャ付き描画コマンドにテクスチャを設定します。
    ///
    /// - Parameter img: テクスチャがバインドされる画像。
    public func texture(_ img: MImage) {
        currentTexture = img.texture
    }

    /// 現在バインドされているテクスチャを除去します。
    public func noTexture() {
        currentTexture = nil
    }
}
