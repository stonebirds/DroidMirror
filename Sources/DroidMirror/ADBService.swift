import Foundation

struct ADBCommandResult: Sendable {
    let output: String
    let errorOutput: String
    let exitCode: Int32
}

enum ADBServiceError: LocalizedError {
    case executableMissing
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .executableMissing:
            return "未找到 adb。请使用内置安装包，或选择有效的 adb 可执行文件。"
        case .commandFailed(let message):
            return message.isEmpty ? "adb 命令执行失败。" : message
        }
    }
}

enum ADBService {
    static func run(_ arguments: [String], acceptFailure: Bool = false) async throws -> ADBCommandResult {
        guard let adb = ToolLocator.executable(named: "adb") else {
            throw ADBServiceError.executableMissing
        }

        return try await Task.detached(priority: .userInitiated) {
            let process = Process()
            let output = Pipe()
            let error = Pipe()
            process.executableURL = adb
            process.arguments = arguments
            process.standardOutput = output
            process.standardError = error

            try process.run()
            process.waitUntilExit()

            let stdout = String(
                decoding: output.fileHandleForReading.readDataToEndOfFile(),
                as: UTF8.self
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            let stderr = String(
                decoding: error.fileHandleForReading.readDataToEndOfFile(),
                as: UTF8.self
            ).trimmingCharacters(in: .whitespacesAndNewlines)

            let result = ADBCommandResult(
                output: stdout,
                errorOutput: stderr,
                exitCode: process.terminationStatus
            )
            if !acceptFailure && process.terminationStatus != 0 {
                throw ADBServiceError.commandFailed(stderr.isEmpty ? stdout : stderr)
            }
            return result
        }.value
    }

    static func arguments(for device: AndroidDevice, command: [String]) -> [String] {
        ["-s", device.serial] + command
    }
}
