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
    case usbDeviceRequired
    case wirelessAddressUnavailable

    var errorDescription: String? {
        switch self {
        case .adbMissing:
            return "未找到 adb。请使用内置安装包，或先安装 Android Platform Tools。"
        case .commandFailed(let message):
            return message.isEmpty ? "无法读取 Android 设备。" : message
        case .usbDeviceRequired:
            return "请先选择一台通过 USB 连接并已授权的设备。"
        case .wirelessAddressUnavailable:
            return "无法读取手机的 Wi-Fi 地址。请确认手机已连接 Wi-Fi。"
        }
    }
}

struct WirelessTransitionResult: Sendable {
    let address: String
    let message: String
}

enum DeviceService {
    static func devices() async throws -> [AndroidDevice] {
        let result = try await ADBService.run(["devices", "-l"])
        return parse(result.output)
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
        let result = try await ADBService.run(["connect", address], acceptFailure: true)
        guard result.exitCode == 0, !result.output.lowercased().contains("failed") else {
            throw DeviceServiceError.commandFailed(
                result.errorOutput.isEmpty ? result.output : result.errorOutput
            )
        }
        return result.output
    }

    static func send(_ event: AndroidKeyEvent, to device: AndroidDevice) async throws {
        _ = try await ADBService.run(
            ADBService.arguments(
                for: device,
                command: ["shell", "input", "keyevent", event.rawValue]
            )
        )
    }

    static func captureScreenshot(from device: AndroidDevice) async throws -> Data {
        guard let adb = ToolLocator.executable(named: "adb") else {
            throw DeviceServiceError.adbMissing
        }
        return try await Task.detached(priority: .userInitiated) {
            let process = Process()
            let output = Pipe()
            let error = Pipe()
            process.executableURL = adb
            process.arguments = ["-s", device.serial, "exec-out", "screencap", "-p"]
            process.standardOutput = output
            process.standardError = error
            try process.run()
            let imageData = output.fileHandleForReading.readDataToEndOfFile()
            let stderr = String(
                decoding: error.fileHandleForReading.readDataToEndOfFile(),
                as: UTF8.self
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            process.waitUntilExit()
            guard process.terminationStatus == 0, imageData.starts(with: [0x89, 0x50, 0x4e, 0x47]) else {
                throw DeviceServiceError.commandFailed(stderr.isEmpty ? "截图失败。" : stderr)
            }
            return imageData
        }.value
    }

    static func enableWirelessADB(for device: AndroidDevice, port: UInt16 = 5555) async throws -> WirelessTransitionResult {
        guard !device.isWireless, device.state == .device else {
            throw DeviceServiceError.usbDeviceRequired
        }

        let route = try await ADBService.run(
            ADBService.arguments(for: device, command: ["shell", "ip", "route"])
        )
        guard let ip = parseWiFiAddress(route.output) else {
            throw DeviceServiceError.wirelessAddressUnavailable
        }

        _ = try await ADBService.run(
            ADBService.arguments(for: device, command: ["tcpip", String(port)])
        )
        try await Task.sleep(nanoseconds: 900_000_000)

        let address = "\(ip):\(port)"
        let connectMessage = try await connect(address: address)
        return WirelessTransitionResult(
            address: address,
            message: connectMessage.isEmpty ? "已通过 \(address) 建立无线连接。" : connectMessage
        )
    }

    static func disableWirelessADB(for device: AndroidDevice) async throws -> String {
        guard device.isWireless else { throw DeviceServiceError.usbDeviceRequired }
        let result = try await ADBService.run(
            ADBService.arguments(for: device, command: ["usb"]),
            acceptFailure: true
        )
        _ = try? await ADBService.run(["disconnect", device.serial], acceptFailure: true)
        guard result.exitCode == 0 else {
            throw DeviceServiceError.commandFailed(
                result.errorOutput.isEmpty ? result.output : result.errorOutput
            )
        }
        return "已关闭 \(device.serial) 的无线 ADB。"
    }

    static func parseWiFiAddress(_ output: String) -> String? {
        let patterns = [#"\bsrc\s+(\d{1,3}(?:\.\d{1,3}){3})\b"#, #"\binet\s+(\d{1,3}(?:\.\d{1,3}){3})/"#]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(output.startIndex..<output.endIndex, in: output)
            guard let match = regex.firstMatch(in: output, range: range),
                  let matchRange = Range(match.range(at: 1), in: output) else { continue }
            let address = String(output[matchRange])
            if address != "127.0.0.1" { return address }
        }
        return nil
    }
}
