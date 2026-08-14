import Foundation

/// ``Sketch/saveState()`` / ``Sketch/restoreState(_:)`` に `Codable` を素直に載せるための
/// ヘルパー。
///
/// JSON エンコーダ/デコーダの生成とエラー処理を毎回書かずに済ませるためだけのもので、
/// フックの契約（`Data?` を返す / `Data` を受け取る）は変えません。独自形式
/// （バイナリ・圧縮など）を使いたい場合はこれを使わず `Data` を直接組み立ててください。
extension Sketch {
    /// 状態を JSON へエンコードします。失敗したら `nil`（= 状態を保存しない）。
    ///
    /// - Parameter value: 保存したい値。
    public func encodeState<T: Encodable>(_ value: T) -> Data? {
        do {
            return try JSONEncoder().encode(value)
        } catch {
            metaphorDiagnostic("state: saveState() のエンコードに失敗しました: \(error)")
            return nil
        }
    }

    /// ``restoreState(_:)`` で受け取ったデータをデコードします。失敗したら `nil`。
    ///
    /// 型は代入先から推論できます（`guard let s: SimState = decodeState(data)`）。
    ///
    /// - Parameters:
    ///   - data: ``restoreState(_:)`` に渡されたデータ。
    ///   - type: デコードする型（通常は推論に任せます）。
    public func decodeState<T: Decodable>(_ data: Data, as type: T.Type = T.self) -> T? {
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            // スケッチのコードを書き換えて状態の形が変わった直後は必ずここを通る
            // （= リロード中の日常）。黙って初期状態へ倒すのが既定の振る舞い。
            metaphorDiagnostic("state: restoreState() のデコードに失敗しました（初期状態のまま続行）: \(error)")
            return nil
        }
    }
}
