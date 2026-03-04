import metaphor
import Foundation

@main
final class DirectoryList: Sketch {
    var config: SketchConfig {
        SketchConfig(title: "DirectoryList", width: 640, height: 480)
    }

    var fileInfoLines: [String] = []

    func setup() {
        noLoop()

        let fm = FileManager.default
        let path = fm.currentDirectoryPath

        fileInfoLines.append("Directory: \(path)")
        fileInfoLines.append("")

        // List files in current directory
        if let items = try? fm.contentsOfDirectory(atPath: path) {
            fileInfoLines.append("Files found: \(items.count)")
            fileInfoLines.append("---")
            for item in items.prefix(20) {
                let fullPath = (path as NSString).appendingPathComponent(item)
                var isDir: ObjCBool = false
                fm.fileExists(atPath: fullPath, isDirectory: &isDir)
                let attrs = try? fm.attributesOfItem(atPath: fullPath)
                let size = attrs?[.size] as? UInt64 ?? 0
                let typeStr = isDir.boolValue ? "[DIR]" : "[FILE]"
                fileInfoLines.append("\(typeStr) \(item) (\(size) bytes)")
            }
            if items.count > 20 {
                fileInfoLines.append("... and \(items.count - 20) more")
            }
        } else {
            fileInfoLines.append("Could not read directory")
        }

        // Print to console as well
        for line in fileInfoLines {
            print(line)
        }
    }

    func draw() {
        background(0)
        fill(255)
        textSize(12)
        textAlign(.left, .top)

        var y: Float = 20
        for line in fileInfoLines {
            text(line, 20, y)
            y += 18
        }
    }
}
