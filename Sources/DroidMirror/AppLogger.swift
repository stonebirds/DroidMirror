import Foundation

final class AppLogger: @unchecked Sendable {
    static let shared = AppLogger()

    private let lock = NSLock()
    private let maxFileSize = 2 * 1024 * 1024
    private let maxMemoryLines = 1_000
    private var lines: [String] = []
    let fileURL: URL?

    private init() {
        let baseURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first
        fileURL = baseURL?
            .appendingPathComponent("DroidMirror", isDirectory: true)
            .appendingPathComponent("DroidMirror.log")

        guard let fileURL else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if let data = try? Data(contentsOf: fileURL),
           let content = String(data: data.suffix(maxFileSize), encoding: .utf8) {
            lines = Array(content.split(whereSeparator: \.isNewline).suffix(maxMemoryLines)).map(String.init)
        }
    }

    func log(_ category: String, _ message: String) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let normalized = message.replacingOccurrences(of: "\n", with: " | ")
        let line = "\(formatter.string(from: Date())) [\(category)] \(normalized)"

        lock.lock()
        lines.append(line)
        if lines.count > maxMemoryLines {
            lines.removeFirst(lines.count - maxMemoryLines)
        }
        persist(line)
        lock.unlock()
    }

    func snapshot() -> String {
        lock.lock()
        defer { lock.unlock() }
        return lines.joined(separator: "\n")
    }

    func clear() {
        lock.lock()
        lines.removeAll()
        if let fileURL {
            try? Data().write(to: fileURL, options: .atomic)
        }
        lock.unlock()
    }

    private func persist(_ line: String) {
        guard let fileURL, let data = (line + "\n").data(using: .utf8) else { return }
        let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        let size = (attributes?[.size] as? NSNumber)?.intValue ?? 0
        if size >= maxFileSize {
            let recent = lines.suffix(maxMemoryLines / 2).joined(separator: "\n") + "\n"
            try? recent.write(to: fileURL, atomically: true, encoding: .utf8)
            return
        }
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: fileURL) else { return }
        defer { try? handle.close() }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            // Logging must never interrupt mirroring or device control.
        }
    }
}
