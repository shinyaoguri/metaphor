import Testing
import Foundation
import simd
@testable import metaphor

// MARK: - D-16: Sound File

@Suite("D-16 Sound File")
@MainActor
struct SoundFileTests {

    @Test("SoundFileError for non-existent file")
    func fileNotFound() {
        #expect(throws: SoundFileError.self) {
            _ = try SoundFile(path: "/nonexistent/audio.mp3")
        }
    }

    @Test("SoundFileError has description")
    func errorDescription() {
        let error = SoundFileError.fileNotFound("/test/path.mp3")
        #expect(error.errorDescription?.contains("Audio file not found") == true)
    }
}

// MARK: - D-17: MIDI

@Suite("D-17 MIDI Message")
struct MIDIMessageTests {

    @Test("Note On detection")
    func noteOn() {
        let msg = MIDIMessage(status: 0x90, channel: 0, data1: 60, data2: 100)
        #expect(msg.isNoteOn == true)
        #expect(msg.isNoteOff == false)
        #expect(msg.note == 60)
        #expect(msg.velocity == 100)
    }

    @Test("Note Off detection (0x80)")
    func noteOff() {
        let msg = MIDIMessage(status: 0x80, channel: 0, data1: 60, data2: 0)
        #expect(msg.isNoteOff == true)
        #expect(msg.isNoteOn == false)
    }

    @Test("Note Off via velocity 0 on Note On")
    func noteOffViaVelocityZero() {
        let msg = MIDIMessage(status: 0x90, channel: 0, data1: 60, data2: 0)
        #expect(msg.isNoteOff == true)
        #expect(msg.isNoteOn == false)
    }

    @Test("Control Change detection")
    func controlChange() {
        let msg = MIDIMessage(status: 0xB0, channel: 5, data1: 1, data2: 64)
        #expect(msg.isControlChange == true)
        #expect(msg.channel == 5)
        #expect(msg.controlNumber == 1)
        #expect(msg.controlValue == 64)
        #expect(abs(msg.normalizedControlValue - 0.5039) < 0.01)
    }

    @Test("Program Change detection")
    func programChange() {
        let msg = MIDIMessage(status: 0xC0, channel: 0, data1: 10, data2: 0)
        #expect(msg.isProgramChange == true)
    }

    @Test("Pitch Bend detection")
    func pitchBend() {
        let msg = MIDIMessage(status: 0xE0, channel: 0, data1: 0, data2: 64)
        #expect(msg.isPitchBend == true)
    }

    @Test("MIDIMessageType enum values")
    func messageTypes() {
        #expect(MIDIMessageType.noteOn.rawValue == 0x90)
        #expect(MIDIMessageType.noteOff.rawValue == 0x80)
        #expect(MIDIMessageType.controlChange.rawValue == 0xB0)
        #expect(MIDIMessageType.programChange.rawValue == 0xC0)
        #expect(MIDIMessageType.pitchBend.rawValue == 0xE0)
        #expect(MIDIMessageType.polyPressure.rawValue == 0xA0)
        #expect(MIDIMessageType.channelPressure.rawValue == 0xD0)
    }
}

@Suite("D-17 MIDI Manager")
@MainActor
struct MIDIManagerTests {

    @Test("MIDIManager initializes with default CC values")
    func defaultValues() {
        let midi = MIDIManager()
        #expect(midi.controllerValue(0) == 0)
        #expect(midi.controllerValue(1) == 0)
        #expect(midi.controllerRawValue(127) == 0)
    }

    @Test("MIDIManager isNoteActive returns false before start")
    func noActiveNotes() {
        let midi = MIDIManager()
        #expect(midi.isNoteActive(60) == false)
        #expect(midi.isNoteActive(127, channel: 15) == false)
    }

    @Test("MIDIManager poll returns empty before start")
    func emptyPoll() {
        let midi = MIDIManager()
        let msgs = midi.poll()
        #expect(msgs.isEmpty)
    }

    @Test("controllerValue bounds check")
    func ccBoundsCheck() {
        let midi = MIDIManager()
        // Out of bounds returns 0
        #expect(midi.controllerValue(200) == 0)
        #expect(midi.controllerValue(0, channel: 20) == 0)
    }
}

// MARK: - D-19: GIF Export

@Suite("D-19 GIF Exporter")
@MainActor
struct GIFExporterTests {

    @Test("GIFExporter recording state")
    func recordingState() {
        let exporter = GIFExporter()
        #expect(exporter.isRecording == false)
        #expect(exporter.frameCount == 0)

        exporter.beginRecord(fps: 10)
        #expect(exporter.isRecording == true)
    }

    @Test("GIFExporter endRecord with no frames throws")
    func noFramesThrows() {
        let exporter = GIFExporter()
        exporter.beginRecord(fps: 10)
        #expect(throws: GIFExporterError.self) {
            try exporter.endRecord(to: NSTemporaryDirectory() + "empty.gif")
        }
    }

    @Test("GIFExporter loopCount default")
    func loopCountDefault() {
        let exporter = GIFExporter()
        #expect(exporter.loopCount == 0)  // infinite loop
    }

    @Test("GIFExporterError descriptions")
    func errorDescriptions() {
        #expect(GIFExporterError.noFrames.errorDescription?.contains("No frames") == true)
        #expect(GIFExporterError.destinationCreationFailed.errorDescription?.contains("destination") == true)
        #expect(GIFExporterError.finalizationFailed.errorDescription?.contains("finalize") == true)
    }
}

// MARK: - D-20: Orbit Camera

