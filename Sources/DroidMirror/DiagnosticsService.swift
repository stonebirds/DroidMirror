import Foundation

enum DiagnosticsService {
    @MainActor
    static func report(model: AppModel) async -> String {
        let adbVersion = try? await ADBService.run(["version"], acceptFailure: true)
        let devices = (try? await DeviceService.devices()) ?? []
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版"

        let deviceLines = devices.map {
            "- \($0.serial) | \($0.name) | \($0.state.displayName) | \($0.isWireless ? "wireless" : "usb")"
        }.joined(separator: "\n")

        return """
        DroidMirror diagnostics
        Generated: \(ISO8601DateFormatter().string(from: Date()))

        App version: \(appVersion)
        macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)
        Architecture: \(architecture)
        Session state: \(model.mirror.state.displayName)
        Mirror engine: \(model.mirror.activeEngine?.rawValue ?? "none")
        Selected device: \(model.selectedDeviceID ?? "none")

        adb path: \(ToolLocator.executable(named: "adb")?.path ?? "missing")
        scrcpy path: \(ToolLocator.executable(named: "scrcpy")?.path ?? "missing")
        scrcpy-server path: \(ToolLocator.scrcpyServerURL()?.path ?? "missing")

        adb version:
        \(adbVersion?.output ?? adbVersion?.errorOutput ?? "unavailable")

        Devices:
        \(deviceLines.isEmpty ? "- none" : deviceLines)

        Settings:
        - max size: \(model.settings.maxSize)
        - bit rate: \(model.settings.bitRateMbps) Mbps
        - max FPS: \(model.settings.maxFPS)
        - video codec: \(model.settings.videoCodec.rawValue)
        - audio: \(model.settings.audioEnabled)
        - presentation: \(model.settings.presentation.rawValue)
        """
    }

    private static var architecture: String {
#if arch(arm64)
        return "arm64"
#elseif arch(x86_64)
        return "x86_64"
#else
        return "unknown"
#endif
    }
}
