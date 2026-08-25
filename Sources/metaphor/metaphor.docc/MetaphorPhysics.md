# ``MetaphorPhysics``

@Metadata {
    @PageColor(orange)
}

@Options {
    @TopicsVisualStyle(compactGrid)
}

2D physics simulation using Verlet integration and spatial hashing.

## Overview

MetaphorPhysics provides a lightweight 2D physics engine built on Verlet integration.
Create rigid bodies with circle or rectangle shapes, connect them with distance constraints
or pin them to world coordinates, and update the simulation every frame.
Broad-phase collision detection uses ``MetaphorPhysics/SpatialHash2D`` to handle large body counts efficiently.

This module does not depend on MetaphorCore and can be used on its own.
With the umbrella module (`import metaphor`), reach it through convenience methods
such as `createPhysics2D()`.

### Quick Start

```swift
let physics = Physics2D(cellSize: 50)
physics.setGravity(0, 500)
physics.bounds = (min: SIMD2(0, 0), max: SIMD2(800, 600))

// The bounds walls behave as immovable bodies with the same coefficients. They act just like
// a static body you place yourself; to collect without bouncing, set the body's restitution to 0
let platform = physics.addRect(x: 400, y: 400, width: 300, height: 20)
platform.isStatic = true

let ball = physics.addCircle(x: 400, y: 100, radius: 20)
ball.restitution = 0.8

// Inside the draw loop: pass real frame time to advance(), not step()
physics.advance(deltaTime)
circle(ball.position.x, ball.position.y, 40)
```

> Important: Pass a **fixed time step** to `step(_:iterations:)`. Verlet stores velocity as
> "displacement per step", and the resting threshold for restitution scales with `dt²`, so
> handing it a fluctuating real frame time lets energy enter and leave the system — the same
> sketch then moves differently from run to run and from machine to machine. To drive it from
> real frame time, use `advance(_:iterations:)` instead: it accumulates elapsed time and
> consumes it in `fixedTimeStep` increments (1/120 second by default), so the result no longer
> depends on frame time jitter. The automatic subsystem update in `import metaphor` goes
> through this path as well. `step()` remains as a low-level API for when you set the step
> yourself — fixed-step loops, offline rendering, and tests.
