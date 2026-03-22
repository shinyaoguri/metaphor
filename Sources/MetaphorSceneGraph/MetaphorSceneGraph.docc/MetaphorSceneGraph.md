# ``MetaphorSceneGraph``

@Metadata {
    @PageColor(purple)
}

@Options {
    @TopicsVisualStyle(compactGrid)
}

3D オブジェクトを整理するための階層型シーングラフ。

## Overview

MetaphorSceneGraph は 3D レンダリングのためのツリーベースのシーン構造を提供します。
``Node`` は位置、向き、スケール、オプションのメッシュ、子ノードを持つオブジェクトを表します。
トランスフォームは階層を通じて伝播するため、親ノードを移動するとすべての子ノードも移動します。

``SceneRenderer`` はノードツリーを走査し、Canvas3D を使って可視メッシュをレンダリングします。
``AABB`` バウンディングボックスによるオプションのフラスタムカリングにも対応しています。

このモジュールは MetaphorCore に依存します。
アンブレラモジュール（`import metaphor`）使用時は、`createNode(name:)` などの
便利なメソッドからアクセスできます。

### クイックスタート

```swift
let root = Node(name: "root")

let cube = Node(name: "cube")
cube.mesh = Mesh.box(1, 1, 1)
cube.position = SIMD3(0, 1, 0)
root.addChild(cube)

// 描画ループ内:
SceneRenderer.render(node: root, canvas: canvas3D)
```

## Topics

### シーンノード

- ``Node``
- ``AABB``

### レンダリング

- ``SceneRenderer``
