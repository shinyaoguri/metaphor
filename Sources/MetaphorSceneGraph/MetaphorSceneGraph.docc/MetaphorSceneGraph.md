# ``MetaphorSceneGraph``

Hierarchical scene graph for organizing 3D objects.

## Overview

MetaphorSceneGraph provides a tree-based scene structure for 3D rendering.
``Node`` represents an object with position, orientation, scale, optional
mesh, and child nodes. Transforms propagate through the hierarchy so that
moving a parent node moves all of its children.

``SceneRenderer`` traverses the node tree and renders visible meshes using
Canvas3D, with optional frustum culling via ``AABB`` bounding boxes.

This module depends on MetaphorCore.
When using the umbrella module (`import metaphor`), scene graph features are
accessible through convenience methods like `createNode(name:)`.

### Quick Start

```swift
let root = Node(name: "root")

let cube = Node(name: "cube")
cube.mesh = Mesh.box(1, 1, 1)
cube.position = SIMD3(0, 1, 0)
root.addChild(cube)

// In your draw loop:
SceneRenderer.render(node: root, canvas: canvas3D)
```

## Topics

### Scene Nodes

- ``Node``
- ``AABB``

### Rendering

- ``SceneRenderer``
