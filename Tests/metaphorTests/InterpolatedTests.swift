import Foundation
import Testing
import simd

@testable import MetaphorCore

/// 値の束を 1 行で補間する（Issue #691）。
///
/// リファレンス作品 #414 では 4 シーンを 25 フィールドの profile として持ち、遷移を
/// 2 つの profile の補間で行った。そのとき手書きになったのが `blend` そのもので、
/// フィールドを 1 つ足すたびに補間側にも書き足す必要があった。**書き忘れても型は通り**、
/// 「そのパラメータだけ遷移せずカクッと切り替わる」という気付きにくい壊れ方をする
/// （実際 `fill` / `rim` を足したときに一度忘れた）。
@Suite("@Interpolated / Blendable")
@MainActor
struct InterpolatedTests {

    /// 作品の `SceneProfile` を小さくしたもの。
    final class Profile: Blendable {
        @Interpolated var elevation: Float = 0
        @Interpolated var bands: Int = 0
        @Interpolated var lightDirection = SIMD3<Float>(0, 0, 0)
        @Interpolated var tint = Color(r: 0, g: 0, b: 0)
        var name = "default"  // 補間対象ではない
        init() {}

        convenience init(
            elevation: Float, bands: Int, lightDirection: SIMD3<Float>, tint: Color, name: String
        ) {
            self.init()
            self.elevation = elevation
            self.bands = bands
            self.lightDirection = lightDirection
            self.tint = tint
            self.name = name
        }
    }

    private var dawn: Profile {
        Profile(
            elevation: 100, bands: 4, lightDirection: SIMD3(0, 1, 0),
            tint: Color(r: 1, g: 0, b: 0), name: "dawn"
        )
    }

    private var dusk: Profile {
        Profile(
            elevation: 300, bands: 8, lightDirection: SIMD3(1, 0, 1),
            tint: Color(r: 0, g: 0, b: 1), name: "dusk"
        )
    }

    // MARK: - 補間そのもの

    @Test("宣言しただけで全フィールドが補間される")
    func blendsEveryDeclaredField() {
        let mid = Profile.blend(dawn, dusk, 0.5)
        #expect(mid.elevation == 200)
        #expect(mid.bands == 6)
        #expect(mid.lightDirection == SIMD3<Float>(0.5, 0.5, 0.5))
        #expect(mid.tint.r == 0.5)
        #expect(mid.tint.b == 0.5)
    }

    @Test("端点はそのままの値になる")
    func endpointsAreExact() {
        let start = Profile.blend(dawn, dusk, 0)
        #expect(start.elevation == 100)
        #expect(start.bands == 4)

        let end = Profile.blend(dawn, dusk, 1)
        #expect(end.elevation == 300)
        #expect(end.bands == 8)
    }

    @Test("Int は四捨五入で補間される")
    func intRounds() {
        #expect(Profile.blend(dawn, dusk, 0.1).bands == 4)   // 4.4 → 4
        #expect(Profile.blend(dawn, dusk, 0.2).bands == 5)   // 4.8 → 5
        #expect(Profile.blend(dawn, dusk, 0.75).bands == 7)
    }

    @Test("t はクランプしない（オーバーシュートするイージングのため）")
    func doesNotClampT() {
        #expect(Profile.blend(dawn, dusk, 1.5).elevation == 400)
        #expect(Profile.blend(dawn, dusk, -0.5).elevation == 0)
    }

    // MARK: - 書き忘れが起きない

    @Test("フィールドを足しても補間側に書き足すものはない")
    func newFieldsParticipateAutomatically() {
        /// `Profile` にフィールドを 1 つ足した想定のクラス。
        /// 補間のコードは 1 行も書いていないが、追加分も補間される。
        final class Extended: Blendable {
            @Interpolated var elevation: Float = 0
            @Interpolated var rim: Float = 0  // 後から足したフィールド
            init() {}
        }

        let a = Extended()
        a.elevation = 0
        a.rim = 10
        let b = Extended()
        b.elevation = 100
        b.rim = 30

        let mid = Extended.blend(a, b, 0.5)
        #expect(mid.elevation == 50)
        #expect(mid.rim == 20)  // 書き足していないのに補間されている
    }

    @Test("継承したプロファイルでも基底クラスのフィールドが補間される")
    func inheritedFieldsBlend() {
        class Base: Blendable {
            @Interpolated var base: Float = 0
            required init() {}
        }
        final class Derived: Base {
            @Interpolated var extra: Float = 0
        }

        let a = Derived()
        a.base = 0
        a.extra = 0
        let b = Derived()
        b.base = 10
        b.extra = 100

        let mid = Derived.blend(a, b, 0.5)
        #expect(mid.base == 5)
        #expect(mid.extra == 50)
    }

    // MARK: - 補間しないフィールド

    @Test("インスタンス版は @Interpolated 以外に触れない")
    func instanceBlendLeavesOtherFieldsAlone() {
        let current = Profile()
        current.name = "keep me"
        current.blend(from: dawn, to: dusk, t: 0.5)

        #expect(current.elevation == 200)
        #expect(current.name == "keep me")  // 触られていない
    }

    @Test("static 版が作る新しいインスタンスでは非補間フィールドが既定値になる")
    func staticBlendUsesDeclaredDefaults() {
        // 仕様として固定する（DocC にも明記してある）。
        #expect(Profile.blend(dawn, dusk, 0.5).name == "default")
    }

    // MARK: - Interpolatable の追加適合

    @Test("Int / Double が Interpolatable に適合している")
    func newConformances() {
        #expect(Int.interpolate(from: 0, to: 10, t: 0.5) == 5)
        #expect(Int.interpolate(from: 0, to: 10, t: 0.44) == 4)
        #expect(Double.interpolate(from: 0, to: 1, t: 0.25) == 0.25)
    }
}
