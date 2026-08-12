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
| 第 3 部以降 | — | 未着手 |

## 対象読者と、他ドキュメントとの役割分担

対象読者は **Processing 経験を前提としない初心者**です。「Swift は書ける / 書いたことがある。グラフィックスプログラミングは初めて」という人が、最初から順に読んで作品を作れるようになることを目指します。

metaphor のドキュメントは読者と用途で分かれています。チュートリアルは**通しで読む**もので、他は**引く**ものです。

| ドキュメント | 読者 | 使い方 |
|---|---|---|
| **チュートリアル**（本ディレクトリ） | 初心者。metaphor が初めて | 最初から順に読む。各節に完結したコードと実行結果が付く |
| [API リファレンス（DocC）](https://shinyaoguri.github.io/metaphor/documentation/metaphor/) | 型やメソッドのシグネチャを知りたい人 | 引く。チュートリアルの各節から深いリンクを張る |
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
| 5.3 3D の変換 | 軸まわりの回転、入れ子の座標系、マウスで視点を回す | `rotateX/Y/Z`, `translate(x,y,z)`, `orbitControl` | `Basics/Transform/RotateXY`, `Topics/Motion/CubesWithinCube` |
| 5.4 カメラ | 視点・注視点、画角、透視投影と平行投影 | `camera`, `perspective`, `ortho` | `Basics/Control/Camera/MoveEye`, `Basics/Control/Camera/Perspective`, `Basics/Control/Camera/Orthographic` |
| 5.5 ライティング | 環境光・平行光・点光源・スポット、鏡面反射 | `lights`, `directionalLight`, `pointLight`, `spotLight`, `ambientLight`, `specular` | `Basics/Lights/OnOff`, `Basics/Lights/Directional`, `Basics/Lights/Spot`, `Basics/Lights/Mixture`, `Basics/Lights/Reflection` |
| 5.6 マテリアルと PBR | Blinn-Phong と PBR の切り替え、金属感・粗さ | `material`, `pbr` | `Basics/Lights/Reflection` |
| 5.7 影 | シャドウマップの有効化と、影が出ないときの見どころ | シャドウ設定 API | — |
| 5.8 テクスチャ | 画像を面に貼る、UV の考え方 | `texture`, `vertex(u:v:)` | `Topics/Textures/TextureQuad`, `Topics/Textures/TextureCube`, `Topics/Textures/TextureSphere` |
| 5.9 メッシュとモデル | 頂点から自作する、OBJ / USDZ / ABC を読み込む | `beginShape` (3D), `loadModel` | `Topics/Geometry/Vertices`, `Topics/Geometry/Icosahedra`, `Basics/Shape/LoadDisplayOBJ` |
| 5.10 大量の 3D | 同一形状の連続描画が自動バッチされる仕組み、明示インスタンシング | インスタンシング API | `Samples/InstancedCubes`, `Demos/Performance/CubicGridImmediate` |

### 第 6 部 GPU を使う

| 節 | 学ぶこと | 主な API | 対応する既存 example |
|---|---|---|---|
| 6.1 GPU に計算させる | `compute()` フックの位置づけ、MSL カーネルを書いて呼ぶ、CPU との往復の考え方 | `createComputeKernel`, `compute()` | — |
| 6.2 GPU パーティクル | 100 万粒子を CPU に降ろさず動かす | `createParticleSystem` | `Demos/Performance/DynamicParticlesImmediate` |
| 6.3 ポストプロセス | 描き終えた絵に効果をかける、組み込みエフェクトの重ねがけ | `addPostEffect`, `BloomEffect` ほか | — |
| 6.4 カスタムポストエフェクト | 自分の MSL フラグメントシェーダーを効果として差し込む、ホットリロード | `createPostEffect` | — |
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
| 10.3 MCP でつなぐ | `metaphor mcp` の 5 ツール（snapshot / capture_sequence / input / build_status / api_reference） | — | — |
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

### 各節の型

節は次の順で書きます。

1. **何を作るか** — 1〜2 文と、完成した実行結果の画像
2. **本文** — 手順や概念の説明。途中のコードは差分・抜粋でよい
3. **完全なコード** — その節のスケッチ全体（生成で埋め込む。後述）
4. **試してみる** — 数値や条件を変えると何が起きるかの短い課題を 1〜3 個
5. **もっと詳しく** — API リファレンス（DocC）への深いリンクと、関連する既存 example へのリンク

本文中に DocC リンクを散らさず、5 にまとめます。読みながらリンクを追わずに済むようにするためです。

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

### 実行結果の画像

- 置き場は `docs/tutorial/images/{部番号}-{部スラッグ}/{節番号}-{節スラッグ}.png`
- Probe と決定論レンダリングで**スクリプトから一括再生成**します（基盤は [#486](https://github.com/shinyaoguri/metaphor/issues/486)）。手で撮ったスクリーンショットは置きません
- 動きが分からないと伝わらない節（イージング・パーティクル・入力）は、静止画に加えてアニメーション GIF か連番のコンタクトシートを置きます
- 音・カメラ・ML など実行環境に依存して再現できない節は画像を必須とせず、代わりに何が起きるかを文章で書きます

撮り直しは 1 コマンドです。各節のスケッチを `METAPHOR_PROBE=1 METAPHOR_VIEWER=1`（ヘッドレス）で起動し、Probe が書いたフレームを配置します。

```bash
make tutorial-shots                                                  # 撮り直しが要る節だけ
make tutorial-shots ARGS="--only 01-GettingStarted/03-SketchSkeleton" # 1 節だけ
make tutorial-shots ARGS="--force"                                    # 全部
```

本文からは `![説明](images/{部番号}-{部スラッグ}/{節番号}-{節スラッグ}.png)` で参照します。

鮮度の見方は他の生成物と違い、**PNG のバイト比較ではありません**。GPU の出力は環境によってビット単位には一致しないためです。代わりに `images/manifest.json` が「撮影したときのスケッチの指紋」を持ち、`--check`（pre-push と CI）が現在のソースと突き合わせて「コードを変えたのに撮り直していない」だけを検出します。指紋の材料はパッケージ配下の全ファイル（`.build` / `.swiftpm` / `.metaphor` を除く）なので、Swift だけでなく同梱リソースの差し替えも拾います（[#505](https://github.com/shinyaoguri/metaphor/issues/505)）。撮影自体は GPU が要るのでローカルで行い、画像をコミットします。

いまは静止画のみです。動きが要る節の GIF / コンタクトシートは、その節を書くときに足します（Probe は `frames >= 2` の連続キャプチャに対応しています）。

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
| [README.md](../../README.md) の「はじめてのスケッチ」 | 60 秒スタートと最小のコード例は残し、詳細（ライフサイクル表・よく使う関数一覧）はチュートリアル第 1 部へ委譲してリンクする | 第 1 部の本文がマージされてから |
| DocC [GettingStarted.md](../../Sources/metaphor/metaphor.docc/GettingStarted.md) | API リファレンス側の最小導入に絞る（インストール + 最小のスケッチ + `Sketch` へのリンク）。ライフサイクル・設定・入力の詳細はチュートリアルへ送り出す | 第 1 部・第 4 部の本文がマージされてから |
| [processing-migration-guide.md](../processing-migration-guide.md) | そのまま維持。読者が違う（既習者向け）ことを冒頭で相互に明記する | 第 1 部と同時 |
| [Examples/LEARNING_PATH.md](../../Examples/LEARNING_PATH.md) | **統合せず残す**。「チュートリアルを読み終えた人が Examples を掘るための地図」に位置づけ直し、冒頭でチュートリアルへ送り出す | 本文（#484）と同時 |

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
