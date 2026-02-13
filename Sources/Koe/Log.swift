import Foundation

enum Log {
    private static let logFile: FileHandle? = {
        let path = "/tmp/typeless_debug.log"
        FileManager.default.createFile(atPath: path, contents: nil)
        return FileHandle(forWritingAtPath: path)
    }()

    static let appVersion: String = {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    }()

    static func d(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] \(message)\n"
        if let data = line.data(using: .utf8) {
            logFile?.seekToEndOfFile()
            logFile?.write(data)
        }
        // Also stderr so it shows in terminal
        fputs(line, stderr)
    }
}
