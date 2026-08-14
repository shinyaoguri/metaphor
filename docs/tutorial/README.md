# チュートリアル — 章立てと執筆規約

**日本語** | English (後追い予定)

metaphor の体系的チュートリアル（読み物）の設計図です。この文書は Epic [#483](https://github.com/shinyaoguri/metaphor/issues/483) の第 1 弾 [#484](https://github.com/shinyaoguri/metaphor/issues/484) として、**執筆を始める前に情報アーキテクチャを確定させる**ために置かれました。以降は執筆規約の正典として使います。

- 各部の本文は `docs/tutorial/NN-slug.md` として、この章立てのとおりに追加されます
- 本文が揃った部から website のチュートリアル領域（[#487](https://github.com/shinyaoguri/metaphor/issues/487)）で公開されます
- 執筆はパイロット（第 1 部・第 2 部、[#488](https://github.com/shinyaoguri/metaphor/issues/488)）から始め、手応えを見て第 3 部以降を起票します

現在の本文:

| 部 | ファイル | 状態 |
|---|---|---|
| 第 1 部 入門 | [`01-getting-started.md`](01-getting-started.md) | 公開 |
| 第 2 部 2D を描く | [`02-drawing-2d.md`](02-drawing-2d.md) | 公開 |
| 第 3 部 動かす | [`03-motion.md`](03-motion.md) | 公開 |
| 第 4 部 入力を受ける | [`04-input.md`](04-input.md) | 公開 |
| 第 5 部 3D へ | [`05-3d.md`](05-3d.md) | 公開 |
| 第 6 部 GPU を使う | [`06-gpu.md`](06-gpu.md) | 公開 |
| 第 7 部 メディア | [`07-media.md`](07-media.md) | 公開 |
| 第 8 部 外とつなぐ | [`08-connect.md`](08-connect.md) | 公開 |
| 第 9 部 作品にする | [`09-artwork.md`](09-artwork.md) | 公開 |
| 第 10 部 AI と作る | [`10-ai.md`](10-ai.md) | 公開 |

## 対象読者と、他ドキュメントとの役割分担

対象読者は **Processing 経験を前提としない初心者**です。「Swift は書ける / 書いたことがある。グラフィックスプログラミングは初めて」という人が、最初から順に読んで作品を作れるようになることを目指します。

metaphor のドキュメントは読者と用途で分かれています。チュートリアルは**通しで読む**もので、他は**引く**ものです。

| ドキュメント | 読者 | 使い方 |
|---|---|---|
| **チュートリアル**（本ディレクトリ） | 初心者。metaphor が初めて | 最初から順に読む。各節に完結したコードと実行結果が付く |
| [API リファレンス（DocC）](https://shinyaoguri.github.io/metaphor/reference/documentation/metaphor/) | 型やメソッドのシグネチャを知りたい人 | 引く。チュートリアルの各節から深いリンクを張る |
| [`llms.txt`](../../llms.txt) | AI エージェント | 引く（コンテキストに貼る） |
| [processing-migration-guide.md](../processing-migration-guide.md) | Processing / p5.js の既習者 | 引く。「Processing の X は metaphor では Y」の対応表 |
| [Examples/LEARNING_PATH.md](../../Examples/LEARNING_PATH.md) | チュートリアルを読み終えた人 | Examples を掘るための地図 |
| [docs/ai/examples-index.md](../ai/examples-index.md) | やりたいことから探す人 | 引く（全サンプルの索引・生成物） |

チュートリアルは**代表コードで語る**もので、Examples 全本の解説ではありません。「もっと例が見たい」に対しては LEARNING_PATH と索引へ送り出します。

## 章立て

10 部構成。各節は「1 節 = 1 つの完結したスケッチ」を原則とします。

表の「対応する既存 example」は、その節の題材と重なる既存サンプルです。チュートリアル本文のコードはこれを流用するのではなく、[Examples/Tutorial/](#コードの置き方) に節専用のスケッチを新しく置きます（既存サンプルは Processing 移植で、説明の流れに合わせて書かれていないため）。空欄は該当サンプルが無いことを示し、その節の題材は新規に書き起こします。

### 第 1 部 入門

| 節 | 学ぶこと | 主な API | 対応する既存 example |
|---|---|---|---|
| 1.1 metaphor とは | 何ができるライブラリか、動作環境（macOS / Apple Silicon）、ドキュメントの地図 | — | — |
| 1.2 インストールと最初のスケッチ | CLI の導入、`metaphor new` / `metaphor run`、ウィンドウが出るまで | — | — |
| 1.3 スケッチの骨格 | `Sketch` プロトコル、`config` / `setup()` / `draw()` の役割分担、`@main` | `SketchConfig` | `Basics/Structure/SetupDraw` |
| 1.4 キャンバスと座標系 | 原点は左上、`width` / `height`、レンダリング解像度とウィンドウサイズの分離 | `width`, `height`, `createCanvas`, `windowScale` | `Basics/Structure/Coordinates`, `Basics/Structure/WidthHeight` |
| 1.5 ライブ編集 | `metaphor watch` で保存のたびに再ビルド、ライブビューア窓を保ったまま直す | — | — |
| 1.6 描画を止める・進める | 連続描画と単一フレーム、フレームレートの指定 | `noLoop()`, `loop()`, `redraw()`, `frameRate()` | `Basics/Structure/NoLoop`, `Basics/Structure/Loop`, `Basics/Structure/Redraw` |

### 第 2 部 2D を描く

| 節 | 学ぶこと | 主な API | 対応する既存 example |
|---|---|---|---|
| 2.1 図形プリミティブ | 円・矩形・線・三角形・弧の描き分け、描画モード | `circle`, `rect`, `ellipse`, `line`, `triangle`, `quad`, `arc`, `point`, `rectMode`, `ellipseMode` | `Basics/Form/ShapePrimitives`, `Basics/Form/PointsLines`, `Basics/Form/PieChart` |
| 2.2 色 | RGB とグレースケール、アルファ、`colorMode` による HSB | `background`, `fill`, `stroke`, `noFill`, `noStroke`, `colorMode`, `lerpColor` | `Basics/Color/Hue`, `Basics/Color/Saturation`, `Basics/Color/LinearGradient` |
| 2.3 線の表情 | 太さ、端点・角の処理、線だけで描く | `strokeWeight`, `strokeCap`, `strokeJoin` | `Basics/Form/PointsLines`, `Topics/Drawing/ContinuousLines` |
| 2.4 自分で形を作る | 頂点列から任意の形、曲線、穴あき（凹多角形） | `beginShape`, `vertex`, `endShape`, `bezier`, `curveVertex`, `beginContour` | `Basics/Form/TriangleStrip`, `Basics/Form/Star`, `Topics/Create Shapes/PolygonPShape`, `Topics/Create Shapes/BeginEndContour` |
| 2.5 変換と push / pop | 座標系を動かして描く、変換の入れ子、スタックの規律 | `translate`, `rotate`, `scale`, `push`, `pop` | `Basics/Transform/Translate`, `Basics/Transform/Rotate`, `Basics/Transform/RotatePushPop`, `Basics/Transform/Arm` |
| 2.6 くり返しで模様を作る | ループとグリッド、入れ子ループ、乱数を混ぜる前の構成力 | `for` + 変換 | `Basics/Control/Iteration`, `Basics/Control/EmbeddedIteration` |
| 2.7 テキスト | 文字を描く、サイズと配置、フォントの現状の制約（[#292](https://github.com/shinyaoguri/metaphor/issues/292)） | `text`, `textSize`, `textAlign` | `Basics/Typography/Words`, `Basics/Typography/Letters`, `Basics/Typography/TextRotation` |
| 2.8 画像 | 読み込みと表示、色を乗せる、透明度 | `loadImage`, `image`, `tint`, `imageMode` | `Basics/Image/LoadDisplayImage`, `Basics/Image/Transparency`, `Basics/Image/BackgroundImage` |
| 2.9 ピクセルを直接触る | 画素配列の読み書きと、その代償（[#267](https://github.com/shinyaoguri/metaphor/issues/267)） | `loadPixels`, `updatePixels`, `createImage` | `Basics/Image/CreateImage`, `Topics/Image Processing/BrightnessPixels`, `Topics/Image Processing/Blur` |
| 2.10 ブレンドモード | 加算・乗算などの合成、光の表現 | `blendMode` | `Topics/Image Processing/Blending` |

### 第 3 部 動かす

| 節 | 学ぶこと | 主な API | 対応する既存 example |
|---|---|---|---|
| 3.1 時間を使う | フレーム番号と経過時間、フレームレート非依存の動き | `frameCount`, `time`, `deltaTime` | `Topics/Motion/Linear`, `Basics/Input/Milliseconds` |
| 3.2 数値を変換する | 範囲の作り替え、制限、補間 | `map`, `constrain`, `lerp` | `Basics/Math/Map`, `Basics/Input/Constrain`, `Basics/Math/Interpolate` |
| 3.3 イージング | 目標値へ追従させる、慣性のある動き | `lerp` + 状態 | `Basics/Input/Easing`, `Topics/Interaction/Follow1` |
| 3.4 三角関数で動かす | 円運動、波、振動 | `sin`, `cos`, `atan2`, `TWO_PI` | `Basics/Math/SineCosine`, `Basics/Math/SineWave`, `Basics/Math/AdditiveWave`, `Basics/Math/Arctangent` |
| 3.5 乱数 | 一様乱数と正規分布、再現性（シード） | `random`, `randomGaussian`, `randomSeed` | `Basics/Math/Random`, `Basics/Math/RandomGaussian`, `Basics/Math/DoubleRandom` |
| 3.6 ノイズ | Perlin ノイズで「自然な」ゆらぎ、次元を上げる | `noise`（1D / 2D / 3D）, `noiseSeed` | `Basics/Math/Noise1D`, `Basics/Math/Noise2D`, `Basics/Math/Noise3D`, `Basics/Math/NoiseWave` |
| 3.7 ベクトル | 位置・速度・加速度をベクトルで扱う | `Vec2`, `Vec3` | `Topics/Vectors/VectorMath`, `Topics/Vectors/BouncingBall`, `Topics/Vectors/AccelerationWithVectors` |
| 3.8 たくさんのものを動かす | 配列と構造体 / クラス、毎フレームの更新と描画の分離 | Swift の型 + `draw()` | `Basics/Objects/Objects`, `Topics/Motion/BouncyBubbles` |
| 3.9 パーティクル | 生成・寿命・消滅、力を加える | `ParticleSystem` | `Topics/Simulate/SimpleParticleSystem`, `Topics/Simulate/SmokeParticleSystem`, `Topics/Simulate/ForcesWithVectors` |
| 3.10 数を増やす | 数万個を破綻させずに描く、自動バッチと明示バッチの境目 | 一括描画 API | `Demos/Performance/MassiveCircles` |

### 第 4 部 入力を受ける

| 節 | 学ぶこと | 主な API | 対応する既存 example |
|---|---|---|---|
| 4.1 マウス | 現在位置と前フレーム位置、押下状態、イベントコールバック | `mouseX`, `mouseY`, `pmouseX`, `pmouseY`, `isMousePressed`, `mousePressed()`, `mouseDragged()` | `Basics/Input/Mouse2D`, `Basics/Input/MousePress`, `Basics/Input/MouseFunctions`, `Basics/Input/StoringInput` |
| 4.2 キーボード | 押されたキーの読み取り、押しっぱなしと単発の違い | `key`, `keyCode`, `isKeyPressed`, `keyPressed()`, `keyReleased()` | `Basics/Input/Keyboard`, `Basics/Input/KeyboardFunctions` |
| 4.3 当たり判定と UI を自作する | 矩形・円の内外判定、ボタン・ロールオーバー・ドラッグ | 距離計算 + 状態 | `Topics/GUI/Button`, `Topics/GUI/Rollover`, `Topics/GUI/Handles`, `Topics/GUI/Scrollbar` |
| 4.4 ウィンドウ | フルスクリーン、リサイズ、複数ウィンドウ | `SketchConfig`（`fullScreen` ほか） | `Demos/Tests/ResizeTest`, `Demos/Tests/MultipleWindows` |

### 第 5 部 3D へ

| 節 | 学ぶこと | 主な API | 対応する既存 example |
|---|---|---|---|
| 5.1 3D 空間に入る | 2D と同じ語彙のまま奥行きを足す、既定のカメラ | `box`, `sphere`, `lights` | `Basics/Form/Primitives3D` |
| 5.2 プリミティブ | 箱・球・平面・円柱・トーラス、分割数 | `box`, `sphere`, `plane`, `cylinder`, `torus` | `Basics/Form/Primitives3D`, `Topics/Geometry/Toroid` |
| 5.3 3D の変換 | 軸まわりの回転、入れ子の座標系 | `rotateX/Y/Z`, `translate(x,y,z)`, `scale(x,y,z)` | `Basics/Transform/RotateXY`, `Topics/Motion/CubesWithinCube` |
| 5.4 カメラ | 視点・注視点、画角、透視投影と平行投影、マウスで視点を回す | `camera`, `perspective`, `ortho`, `orbitControl` | `Basics/Control/Camera/MoveEye`, `Basics/Control/Camera/Perspective`, `Basics/Control/Camera/Orthographic` |
| 5.5 ライティング | 環境光・平行光・点光源・スポット、鏡面反射 | `lights`, `directionalLight`, `pointLight`, `spotLight`, `ambientLight`, `specular` | `Basics/Lights/OnOff`, `Basics/Lights/Directional`, `Basics/Lights/Spot`, `Basics/Lights/Mixture`, `Basics/Lights/Reflection` |
| 5.6 マテリアルと PBR | Blinn-Phong と PBR の切り替え、金属感・粗さ | `specular`, `shininess`, `metallic`, `roughness`, `pbr` | `Basics/Lights/Reflection` |
| 5.7 影 | シャドウマップの有効化と、影が出ないときの見どころ | `enableShadows`, `shadowBias` | — |
| 5.8 テクスチャ | 画像を面に貼る、UV の考え方 | `texture`, `vertex(u:v:)` | `Topics/Textures/TextureQuad`, `Topics/Textures/TextureCube`, `Topics/Textures/TextureSphere` |
| 5.9 メッシュとモデル | 頂点から自作する、OBJ / USDZ / ABC を読み込む | `beginShape3D`, `normal`, `mesh`, `loadModel` | `Topics/Geometry/Vertices`, `Topics/Geometry/Icosahedra`, `Basics/Shape/LoadDisplayOBJ` |
| 5.10 大量の 3D | 同一形状の連続描画が自動バッチされる仕組み、明示インスタンシング | `drawInstanced`, `createBoxMesh` | `Samples/InstancedCubes`, `Demos/Performance/CubicGridImmediate` |

### 第 6 部 GPU を使う

| 節 | 学ぶこと | 主な API | 対応する既存 example |
|---|---|---|---|
| 6.1 GPU に計算させる | `compute()` フックの位置づけ、MSL カーネルを書いて呼ぶ、CPU との往復の考え方 | `createComputeKernel`, `compute()` | — |
| 6.2 GPU パーティクル | 100 万粒子を CPU に降ろさず動かす | `createParticleSystem` | `Demos/Performance/DynamicParticlesImmediate` |
| 6.3 ポストプロセス | 描き終えた絵に効果をかける、組み込みエフェクトの重ねがけ | `addPostEffect`, `BloomEffect` ほか | — |
| 6.4 カスタムポストエフェクト | 自分の MSL フラグメントシェーダーを効果として差し込む、保存だけで効く自動ホットリロード | `createPostEffect`, `createPostEffectFromFile` | — |
| 6.5 いまできないこと | 描画そのもののシェーダー差し替え（[#291](https://github.com/shinyaoguri/metaphor/issues/291)）は未実装。`Topics/Shaders/` の各例は元の GLSL を CPU で近似したもので、カスタムシェーダーの書き方の参考にはならない | — | — |

### 第 7 部 メディア

| 節 | 学ぶこと | 主な API | 対応する既存 example |
|---|---|---|---|
| 7.1 音を入力する | マイク入力、音量で絵を動かす、権限ダイアログ | `createAudioInput` | —（[permissions.md](../permissions.md) と CLI の `audio-reactive` テンプレートへ送り出す） |
| 7.2 音を分析する | FFT でスペクトルを取る、ビート検出 | `AudioAnalyzer` | — |
| 7.3 カメラ入力 | 接続カメラの列挙と切り替え、フレームをテクスチャとして使う | `listCaptureDevices`, `createCapture` | `Basics/Video/CameraSwitching` |
| 7.4 動画再生 | 動画をテクスチャとして再生する | 動画再生 API | `Basics/Video/VideoPlayback` |
| 7.5 機械学習 | Vision / Core ML を映像に重ねる | ML ブリッジ | `ML/FaceDetection`, `ML/PersonSegmentation`, `ML/ImageClassification`, `ML/StyleTransfer` |

### 第 8 部 外とつなぐ

| 節 | 学ぶこと | 主な API | 対応する既存 example |
|---|---|---|---|
| 8.1 OSC | 送受信、他アプリ・他マシンから操作する | `OSCSender`, `OSCReceiver`, `createOSCReceiver` | `Samples/OSCLoopback` |
| 8.2 MIDI | コントローラのノブを値に結ぶ | MIDI 入出力 API | — |
| 8.3 Syphon | 映像を他アプリへ流す、固定解像度出力 | `SketchConfig.syphonName`, `MetaphorSyphon` | `Samples/Syphon/SyphonOutput`, `Samples/Syphon/SyphonMultiWindow` |
| 8.4 パラメータを外に出す | `@Param` で調整値を宣言し、GUI と外部から動かす | `@Param`, `params`, `gui.params()` | `Samples/ParameterPanel` |

### 第 9 部 作品にする

| 節 | 学ぶこと | 主な API | 対応する既存 example |
|---|---|---|---|
| 9.1 静止画で書き出す | 1 枚保存、連番保存 | `save`, `saveFrame` | `Topics/File IO/SaveOneImage`, `Topics/File IO/SaveFrames` |
| 9.2 動画・GIF で書き出す | 録画の開始と終了、GIF ループ | `beginVideoRecord`, `endVideoRecord`, GIF API | — |
| 9.3 ベクタで書き出す | SVG 出力、ペンプロッタ向けの線画 | SVG エクスポート API | `Samples/SVGExport` |
| 9.4 きれいに焼き出す | 決定論レンダリング（固定 FPS・高解像度）、同じ絵を再現する | `noLoop`, 決定論レンダリング設定 | — |
| 9.5 長く動かす | 状態保持リロード、常駐時の注意点、パフォーマンス HUD | `StatePreservation` 系 API | `Samples/StatePreservation` |

### 第 10 部 AI と作る

| 節 | 学ぶこと | 主な API | 対応する既存 example |
|---|---|---|---|
| 10.1 観測ループという考え方 | AI が「いま見えている絵」を見て直せることの意味 | — | — |
| 10.2 内部状態を申告する | `probe()` で AI に見せたい値を渡す | `probe` | `Samples/ProbeSnapshot` |
| 10.3 MCP でつなぐ | `metaphor mcp` が公開する道具（snapshot / capture_sequence / input / params / set_param / build_status / api_reference） | `probe`, `@Param` | — |
| 10.4 人と AI で同じスケッチを見る | `metaphor watch` と共有セッション | — | — |
| 10.5 AI に metaphor 流を教える | `llms.txt` / `llms-sketch.txt` / [用途別プロンプト](../ai/prompts/) | — | — |

## 未実装領域の扱い

未実装の機能について**章や節を立てません**。関係する節の末尾に「いまできないこと」として現状と対応 Issue を書きます（例: 2.7 テキストにフォント読み込みの制約、6.5 に描画シェーダーの差し替え）。

| 領域 | Issue | 書く場所 |
|---|---|---|
| 2D カスタムシェーダ（`loadShader` / `shader`） | [#291](https://github.com/shinyaoguri/metaphor/issues/291) | 6.5 |
| タイポグラフィ（フォントファイル / textToPoints / text-on-path） | [#292](https://github.com/shinyaoguri/metaphor/issues/292) | 2.7 |
| モダン 3D（UV / PBR テクスチャ / IBL / glTF） | [#293](https://github.com/shinyaoguri/metaphor/issues/293) | 5.6, 5.8, 5.9 |

実装されたら、その節の「いまできないこと」を本文に昇格させます。

## 執筆規約

### 文体

- **敬体（です・ます）**。README・DocC と揃えます
- **二人称を使わない**。「あなたのスケッチ」ではなく「スケッチ」、指示は「〜します」「〜してください」
- 一人称の主語（「私たち」）も使いません
- 断定を避けた言い回し（「〜かもしれません」「〜と思います」）を避けます。制約は制約として書きます
- 専門用語は初出で 1 文の説明を添えます。カタカナ語と英語表記の混在は避け、API 名以外は日本語に寄せます
- 見出しは体言止めか「〜する」。節タイトルは「何ができるようになるか」で付けます（「`beginShape` の使い方」ではなく「自分で形を作る」）

### 各部の冒頭 — この部の前提

各部の導入のあとに `## この部の前提` を置き、**1〜2 文**で「この部を読む前に何が要るか」を書きます。先行する部と、そこで覚えた具体的な事柄を名指しします（「第 2 部の図形と色、第 3 部の `frameCount` を使います」）。第 1 部だけは先行する部が無いので、必要な前提知識そのもの（Swift の基本文法）と動作環境を書きます。

部の順序は番号で暗示されているだけなので、飛ばして読みに来た読者が戻るべき場所をここで示します。長い解説は書きません。要る知識と、それがどの節にあるかだけです。

### 各節の型

節は次の順で書きます。

1. **何を作るか** — 1〜2 文と、完成した実行結果の画像
2. **本文** — 手順や概念の説明。途中のコードは差分・抜粋でよい
3. **完全なコード** — その節のスケッチ全体（生成で埋め込む。後述）
4. **試してみる** — 数値や条件を変えると何が起きるかの短い課題を 1〜3 個
5. **ふりかえり** — その節で何ができるようになったかのチェックリスト（3〜5 項目）
6. **もっと詳しく** — API リファレンス（DocC）への深いリンクと、関連する既存 example へのリンク

本文中に DocC リンクを散らさず、6 にまとめます。読みながらリンクを追わずに済むようにするためです。

### ふりかえり

節末の「ふりかえり」は、読者が自分で読み飛ばしを検知するための装置です。Markdown のタスクリストで書きます。

```markdown
### ふりかえり

- [ ] `circle()` の 3 番目の引数が半径ではなく直径だと分かった
- [ ] `fill()` や `noStroke()` が「以降の描画すべてに効く設定」だと分かった
```

規約:

- **3〜5 項目**。多いと読まれません
- **本文で扱ったことだけ**を書きます。ここで新しい知識を出しません
- **達成の形（「〜できるようになった」「〜が分かった」）で書きます**。本文の敬体とは揃いませんが、読者自身が自分に対して checking する文なので、この節だけ常体にします
- 「試してみる」が「やってみないと分からないこと」を問うのに対し、ふりかえりは「読めば分かったはずのこと」を並べます。同じ内容を重ねません
- チェックボックスは**静的な表示で足ります**。website 側で状態を保存する仕組みは持ちません

### コードの置き方

コードを Markdown に直書きしません。腐るためです。

- 各節のスケッチは `Examples/Tutorial/{部番号}-{部スラッグ}/{節番号}-{節スラッグ}/` に**実在する SwiftPM パッケージ**として置きます（例: `Examples/Tutorial/01-GettingStarted/03-SketchSkeleton/`）。レイアウトは既存の `{Category}/{Subcategory}/{Name}/` 規約（[Examples/README.md](../../Examples/README.md)）に従います
- Markdown へは生成スクリプトで埋め込みます。`--check` と pre-push フック・CI がドリフトを検出します（基盤は [#485](https://github.com/shinyaoguri/metaphor/issues/485)）
- これにより**チュートリアルの全コードが CI でコンパイルを通っていること**が構造的に保証されます
- 節の途中で見せる差分・抜粋は手書きでよい。ただし必ず完全なコードを同じ節に置き、抜粋だけで終わらせません
- チュートリアルのコードは `docs/ai/examples-index` の索引には載せません（索引は「やりたいことから探す」ためのもので、チュートリアルの学習用コードはノイズになります）。除外は [#485](https://github.com/shinyaoguri/metaphor/issues/485) で実装済みです

埋め込みは本文に次の 2 行を置き、`make tutorial-snippets` を実行します。開始マーカーの引数は `Examples/Tutorial/` からの相対パスです。

```markdown
<!-- tutorial-snippet: 01-GettingStarted/03-SketchSkeleton -->
<!-- /tutorial-snippet -->
```

マーカーの間はスクリプトが毎回まるごと書き換えます（**手で編集しない**）。書き出されるのは、パッケージ配下の `*.swift` を並べた ```` ```swift ```` フェンスと、実行方法の 1 行です。ソースが 2 本以上あるときは各フェンスの前にファイル名が付きます。

新しい節のコードを足す手順:

1. `Examples/Tutorial/{部番号}-{部スラッグ}/{節番号}-{節スラッグ}/` にパッケージを作る（`Package.swift` の `metaphor` 依存は `path: "../../../.."`）
2. `cd` して `swift run` で動くことを確かめる
3. 本文にマーカーを置き、`make tutorial-snippets` を実行する

`--check` が pre-push フックと CI（`build-and-test`）で走り、コードと本文がずれたまま push・merge されるのを止めます。

### 本文ファイルの frontmatter

各部の Markdown は YAML frontmatter を持ちます。website のチュートリアル領域（[#487](https://github.com/shinyaoguri/metaphor/issues/487)）はこれを読んで並び順と見出しを決めます。

```yaml
---
title: 入門          # 部のタイトル（「第 N 部」は含めない）
part: 1              # 部番号。サイドバーの並び順に使う
slug: getting-started # URL に使う。ファイル名 NN-slug.md の slug と一致させる
description: この部で何ができるようになるか（1 文）
draft: true          # 執筆中は true。公開対象から外す
---
```

**この frontmatter が「どこまで公開されているか」の正典です**（[#584](https://github.com/shinyaoguri/metaphor/issues/584)）。README 群（[README.md](../../README.md) / [README.en.md](../../README.en.md) / [docs/README.md](../README.md) / [docs/README.en.md](../README.en.md) / [Examples/README.md](../../Examples/README.md)）が案内する公開状況は `<!-- tutorial-status: … -->` ブロックの**生成物**なので、手で編集せず `make tutorial-status` で書き出します。部を 1 つ公開するときに手で直すのは、この表の状態欄と README.md / README.en.md の部の表（説明文が手書き）だけです — 両方とも `--check`（pre-push と CI）が frontmatter と突き合わせます。

### 実行結果の画像

- **画像の実体はリポジトリに置きません**。Gyazo に上げ、本文からは `https://i.gyazo.com/<hash>.png` の絶対 URL で参照します（[ADR-0010](../adr/0010-tutorial-images-via-gyazo.md)）。Git で管理するのは本文と台帳（`images/manifest.json` の URL + content hash）だけです
- Probe と決定論レンダリングで**スクリプトから一括再生成**します（基盤は [#486](https://github.com/shinyaoguri/metaphor/issues/486)）。手で撮ったスクリーンショットは置きません
- 動きが分からないと伝わらない節（イージング・パーティクル・入力）は、静止画に加えてアニメーション（WebP）か連番のコンタクトシートを上げます（後述）
- 音・カメラ・ML など実行環境に依存して再現できない節は画像を必須とせず、代わりに何が起きるかを文章で書きます

撮り直しは 1 コマンドです。各節のスケッチを `METAPHOR_PROBE=1 METAPHOR_VIEWER=1`（ヘッドレス）で起動し、Probe が書いたフレームを Gyazo へ上げて、台帳と本文の URL を書き戻します。

```bash
make tutorial-shots                                                  # 撮り直しが要る節だけ
make tutorial-shots ARGS="--only 01-GettingStarted/03-SketchSkeleton" # 1 節だけ
make tutorial-shots ARGS="--force"                                    # 全部
```

アップロードには Gyazo のトークンが要ります（1Password から都度読みます。平文の環境変数として常駐させません）。撮影も GPU が要るので、どちらもローカルで行い、**本文と台帳の差分をコミット**します。

**アセットは不変・追記型として扱います。** 撮り直しは既存 URL の中身の差し替えではなく、新しくアップロードして本文と台帳の URL を更新する形です。古い URL は消しません。これで過去のリビジョンを checkout すれば当時の絵がそのまま出ます（「各リビジョンがどの不変アセットを参照していたか」を Git が持つ）。URL の履歴は `git log -p docs/tutorial/images/manifest.json` で辿れます。

本文の書き換えはスクリプトが行います。**台帳を正として、節の構造（節見出しと `<!-- tutorial-snippet: … -->`）から画像行の位置を決めて URL を上書きする**ため、初回の外部化・撮り直し・中断後の再実行がすべて同じ操作になります。本文の URL を手で書き換える必要はありません（書き換えても次回の実行で台帳の値に戻ります）。

鮮度の見方は他の生成物と違い、**画像のバイト比較ではありません**。GPU の出力は環境によってビット単位には一致しないためです。代わりに `images/manifest.json` が「撮影したときのスケッチの指紋」を持ち、`--check`（pre-push と CI）が現在のソースと突き合わせて「コードを変えたのに撮り直していない」だけを検出します。指紋の材料はパッケージ配下の全ファイル（`.build` / `.swiftpm` / `.metaphor` を除く）なので、Swift だけでなく同梱リソースの差し替えも拾います（[#505](https://github.com/shinyaoguri/metaphor/issues/505)）。あわせて「本文が指す URL が台帳と揃っているか」も見ます。台帳の `sha256` は鮮度判定には使いません（上げたバイト列の指紋で、URL の中身が入れ替わっていないことを後から確かめるためのものです）。

外部 URL は**死んでも本文の変換もサイトのビルドも成功してしまう**ので、生死は週次の [`asset-health.yml`](../../.github/workflows/asset-health.yml) が見張ります（`scripts/check-tutorial-image-urls.py`）。per-PR の CI には入れません（ネットワークの一時的な不調で PR を止めないため）。

外部化のトレードオフとして、**fork や外部コントリビュータは画像を差し替えられません**（アップロードにトークンが要るため、メンテナのアップロード待ちになります）。コードだけの PR は従来どおり出せます。また**オフラインでは本文の画像が出ません**。

### 動きが要る節（[#507](https://github.com/shinyaoguri/metaphor/issues/507)）

イージング・パーティクル・入力のように、**静止画では正誤を判定できない**節があります。その節は `docs/tutorial/images/motion.json` に登録すると、Probe の連続キャプチャ（[CONTRACT.md](../../CONTRACT.md) 契約点 4 の `frames >= 2`）で撮り、静止画に加えて動きの証跡も作られます。

```json
{
  "sections": {
    "03-Motion/03-Easing": { "kind": "webp", "frames": 64, "every": 4, "fps": 15, "width": 720 }
  }
}
```

| キー | 意味 |
|---|---|
| `kind` | `webp`（アニメーション WebP）か `sheet`（コンタクトシート） |
| `frames` | 採取枚数。**上限 64**（Probe 側のクランプ値。超えると設定エラー） |
| `every` | 採取間隔。`4` なら 60fps 実行の 4 フレームごと＝約 4.3 秒ぶん |
| `fps` | 書き出すアニメーションのフレームレート（既定 15） |
| `width` | 幅の上限（既定 720。元より大きくても拡大はしません） |
| `quality` | 省略すると `img2webp` に lossy / lossless を選ばせます。明示すると lossy 固定 |

`kind` を指定した節でも**代表静止画は作られます**（連続キャプチャの真ん中のフレーム）。本文の頭に 1 枚置き、その下に動きを貼る形になります。台帳では静止画が `url`、動きの証跡が `motion.url` で、本文の画像行もその順に並びます。

**GIF ではなく WebP** です。同じ絵で 1 桁小さく、`![](...)` のまま GitHub でも website でも動きます。mp4 はさらに小さいものの、GitHub の Markdown が動画を再生しないため採っていません（本文が GitHub 上でもそのまま読めることが要件）。生成には `img2webp`（`brew install webp`）が要ります。

Gyazo は公式ヘルプの対応形式一覧に WebP を挙げていませんが、**アニメーション WebP をそのまま受け取り、バイト列を変えずに配信します**（実測。ADR-0010 に記録）。website 側では Astro が取得して再最適化するので、読者が受け取るのは今までと同じアニメーション WebP です。

規約:

- **1 ファイル 500KB 以下**。超えるとスクリプトがエラーにします。`width` か `frames` を落としてください（リポジトリには置かなくなりましたが、GitHub 上で本文を読むときにそのまま読み込まれる重さなので上限は残します）
- 動きの証跡を撮る節のスケッチは、**乱数の種を固定し、時刻ではなく `frameCount` で動かします**。連続キャプチャは `noLoop()` と両立しないので、そうしないと撮るたびに絵が変わり、差分レビューがノイズだらけになります（`time` / `deltaTime` を教える 3.1 のような節は例外）
- 撮り直しは指紋（スケッチ + `motion.json` の設定）が変わったときだけです。`--force` を付けない限り、無関係な PR で画像が差し替わることはありません
- **例外**: `ParticleSystem`（GPU パーティクル、6.2）のように**時刻と `deltaTime` で駆動される仕組みは、原理的に同じ絵を再現できません**（放出の乱数が時刻から作られます）。この種の節は撮り直すたびに細部が変わります。撮り直し自体は指紋が変わったときだけなので差分の量は増えませんが、レビューでは「同じ絵か」ではなく「同じ性質の絵か」で見ます

**`prefers-reduced-motion` では動きを出しません**（[#553](https://github.com/shinyaoguri/metaphor/issues/553)）。動きの証跡は `<img>` なので読者に止める手段がありません。website は「視差効果を減らす」を設定している読者に対して、動きの証跡を段落ごと隠し、**対の代表静止画だけ**を見せます。静止画と動きは台帳の同じエントリに入っている（`url` と `motion.url`）ので、`website/src/plugins/remark-tutorial-images.mjs` が動きの側に印を付け、`website/src/styles/global.css` が出し分けます。隠れた画像は取得もされません。**GitHub 上の Markdown 表示ではこの制御が効きません**（アニメーションはそのまま再生されます）。

### 画像の alt（[#553](https://github.com/shinyaoguri/metaphor/issues/553)）

alt は「何の画像か」ではなく、**「何が見えるか」を 1 文**で書きます。読み上げで聞く読者にとって、alt は絵の代わりに読む本文です。

- ×「イージングの実行結果」→ ○「白い輪（目標）へ向かう 3 つの円。イージングの係数が小さい円ほど後ろに取り残されている」
- **節のタイトルを繰り返しません**。見出しはすぐ上にあり、読み上げでも読まれます。「〜の実行結果」「〜の画像」で始めない
- **動きの証跡の alt には動きの内容**を書きます（静止画の alt と重ねない）。「3 つの円が目標の輪を追いかけ、近づくほど減速する」
- **静止画の alt だけで節の絵が伝わるように**書きます。`prefers-reduced-motion` の読者には動きの証跡が出ないためです（上記）
- 絵に出ている数値・凡例・操作案内は、読み取れる範囲で 1 つ 2 つ入れます（「下に frameCount 97、time 1.61 秒が出ている」）
- **撮り直しても変わらない粒度**で書きます。乱数で細部が変わる節は、粒の 1 つ 1 つではなく構図を書きます
- 末尾に句点を打ちません（体言止め、または「〜している」「〜していく」のような言い切りで止めます）。2 文になるときだけ途中に句点を使います

**alt は手で書きます。** 撮影スクリプトは本文の URL だけを台帳の値へ差し替え、**alt はそのまま残します**（`--check` も alt を見ません）。逆に URL は手で書きません。

### 入力が要る節（[#509](https://github.com/shinyaoguri/metaphor/issues/509)）

マウス・キーボードの節は、入力が無いと絵が出来上がりません。パッケージ直下に
`probe-input.jsonl` を置くと、撮影スクリプトがスケッチを起動した後に**その内容を stdin へ
流してから**撮ります。ヘッドレス起動では `InputInjectionPlugin` が自動登録され、stdin の
JSON Lines（[CONTRACT.md](../../CONTRACT.md) 契約点 3）を入力として受け取るため、cli を挟まずに入力を再現できます。
この規約と実装は Examples の撮影（`make example-shots`）と共有です（[#610](https://github.com/shinyaoguri/metaphor/issues/610)。読み取りと送出は `scripts/shots_common.py`）。

```text
// コメント行と空行は無視される
{"t":"mouseMove","x":120,"y":80}
{"t":"mouseDown","x":120,"y":80,"button":0}
{"wait":200}
{"t":"mouseDrag","x":180,"y":90}
```

| 行の形 | 意味 |
|---|---|
| `t` を持つ行 | そのまま stdin へ送るイベント（`mouseDown` / `mouseUp` / `mouseMove` / `mouseDrag` / `scroll` / `keyDown` / `keyUp`） |
| `{"wait": ミリ秒}` | 送らずに待つ。押しっぱなしの区間を作るのに使う |
| `//` で始まる行・空行 | 無視される。台本の意図を書くための行 |

規約:

- **`mouseUp` / `keyUp` を送らずに終えれば「押されている状態」の絵が撮れます**。押下中の見た目
  （沈んだボタン、掴んだハンドル）はこれで撮ります
- 撮影は**入力を流し終えてから**始まるので、撮り直しても同じ絵になります（実測で全画素一致）。
  代わりに `noLoop()` のスケッチとは両立しません（起動後に置いたリクエストを処理する機会が
  無いため）
- 押しっぱなしの間に動かすものは、**フレーム数ではなく `deltaTime` で動かします**。台本の
  待ち時間は実時間なので、そうすれば実行環境のフレームレートに関係なく同じ位置に来ます
- 台本はパッケージ配下なので指紋（`sourceHash`）に入ります。台本を書き換えれば `--check` が
  撮り直しを要求し、本文の埋め込み（`*.swift` だけを拾う）には現れません

### 撮れない節（[#544](https://github.com/shinyaoguri/metaphor/issues/544)）

音・カメラ・機械学習のように、**実行環境に依存して絵が決まらない**節があります。マイクが無音なら何も動かず、カメラの映像は撮る場所によって変わり、どちらもヘッドレス起動では TCC の権限が降りないこともあります（[permissions.md](../permissions.md)）。

この種の節はパッケージ直下に `no-capture.txt` を置き、**撮らない理由を 1 行書きます**。撮影も鮮度検査も飛ばされ、`--check` は画像を要求しません。

```text
マイク入力は環境（無音・権限）で絵が変わり、撮っても読者の画面と一致しない
```

規約:

- 理由は必須です。空のファイルはエラーになります。「撮り忘れ」と区別できるようにするためです
- 撮らない節の本文は、画像の代わりに**何が起きるかを文章で書きます**。「何を作るか」で絵を見せられないぶん、操作と反応を言葉で補います
- `motion.json` との併記は矛盾なのでエラーになります
- 撮ったあとで「撮らない」に変えたときは、`make tutorial-shots` が古い画像と manifest のエントリを片付けます（`--check` は片付くまで差し戻します）

### スケッチを持たない節（[#547](https://github.com/shinyaoguri/metaphor/issues/547)）

**題材がコードではなく操作や文脈である節**は、`Examples/Tutorial/` にパッケージを置きません（第 10 部 10.4 の共有セッション、10.5 の AI へ渡す資料）。パッケージが無ければ埋め込みも撮影も対象外なので、仕組みの側で足すものはありません。

「撮れない節」（`no-capture.txt`）とは別物です。あちらは**スケッチはあるが絵が決まらない**節で、こちらは**そもそもスケッチが無い**節です。

規約:

- 節の冒頭で**スケッチが無いことと、代わりに何を扱うかを 1 文で書きます**。「何を作るか」の画像が無い理由を読者に説明しないまま始めません
- 手順が主役になるので、**確かめ方を「試してみる」に書きます**（この順で起動する、逆順にして直す、など）
- 操作の正典が別リポジトリ（metaphor-cli）にあるときは、深いリンクで送り出して**手順を二重に持ちません**

### 起動直後は絵が完成しない節（[#543](https://github.com/shinyaoguri/metaphor/issues/543)）

撮影スクリプトはリクエストを**起動前**に置くので、静止画は 1 フレーム目です。ところが
`compute()` で GPU に計算させた結果が `GPUBuffer` に届くのは**次のフレーム**なので、
6.1 のような節は 1 フレーム目だと「まだ何も計算されていない絵」が撮れてしまいます。

入力が要らなくても、`probe-input.jsonl` に**待つだけの行**を置けば解決します。台本がある節は
下見の 1 枚を待ってから本番のリクエストを置く仕組みなので、そのぶん撮影が後ろへずれます。

```text
// 入力は要らない。GPU の計算結果が届くまで撮影を遅らせるための台本
{"wait": 400}
```

`noLoop()` と両立しないのは入力の節と同じです（起動後に置いたリクエストを処理する機会が
無いため）。

### API 名の表記とリンク

- API 名はバッククォートで囲みます。関数は `circle()` のように括弧を付け、型・プロパティは `SketchConfig` / `frameCount` のように付けません
- DocC への深いリンクは各節の「もっと詳しく」に置きます
- 既存 example への参照はリポジトリ相対リンクで書き、実行方法（`cd Examples/... && swift run`）を初出の節で 1 度だけ示します

### 数値を書かない

Examples の本数やバージョン番号のような、増減する数値を本文に書きません（[#490](https://github.com/shinyaoguri/metaphor/issues/490) と同じ腐り方をするためです）。必要なら生成で埋め込みます。

## 既存ドキュメントの再配置

チュートリアルを新設すると、入門的な内容が複数箇所に重複します。役割を次のように整理します。

| ドキュメント | 再配置後の役割 | いつ |
|---|---|---|
| [README.md](../../README.md) / [README.en.md](../../README.en.md) の「はじめてのスケッチ」 | 60 秒スタートと最小のコード例は残し、詳細（ライフサイクル表・よく使う関数一覧）はチュートリアル第 1 部・第 2 部へ委譲してリンクする | 完了（[#510](https://github.com/shinyaoguri/metaphor/issues/510)）。`## チュートリアル` 節から公開中の各部へ張る |
| DocC [GettingStarted.md](../../Sources/metaphor/metaphor.docc/GettingStarted.md) | API リファレンス側の最小導入に絞る（インストール + 最小のスケッチ + `Sketch` へのリンク）。ライフサイクル・設定・入力の詳細はチュートリアルへ送り出す | 完了（入力は [#509](https://github.com/shinyaoguri/metaphor/issues/509)、残りは [#510](https://github.com/shinyaoguri/metaphor/issues/510)） |
| [processing-migration-guide.md](../processing-migration-guide.md) | そのまま維持。読者が違う（既習者向け）ことを冒頭で相互に明記する | 完了（冒頭の "Never used Processing?" から本チュートリアルへ送り出している） |
| [Examples/LEARNING_PATH.md](../../Examples/LEARNING_PATH.md) | **統合せず残す**。「チュートリアルを読み終えた人が Examples を掘るための地図」に位置づけ直し、冒頭でチュートリアルへ送り出す | 完了（[#484](https://github.com/shinyaoguri/metaphor/issues/484) の本文と同時） |

`LEARNING_PATH.md` を残す理由: 読者と目的が違うためです。チュートリアルは日本語ファーストで**代表コードを通しで読む**もの、`LEARNING_PATH.md` は英語で **Examples 全体をどの順に開くか**の地図です。統合すると Examples 側の入口が消え、英語の資産も失われます。重複する入門部分（"First shapes" など）はチュートリアルへの導線に置き換えます。

なお `LEARNING_PATH.md` には GPU shader 節が実態と食い違う問題が別にあります（[#489](https://github.com/shinyaoguri/metaphor/issues/489)）。チュートリアル 6.5 が同じ誤解を引き継がないよう、そちらを先に解消します。

## 英語版

日本語ファーストで書き、英語は後追いです（[docs/README.md](../README.md) の「英語化の対象境界」と、ロードマップの「docs 翻訳は定型作業として委譲する」方針に従います）。本文が溜まってから `docs/tutorial/en/` として起票します。

## 関連 Issue

- [#483](https://github.com/shinyaoguri/metaphor/issues/483) Epic — 体系的チュートリアル
- [#484](https://github.com/shinyaoguri/metaphor/issues/484) 情報アーキテクチャの確定（本文書）
- [#485](https://github.com/shinyaoguri/metaphor/issues/485) コード基盤（`Examples/Tutorial/` + 埋め込み生成 + ドリフト検出）
- [#486](https://github.com/shinyaoguri/metaphor/issues/486) 画像基盤（Probe + 決定論レンダリング）
- [#487](https://github.com/shinyaoguri/metaphor/issues/487) website のチュートリアル領域
- [#488](https://github.com/shinyaoguri/metaphor/issues/488) 執筆パイロット（第 1 部・第 2 部）
- [#508](https://github.com/shinyaoguri/metaphor/issues/508) 第 3 部 / [#509](https://github.com/shinyaoguri/metaphor/issues/509) 第 4 部 / [#526](https://github.com/shinyaoguri/metaphor/issues/526) 第 5 部 / [#543](https://github.com/shinyaoguri/metaphor/issues/543) 第 6 部 / [#544](https://github.com/shinyaoguri/metaphor/issues/544) 第 7 部 / [#545](https://github.com/shinyaoguri/metaphor/issues/545) 第 8 部 / [#546](https://github.com/shinyaoguri/metaphor/issues/546) 第 9 部 / [#547](https://github.com/shinyaoguri/metaphor/issues/547) 第 10 部
