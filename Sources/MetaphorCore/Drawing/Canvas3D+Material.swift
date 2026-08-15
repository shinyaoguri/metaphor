import Metal
import simd

// MARK: - ToneMapMode

/// 3D のライティング結果を 0…1 へ写像する方法。
///
/// レンダーターゲットは LDR（8bit）なので、ライティング結果が 1.0 を超えると
/// そのままではハードクランプされ、ハイライトが白く潰れます。トーンマッピングは
/// 高輝度側を滑らかに丸めて階調を残します。
///
/// - Note: 掛かるのは **3D のライティング結果だけ**です。2D の描画の色は変わりません。
public enum ToneMapMode: Int, CaseIterable, Hashable, Sendable {
    /// トーンマッピングなし（**既定**）。1.0 を超えた値はクランプされます。
    case none = 0
    /// Reinhard（`x / (1 + x)`）。単純で色相が安定しますが、中間調は眠くなります。
    case reinhard = 1
    /// ACES filmic 近似。暗部を締めてハイライトを滑らかに丸めます。
    /// 金属や強い光源のある絵ではこちらが破綻しにくいです。
    case acesFilmic = 2
}

extension Canvas3D {
    // MARK: - トーンマッピング

    /// 3D のライティング結果に適用するトーンマッピングを設定します。
    ///
    /// - Parameter mode: トーンマッピングの方法。
    public func toneMapping(_ mode: ToneMapMode) {
        // 明示指定を記録しておく。`environment()` は未指定のときだけ
        // `.acesFilmic` へ自動昇格させる（#710）。
        userSetToneMapping = true
        toneMapParams.x = Float(mode.rawValue)
        currentMaterial.toneMapParams = toneMapParams
    }

    /// トーンマッピング前に掛ける露出倍率を設定します。
    ///
    /// - Parameter value: 露出倍率（既定 1.0）。
    public func exposure(_ value: Float) {
        toneMapParams.y = value
        currentMaterial.toneMapParams = toneMapParams
    }

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

    /// チャンネル値でスペキュラハイライト色を設定します。
    ///
    /// 値は `fill` などと同じく **`colorMode` のレンジ基準**（既定 0〜255）です。
    ///
    /// - Parameters:
    ///   - v1: 第1カラーチャンネル値（赤または色相）。
    ///   - v2: 第2カラーチャンネル値（緑または彩度）。
    ///   - v3: 第3カラーチャンネル値（青または明度）。
    public func specular(_ v1: Float, _ v2: Float, _ v3: Float) {
        let c = colorModeConfig.toColor(v1, v2, v3, nil)
        currentMaterial.specularAndShininess = SIMD4(
            c.r, c.g, c.b,
            currentMaterial.specularAndShininess.w
        )
    }

    /// グレースケール値でスペキュラハイライト色を設定します。
    ///
    /// 値は `fill` などと同じく **`colorMode` のレンジ基準**（既定 0〜255）です。
    ///
    /// - Parameter gray: 全チャンネルに適用されるグレースケール強度。
    public func specular(_ gray: Float) {
        let c = colorModeConfig.toGray(gray)
        currentMaterial.specularAndShininess = SIMD4(
            c.r, c.g, c.b,
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

    /// チャンネル値でエミッシブ色を設定します。
    ///
    /// 値は `fill` などと同じく **`colorMode` のレンジ基準**（既定 0〜255）です。
    ///
    /// - Parameters:
    ///   - v1: 第1カラーチャンネル値（赤または色相）。
    ///   - v2: 第2カラーチャンネル値（緑または彩度）。
    ///   - v3: 第3カラーチャンネル値（青または明度）。
    public func emissive(_ v1: Float, _ v2: Float, _ v3: Float) {
        let c = colorModeConfig.toColor(v1, v2, v3, nil)
        currentMaterial.emissiveAndMetallic = SIMD4(
            c.r, c.g, c.b,
            currentMaterial.emissiveAndMetallic.w
        )
    }

    /// グレースケール値でエミッシブ色を設定します。
    ///
    /// 値は `fill` などと同じく **`colorMode` のレンジ基準**（既定 0〜255）です。
    ///
    /// - Parameter gray: 全チャンネルに適用されるグレースケール強度。
    public func emissive(_ gray: Float) {
        let c = colorModeConfig.toGray(gray)
        currentMaterial.emissiveAndMetallic = SIMD4(
            c.r, c.g, c.b,
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
