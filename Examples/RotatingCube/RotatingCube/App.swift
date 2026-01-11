import SwiftUI
import metaphor

@main
struct RotatingCubeApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    @State private var renderer: MetaphorRenderer?
    @State private var cubeRenderer: CubeRenderer?

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

        let cube = CubeRenderer(device: renderer.device)
        self.cubeRenderer = cube

        renderer.startSyphonServer(name: "RotatingCube")

        renderer.onDraw = { [weak cube] encoder, time in
            cube?.draw(encoder: encoder, time: time, aspect: 1920.0 / 1080.0)
        }

        self.renderer = renderer
    }
}
