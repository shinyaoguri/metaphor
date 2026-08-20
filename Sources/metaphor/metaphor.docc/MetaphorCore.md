# ``MetaphorCore``

@Metadata {
    @PageColor(purple)
}

@Options {
    @TopicsVisualStyle(compactGrid)
}

metaphor の中核となるレンダリングエンジン、描画システム、Sketch プロトコル。

## Overview

MetaphorCore は Metal レンダリングパイプライン、2D/3D 描画バックエンド、
コンピュートシェーダーサポート、そしてすべてを統合する ``MetaphorCore/Sketch`` プロトコルを提供します。

通常は MetaphorCore を直接インポートせず、`import metaphor`（アンブレラモジュール）を使用してください。
すべてのモジュール（オーディオ、物理演算、ML など）を含む
[完全な API リファレンスはこちら](https://shinyaoguri.github.io/metaphor/reference/documentation/metaphor)。
