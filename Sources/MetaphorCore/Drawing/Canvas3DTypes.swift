import Metal
import simd

// MARK: - Canvas3D ユニフォーム

/// Canvas3D シェーダー用のユニフォームデータ。MSL の `Canvas3DUniforms` レイアウトに対応します。
struct Canvas3DUniforms {
    var modelMatrix: float4x4
    var viewProjectionMatrix: float4x4
    var normalMatrix: float4x4
    var color: SIMD4<Float>
    var cameraPosition: SIMD4<Float>
    var time: Float
    var lightCount: UInt32
    var hasTexture: UInt32
    var _pad: UInt32 = 0
}

// MARK: - Light3D

/// GPU 互換のライトデータ（64バイト、16バイトアラインメント）。
struct Light3D {
    var positionAndType: SIMD4<Float>           // xyz=位置, w=タイプ(0=ディレクショナル,1=ポイント,2=スポット)
    var directionAndCutoff: SIMD4<Float>        // xyz=方向, w=cos(内側カットオフ)
    var colorAndIntensity: SIMD4<Float>         // xyz=色, w=強度
    var attenuationAndOuterCutoff: SIMD4<Float> // xyz=(定数,線形,二次), w=cos(外側カットオフ)

    static let zero = Light3D(
        positionAndType: .zero,
        directionAndCutoff: .zero,
        colorAndIntensity: .zero,
        attenuationAndOuterCutoff: .zero
    )
}

// スナップショットの変更検出（#201）に使用
extension Light3D: Equatable {}

// MARK: - Material3D

/// GPU 互換のマテリアルデータ（64バイト）。
struct Material3D {
    var ambientColor: SIMD4<Float>         // xyz=アンビエント色
    var specularAndShininess: SIMD4<Float> // xyz=スペキュラ色, w=光沢度
    var emissiveAndMetallic: SIMD4<Float>  // xyz=エミッシブ色, w=メタリック
    var pbrParams: SIMD4<Float>            // x=ラフネス, y=usePBR(0/1), z=ao, w=予約

    static let `default` = Material3D(
        ambientColor: SIMD4(0.2, 0.2, 0.2, 0),
        specularAndShininess: SIMD4(0, 0, 0, 32),
        emissiveAndMetallic: SIMD4(0, 0, 0, 0),
        pbrParams: SIMD4(0.5, 0, 1, 0)    // roughness=0.5, usePBR=off, ao=1, reserved=0
    )
}
