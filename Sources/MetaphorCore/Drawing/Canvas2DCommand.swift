import Metal
import simd

// MARK: - 2D 遅延コマンド（#71）
//
// #70 では 2D の遅延描画を `Canvas2D.deferredDraws: [(MTLRenderCommandEncoder) -> Void]`
// のクロージャ捕捉で表現していた。これは型情報を持たず、検査・順序マージ・テストができない
// （ADR-0003 の宿題④）。#71 はこれを明示コマンド型へ昇格する。
//
// 本ファイルは PR-1 時点では「型の置き場」であり、まだ flush 群とは配線されていない
// （`deferredDraws` クロージャ経路が現役）。PR-2 で flush 群がこの enum を積むように
// 載せ替え、PR-3 で 3D（`DrawCall3D`）と seq 昇順マージして単一メインパスへ再生する。

/// 遅延記録された 2D 描画コマンド1件。クロージャ捕捉（#70）を置き換える明示表現。
///
/// ペイロードは「コマンドごとに変わるデータ」のみを持つ。頂点バッファ・投影行列・
/// デプスステンシルステートといったフレーム定数や Canvas2D の内部状態は、再生時に
/// Canvas2D 側が補う（PR-2 で実装）。
enum Deferred2DCommand {
    /// 色付き頂点バッチ（`flushColorVertices` 相当）。
    case colorBatch(blend: BlendMode, vertexStart: Int, vertexCount: Int)

    /// テクスチャ付き頂点バッチ（`flushTexturedVertices` 相当）。
    case texturedBatch(blend: BlendMode, vertexStart: Int, vertexCount: Int, texture: MTLTexture)

    /// インスタンス描画バッチ（`flushInstancedBatch` 相当）。
    case instancedBatch(blend: BlendMode, instanceStart: Int, instanceCount: Int)

    /// massive 円インスタンス（`Canvas2DMassive.drawCircleInstances` 相当・宿題②）。
    case massiveCircles(blend: BlendMode, buffer: MTLBuffer, byteOffset: Int, count: Int)

    /// クリップ（scissor）の設定・解除（`beginClip`/`endClip` 相当・宿題③）。
    /// `nil` はクリップ解除（フルビューポート）。
    case setScissor(MTLScissorRect?)
}

/// 呼び出し順（seq）でタグ付けした 2D 遅延コマンド。
struct Deferred2DSlot {
    let seq: UInt32
    let command: Deferred2DCommand
}

// MARK: - 呼び出し順マージ（基盤・PR-3 の interleave 再生で使用）

/// seq 昇順の 2 ストリーム（3D の `DrawCall3D` と 2D の `Deferred2DSlot`）を
/// 呼び出し順の単一列へマージする純粋ユーティリティ。
///
/// 各ストリームは append 順＝単調増加 seq 前提。seq は `SketchContext` の単一カウンタから
/// 払い出されるため両ストリーム横断で一意（同値タイなし）。線形 O(n+m) マージ。
enum DrawStreamMerge {
    /// マージ結果の1要素。元ストリームと、そのストリーム内インデックスを指す。
    enum Slot: Equatable {
        case threeD(index: Int)
        case twoD(index: Int)
    }

    /// 3D / 2D の seq 列を受け取り、呼び出し順（seq 昇順）に並べたスロット列を返す。
    /// - Parameters:
    ///   - threeDSeqs: 記録順（= seq 昇順）に並んだ 3D ドローコールの seq 列。
    ///   - twoDSeqs: 記録順（= seq 昇順）に並んだ 2D コマンドの seq 列。
    static func mergeOrder(threeDSeqs: [UInt32], twoDSeqs: [UInt32]) -> [Slot] {
        var result: [Slot] = []
        result.reserveCapacity(threeDSeqs.count + twoDSeqs.count)
        var i = 0
        var j = 0
        while i < threeDSeqs.count && j < twoDSeqs.count {
            if threeDSeqs[i] <= twoDSeqs[j] {
                result.append(.threeD(index: i))
                i += 1
            } else {
                result.append(.twoD(index: j))
                j += 1
            }
        }
        while i < threeDSeqs.count {
            result.append(.threeD(index: i))
            i += 1
        }
        while j < twoDSeqs.count {
            result.append(.twoD(index: j))
            j += 1
        }
        return result
    }
}
