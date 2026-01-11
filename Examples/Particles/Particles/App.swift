import SwiftUI
import metaphor

@main
struct ParticlesApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    @State private var renderer: MetaphorRenderer?
    @State private var particleSystem: ParticleSystem?

    var body: some View {
        Group {
            if let renderer = renderer {
                MetaphorView(renderer: renderer, preferredFPS: 60)
            } else {
                Text("Initializing...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            setupRenderer()
        }
    }

    private func setupRenderer() {
        guard let renderer = MetaphorRenderer(width: 1920, height: 1080) else {
            return
        }

        let particles = ParticleSystem(device: renderer.device, maxParticles: 100000)
        self.particleSystem = particles

        renderer.startSyphonServer(name: "Particles")

        renderer.onDraw = { [weak particles] encoder, time in
            particles?.update(time: time)
            particles?.draw(encoder: encoder)
        }

        self.renderer = renderer
    }
}
