import Foundation

// MARK: - @Interpolated

/// 型を伏せた ``Interpolated`` への参照。``Blendable`` の補間が使います。
@MainActor
protocol AnyInterpolatedBox: AnyObject {
    /// `a` と `b` の同じ位置の箱から補間した値を自分へ書き込みます。
    /// - Returns: 型が食い違って書けなかったときは `false`。
    @discardableResult
    func writeInterpolated(from a: AnyInterpolatedBox, to b: AnyInterpolatedBox, t: Float) -> Bool
}

/// プロパティを **補間の対象として宣言**するプロパティラッパー。
///
/// ``Blendable`` に適合したクラスの中で使うと、``Blendable/blend(_:_:_:)`` が
/// **宣言したフィールドを自動的に**補間します。フィールドを足しても補間側に
/// 書き足すものはありません。
///
/// ```swift
/// final class SceneProfile: Blendable {
///     @Interpolated var elevation: Float = 210
///     @Interpolated var bands: Int = 7               // Int は四捨五入で補間
///     @Interpolated var lightDirection = SIMD3<Float>(-0.4, 1, -0.6)
///     var name = "dawn"                              // 補間しない値はそのまま
///     init() {}
/// }
///
/// let profile = SceneProfile.blend(dawn, dusk, t)
/// ```
///
/// 値の型は ``Interpolatable``（`Float` / `Double` / `Int` / `SIMD2` / `SIMD3` /
/// `SIMD4` / ``Color``）である必要があります。
@propertyWrapper
@MainActor
public final class Interpolated<Value: Interpolatable>: AnyInterpolatedBox {
    /// 現在の値。
    public var wrappedValue: Value

    public init(wrappedValue: Value) {
        self.wrappedValue = wrappedValue
    }

    /// `$elevation` で箱そのものを取り出せます。
    public var projectedValue: Interpolated<Value> { self }

    @discardableResult
    func writeInterpolated(
        from a: AnyInterpolatedBox, to b: AnyInterpolatedBox, t: Float
    ) -> Bool {
        guard let from = a as? Interpolated<Value>, let to = b as? Interpolated<Value> else {
            return false
        }
        wrappedValue = Value.interpolate(from: from.wrappedValue, to: to.wrappedValue, t: t)
        return true
    }
}

// MARK: - Blendable

/// **値の束**（シーンのプロファイルなど）を 1 行で補間できるようにするプロトコル。
///
/// ``Interpolated`` で宣言したプロパティが自動的に補間対象になります。
/// 手書きの `blend` 関数（フィールドの数だけ行が並ぶもの）を置き換えるためのもので、
/// **フィールドを足したときに補間側へ書き足し忘れる**という壊れ方をなくします。
/// 書き忘れは型が通ってしまい、「そのパラメータだけ遷移せずカクッと切り替わる」という
/// 気付きにくい形で現れます（Issue #691）。
///
/// ```swift
/// final class SceneProfile: Blendable {
///     @Interpolated var elevation: Float = 210
///     @Interpolated var fogDensity: Float = 0.2
///     init() {}
/// }
///
/// // 4 シーンを巡回しながら遷移する
/// let current = SceneProfile.blend(from, to, ease(t))
/// ```
///
/// ## クラスであること
///
/// ``Interpolated`` は参照型（`final class`）なので、`struct` に入れるとコピーしても
/// 箱が共有され、片方を書き換えると両方が変わってしまいます。そのため ``Blendable``
/// は `AnyObject` に限定しています（`@Param` と同じ流儀）。
///
/// ## 補間されないプロパティ
///
/// ``Interpolated`` を付けていないプロパティは補間されません。
/// ``blend(_:_:_:)`` は新しいインスタンスを `init()` で作るため、それらは
/// **宣言時の既定値**になります。`a` の値を引き継ぎたいときは、インスタンス版の
/// ``blend(from:to:t:)`` で手元のオブジェクトへ書き込んでください
/// （毎フレーム確保しないので、遷移の常用にはこちらが向きます）。
@MainActor
public protocol Blendable: AnyObject {
    /// 補間結果を入れる新しいインスタンスを作るために使います。
    init()
}

extension Blendable {
    /// `a` と `b` を `t` で補間した**新しいインスタンス**を返します。
    ///
    /// - Parameters:
    ///   - a: `t = 0` のときの値。
    ///   - b: `t = 1` のときの値。
    ///   - t: 補間係数。オーバーシュートするイージングのためにクランプしません。
    public static func blend(_ a: Self, _ b: Self, _ t: Float) -> Self {
        let result = Self()
        result.blend(from: a, to: b, t: t)
        return result
    }

    /// `a` と `b` を `t` で補間した値を**自分自身へ**書き込みます。
    ///
    /// 新しいインスタンスを作らないので、毎フレーム呼ぶ遷移に向きます。
    /// ``Interpolated`` を付けていないプロパティには触れません。
    public func blend(from a: Self, to b: Self, t: Float) {
        let target = InterpolatedBoxScanner.boxes(of: self)
        let from = InterpolatedBoxScanner.boxes(of: a)
        let to = InterpolatedBoxScanner.boxes(of: b)

        // 3 つとも同じ型なので、Mirror の子は同じ順序・同じ個数で並ぶ。
        // 万一ずれていたら黙って壊れた絵を出すより気付ける形にする。
        guard target.count == from.count, target.count == to.count else {
            metaphorWarning(
                "Blendable: \(String(describing: Self.self)) の @Interpolated の数が "
                    + "一致しません（target \(target.count) / from \(from.count) / to \(to.count)）")
            return
        }

        for index in target.indices {
            if !target[index].writeInterpolated(from: from[index], to: to[index], t: t) {
                metaphorWarning(
                    "Blendable: \(String(describing: Self.self)) の \(index) 番目の "
                        + "@Interpolated で型が一致しませんでした")
            }
        }
    }
}

/// `@Interpolated` の箱を宣言順に集める Mirror 走査（``Blendable`` の内部実装）。
///
/// 基底クラス側から順に走査するのは ``ParameterStore/discover(in:)`` と同じ流儀です
/// （継承したプロファイルでも順序が一致する）。
@MainActor
enum InterpolatedBoxScanner {
    static func boxes(of object: Any) -> [AnyInterpolatedBox] {
        var mirrors: [Mirror] = []
        var mirror: Mirror? = Mirror(reflecting: object)
        while let current = mirror {
            mirrors.append(current)
            mirror = current.superclassMirror
        }
        var result: [AnyInterpolatedBox] = []
        for current in mirrors.reversed() {
            for child in current.children {
                if let box = child.value as? AnyInterpolatedBox { result.append(box) }
            }
        }
        return result
    }
}
