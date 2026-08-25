# ``MetaphorSceneGraph``

@Metadata {
    @PageColor(purple)
}

@Options {
    @TopicsVisualStyle(compactGrid)
}

A hierarchical scene graph for organizing 3D objects.

## Overview

MetaphorSceneGraph provides a tree-based scene structure for 3D rendering.
``MetaphorSceneGraph/Node`` represents an object with a position, orientation, scale, an optional mesh, and child nodes.
Transforms propagate through the hierarchy, so moving a parent node moves all of its children.

``MetaphorSceneGraph/SceneRenderer`` walks the node tree and renders visible meshes using Canvas3D.
Optional frustum culling with ``MetaphorSceneGraph/AABB`` bounding boxes is supported as well.

This module depends on MetaphorCore.
With the umbrella module (`import metaphor`), reach it through convenience methods
such as `createNode(name:)`.

### Quick Start

```swift
let root = Node(name: "root")

let cube = Node(name: "cube")
cube.mesh = Mesh.box(1, 1, 1)
cube.position = SIMD3(0, 1, 0)
root.addChild(cube)

// Inside the draw loop:
SceneRenderer.render(node: root, canvas: canvas3D)
```
