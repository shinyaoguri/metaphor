import metaphor

struct Planet {
    var px: Float, py: Float, pz: Float
    var vx: Float = 1, vy: Float = 0, vz: Float = 0
    var ax: Float = 0, ay: Float = 0, az: Float = 0
    var mass: Float
}

@main
final class GravitationalAttraction3D: Sketch {
    var config: SketchConfig { SketchConfig(width: 640, height: 360, title: "Gravitational Attraction 3D") }

    var planets: [Planet] = []
    let sunMass: Float = 20
    let G: Float = 0.4
    var angle: Float = 0

    func setup() {
        for _ in 0..<10 {
            planets.append(Planet(
                px: random(-width / 2, width / 2),
                py: random(-height / 2, height / 2),
                pz: random(-100, 100),
                mass: random(0.1, 2)
            ))
        }
    }

    func draw() {
        background(0)
        lights()
        translate(width / 2, height / 2, 0)
        rotateY(angle)
        // Sun
        stroke(255); noFill()
        sphere(sunMass * 2)
        // Planets
        for i in 0..<planets.count {
            var fx = -planets[i].px, fy = -planets[i].py, fz = -planets[i].pz
            let d = max(5, min(25, sqrt(fx * fx + fy * fy + fz * fz)))
            let strength = (G * sunMass * planets[i].mass) / (d * d)
            let fm = sqrt(fx * fx + fy * fy + fz * fz)
            if fm > 0 { fx = fx / fm * strength; fy = fy / fm * strength; fz = fz / fm * strength }
            planets[i].ax += fx / planets[i].mass
            planets[i].ay += fy / planets[i].mass
            planets[i].az += fz / planets[i].mass
            planets[i].vx += planets[i].ax; planets[i].vy += planets[i].ay; planets[i].vz += planets[i].az
            planets[i].px += planets[i].vx; planets[i].py += planets[i].vy; planets[i].pz += planets[i].vz
            planets[i].ax = 0; planets[i].ay = 0; planets[i].az = 0
            noStroke(); fill(255)
            pushMatrix()
            translate(planets[i].px, planets[i].py, planets[i].pz)
            sphere(planets[i].mass * 8)
            popMatrix()
        }
        angle += 0.003
    }
}
