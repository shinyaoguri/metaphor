import Metal
import simd

// 記録 → 再生経路（影オン、または METAPHOR_COMMAND_RECORD）の状態管理。
// 記録そのものは drawMesh（Canvas3D+MeshDrawing.swift）が行う。
extension Canvas3D {
    // MARK: - 記録・再生（#70 / #71 / #201）

    /// 再生中に退避した描画状態（`beginReplay`/`endReplay` で保存・復元）。
    struct ReplaySavedState {
        var transform: float4x4
        var fillColor: SIMD4<Float>
        var material: Material3D
        var customMaterial: CustomMaterial?
        var texture: MTLTexture?
        var hasFill: Bool
        var hasStroke: Bool
        var strokeColor: SIMD4<Float>
        // カメラ/ライト（#201: スナップショット適用で書き換えるため保存・復元する）
        var cameraEye: SIMD3<Float>
        var lights: [Light3D]
        var cachedViewProjection: float4x4
        var viewProjectionDirty: Bool
    }

    /// 現在のカメラ/投影/ライト状態のスナップショットを返します（変化がなければ
    /// 直前のインスタンスを再利用。参照同一性が「状態が同じ」を意味する）。
    func snapshotForRecording() -> RenderStateSnapshot3D {
        let vp = computeViewProjection()
        if let snap = currentStateSnapshot,
           snap.viewProjection == vp,
           snap.cameraEye == cameraEye,
           snap.lights == lightArray {
            return snap
        }
        let snap = RenderStateSnapshot3D(viewProjection: vp, cameraEye: cameraEye, lights: lightArray)
        currentStateSnapshot = snap
        return snap
    }

    /// 再生時にスナップショットの状態を復元します（#201）。
    /// cachedViewProjection を直接差し替えるため、以降の computeViewProjection() は
    /// スナップショットの行列を返す。
    private func applySnapshot(_ snap: RenderStateSnapshot3D) {
        cameraEye = snap.cameraEye
        lightArray = snap.lights
        cachedViewProjection = snap.viewProjection
        viewProjectionDirty = false
    }

    /// 記録済みドローコールの再生を開始します（#70 / #71）。
    ///
    /// `performShadowPass` で `shadow.shadowTexture` が当該フレームの内容（影N）に
    /// 更新された後に呼ぶこと。`replayRecordedRange` で範囲ごとに再投入し、`endReplay`
    /// で締める。2D と呼び出し順でインターリーブするため、再生は範囲分割される（#71・宿題①）。
    func beginReplay(encoder: MTLRenderCommandEncoder) {
        replaySaved = ReplaySavedState(
            transform: currentTransform, fillColor: fillColor,
            material: currentMaterial, customMaterial: currentCustomMaterial,
            texture: currentTexture, hasFill: hasFill,
            hasStroke: hasStroke, strokeColor: strokeColor,
            cameraEye: cameraEye, lights: lightArray,
            cachedViewProjection: cachedViewProjection,
            viewProjectionDirty: viewProjectionDirty)
        self.encoder = encoder
        isReplaying = true
    }

    /// 記録済みドローコールの指定レンジをメインパスへ再投入し、末尾でインスタンスバッチを
    /// 確定します。run（呼び出し順の連続する 3D 区間）単位で呼ぶ。末尾フラッシュにより、
    /// 続く 2D 描画が必ずこの 3D run の後に来る（呼び出し順の保証）。
    func replayRecordedRange(_ range: Range<Int>) {
        guard isReplaying, !recordedDrawCalls.isEmpty else { return }
        let clamped = range.clamped(to: 0..<recordedDrawCalls.count)
        for call in recordedDrawCalls[clamped] {
            // 呼び出し時点のカメラ/ライトを復元（#201）。インスタンスバッチの
            // ユニフォームは flush 時の状態で確定するため、スナップショットが
            // 変わる境界では先にバッチを確定する（同一スナップショットは
            // インスタンス間で参照共有されるので、切替時のみ flush が走る）。
            if let snap = call.stateSnapshot {
                if snap !== lastReplaySnapshot {
                    flushInstanceBatch()
                    applySnapshot(snap)
                    lastReplaySnapshot = snap
                }
            }
            currentTransform = call.transform
            fillColor = call.fillColor
            currentMaterial = call.material
            currentCustomMaterial = call.customMaterial
            currentTexture = call.texture
            hasFill = call.hasFill
            hasStroke = call.hasStroke
            strokeColor = call.strokeColor
            drawMesh(call.mesh)
        }
        flushInstanceBatch()
    }

    /// 再生を終了し、描画状態を復元します（#70 / #71）。
    func endReplay() {
        flushInstanceBatch()
        isReplaying = false
        self.encoder = nil
        lastReplaySnapshot = nil
        if let s = replaySaved {
            currentTransform = s.transform
            fillColor = s.fillColor
            currentMaterial = s.material
            currentCustomMaterial = s.customMaterial
            currentTexture = s.texture
            hasFill = s.hasFill
            hasStroke = s.hasStroke
            strokeColor = s.strokeColor
            cameraEye = s.cameraEye
            lightArray = s.lights
            cachedViewProjection = s.cachedViewProjection
            viewProjectionDirty = s.viewProjectionDirty
        }
        replaySaved = nil
    }
}
