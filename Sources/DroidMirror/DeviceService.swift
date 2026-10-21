import Foundation

struct AndroidDevice: Identifiable, Hashable, Sendable {
    enum State: String, Sendable {
        case device
        case unauthorized
        case offline
        case unknown

        var displayName: String {
            switch self {
            case .device: return "已连接"
            case .unauthorized: return "等待手机授权"
            case .offline: return "设备离线"
            case .unknown: return "状态未知"
            }
        }
    }

    let serial: String
    let state: State
    let model: String?
    let product: String?

    var id: String { serial }
    var name: String { model?.replacingOccurrences(of: "_", with: " ") ?? serial }
    var isWireless: Bool { serial.contains(":") }
}

enum AndroidKeyEvent: String, Sendable {
    case back = "KEYCODE_BACK"
    case home = "KEYCODE_HOME"
    case appSwitch = "KEYCODE_APP_SWITCH"
}

enum DeviceServiceError: LocalizedError {
    case adbMissing
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .adbMissing:
            return "未找到 adb。请使用内置安装包，或先安装 Android Platform Tools。"
        case .commandFailed(let message):
            return message.isEmpty ? "无法读取 Android 设备。" : message
        }
    }
}

enum DeviceService {
    static func devices() async throws -> [AndroidDevice] {
        guard let adb = ToolLocator.executable(named: "adb") else {
            throw DeviceServiceError.adbMissing
        }

        return try await Task.detached(priority: .userInitiated) {
            let process = Process()
            let output = Pipe()
            let error = Pipe()
            process.executableURL = adb
            process.arguments = ["devices", "-l"]
            process.standardOutput = output
            process.standardError = error

            try process.run()
            process.waitUntilExit()

            let stdout = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            let stderr = String(decoding: error.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard process.terminationStatus == 0 else {
                throw DeviceServiceError.commandFailed(stderr)
            }
            return parse(stdout)
        }.value
    }

    static func parse(_ output: String) -> [AndroidDevice] {
        output.split(whereSeparator: \.isNewline).compactMap { rawLine in
            let fields = rawLine.split(whereSeparator: \.isWhitespace).map(String.init)
            guard fields.count >= 2, fields[0] != "List" else { return nil }

            var metadata: [String: String] = [:]
            for field in fields.dropFirst(2) {
                let pair = field.split(separator: ":", maxSplits: 1).map(String.init)
                if pair.count == 2 { metadata[pair[0]] = pair[1] }
            }

            return AndroidDevice(
                serial: fields[0],
                state: AndroidDevice.State(rawValue: fields[1]) ?? .unknown,
                model: metadata["model"],
                product: metadata["product"]
            )
        }
    }

    static func connect(address: String) async throws -> String {
        guard let adb = ToolLocator.executable(named: "adb") else {
            throw DeviceServiceError.adbMissing
        }

        return try await Task.detached(priority: .userInitiated) {
            let process = Process()
            let output = Pipe()
            let error = Pipe()
            process.executableURL = adb
            process.arguments = ["connect", address]
            process.standardOutput = output
            process.standardError = error
            try process.run()
            process.waitUntilExit()

            let stdout = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let stderr = String(decoding: error.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard process.terminationStatus == 0, !stdout.lowercased().contains("failed") else {
                throw DeviceServiceError.commandFailed(stderr.isEmpty ? stdout : stderr)
            }
            return stdout
        }.value
    }

    static func send(_ event: AndroidKeyEvent, to device: AndroidDevice) async throws {
        guard let adb = ToolLocator.executable(named: "adb") else {
            throw DeviceServiceError.adbMissing
        }

        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            let output = Pipe()
            let error = Pipe()
            process.executableURL = adb
            process.arguments = ["-s", device.serial, "shell", "input", "keyevent", event.rawValue]
            process.standardOutput = output
            process.standardError = error
            try process.run()
            process.waitUntilExit()

            let stderr = String(decoding: error.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard process.terminationStatus == 0 else {
                throw DeviceServiceError.commandFailed(stderr)
            }
        }.value
    }
}
