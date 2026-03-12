# ``MetaphorPhysics``

2D physics simulation with Verlet integration and spatial hashing.

## Overview

MetaphorPhysics provides a lightweight 2D physics engine using Verlet
integration. Create rigid bodies with circle or rectangle shapes, connect
them with distance constraints or pin them to world positions, and step the
simulation each frame. Broad-phase collision detection uses ``SpatialHash2D``
for efficient handling of many bodies.

This module has no dependency on MetaphorCore and can be used standalone.
When using the umbrella module (`import metaphor`), physics features are
accessible through convenience methods like `createPhysics2D()`.

### Quick Start

```swift
let physics = Physics2D(cellSize: 50)
physics.addGravity(0, 500)
physics.bounds = (min: SIMD2(0, 0), max: SIMD2(800, 600))

let ball = physics.addCircle(x: 400, y: 100, radius: 20)
ball.restitution = 0.8

// In your draw loop:
physics.step(deltaTime)
circle(ball.position.x, ball.position.y, 40)
```

## Topics

### Physics World

- ``Physics2D``

### Bodies and Shapes

- ``PhysicsBody2D``
- ``PhysicsShape2D``

### Constraints

- ``PhysicsConstraint2D``

### Collision Detection

- ``SpatialHash2D``
