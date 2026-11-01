import Foundation

enum RelayLog {
    private static let lock = NSLock()

    static var fileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/BrightnessRelay-receiver.log")
    }

    static func write(_ message: String) {
        lock.lock()
        defer { lock.unlock() }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let line = "\(formatter.string(from: Date())) \(message)\n"
        let data = Data(line.utf8)

        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                try data.write(to: fileURL, options: .atomic)
                return
            }
            let handle = try FileHandle(forWritingTo: fileURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            fputs("Brightness Relay log failure: \(error)\n", stderr)
        }
    }
}