@Suite("D-20 Orbit Camera")
@MainActor
struct OrbitCameraTests {

    @Test("Default camera position")
    func defaultPosition() {
        let camera = OrbitCamera()
        let eye = camera.eye
        // default: distance=500, azimuth=0, elevation=0.3
        // x = 500 * cos(0.3) * sin(0) = 0
        // y = 500 * sin(0.3) ≈ 147.8
        // z = 500 * cos(0.3) * cos(0) ≈ 477.7
        #expect(abs(eye.x) < 0.01)
        #expect(abs(eye.y - 500 * sin(0.3)) < 0.1)
        #expect(abs(eye.z - 500 * cos(0.3)) < 0.1)
    }

    @Test("Custom initialization")
    func customInit() {
        let camera = OrbitCamera(distance: 100, azimuth: Float.pi / 2, elevation: 0)
        let eye = camera.eye
        // x = 100 * cos(0) * sin(π/2) = 100
        // y = 100 * sin(0) = 0
        // z = 100 * cos(0) * cos(π/2) ≈ 0
        #expect(abs(eye.x - 100) < 0.1)
        #expect(abs(eye.y) < 0.1)
        #expect(abs(eye.z) < 0.1)
    }

    @Test("Mouse drag changes azimuth and elevation")
    func mouseDrag() {
        let camera = OrbitCamera()
        let initialAzimuth = camera.azimuth
        let initialElevation = camera.elevation

        camera.handleMouseDrag(dx: 100, dy: 50)

        // dx → azimuth decreases (negative dx * sensitivity)
        #expect(camera.azimuth != initialAzimuth)
        // dy → elevation increases
        #expect(camera.elevation != initialElevation)
    }

    @Test("Scroll zoom changes distance")
    func scrollZoom() {
        let camera = OrbitCamera()
        let initialDistance = camera.distance

        camera.handleScroll(delta: 10)

        #expect(camera.distance < initialDistance)
    }

    @Test("Elevation clamping")
    func elevationClamping() {
        let camera = OrbitCamera()

        // 大きなドラッグで elevation を限界に
        camera.handleMouseDrag(dx: 0, dy: 10000)
        #expect(camera.elevation <= camera.maxElevation)

        camera.handleMouseDrag(dx: 0, dy: -20000)
        #expect(camera.elevation >= camera.minElevation)
    }

    @Test("Distance clamping")
    func distanceClamping() {
        let camera = OrbitCamera()

        // 大量ズームイン
        for _ in 0..<100 {
            camera.handleScroll(delta: 100)
        }
        #expect(camera.distance >= camera.minDistance)

        // 大量ズームアウト
        for _ in 0..<100 {
            camera.handleScroll(delta: -100)
        }
        #expect(camera.distance <= camera.maxDistance)
    }

    @Test("Reset restores defaults")
    func reset() {
        let camera = OrbitCamera()
        camera.handleMouseDrag(dx: 100, dy: 50)
        camera.handleScroll(delta: 10)

        camera.reset()

        #expect(camera.distance == 500)
        #expect(camera.azimuth == 0)
        #expect(camera.elevation == 0.3)
    }

    @Test("Damping smooths movement")
    func damping() {
        let camera = OrbitCamera()
        camera.damping = 0.9

        camera.handleMouseDrag(dx: 100, dy: 0)
        let initialAzimuth = camera.azimuth

        // ダンピング中は update() で徐々に反映
        camera.update()
        let afterFirstUpdate = camera.azimuth

        #expect(afterFirstUpdate != initialAzimuth)

        // 複数回 update でさらに変化
        camera.update()
        camera.update()
        let afterMultipleUpdates = camera.azimuth

        #expect(afterMultipleUpdates != afterFirstUpdate)
    }

    @Test("Up vector is (0,1,0)")
    func upVector() {
        let camera = OrbitCamera()
        #expect(camera.up == SIMD3(0, 1, 0))
    }

    @Test("Target offset affects eye position")
    func targetOffset() {
        let camera = OrbitCamera(distance: 100, azimuth: 0, elevation: 0)
        let eye1 = camera.eye

        camera.target = SIMD3(100, 0, 0)
        let eye2 = camera.eye

        #expect(abs(eye2.x - eye1.x - 100) < 0.1)
    }
}

// MARK: - D-16/D-17 AudioAnalyzer injectSamples

@Suite("D-16 AudioAnalyzer injectSamples")
@MainActor
struct AudioAnalyzerInjectTests {

    @Test("injectSamples feeds data to update")
    func injectSamples() {
        let analyzer = AudioAnalyzer(fftSize: 256)

        // Generate a simple sine wave
        var samples = [Float](repeating: 0, count: 256)
        for i in 0..<256 {
            samples[i] = sin(Float(i) * 2 * Float.pi / 256.0) * 0.5
        }

        analyzer.injectSamples(samples)
        analyzer.update()

        // After update, volume should be non-zero
        #expect(analyzer.volume > 0)
        // Waveform should be populated
        #expect(analyzer.waveform.count == 256)
        // Spectrum should be populated
        #expect(analyzer.spectrum.count == 128)
    }

    @Test("injectSamples without update has no effect")
    func injectWithoutUpdate() {
        let analyzer = AudioAnalyzer(fftSize: 256)

        var samples = [Float](repeating: 0, count: 256)
        for i in 0..<256 {
            samples[i] = sin(Float(i) * 2 * Float.pi / 256.0) * 0.5
        }

        analyzer.injectSamples(samples)
        // Don't call update
        #expect(analyzer.volume == 0)
    }
}
