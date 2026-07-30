import Testing
@testable import metaphor
@testable import MetaphorCore

// MARK: - File Drop Callbacks (#281)

@Suite("File drop callbacks")
@MainActor
struct FileDropCallbackTests {

    @Test("handleFileDrop invokes both user and internal callbacks")
    func bothCallbacksInvoked() {
        let input = InputManager()
        var userPaths: [String] = []
        var internalPaths: [String] = []
        input.onFileDrop = { userPaths = $0 }
        input.onFileDropInternal = { internalPaths = $0 }
        input.handleFileDrop(paths: ["/tmp/a.png", "/tmp/b.png"])
        // ユーザーの onFileDrop 直接設定と Sketch.fileDropped 配線が衝突しない
        #expect(userPaths == ["/tmp/a.png", "/tmp/b.png"])
        #expect(internalPaths == ["/tmp/a.png", "/tmp/b.png"])
    }

    @Test("handleFileDrop with only one callback set does not crash")
    func singleCallback() {
        let input = InputManager()
        var received: [String] = []
        input.onFileDropInternal = { received = $0 }
        input.handleFileDrop(paths: ["/tmp/c.txt"])
        #expect(received == ["/tmp/c.txt"])
    }
}
